// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.httpd

// Runnable XVECTOR HTTP server: the user-testable face of the DB.
// Single-threaded sequential-accept loop over the stdlib socket layer
// (`xiom.net.socket`; the PULSE production pattern), whole requests in /
// responses out through the transport-agnostic `http_service_handle`.
// This module only frames sockets: read headers to CRLFCRLF, honor
// Content-Length, guard the buffer, send, close. The service does the
// strict HTTP work (parsing, routing, limits, JSON).
//
// Run: xvectord.exe [--bind 127.0.0.1] [--port 7707]
// Env fallback: XVECTORD_BIND / XVECTORD_PORT
// Quit: any request carrying header `X-Xvector-Quit: 1`.

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.os.env;
use xiom.net;
use xiom.net.socket;
use xiom.vectors;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
use xiom.vector.durability.wal_file;
use xiom.vector.durability.wal_segment;

// Socket-side guard so a hostile peer cannot grow the buffer forever
// (generous for benchmark fits; the service's own max_request_bytes --
// XVECTOR_MAX_REQUEST_BYTES, applied in httpd_once -- is the real cap).
const MAX_REQUEST_BYTES: Int = 33554432;

// Byte index of CRLFCRLF (end of headers) or -1.
fn header_end(b: &Vec[UInt8]) -> Int {
  if b.len() < 4 { return -1; }
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13u8 && b[i + 1] == 10u8 && b[i + 2] == 13u8 && b[i + 3] == 10u8 { return i; }
    i = i + 1;
  }
  return -1;
}

// Case-insensitive Content-Length within the header block (0 when absent).
fn content_length(b: &Vec[UInt8], he: Int) -> Int {
  let needle = slice.str_bytes("content-length:");
  var i: Int = 0;
  while i + needle.len() <= he {
    var j: Int = 0;
    var hit: Bool = true;
    while j < needle.len() {
      var c = b[i + j];
      if c >= 65u8 && c <= 90u8 { c = c + 32u8; }
      if c != needle[j] { hit = false; }
      j = j + 1;
    }
    if hit {
      var p: Int = i + needle.len();
      while p < he && (b[p] == 32u8 || b[p] == 9u8) { p = p + 1; }
      var n: Int = 0;
      while p < he && b[p] >= 48u8 && b[p] <= 57u8 {
        n = n * 10 + ((b[p] - 48u8) as Int);
        p = p + 1;
      }
      return n;
    }
    i = i + 1;
  }
  return 0;
}

// Case-insensitive token presence anywhere in the request bytes.
fn has_token(b: &Vec[UInt8], s: Str) -> Bool {
  let t = slice.str_bytes(s);
  if t.len() == 0 || b.len() < t.len() { return false; }
  var i: Int = 0;
  while i + t.len() <= b.len() {
    var j: Int = 0;
    var hit: Bool = true;
    while j < t.len() {
      var c = b[i + j];
      if c >= 65u8 && c <= 90u8 { c = c + 32u8; }
      if c != t[j] { hit = false; }
      j = j + 1;
    }
    if hit { return true; }
    i = i + 1;
  }
  return false;
}

// One complete request per connection: headers, then exactly the
// Content-Length body (a peer that sends nothing -> empty). O(n) syscalls.
pub fn httpd_read_request(fd: Int) -> Vec[UInt8] {
  var raw = Vec[UInt8].new();
  var done: Bool = false;
  var rounds: Int = 0;
  while !done && rounds < 4096 {
    let rr = socket.socket_recv(fd, 65536);
    if rr.is_err {
      done = true;
    } else {
      let chunk = rr.value;
      if chunk.len() == 0 {
        done = true;
      } else {
        var i: Int = 0;
        while i < chunk.len() {
          raw.push(chunk[i]);
          i = i + 1;
        }
        if raw.len() >= MAX_REQUEST_BYTES {
          done = true;
        } else {
          let he = header_end(&raw);
          if he >= 0 {
            let want = he + 4 + content_length(&raw, he);
            if raw.len() >= want { done = true; }
          }
        }
      }
    }
    rounds = rounds + 1;
  }
  return raw;
}

