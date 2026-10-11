// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Repro: `slice.str_bytes(Str)` is superlinear in string size (found
// 2026-10-11 as the ROOT CAUSE of the json-parse quadratic and of every
// Str-heavy service path). Builds Strs of growing size in a LINEAR byte
// buffer (no concat noise), times one `str_bytes` per size, and gates the
// 400 KB case at 500 ms (pre-fix: ~3.7 s, quadratic).
//
// Run: .\scripts\build.ps1 docs\repro\xv-json-parse-quadratic\probe_strbytes.xi -Name repro_strbytes
//      .\out\repro_strbytes.exe

module xiom.vector.repro_str_bytes_quadratic

use xiom.io;
use xiom.time;
use xiom.convert;
use xiom.string.slice;

fn main() -> Int {
  var fails: Int = 0;
  var sizes = Vec[Int].new();
  sizes.push(50000);
  sizes.push(100000);
  sizes.push(200000);
  sizes.push(400000);
  var last: Int = 0;
  var i: Int = 0;
  while i < sizes.len() {
    var n = sizes[i];
    var buf = Vec[UInt8].new();
    var k: Int = 0;
    while k < n {
      buf.push(65u8);
      k = k + 1;
    }
    var s = Str::from_utf8(&buf);
    var t0 = time.monotonic_ms();
    let b = slice.str_bytes(s);
    var dt = time.monotonic_ms() - t0;
    io.println("  len=" + convert.int_to_string(n)
      + " str_bytes_ms=" + convert.int_to_string(dt)
      + " bytes=" + convert.int_to_string(b.len()));
    last = dt;
    i = i + 1;
  }
  if last > 500 {
    fails = 1;
    io.println("  [FAIL] 400 KB str_bytes exceeds 500 ms (superlinear)");
  } else {
    io.println("  [PASS] 400 KB str_bytes under 500 ms");
  }
  io.println("repro_str_bytes_quadratic: exit=" + convert.int_to_string(fails));
  return fails;
}
