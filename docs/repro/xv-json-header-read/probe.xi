// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC 1243 follow-up: service-shaped read of a JSON number from an HTTP
// header. The compiler's standalone JSON repro is green; this probe keeps
// the HttpRequest -> http_header -> json_parse -> json_get shape that the
// L-6 shard used when it observed Number(0). v0.64.8 and v0.64.9 can both
// run it; no workaround is applied here.
//
// Build:
//   .\scripts\build.ps1 docs\repro\xv-json-header-read\probe.xi -Name repro_json_header
//   .\out\repro_json_header.exe

module repro_json_header

use xiom.convert;
use xiom.string.slice;
use xiom.serialize.json;
use xiom.io;
use xiom.vector.api.http_service;

fn read_distance(req: &HttpRequest) -> Float64 {
  match http_header(req, "x-xvector-after-distance") {
    Some(v) => {
      io.println("header=" + v);
      var p = json.json_parse(v);
      var doc = json.json_null();
      var ok: Bool = false;
      match p {
        Ok(x) => { doc = x; ok = true; }
        Err(e) => { io.println("parse_err=" + e); }
      }
      if ok {
        match json.json_get(doc, "d") {
          Some(Number(d)) => {
            io.println("d=" + convert.float_to_string(d));
            return d;
          }
          Some(_) => { io.println("d_not_number"); }
          None => { io.println("d_missing"); }
        }
      }
    }
    None => { io.println("header_missing"); }
  }
  return -999.0;
}

fn main() -> Int {
  var raw = "POST /search HTTP/1.1\r\nHost: t\r\n"
    + "x-xvector-after-distance: {\"d\":3.73975348472595}\r\n"
    + "Content-Length: 2\r\n\r\n{}";
  var b = slice.str_bytes(raw);
  var req = http_parse_request(b);
  var okstr = "false";
  if req.ok { okstr = "true"; }
  io.println("req_ok=" + okstr);

  // Arm 1: literal in main (the compiler's standalone shape).
  var lit = "{\"d\":3.73975348472595}";
  var lit_d: Float64 = -999.0;
  var lp = json.json_parse(lit);
  match lp {
    Ok(x) => {
      match json.json_get(x, "d") {
        Some(Number(n)) => { lit_d = n; }
        _ => { io.println("literal_d_not_number"); }
      }
    }
    Err(e) => { io.println("literal_parse_err=" + e); }
  }
  io.println("literal_d=" + convert.float_to_string(lit_d));

  // Arm 2: the header value copied through http_header in main.
  var hdr_d: Float64 = -999.0;
  match http_header(&req, "x-xvector-after-distance") {
    Some(v) => {
      var hp = json.json_parse(v);
      match hp {
        Ok(x) => {
          match json.json_get(x, "d") {
            Some(Number(n)) => { hdr_d = n; }
            _ => { io.println("header_d_not_number"); }
          }
        }
        Err(e) => { io.println("header_parse_err=" + e); }
      }
    }
    None => { io.println("header_missing"); }
  }
  io.println("header_d=" + convert.float_to_string(hdr_d));

  // Arm 3: the extracted helper shape.
  var d = read_distance(&req);
  if d == 3.73975348472595 && hdr_d == 3.73975348472595 && lit_d == 3.73975348472595 {
    io.println("PASS");
    return 0;
  }
  io.println("FAIL literal=" + convert.float_to_string(lit_d)
    + " header=" + convert.float_to_string(hdr_d)
    + " helper=" + convert.float_to_string(d));
  return 1;
}
