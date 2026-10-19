// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Registry consumption gate: xiom.pulse 0.3.1 (PULSE Beacon -- the
// embeddable protocol core; Station consumes the same package). Proves the
// published artifact is consumable from the lane XIOM_HOME and that the
// pure surface works: request parse + header/body framing, the
// version-identity seam (server token roundtrip + rejection rules), the
// stateless hook seam, the stateful HookCtx seam (pre->after mutation,
// limiter short-circuit, idempotent clear), the 0.3.1 unmatched-route
// fallback seam, and the 0.3.1 HEAD wire trim (loopback response: GET
// Content-Length with zero body bytes).
// Exit = failed checks.

module probe_package_pulse

use xiom.pulse;
use xiom.pulse.http;
use xiom.pulse.reqctx;
use xiom.pulse.app;
use xiom.pulse.router;
use xiom.string.slice;
use xiom.net;
use xiom.net.socket;
use xiom.thread;
use xiom.io;
use xiom.convert;

// Scalar-only global (XVC-C-19): the HEAD loopback port.
var H_PORT: Int = 0;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn pre_hook(_req: &PulseRequest, _body: Str) -> PreOut {
  return app.pre_continue();
}

fn pre_ctx_mark(_req: &PulseRequest, _body: Str, ctx: &mut HookCtx) -> PreOut {
  let _ = app.hookctx_set(ctx, 0, 7);
  return app.pre_continue();
}

fn after_ctx_mark(_req: &PulseRequest, _body: Str, _out: &HandlerOut, _info: &ResponseInfo, ctx: &mut HookCtx) {
  let v = app.hookctx_get(ctx, 0);
  let _ = app.hookctx_set(ctx, 1, v + 1);
}

fn pre_ctx_limit(_req: &PulseRequest, _body: Str, ctx: &mut HookCtx) -> PreOut {
  let n = app.hookctx_get(ctx, 0) + 1;
  let _ = app.hookctx_set(ctx, 0, n);
  if n > app.hookctx_get(ctx, 1) {
    return app.pre_stop(app.out_json(429, "{\"error\":{\"code\":\"rate_limited\"}}"));
  }
  return app.pre_continue();
}

fn handler_ok(_req: &PulseRequest, _route: &PulseRoute, _body: Str) -> HandlerOut {
  return app.out_json(200, "{\"ok\":true}");
}

// 0.3.1 fallback seam: an unmatched route consults this before the 404.
fn fallback_site(_req: &PulseRequest, _body: Str) -> HandlerOut {
  return app.out_json(200, "{\"fallback\":\"site\"}");
}

// ---- loopback helpers (HEAD wire trim) ------------------------------------

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

