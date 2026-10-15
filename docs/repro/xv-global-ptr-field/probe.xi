// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-17 repro: a module-level `var` whose declared type is a struct from
// an IMPORTED module SILENTLY DROPS pointer-typed fields on whole-struct
// assignment (a local-type control works). Found while building the G-1
// thread + sync smoke: `var G_M: mutex.SyncMutex = ...; G_M = mutex_new();`
// reads back `locked == null` everywhere, so the lock is never shared (the
// stdlib requires abort: "contract violated: requires at line 52").
//
// Observed (v0.64.5, Windows + WSL): checks A and B FAIL (pointer dropped);
// the local-type controls (C/D) pass. Expected (correct): all pass.
//
// Run (from the repo root):
//   . .\scripts\dev-env.ps1
//   .\scripts\build.ps1 docs\repro\xv-global-ptr-field\probe.xi -Name repro_global_ptr
//   .\out\repro_global_ptr.exe
//   WSL: bash scripts/build.sh docs/repro/xv-global-ptr-field/probe.xi repro_global_ptr
//        ./out/repro_global_ptr

module repro_global_ptr

use xiom.sync.mutex;
use xiom.io;
use xiom.convert;

// Local-type control (C/D): same pointer-fetch shapes as A/B below.
type Mixed = { p: *Int; v: Int; }

// A: imported struct type (xiom.sync.mutex.SyncMutex = { locked: *Int; }).
var GA: mutex.SyncMutex = mutex.SyncMutex{ locked: null };
// B: same imported type, assigned from the module's own constructor.
var GB: mutex.SyncMutex = mutex.SyncMutex{ locked: null };
// C/D: the local-type control.
var GM: Mixed = Mixed{ p: null; v: 0 };

fn hptr() -> *Int {
  var p: *Int = null;
  unsafe { p = 64 as *Int; }   // never dereferenced; only tested for null
  return p;
}

fn a_null() -> Bool { return GA.locked == null; }
fn b_null() -> Bool { return GB.locked == null; }
fn m_null() -> Bool { return GM.p == null; }
fn m_v() -> Int { return GM.v; }

fn main() -> Int {
  io.println("=== xvector probe: imported-type global struct stores (XVC-C-17 repro) ===");
  var fails: Int = 0;

  // A: imported type + const pointer.
  GA = mutex.SyncMutex{ locked: hptr() };
  if a_null() {
    io.println("  [FAIL] A imported-type global store: pointer DROPPED (locked null)");
    fails = fails + 1;
  } else {
    io.println("  [PASS] A imported-type global store keeps the pointer");
  }

  // B: imported type + cross-module call-return struct.
  GB = mutex.mutex_new();
  if b_null() {
    io.println("  [FAIL] B imported-type global store from mutex_new(): DROPPED (locked null)");
    fails = fails + 1;
  } else {
    io.println("  [PASS] B imported-type global store from mutex_new() ok");
  }

  // C: control -- local type, same shapes.
  GM = Mixed{ p: hptr(); v: 9 };
  if m_null() {
    io.println("  [FAIL] C local-type global store: pointer DROPPED");
    fails = fails + 1;
  } else {
    io.println("  [PASS] C local-type global store keeps the pointer");
  }
  if m_v() == 9 {
    io.println("  [PASS] C2 scalar field persists (v=9)");
  } else {
    io.println("  [FAIL] C2 scalar field lost (v=" + convert.int_to_string(m_v()) + ")");
    fails = fails + 1;
  }

  io.println("");
  io.println("repro_global_ptr: " + convert.int_to_string(fails) + " failed checks");
  if fails == 0 { return 0; }
  return 1;
}
