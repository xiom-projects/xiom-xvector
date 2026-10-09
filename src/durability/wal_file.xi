// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.wal_file

// File-backed WAL using the stdlib's whole-file APIs (write_file_bytes /
// read_file_bytes / file_exists). The format is text: a header line plus one
// line per record (lsn op key value timestamp payload_len [w1,w2,...]).
// Persist is a whole-file CHECKPOINT (rewrite), not append+fsync -- the
// stdlib fd/fsync/append ops are still stubs -- so a crash can lose records
// written after the last persist; when the fd/fsync gap lands this path is
// upgraded to append + fsync. Load is torn-tail tolerant: a missing,
// corrupt, or byte-truncated file yields the longest prefix of COMPLETE
// valid records (prefix exactness).
//
// The loader parses BYTES directly (no Str::from_utf8 / str_split): those
// mis-lowered in this compilation unit (correct lengths, element content
// reads as address-like digits -- XVC-C-11, C-08-family), so the reader
// avoids Str content handling entirely and operates on the raw Vec[UInt8].

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.vector.durability.wal;

fn op_code(op: WalOpKind) -> Int {
  if op == WalOpKind.Insert { return 1; }
  if op == WalOpKind.Update { return 2; }
  if op == WalOpKind.Delete { return 3; }
  if op == WalOpKind.SegmentSeal { return 4; }
  if op == WalOpKind.ManifestUpdate { return 5; }
  if op == WalOpKind.Checkpoint { return 6; }
  return 7;
}

fn code_op(c: Int) -> WalOpKind {
  if c == 2 { return WalOpKind.Update; }
  if c == 3 { return WalOpKind.Delete; }
  if c == 4 { return WalOpKind.SegmentSeal; }
  if c == 5 { return WalOpKind.ManifestUpdate; }
  if c == 6 { return WalOpKind.Checkpoint; }
  if c == 7 { return WalOpKind.SnapshotMarker; }
  return WalOpKind.Insert;
}

// One parsed integer: value plus the position after it; ok=false when no
// digits were present at `start` (strict: optional '-', then digits).
pub type ParsedInt = {
  value: Int;
  pos: Int;
  ok: Bool;
}

fn parse_int_at(b: &Vec[UInt8], start: Int) -> ParsedInt {
  var p: Int = start;
  var neg: Bool = false;
  if p < b.len() && b[p] == 45 {
    neg = true;
    p = p + 1;
  }
  var v: Int = 0;
  var digits: Int = 0;
  while p < b.len() && b[p] >= 48 && b[p] <= 57 {
    v = v * 10 + ((b[p] as Int) - 48);
    p = p + 1;
    digits = digits + 1;
  }
  if digits == 0 {
    return ParsedInt{ value: 0, pos: start, ok: false };
  }
  if neg { v = 0 - v; }
  return ParsedInt{ value: v, pos: p, ok: true };
}

// Whole-file checkpoint write. False on any IO error.
pub fn wal_persist(w: &WalWriter, path: Str) -> Bool {
  var text = "xvector-wal 1\n";
  var i: Int = 0;
  while i < w.records.len() {
    var r = w.records[i];
    text = text + convert.int_to_string(r.lsn) + " "
      + convert.int_to_string(op_code(r.op)) + " "
      + convert.int_to_string(r.key) + " "
      + convert.int_to_string(r.value) + " "
      + convert.int_to_string(r.timestamp) + " "
      + convert.int_to_string(r.payload.len());
    if r.payload.len() > 0 {
      text = text + " ";
      var j: Int = 0;
      while j < r.payload.len() {
        if j > 0 { text = text + ","; }
        text = text + convert.int_to_string(r.payload[j]);
        j = j + 1;
      }
    }
    text = text + "\n";
    i = i + 1;
  }
  var bytes = slice.str_bytes(text);
  var res = io.write_file_bytes(path, &bytes);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Load the longest complete-record prefix (missing / corrupt / truncated
// files degrade gracefully; never fails).
pub fn wal_load(path: Str) -> WalWriter {
  var w = wal_writer_new();
  if !io.file_exists(path) { return w; }
  var fs = io.file_size(path);
  var sz: Int = -1;
  match fs {
    Some(n) => { sz = n; }
    None => { return w; }
  }
  // Files shorter than the shortest VALID wal (13-byte header + the shortest
  // record line "1 5 0 0 0 0\n" = 25 bytes) cannot contain a complete
  // record, so they are empty logs -- and this also skips reads of tiny
  // files: read_file_bytes aborts on files of <= 8 bytes on v0.64.1
  // (spurious ensures violation at io.xi:947; XVC-C-12).
  if sz < 25 { return w; }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return w; }
  }
  var hdr = slice.str_bytes("xvector-wal 1");
  if b.len() < hdr.len() + 1 { return w; }
  var hi: Int = 0;
  while hi < hdr.len() {
    if b[hi] != hdr[hi] { return w; }
    hi = hi + 1;
  }
  var pos: Int = hdr.len();
  if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
  if pos >= b.len() || b[pos] != 10 { return w; }
  pos = pos + 1;
  var lsn: Int = 0;
  var stop: Bool = false;
  while pos < b.len() && !stop {
    var fields = Vec[Int].new();
    var fi: Int = 0;
    var bad: Bool = false;
    while fi < 6 && !bad {
      var r = parse_int_at(b, pos);
      if !r.ok {
        bad = true;
      } else {
        fields.push(r.value);
        pos = r.pos;
        if fi < 5 {
          if pos < b.len() && b[pos] == 32 {
            pos = pos + 1;
          } else {
            bad = true;
          }
        }
        fi = fi + 1;
      }
    }
    var payload = Vec[Int].new();
    if !bad {
      var plen: Int = fields[5];
      if plen < 0 {
        bad = true;
      } elif plen == 0 {
        if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
        if pos < b.len() && b[pos] == 10 {
          pos = pos + 1;
        } else {
          bad = true;
        }
      } else {
        if pos < b.len() && b[pos] == 32 {
          pos = pos + 1;
        } else {
          bad = true;
        }
        var wc: Int = 0;
        while wc < plen && !bad {
          var r2 = parse_int_at(b, pos);
          if !r2.ok {
            bad = true;
          } else {
            payload.push(r2.value);
            pos = r2.pos;
            if wc < plen - 1 {
              if pos < b.len() && b[pos] == 44 {
                pos = pos + 1;
              } else {
                bad = true;
              }
            }
            wc = wc + 1;
          }
        }
        if !bad {
          if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
          if pos < b.len() && b[pos] == 10 {
            pos = pos + 1;
          } else {
            bad = true;
          }
        }
      }
    }
    if bad {
      stop = true;
    } else {
      if fields[0] != lsn + 1 || fields[1] < 1 || fields[1] > 7 {
        stop = true;
      } else {
        var rec = WalRecord{
          lsn: fields[0],
          op: code_op(fields[1]),
          key: fields[2],
          value: fields[3],
          payload: payload,
          timestamp: fields[4],
        };
        w.records.push(rec);
        lsn = fields[0];
        w.next_lsn = lsn + 1;
        w.synced_lsn = lsn;
      }
    }
  }
  return w;
}
