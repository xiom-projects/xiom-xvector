// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// G-2b concurrency probe: the REAL threaded server (`httpd_serve_cfg`, 4
// workers) against 4 concurrent client threads x 8 deterministic vectors.
// Each client upserts unique ids in its own range and immediately searches
// for its own vector; the top-1 hit must be its own id (exact distance 0).
// After all clients join, /stats must report exactly 4 x 8 = 32 points.
// The quit request goes through a worker; the acceptor stops, joins every
// worker, and the server thread returns 0 (graceful shutdown joins).
//
// Deterministic by construction: unique vectors, one collection, all engine
// calls serialized by the server's coarse mutex; the mutex is the only
// sharing, so any lost update shows up as a wrong count or a wrong hit.
//
// Exit = failed checks.

module probe_concurrency

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.net;
use xiom.net.socket;
use xiom.thread;
use xiom.vector.api.httpd;

// Scalar-only globals (XVC-C-19: no allocating initializers).
var S_PORT: Int = 0;
var C_PORT: Int = 0;
var CLIENTS: Int = 4;
var PER_CLIENT: Int = 8;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); }
  else { io.println("  [FAIL] " + name); }
  io.flush_stdout();
  if ok { return fails; }
  return fails + 1;
}

// ---- wire helpers ---------------------------------------------------------

fn mk_req(method: Str, path: Str, body: Str, quit: Bool) -> Vec[UInt8] {
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nConnection: close\r\nContent-Type: application/json\r\n";
  if quit { s = s + "X-Xvector-Quit: 1\r\n"; }
  s = s + "Content-Length: " + int_to_str(body.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn recv_all(fd: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var done: Bool = false;
  var rounds: Int = 0;
  while !done && rounds < 64 {
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
          out.push(chunk[i]);
          i = i + 1;
        }
      }
    }
    rounds = rounds + 1;
  }
  return out;
}

fn roundtrip(port: Int, req: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let cs = socket.socket_tcp();
  if cs.is_err { return out; }
  let cfd = cs.value;
  let _t = socket.socket_set_timeout(cfd, 5000);
  let cr = socket.socket_connect(cfd, "127.0.0.1", port);
  if cr.is_err {
    socket.socket_close(cfd);
    return out;
  }
  let _sr = socket.socket_send_all(cfd, req);
  out = recv_all(cfd);
  socket.socket_close(cfd);
  return out;
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i < resp.len() && resp[i] != 32u8 { i = i + 1; }
  if i >= resp.len() { return -1; }
  i = i + 1;
  var code: Int = 0;
  var n: Int = 0;
  while i < resp.len() && resp[i] >= 48u8 && resp[i] <= 57u8 && n < 3 {
    code = code * 10 + ((resp[i] - 48u8) as Int);
    i = i + 1;
    n = n + 1;
  }
  if n == 0 { return -1; }
  return code;
}

fn body_start(resp: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < resp.len() {
    if resp[i] == 13u8 && resp[i + 1] == 10u8 && resp[i + 2] == 13u8 && resp[i + 3] == 10u8 {
      return i + 4;
    }
    i = i + 1;
  }
  return -1;
}

fn body_has(resp: &Vec[UInt8], s: Str) -> Bool {
  if s.len() == 0 { return true; }
  let t = slice.str_bytes(s);
  let b0 = body_start(resp);
  if b0 < 0 || b0 + t.len() > resp.len() { return false; }
  var i: Int = b0;
  while i + t.len() <= resp.len() {
    var j: Int = 0;
    var hit: Bool = true;
    while j < t.len() {
      if resp[i + j] != t[j] { hit = false; j = t.len(); } else { j = j + 1; }
    }
    if hit { return true; }
    i = i + 1;
  }
  return false;
}

