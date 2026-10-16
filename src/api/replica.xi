// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.replica

// L-4 replica v1: async catch-up by shipping WAL files + manual promotion.
//
// The follower home is an ordinary durable home whose FILES are byte
// copies of the leader's: the whole-file checkpoint (copied when its
// size changed -- a swap rewrites it) and the append+fsync delta segment
// (copied whole each pass; bounded by the leader's swap cadence).
// Serving reads from the follower is `open_durable(follower_ckpt,
// follower_seg)`; the loader's own checkpoint-dedupe merge IS the "apply
// with checkpoint skip" rule (segment records <= the copied checkpoint's
// LSN are skipped; +1 prefix-exact). Every component therefore stays in
// ONE canonical LSN space and no engine output is ever re-persisted into
// a home.
//
// Why files, not replayed records: `engine_recover` produces a fresh
// checkpoint WAL whose record numbering is compacted while `next_lsn`
// keeps the frontier. Persisting that as a follower home (the first cut
// of this module) opens fine alone, but the loader's segment merge then
// gaps against it (the dedupe cursor is the last record while appends
// continue at `next_lsn`) -- found by probe_replica. Byte-shipping the
// leader's canonical files removes the whole class.
//
// Watermark: `<follower_ckpt>.ack` holds the shipped leader frontier
// (atomic temp+rename, written after both files). Lag = leader frontier
// (max checkpoint lsn, delta last lsn) - ack (clamped >= 0); the
// embedder copies it into `ServiceState.replica_lag` for the `/stats`
// `replica_lag` field + the `xvector_replica_lag` gauge. Crash windows:
// checkpoint first, segment second, ack last -- an interruption leaves
// the follower OPENABLE at the previous or partial point (prefix-exact
// merge), never corrupt; the next ship repairs it.
//
// Scope (L-4 v1): WAL/active state only -- sealed segment FILES are not
// shipped here (a rolled collection needs the artifact path:
// `export_collection` + file copy + `attach_segment`); the sealed-set
// file-ship loop is the L-4 follow-up. Promotion is MANUAL: stop the
// leader -> one final ship -> `open_durable` the follower home -> flip
// the mapping (version bump; the router's single retry covers the
// window). The promoted home is canonical (leader-shaped files), so the
// D5/D6 durable machinery owns it from then on.

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.durability.wal_segment;

pub type ReplicaOut = {
  ok: Bool;
  err: Str;
  frontier: Int;
  snapshot: Bool;
  ckpt_bytes: Int;
  seg_bytes: Int;
}

fn replica_file_bytes(path: Str) -> Vec[UInt8] {
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => {}
  }
  return b;
}

fn replica_write_file(path: Str, b: &Vec[UInt8]) -> Bool {
  var w = io.write_file_bytes(path, &b);
  match w {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn replica_size(path: Str) -> Int {
  var fs = io.file_size(path);
  var n: Int = -1;
  match fs {
    Some(x) => { n = x; }
    None => {}
  }
  return n;
}

// Leader frontier in ITS OWN LSN space (checkpoint + delta segment).
pub fn replica_frontier(leader_ckpt: Str, leader_seg: Str) -> Int {
  var lw = wal_load(leader_ckpt);
  var frontier = wal_writer_current_lsn(&lw);
  var l_seg = segment_last_lsn(leader_seg);
  if l_seg > frontier { frontier = l_seg; }
  return frontier;
}

// Read the shipped-frontier watermark (`<ckpt>.ack`); 0 when missing.
fn replica_ack_read(ckpt_path: Str) -> Int {
  if ckpt_path.len() == 0 { return 0; }
  var ap = ckpt_path + ".ack";
  if !io.file_exists(ap) { return 0; }
  var b = replica_file_bytes(ap);
  var v: Int = 0;
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    if c >= 48 && c <= 57 { v = v * 10 + ((c as Int) - 48); }
    i = i + 1;
  }
  return v;
}

// Persist the watermark atomically (temp + rename).
fn replica_ack_write(ckpt_path: Str, lsn: Int) -> Bool {
  if ckpt_path.len() == 0 { return true; }
  var ap = ckpt_path + ".ack";
  var tmp = ap + ".tmp";
  var s = convert.int_to_string(lsn);
  var b = slice.str_bytes(s);
  var w = io.write_file_bytes(tmp, &b);
  match w {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  var r = io.rename(tmp, ap);
  match r {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Monitoring helper: current lag without shipping (frontier - ack).
pub fn replica_lag_estimate(leader_ckpt: Str, leader_seg: Str, follower_ckpt: Str) -> Int {
  var lag = replica_frontier(leader_ckpt, leader_seg) - replica_ack_read(follower_ckpt);
  if lag < 0 { lag = 0; }
  return lag;
}

// One ship pass. `snapshot` = the checkpoint was (re)copied this pass
// (join or leader swap); false = delta-only (segment copied, checkpoint
// unchanged). The frontier is observed BEFORE the copies; a leader that
// advances mid-copy is picked up by the next pass (lag reflects it).
pub fn replica_ship(leader_ckpt: Str, leader_seg: Str, follower_ckpt: Str, follower_seg: Str) -> ReplicaOut {
  var frontier = replica_frontier(leader_ckpt, leader_seg);
  var l_ckpt_size = replica_size(leader_ckpt);
  var f_ckpt_size = replica_size(follower_ckpt);
  var snapshot: Bool = false;
  var ckpt_bytes: Int = 0;
  if l_ckpt_size > 0 && l_ckpt_size != f_ckpt_size {
    var cb = replica_file_bytes(leader_ckpt);
    if cb.len() == 0 {
      return ReplicaOut{ ok: false, err: "leader checkpoint read failed", frontier: frontier, snapshot: false, ckpt_bytes: 0, seg_bytes: 0 };
    }
    if !replica_write_file(follower_ckpt, &cb) {
      return ReplicaOut{ ok: false, err: "follower checkpoint write failed", frontier: frontier, snapshot: false, ckpt_bytes: 0, seg_bytes: 0 };
    }
    snapshot = true;
    ckpt_bytes = cb.len();
  }
  var sb = replica_file_bytes(leader_seg);
  if !replica_write_file(follower_seg, &sb) {
    return ReplicaOut{ ok: false, err: "follower segment write failed", frontier: frontier, snapshot: snapshot, ckpt_bytes: ckpt_bytes, seg_bytes: 0 };
  }
  if !replica_ack_write(follower_ckpt, frontier) {
    return ReplicaOut{ ok: false, err: "ack write failed", frontier: frontier, snapshot: snapshot, ckpt_bytes: ckpt_bytes, seg_bytes: sb.len() };
  }
  return ReplicaOut{ ok: true, err: "", frontier: frontier, snapshot: snapshot, ckpt_bytes: ckpt_bytes, seg_bytes: sb.len() };
}
