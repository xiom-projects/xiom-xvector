// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Minimal JSON number read isolation for XVC 1243. Run on v0.64.8 and
// v0.64.9; expected d values are 3.73975348472595 (top-level and object)
// and 42 (integral object).
//
// Build:
//   .\scripts\build.ps1 docs\repro\xv-json-read-min\probe.xi -Name repro_json_min
//   .\out\repro_json_min.exe

module repro_json_min

use xiom.convert;
use xiom.serialize.json;
use xiom.io;

fn read_d(v: Str) -> Float64 {
  var out: Float64 = -999.0;
  var p = json.json_parse(v);
  match p {
    Ok(x) => {
      io.println("render=" + json.json_stringify(x));
      io.println("type=" + json.json_type(x));
      match json.json_get(x, "d") {
        Some(Number(n)) => {
          io.println("match_n=" + convert.float_to_string(n));
          out = n;
        }
        Some(_) => { io.println("not_number"); }
        None => { io.println("no_d"); }
      }
    }
    Err(e) => { io.println("parse_err=" + e); }
  }
  return out;
}

fn main() -> Int {
  var pn = json.json_parse("3.73975348472595");
  var top_d: Float64 = -999.0;
  match pn {
    Ok(Number(n)) => { top_d = n; }
    Ok(_) => { io.println("top_not_number"); }
    Err(e) => { io.println("top_parse_err=" + e); }
  }
  io.println("top_d=" + convert.float_to_string(top_d));

  var inputs = Vec[Str].new();
  inputs.push("3.73975348472595");
  inputs.push("{\"d\":3.73975348472595}");
  inputs.push("{\"d\":42}");
  var i: Int = 0;
  while i < inputs.len() {
    var v = inputs[i];
    var d = read_d(v);
    io.println("input=" + convert.int_to_string(i) + " d=" + convert.float_to_string(d));
    i = i + 1;
  }
  var ok = read_d("{\"d\":3.73975348472595}") == 3.73975348472595;
  if ok { io.println("PASS"); return 0; }
  io.println("FAIL");
  return 1;
}
