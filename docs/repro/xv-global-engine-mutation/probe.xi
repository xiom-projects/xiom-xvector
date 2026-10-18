// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-20 repro: mutations through `&mut` on a module-level VectorEngine
// global do NOT persist. engine_create_named returns Ok, but
// engine_collection_count still reads 0; a second create with the SAME name
// also returns Ok (the first collection vanished). G-2b (threaded accept
// loop) needs the engine to be shared by worker threads; this blocks the
// natural imported-type global pattern until the compiler keeps the state.
//
// Expected: count after create = 1; second create Err "collection exists";
// exit 0. Observed on v0.64.7 Windows: count 0; second create Ok; exit 1.
//
// Run:
//   .\scripts\build.ps1 docs\repro\xv-global-engine-mutation\probe.xi -Name repro_global_engine_mutation
//   .\out\repro_global_engine_mutation.exe

module repro_global_engine_mutation

use xiom.io;
use xiom.convert;
use xiom.mem;
use xiom.vector.primitives;
use xiom.vector.engine.core;

// Non-allocating zero literal (the shape that builds and runs; the bug is
// the lost mutation, not the initializer).
var G_ENGINE: VectorEngine = mem.zeroed[VectorEngine]();

fn main() -> Int {
  G_ENGINE = engine_new();
  let c = engine_create_named(&mut G_ENGINE, "scratch", 3, DistanceMetric.Cosine);
  match c {
    Ok(_) => {}
    Err(e) => {
      io.println("create failed: " + e.msg);
      return 2;
    }
  }
  let n = engine_collection_count(&G_ENGINE);
  io.println("count after create = " + convert.int_to_string(n) + " (expected 1)");
  io.flush_stdout();

  let c2 = engine_create_named(&mut G_ENGINE, "scratch", 3, DistanceMetric.Cosine);
  var second = "";
  match c2 {
    Ok(_) => { second = "Ok (BUG: the first create vanished)"; }
    Err(e2) => { second = "Err " + e2.msg; }
  }
  io.println("second create = " + second);
  io.flush_stdout();

  if n == 1 { return 0; }
  return 1;
}
