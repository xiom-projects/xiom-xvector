// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Station read-only web UI gate:
// - /ui serves the static admin page (GET), and HEAD returns headers only
// - /collections/{n}/sample is active-store, deterministic, bounded
// - unknown /ui/* paths 404
// - the threaded server quits and joins its workers cleanly
//
// Exit = failed checks.

module probe_ui

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.net;
use xiom.net.socket;
use xiom.thread;
use xiom.vector.api.httpd;

// Scalar-only globals.
var S_PORT: Int = 0;

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
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn mk_req(method: Str, path: Str, body: Str, quit: Bool) -> Vec[UInt8] {
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nConnection: close\r\n";
  if quit { s = s + "X-Xvector-Quit: 1\r\n"; }
  s = s + "Content-Type: application/json\r\nContent-Length: " + int_to_str(body.len()) + "\r\n\r\n" + body;
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

fn bytes_has(resp: &Vec[UInt8], s: Str) -> Bool {
  if s.len() == 0 { return true; }
  let t = slice.str_bytes(s);
  if t.len() > resp.len() { return false; }
  var i: Int = 0;
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

fn run_server() -> Int {
  return httpd.httpd_serve_cfg("127.0.0.1", S_PORT, 2);
}

fn pick_port() -> Int {
  var tryp: Int = 19060;
  while tryp < 19160 {
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
    let resp = roundtrip(port, &mk_req("GET", "/health", "", false));
    if status_of(&resp) == 200 { return true; }
    thread.sleep_ms(20);
    tries = tries + 1;
  }
  return false;
}

fn main() -> Int {
  io.println("=== xvector probe: station web UI + sample endpoint ===");
  var fails: Int = 0;

  S_PORT = pick_port();
  if S_PORT < 0 {
    io.println("  [FAIL] no free port in 19060..19159");
    return 1;
  }

  let sh = spawn(run_server);
  if !wait_ready(S_PORT) {
    io.println("  [FAIL] station did not become ready");
    match sh.join() { Ok(_) => {} Err(_) => {} }
    return 1;
  }
  fails = check(true, "server: threaded station ready", fails);

  let uresp = roundtrip(S_PORT, &mk_req("GET", "/ui", "", false));
  fails = check(status_of(&uresp) == 200 && bytes_has(&uresp, "<canvas") && bytes_has(&uresp, "XVector Station"),
    "ui: GET /ui serves the admin page", fails);

  let hresp = roundtrip(S_PORT, &mk_req("HEAD", "/ui", "", false));
  let hend = body_start(&hresp);
  fails = check(status_of(&hresp) == 200 && bytes_has(&hresp, "Content-Length: ") && hend == hresp.len(),
    "ui: HEAD /ui returns headers only", fails);

  let missing = roundtrip(S_PORT, &mk_req("GET", "/ui/does-not-exist", "", false));
  fails = check(status_of(&missing) == 404, "ui: unknown /ui/* path is 404", fails);

  let creq = mk_req("POST", "/collections", "{\"name\":\"ui\",\"dim\":4,\"metric\":\"euclidean\"}", false);
  let cresp = roundtrip(S_PORT, &creq);
  fails = check(status_of(&cresp) == 201, "setup: collection ui created", fails);

  let ub = "{\"ids\":[1,2,3,4,5,6],\"vectors\":[[1,0,0,0],[2,0,0,0],[3,0,0,0],[4,0,0,0],[5,0,0,0],[6,0,0,0]]}";
  let uresp2 = roundtrip(S_PORT, &mk_req("POST", "/collections/ui/points", ub, false));
  fails = check(status_of(&uresp2) == 200 && bytes_has(&uresp2, "\"count\":6"),
    "setup: six points upserted", fails);

  let s3 = roundtrip(S_PORT, &mk_req("GET", "/collections/ui/sample?limit=3&seed=1", "", false));
  fails = check(status_of(&s3) == 200 && bytes_has(&s3, "\"sampled\":3")
    && bytes_has(&s3, "\"total\":6") && bytes_has(&s3, "\"scope\":\"active\""),
    "sample: limit=3 returns 3 of 6 active points", fails);

  let sall = roundtrip(S_PORT, &mk_req("GET", "/collections/ui/sample?limit=9999&seed=0", "", false));
  fails = check(status_of(&sall) == 200 && bytes_has(&sall, "\"sampled\":6"),
    "sample: limit clamps and returns all 6", fails);

  let qresp = roundtrip(S_PORT, &mk_req("GET", "/health", "", true));
  fails = check(status_of(&qresp) == 200, "quit: worker-served quit answered", fails);
  var src: Int = -1;
  match sh.join() { Ok(v) => { src = v; } Err(_) => { src = -2; } }
  fails = check(src == 0, "shutdown: station joined all workers (got " + int_to_str(src) + ")", fails);

  io.println("");
  io.println("probe_ui: " + int_to_str(fails) + " failed checks");
  return fails;
}