fn header_end(resp: &Vec[UInt8]) -> Int {
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

// Send HEAD /health and assert: 200, the GET Content-Length (11 for
// {"ok":true}) is present, and the response carries zero body bytes.
fn head_client() -> Int {
  var fails: Int = 0;
  let cs = socket.socket_tcp();
  if cs.is_err { return 1; }
  let cfd = cs.value;
  let _t = socket.socket_set_timeout(cfd, 5000);
  let cr = socket.socket_connect(cfd, "127.0.0.1", H_PORT);
  if cr.is_err {
    socket.socket_close(cfd);
    return 1;
  }
  let req = slice.str_bytes("HEAD /health HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n");
  let _s = socket.socket_send_all(cfd, &req);
  let resp = recv_all(cfd);
  socket.socket_close(cfd);
  if status_of(&resp) != 200 { fails = fails + 1; }
  if !bytes_has(&resp, "Content-Length: 11") { fails = fails + 1; }
  let he = header_end(&resp);
  if he < 0 || he != resp.len() { fails = fails + 1; }
  return fails;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.pulse 0.3.1 (Beacon embedded tier) ===");
  var fails: Int = 0;

  // Version-identity gate: 0.3.1 is the exact published identity.
  var pv = pulse.pulse_version();
  var pv_ok = pv == "0.3.1";
  fails = check(pv_ok, "version: pulse_version() reports the exact 0.3.1 identity (" + pv + ")", fails);

  var raw = slice.str_bytes("GET /health HTTP/1.1\r\nHost: t\r\nX-Api-Key: abc123\r\n\r\n");
  var req = http.parse_request(&raw);
  var hdr = http.header_get(&req, "x-api-key");
  fails = check(req.ok && req.method == "GET" && req.target == "/health" && req.version == "HTTP/1.1" && hdr == "abc123",
    "parse: GET request method/target/version + header lookup", fails);

  var raw2 = slice.str_bytes("POST /collections HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\n\r\nabc1234");
  var req2 = http.parse_request(&raw2);
  var body_s = http.bytes_to_str(&req2.body, 0, req2.body.len());
  fails = check(req2.ok && req2.method == "POST" && body_s == "abc1234",
    "parse: POST body framed by Content-Length", fails);

  var dflt = http.server_token();
  fails = check(dflt == "xiom-pulse", "token: default neutral Server token (no version)", fails);
  var set_ok = http.set_server_token("xiom-pulse-xvector/0.1.0");
  fails = check(set_ok && http.server_token() == "xiom-pulse-xvector/0.1.0",
    "token: consumer-set Server token roundtrip", fails);
  var before = http.server_token();
  var rej_crlf = http.set_server_token("bad\r\nX-Inject: 1");
  var rej_tab = http.set_server_token("bad\ttoken");
  fails = check(!rej_crlf && !rej_tab && http.server_token() == before,
    "token: CR/LF + non-printable injection rejected, value unchanged", fails);

  var hs = app.hooks_new();
  var hp = app.hooks_install_pre(&mut hs, pre_hook);
  var installed = false;
  match hp {
    Ok(_) => { installed = true; }
    Err(_) => {}
  }
  fails = check(installed && app.hooks_clear_pre(&mut hs), "hooks: install + clear a stateless pre hook", fails);

  // ---- 0.3.0 stateful HookCtx seam ----
  let _reg = app.register("GET", "/health");
  var hc = app.hooks_new();
  var pc_ok = false;
  var ac_ok = false;
  match app.hooks_install_pre_ctx(&mut hc, pre_ctx_mark) { Ok(_) => { pc_ok = true; } Err(_) => {} }
  match app.hooks_install_after_ctx(&mut hc, after_ctx_mark) { Ok(_) => { ac_ok = true; } Err(_) => {} }
  var ctx = app.hookctx_new();
  let _c0 = app.hookctx_push(&mut ctx, 0);
  let _c1 = app.hookctx_push(&mut ctx, 0);
  let dreq = http.parse_request(&slice.str_bytes("GET /health HTTP/1.1\r\nHost: t\r\n\r\n"));
  let dout = app.dispatch_with_ctx(&hc, &mut ctx, "GET", &dreq, "", handler_ok);
  fails = check(pc_ok && ac_ok && dout.status == 200
    && app.hookctx_len(&ctx) == 2
    && app.hookctx_get(&ctx, 0) == 7
    && app.hookctx_get(&ctx, 1) == 8,
    "hooks_ctx: pre mutation visible to after (state[0]=7, state[1]=8) on a 200", fails);

  var lh = app.hooks_new();
  var li = false;
  match app.hooks_install_pre_ctx(&mut lh, pre_ctx_limit) { Ok(_) => { li = true; } Err(_) => {} }
  var lctx = app.hookctx_new();
  let _l0 = app.hookctx_push(&mut lctx, 0);  // count
  let _l1 = app.hookctx_push(&mut lctx, 1);  // limit
  let o1 = app.dispatch_with_ctx(&lh, &mut lctx, "GET", &dreq, "", handler_ok);
  let o2 = app.dispatch_with_ctx(&lh, &mut lctx, "GET", &dreq, "", handler_ok);
  fails = check(li && o1.status == 200 && o2.status == 429 && app.hookctx_get(&lctx, 0) == 2,
    "hooks_ctx: limiter handle short-circuits the second request (200 then 429)", fails);

  let clr1 = app.hookctx_clear(&mut lctx);
  let clr2 = app.hookctx_clear(&mut lctx);
  fails = check(clr1 && !clr2 && app.hookctx_len(&lctx) == 0,
    "hookctx: clear empties once, is idempotent (second call returns false)", fails);

  // ---- 0.3.1 fallback seam ----
  var fh = app.hooks_new();
  var fi = false;
  match app.hooks_install_fallback(&mut fh, fallback_site) { Ok(_) => { fi = true; } Err(_) => {} }
  fails = check(fi && app.hooks_has_fallback(&fh), "fallback: install + has", fails);

  var dup = false;
  match app.hooks_install_fallback(&mut fh, fallback_site) {
    Ok(_) => {}
    Err(e) => { dup = app.hook_error_code(&e) == "fallback_already_installed"; }
  }
  fails = check(dup, "fallback: duplicate rejected with fallback_already_installed", fails);

  var fctx = app.hookctx_new();
  let miss = http.parse_request(&slice.str_bytes("GET /no-such-page HTTP/1.1\r\nHost: t\r\n\r\n"));
  let fout = app.dispatch_with_ctx(&fh, &mut fctx, "GET", &miss, "", handler_ok);
  fails = check(fout.status == 200 && fout.body == "{\"fallback\":\"site\"}",
    "fallback: unmatched route served by the fallback (site mode)", fails);

  let fc = app.hooks_clear_fallback(&mut fh);
  let fout2 = app.dispatch_with_ctx(&fh, &mut fctx, "GET", &miss, "", handler_ok);
  fails = check(fc && !app.hooks_has_fallback(&fh) && fout2.status == 404,
    "fallback: clear restores the package 404", fails);

  // ---- 0.3.1 HEAD wire trim (loopback) ----
  let ls = socket.socket_tcp();
  var lfd: Int = -1;
  var port: Int = -1;
  if ls.is_ok {
    lfd = ls.value;
    let _ra = socket.socket_reuse_addr(lfd, true);
    var tryp: Int = 18960;
    while port < 0 && tryp < 19060 {
      var ok: Bool = false;
      let br = socket.socket_bind(lfd, "127.0.0.1", tryp);
      match br { Ok(_) => { ok = true; } Err(_) => {} }
      if ok { port = tryp; } else { tryp = tryp + 1; }
    }
    if port > 0 {
      let _lr = socket.socket_listen(lfd, 4);
    }
  }
  if port > 0 {
    H_PORT = port;
    let hc = spawn(head_client);
    let ar = socket.socket_accept(lfd);
    if ar.is_ok {
      var hctx2 = app.hookctx_new();
      var hhooks = app.hooks_new();
      app.handle_connection_with_ctx(ar.value, handler_ok, &hhooks, &mut hctx2);
      socket.socket_close(ar.value);
    }
    var hf: Int = -1;
    match hc.join() { Ok(v) => { hf = v; } Err(_) => { hf = 1; } }
    fails = check(ar.is_ok && hf == 0,
      "HEAD: headers only (GET Content-Length 11, zero body bytes)", fails);
    socket.socket_close(lfd);
  } else {
    fails = check(false, "HEAD: no loopback port available", fails);
  }

  var resp = slice.str_bytes("HTTP/1.1 200 OK\r\n");
  var with_hdr = http.with_header_line(&resp, "X-Test: 1");
  var hdr_line = slice.str_bytes("X-Test: 1\r\n");
  var contains = false;
  var i: Int = 0;
  while i + hdr_line.len() <= with_hdr.len() && !contains {
    var j: Int = 0;
    var ok_here: Bool = true;
    while j < hdr_line.len() {
      if with_hdr[i + j] != hdr_line[j] { ok_here = false; j = hdr_line.len(); } else { j = j + 1; }
    }
    if ok_here { contains = true; }
    i = i + 1;
  }
  fails = check(contains, "build: with_header_line appends the wire header", fails);

  io.println("");
  io.println("probe_package_pulse: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