fn send_all(fd: Int, data: &Vec[UInt8]) -> Bool {
  var ts = TcpStream{ fd: fd };
  let r = ts.write_all(data);
  return r.is_ok;
}

// Serve exactly one accepted connection. Returns 0 = served, 1 = served +
// quit requested, -1 = empty/error. Exposed so the probe can drive the exact
// same per-connection path the serve loop uses.
pub fn httpd_once(eng: &mut VectorEngine, client: Int) -> Int {
  // A peer that connects and goes silent must not stall the accept loop.
  let _to = socket.socket_set_timeout(client, 30000);
  var cfg = service_config_default();
  let _n = service_config_from_env(&mut cfg);
  let raw = httpd_read_request(client);
  if raw.len() == 0 {
    socket.socket_close(client);
    return -1;
  }
  let quit = has_token(&raw, "x-xvector-quit");
  let resp = http_service_handle_cfg(eng, &raw, &cfg);
  let ok = send_all(client, &resp);
  socket.socket_close(client);
  if !ok { return -1; }
  if quit { return 1; }
  return 0;
}

pub fn httpd_serve(bind: Str, port: Int) -> Int {
  // Durable home (M-D5, opt-in): XVECTORD_WAL=<checkpoint path> enables
  // fsync-on-ack via the delta segment <path>.seg; XVECTORD_MANIFEST is
  // optional. Without XVECTORD_WAL the server runs in-memory (no durability
  // claim) -- exactly the benchmark/server default before D5.
  var eng = engine_new();
  var wal_path: Str = "";
  var seg_path: Str = "";
  let vw = env.var_opt("XVECTORD_WAL");
  match vw {
    Some(p) => {
      if p.len() > 0 {
        wal_path = p;
        seg_path = p + ".seg";
        var manifest = "";
        let vm = env.var_opt("XVECTORD_MANIFEST");
        match vm {
          Some(m) => { if m.len() > 0 { manifest = m; } }
          None => {}
        }
        eng = open_durable(wal_path, seg_path, manifest, 1, DistanceMetric.Euclidean);
        io.println("xvectord: durable home " + wal_path + " (segment " + seg_path + ")");
        // Auto-checkpoint policy (M-D6): a compact+swap every N commits
        // bounds recovery time and the checkpoint size. 0 / absent = off
        // (clean quit still swaps).
        var every: Int = 0;
        let ve = env.var_opt("XVECTORD_CHECKPOINT_EVERY");
        match ve {
          Some(v) => {
            var e2: Int = 0;
            if parse_port(v, &mut e2) { every = e2; }
          }
          None => {}
        }
        if every > 0 {
          let _pol = engine_set_checkpoint_policy(&mut eng, every);
          io.println("xvectord: auto-checkpoint every " + convert.int_to_string(every) + " commits");
        }
      }
    }
    None => {}
  }
  // Auto-roll policy (M-D7): roll the active collection at N points into
  // XVECTORD_SEAL_DIR (default: the durable home's directory). 0 / absent
  // = off; a missing dir disables the policy with a visible warning.
  var seal_every: Int = 0;
  let vse = env.var_opt("XVECTORD_SEAL_EVERY");
  match vse {
    Some(v) => {
      var e3: Int = 0;
      if parse_port(v, &mut e3) { seal_every = e3; }
    }
    None => {}
  }
  if seal_every > 0 {
    var s_dir = "";
    let vsd = env.var_opt("XVECTORD_SEAL_DIR");
    match vsd {
      Some(d) => { if d.len() > 0 { s_dir = d; } }
      None => {}
    }
    if s_dir.len() == 0 && wal_path.len() > 0 {
      s_dir = path_parent(wal_path);
    }
    if s_dir.len() == 0 {
      io.println("xvectord: XVECTORD_SEAL_EVERY ignored (set XVECTORD_SEAL_DIR or XVECTORD_WAL)");
    } else {
      match engine_set_seal_policy(&mut eng, seal_every, s_dir) {
        Ok(_) => {
          io.println("xvectord: auto-roll every " + convert.int_to_string(seal_every) + " points into " + s_dir);
        }
        Err(_) => {
          io.println("xvectord: XVECTORD_SEAL_EVERY ignored (seal dir missing: " + s_dir + ")");
        }
      }
    }
  }
  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("xvectord: socket create failed");
    io.flush_stdout();
    return 1;
  }
  let fd = sr.value;
  let _ra = socket.socket_reuse_addr(fd, true);
  let br = socket.socket_bind(fd, bind, port);
  if br.is_err {
    io.println("xvectord: bind " + bind + ":" + convert.int_to_string(port) + " failed: " + br.error);
    io.flush_stdout();
    return 1;
  }
  let lr = socket.socket_listen(fd, 128);
  if lr.is_err {
    io.println("xvectord: listen failed: " + lr.error);
    io.flush_stdout();
    return 1;
  }
  io.println("xvectord: listening on http://" + bind + ":" + convert.int_to_string(port));
  io.println("xvectord: endpoints /health /collections /stats /search (quit: header X-Xvector-Quit: 1)");
  io.flush_stdout();
  var running: Bool = true;
  while running {
    let ar = socket.socket_accept(fd);
    if ar.is_err {
      io.println("xvectord: accept failed: " + ar.error);
      io.flush_stdout();
      socket.socket_close(fd);
      return 1;
    }
    let rc = httpd_once(&mut eng, ar.value);
    if rc == 1 {
      running = false;
      io.println("xvectord: quit requested; shutting down");
      io.flush_stdout();
    }
  }
  socket.socket_close(fd);
  if wal_path.len() > 0 {
    // Clean shutdown (M-D6): a full compact+swap (bounded checkpoint,
    // crash-safe ordering, segment rotation). On failure fall back to the
    // plain whole-file persist; the delta segment stays intact either way.
    match engine_checkpoint_swap(&mut eng) {
      Ok(lsn) => {
        io.println("xvectord: checkpoint swap committed (frontier "
          + convert.int_to_string(lsn) + "); segment rotated");
      }
      Err(_) => {
        let ck = http_service_shutdown(&eng, wal_path);
        let _rot = segment_reset(seg_path);
        if ck {
          io.println("xvectord: checkpoint persisted (swap unavailable); segment rotated");
        } else {
          io.println("xvectord: WARNING checkpoint persist failed (segment intact)");
        }
      }
    }
    io.flush_stdout();
  }
  return 0;
}

// Digits-only decimal parse of `s` into `out`; false on empty/garbage.
fn parse_port(s: Str, out: &mut Int) -> Bool {
  if s.len() == 0 { return false; }
  var p: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let c = s.byte_at(i);
    if c < 48u8 || c > 57u8 { return false; }
    p = p * 10 + ((c - 48u8) as Int);
    i = i + 1;
  }
  out = p;
  return true;
}

pub fn main() -> Int {
  var bind: Str = "127.0.0.1";
  var port: Int = 7707;
  let vb = env.var_opt("XVECTORD_BIND");
  match vb {
    Some(v) => { if v.len() > 0 { bind = v; } }
    None => {}
  }
  let vp = env.var_opt("XVECTORD_PORT");
  match vp {
    Some(v) => {
      var p: Int = 0;
      if parse_port(v, &mut p) { port = p; }
    }
    None => {}
  }
  let args = env.args();
  var ai: Int = 0;
  while ai + 1 < args.len() {
    if args[ai] == "--port" {
      var p2: Int = 0;
      if parse_port(args[ai + 1], &mut p2) { port = p2; }
    }
    if args[ai] == "--bind" { bind = args[ai + 1]; }
    ai = ai + 1;
  }
  return httpd_serve(bind, port);
}