// Parse the decimal integer immediately after `prefix` in the response
// body (the Prometheus exposition shape `<name> <value>`); -1 when absent.
fn body_int_after(resp: &Vec[UInt8], prefix: Str) -> Int {
  let t = slice.str_bytes(prefix);
  let b0 = body_start(resp);
  if b0 < 0 || t.len() == 0 { return -1; }
  var i: Int = b0;
  while i + t.len() <= resp.len() {
    var j: Int = 0;
    var hit: Bool = true;
    while j < t.len() {
      if resp[i + j] != t[j] { hit = false; j = t.len(); } else { j = j + 1; }
    }
    if hit {
      var p: Int = i + t.len();
      var n: Int = 0;
      var digits: Int = 0;
      while p < resp.len() && resp[p] >= 48u8 && resp[p] <= 57u8 {
        n = n * 10 + ((resp[p] - 48u8) as Int);
        p = p + 1;
        digits = digits + 1;
      }
      if digits > 0 { return n; }
      // A `# TYPE <name> ...` line also contains `<name> `; keep looking
      // for the sample line instead of bailing on the first non-digit.
    }
    i = i + 1;
  }
  return -1;
}

// ---- server + clients -----------------------------------------------------

fn run_server() -> Int {
  return httpd.httpd_serve_cfg("127.0.0.1", S_PORT, CLIENTS);
}

// Pick a port by binding then closing a probe listener (the stdlib bind
// rejects port 0; same deterministic-band approach as probe_http_server).
fn pick_port() -> Int {
  var tryp: Int = 18850;
  while tryp < 18950 {
    let ls = socket.socket_tcp();
    if ls.is_err { return -1; }
    let lfd = ls.value;
    let _ra = socket.socket_reuse_addr(lfd, true);
    var ok: Bool = false;
    let br = socket.socket_bind(lfd, "127.0.0.1", tryp);
    match br { Ok(_) => { ok = true; } Err(_) => {} }
    socket.socket_close(lfd);
    if ok { return tryp; }
    tryp = tryp + 1;
  }
  return -1;
}

fn wait_ready(port: Int) -> Bool {
  var tries: Int = 0;
  while tries < 200 {
    let req = mk_req("GET", "/health", "", false);
    let resp = roundtrip(port, &req);
    if status_of(&resp) == 200 { return true; }
    thread.sleep_ms(20);
    tries = tries + 1;
  }
  return false;
}

fn upsert_body(id: Int) -> Str {
  return "{\"ids\":[" + int_to_str(id) + "],\"vectors\":[[" + int_to_str(id) + ",0,0,0]]}";
}

fn search_body(id: Int) -> Str {
  return "{\"collection\":\"conc\",\"vector\":[" + int_to_str(id) + ",0,0,0],\"top_k\":1}";
}

// One concurrent client: upsert its own range, verify each exact top-1 hit.
fn client_run(cid: Int) -> Int {
  var fails: Int = 0;
  var i: Int = 0;
  while i < PER_CLIENT {
    let id = cid * 100 + i + 1;
    let ub = upsert_body(id);
    let ureq = mk_req("POST", "/collections/conc/points", ub, false);
    let uresp = roundtrip(C_PORT, &ureq);
    if status_of(&uresp) != 200 || !body_has(&uresp, "\"count\":1") {
      fails = fails + 1;
      io.println("  [FAIL] client " + int_to_str(cid) + " upsert id " + int_to_str(id)
        + " status " + int_to_str(status_of(&uresp)));
    }
    let sb = search_body(id);
    let sreq = mk_req("POST", "/search", sb, false);
    let sresp = roundtrip(C_PORT, &sreq);
    if status_of(&sresp) != 200 || !body_has(&sresp, "\"id\":" + int_to_str(id)) {
      fails = fails + 1;
      io.println("  [FAIL] client " + int_to_str(cid) + " search id " + int_to_str(id)
        + " status " + int_to_str(status_of(&sresp)));
    }
    i = i + 1;
  }
  return fails;
}

fn client_1() -> Int { return client_run(1); }
fn client_2() -> Int { return client_run(2); }
fn client_3() -> Int { return client_run(3); }
fn client_4() -> Int { return client_run(4); }

