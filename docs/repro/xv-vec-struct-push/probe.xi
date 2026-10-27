// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-23 repro (v0.65.2): a NAMED local struct with a Vec field, pushed
// into a Vec[Struct], has its Vec freed at scope exit even though the Vec
// element still references it. The inline-literal form is green.
//
// Build/run:
//   .\scripts\build.ps1 docs\repro\xv-vec-struct-push\probe.xi -Name repro_vec_struct_push
//   .\out\repro_vec_struct_push.exe
// Expected (fixed): named-literal bad=0, inline-literal bad=0, PASS, exit 0.
// Observed on v0.65.2 (Windows): named-literal bad=32 first=0, FAIL, exit 32.
// Control v0.65.1: both bad=0, PASS, exit 0.

module repro_vec_struct_push

use xiom.io;
use xiom.convert;

pub type R = {
  id: Int;
  xs: Vec[Int];
}

fn main() -> Int {
  var rs = Vec[R].new();
  var i: Int = 0;
  while i < 32 {
    var xs = Vec[Int].new();
    xs.push(i);
    xs.push(i + 100);
    var r = R{ id: i, xs: xs };
    rs.push(r);
    // Force allocator reuse if the pushed Vec was wrongly dropped.
    var junk = Vec[Int].with_len(8);
    junk[0] = 999;
    i = i + 1;
  }
  var bad: Int = 0;
  var first: Int = -1;
  i = 0;
  while i < rs.len() {
    if rs[i].id != i { bad = bad + 1; if first < 0 { first = i; } }
    if rs[i].xs.len() != 2 {
      bad = bad + 1;
      if first < 0 { first = i; }
    } elif rs[i].xs[0] != i || rs[i].xs[1] != i + 100 {
      bad = bad + 1;
      if first < 0 { first = i; }
    }
    i = i + 1;
  }
  io.println("named-literal bad=" + convert.int_to_string(bad)
    + " first=" + convert.int_to_string(first)
    + " records=" + convert.int_to_string(rs.len()));

  var rs2 = Vec[R].new();
  i = 0;
  while i < 32 {
    var ys = Vec[Int].new();
    ys.push(i);
    ys.push(i + 200);
    rs2.push(R{ id: i, xs: ys });
    var junk2 = Vec[Int].with_len(8);
    junk2[0] = 777;
    i = i + 1;
  }
  var bad2: Int = 0;
  i = 0;
  while i < rs2.len() {
    if rs2[i].id != i { bad2 = bad2 + 1; }
    if rs2[i].xs.len() != 2 {
      bad2 = bad2 + 1;
    } elif rs2[i].xs[0] != i || rs2[i].xs[1] != i + 200 {
      bad2 = bad2 + 1;
    }
    i = i + 1;
  }
  io.println("inline-literal bad=" + convert.int_to_string(bad2)
    + " records=" + convert.int_to_string(rs2.len()));

  if bad == 0 && bad2 == 0 {
    io.println("PASS vec-struct-push");
    return 0;
  }
  io.println("FAIL vec-struct-push");
  return bad + bad2;
}