fn main() -> Int {
  io.println("=== xvector probe: concurrency / XVECTORD_THREADS (G-2b) ===");
  var fails: Int = 0;

  S_PORT = pick_port();
  if S_PORT < 0 {
    io.println("  [FAIL] no free port in 18850..18949");
    return 1;
  }
  C_PORT = S_PORT;

  let sh = spawn(run_server);
  if !wait_ready(S_PORT) {
    io.println("  [FAIL] threaded server did not become ready on port " + int_to_str(S_PORT));
    match sh.join() { Ok(_) => {} Err(_) => {} }
    return 1;
  }
  fails = check(true, "server: threaded listener ready (4 workers)", fails);

  // Setup: one collection for all clients.
  let creq = mk_req("POST", "/collections",
    "{\"name\":\"conc\",\"dim\":4,\"metric\":\"euclidean\"}", false);
  let cresp = roundtrip(S_PORT, &creq);
  fails = check(status_of(&cresp) == 201 && body_has(&cresp, "\"name\":\"conc\""),
    "setup: collection conc created", fails);

  // Four clients run concurrently against four workers.
  let h1 = spawn(client_1);
  let h2 = spawn(client_2);
  let h3 = spawn(client_3);
  let h4 = spawn(client_4);
  var c1: Int = 0;
  var c2: Int = 0;
  var c3: Int = 0;
  var c4: Int = 0;
  match h1.join() { Ok(v) => { c1 = v; } Err(_) => { c1 = 1; } }
  match h2.join() { Ok(v) => { c2 = v; } Err(_) => { c2 = 1; } }
  match h3.join() { Ok(v) => { c3 = v; } Err(_) => { c3 = 1; } }
  match h4.join() { Ok(v) => { c4 = v; } Err(_) => { c4 = 1; } }
  fails = check(c1 == 0 && c2 == 0 && c3 == 0 && c4 == 0,
    "clients: 4 x (8 upserts + 8 exact searches) under the coarse lock", fails);

  let stresp = roundtrip(S_PORT, &mk_req("GET", "/stats?collection=conc", "", false));
  let want = CLIENTS * PER_CLIENT;
  fails = check(status_of(&stresp) == 200 && body_has(&stresp, "\"points\":" + int_to_str(want)),
    "stats: exactly " + int_to_str(want) + " points after concurrent writes", fails);

  // ---- G-4: metrics under concurrency -----------------------------------
  // The 4 clients issued exactly `want` upserts and `want` searches. Both
  // counters are atomic fetch_adds, so a lost increment shows up as a
  // short count; the histogram is observed under the shared state lock, so
  // its count must equal requests_total at scrape time (the scrape renders
  // before counting itself).
  let m1 = roundtrip(S_PORT, &mk_req("GET", "/metrics", "", false));
  let req1 = body_int_after(&m1, "xvector_requests_total ");
  let lat1 = body_int_after(&m1, "xvector_latency_ms_count ");
  let ups1 = body_int_after(&m1, "xvector_upsert_ops ");
  let srch1 = body_int_after(&m1, "xvector_search_ops ");
  fails = check(status_of(&m1) == 200 && ups1 == want && srch1 == want,
    "metrics: " + int_to_str(want) + " concurrent upserts + " + int_to_str(want)
    + " searches counted exactly (got " + int_to_str(ups1) + "/" + int_to_str(srch1) + ")", fails);
  fails = check(req1 > 0 && lat1 == req1,
    "metrics: histogram observes every request (count " + int_to_str(lat1)
    + " == requests_total " + int_to_str(req1) + ")", fails);

  // A second scrape sees the first scrape's own request (counted after its
  // render), with both counters advancing by exactly one.
  let m2 = roundtrip(S_PORT, &mk_req("GET", "/metrics", "", false));
  let req2 = body_int_after(&m2, "xvector_requests_total ");
  let lat2 = body_int_after(&m2, "xvector_latency_ms_count ");
  let ups2 = body_int_after(&m2, "xvector_upsert_ops ");
  let srch2 = body_int_after(&m2, "xvector_search_ops ");
  fails = check(req2 == req1 + 1 && lat2 == lat1 + 1 && ups2 == ups1 && srch2 == srch1,
    "metrics: scrape counted once, atomics exact across scrapes ("
    + int_to_str(req1) + "->" + int_to_str(req2) + ")", fails);

  // Quit through a worker; the acceptor stops and joins every worker.
  let qreq = mk_req("GET", "/health", "", true);
  let qresp = roundtrip(S_PORT, &qreq);
  fails = check(status_of(&qresp) == 200, "quit: worker-served quit request answered 200", fails);
  var src: Int = -1;
  match sh.join() { Ok(v) => { src = v; } Err(_) => { src = -2; } }
  fails = check(src == 0, "shutdown: server joined all workers and returned 0 (got "
    + int_to_str(src) + ")", fails);

  io.println("");
  io.println("probe_concurrency: " + int_to_str(fails) + " failed checks");
  return fails;
}
