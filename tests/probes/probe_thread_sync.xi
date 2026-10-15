// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// G-1 thread + sync smoke (v0.64.5: the real-spawn thread gate is GREEN, so
// the lane gets its first cross-thread acceptance in CI). Promotes the
// docs/repro/xv-thread-abi acceptance and adds the sync smoke:
//   1) spawn/join: 3 workers return exact values; a worker's OS thread id
//      differs from main; available_parallelism() >= 1.
//   2) mutex-guarded shared counter: 4 workers x 500 increments through the
//      real spinlock (xiom.sync.mutex) -> exact total, no lost updates.
//   3) atomic counter: 4 workers x 500 atomic_fetch_add -> exact total.
//   4) channel contract (same-thread): bounded capacity, FIFO order, close
//      semantics. The CROSS-THREAD producer/consumer leg is deferred: the
//      channel is a Vec-backed value with no handle form and no internal
//      lock, so sharing it across real threads needs the XVC-C-17 fix
//      (or an explicit lock around a future handle-based channel).
// NOTE (XVC-C-17, REL-20261015-2216-xvector): module-level vars whose type
// is an IMPORTED struct drop pointer fields on assignment, so the shared
// handles travel as Int globals and are reconstructed as local handles
// inside each worker (validated pattern; see docs/repro/xv-global-ptr-field).
// Exit = failed checks (0 = green).

module probe_thread_sync

use xiom.thread;
use xiom.sync.mutex;
use xiom.sync.atomics;
use xiom.sync.channel;
use xiom.io;
use xiom.convert;

// Shared state (Int handles; see the XVC-C-17 note above).
var G_LOCKP: Int = 0;      // address of the SyncMutex owner flag
var G_ATOM_ADDR: Int = 0;  // address of the AtomicInt cell
var G_COUNT: Int = 0;      // guarded by the spinlock
var G_ITERS: Int = 500;    // per-worker iterations

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// ---- part 1: spawn/join acceptance ----------------------------------------

fn work_ten() -> Int { return 10; }
fn work_twenty() -> Int { return 20; }
fn work_thirty() -> Int { return 30; }
fn work_whoami() -> Int { return current_thread_id(); }

// ---- part 2: mutex-guarded counter -----------------------------------------

fn bump_locked() -> Int {
  var p: *Int = null;
  unsafe { p = G_LOCKP as *Int; }
  var m = mutex.SyncMutex{ locked: p };
  var i: Int = 0;
  while i < G_ITERS {
    mutex.mutex_lock(&mut m);
    G_COUNT = G_COUNT + 1;
    mutex.mutex_unlock(&mut m);
    i = i + 1;
  }
  return 0;
}

// ---- part 3: atomic counter ------------------------------------------------

fn bump_atomic() -> Int {
  var p: *Int = null;
  unsafe { p = G_ATOM_ADDR as *Int; }
  var a = atomics.AtomicInt{ ptr: p };
  var i: Int = 0;
  while i < G_ITERS {
    atomics.atomic_fetch_add(&mut a, 1);
    i = i + 1;
  }
  return 0;
}

fn main() -> Int {
  io.println("=== xvector probe: thread + sync smoke (G-1) ===");
  var fails: Int = 0;

  // Part 1: real spawn/join.
  var h1 = spawn(work_ten);
  var h2 = spawn(work_twenty);
  var h3 = spawn(work_thirty);
  var r1: Int = -1;
  var r2: Int = -1;
  var r3: Int = -1;
  match h1.join() {
    Ok(v) => { r1 = v; }
    Err(e) => { io.println("  join1 Err " + e); }
  }
  match h2.join() {
    Ok(v) => { r2 = v; }
    Err(e) => { io.println("  join2 Err " + e); }
  }
  match h3.join() {
    Ok(v) => { r3 = v; }
    Err(e) => { io.println("  join3 Err " + e); }
  }
  io.println("  sums: " + convert.int_to_string(r1) + "+" + convert.int_to_string(r2)
    + "+" + convert.int_to_string(r3));
  fails = check(r1 == 10 && r2 == 20 && r3 == 30, "spawn/join: 3 workers return exact values", fails);

  var main_id = current_thread_id();
  var hw = spawn(work_whoami);
  var wid: Int = -1;
  match hw.join() {
    Ok(v) => { wid = v; }
    Err(e) => { io.println("  joinw Err " + e); }
  }
  fails = check(wid != main_id && wid > 0,
    "spawn: worker OS thread id != main (" + convert.int_to_string(wid) + " vs "
    + convert.int_to_string(main_id) + ")", fails);
  fails = check(available_parallelism() >= 1, "available_parallelism >= 1", fails);

  // Part 2: mutex-guarded counter (4 x 500 = 2000).
  var m0 = mutex.mutex_new();
  unsafe { G_LOCKP = m0.locked as Int; }
  G_COUNT = 0;
  fails = check(G_LOCKP != 0, "sync setup: spinlock handle installed", fails);
  if G_LOCKP != 0 {
    var a = spawn(bump_locked);
    var b = spawn(bump_locked);
    var c = spawn(bump_locked);
    var d = spawn(bump_locked);
    var ja: Int = -1;
    var jb: Int = -1;
    var jc: Int = -1;
    var jd: Int = -1;
    match a.join() { Ok(v) => { ja = v; } Err(_) => {} }
    match b.join() { Ok(v) => { jb = v; } Err(_) => {} }
    match c.join() { Ok(v) => { jc = v; } Err(_) => {} }
    match d.join() { Ok(v) => { jd = v; } Err(_) => {} }
    var expected = G_ITERS * 4;
    io.println("  mutex counter: " + convert.int_to_string(G_COUNT) + " (expect "
      + convert.int_to_string(expected) + "), joins " + convert.int_to_string(ja + jb + jc + jd));
    fails = check(G_COUNT == expected, "mutex: 4 workers x 500 -> exact total, no lost updates", fails);
  }

  // Part 3: atomic counter (4 x 500 = 2000).
  var at0 = atomics.atomic_int_new(0);
  unsafe { G_ATOM_ADDR = at0.ptr as Int; }
  fails = check(G_ATOM_ADDR != 0, "sync setup: atomic cell installed", fails);
  if G_ATOM_ADDR != 0 {
    var e = spawn(bump_atomic);
    var f = spawn(bump_atomic);
    var g = spawn(bump_atomic);
    var h = spawn(bump_atomic);
    match e.join() { Ok(_) => {} Err(_) => {} }
    match f.join() { Ok(_) => {} Err(_) => {} }
    match g.join() { Ok(_) => {} Err(_) => {} }
    match h.join() { Ok(_) => {} Err(_) => {} }
    var p: *Int = null;
    unsafe { p = G_ATOM_ADDR as *Int; }
    var av = atomics.AtomicInt{ ptr: p };
    var aval = atomics.atomic_load(&av);
    var aexpected = G_ITERS * 4;
    io.println("  atomic counter: " + convert.int_to_string(aval) + " (expect "
      + convert.int_to_string(aexpected) + ")");
    fails = check(aval == aexpected, "atomics: 4 workers x 500 fetch_add -> exact total", fails);
  }

  // Part 4: channel contract (same-thread; the cross-thread leg is blocked
  // by XVC-C-17 -- see the header note).
  var ch = channel.channel_new[Int](4);
  fails = check(channel.channel_capacity(&ch) == 4 && channel.channel_len(&ch) == 0,
    "channel: new(cap=4) -> cap 4, empty", fails);
  var s1ok = true;
  var sr1 = channel.channel_send(&mut ch, 11);
  var sr2 = channel.channel_send(&mut ch, 22);
  var sr3 = channel.channel_send(&mut ch, 33);
  var sr4 = channel.channel_send(&mut ch, 44);
  match sr1 { Ok(_) => {} Err(_) => { s1ok = false; } }
  match sr2 { Ok(_) => {} Err(_) => { s1ok = false; } }
  match sr3 { Ok(_) => {} Err(_) => { s1ok = false; } }
  match sr4 { Ok(_) => {} Err(_) => { s1ok = false; } }
  var full = channel.channel_try_send(&mut ch, 55);
  fails = check(s1ok && channel.channel_len(&ch) == 4 && !full,
    "channel: 4 sends fill cap 4; try_send when full -> false", fails);
  var got: Int = 0;
  var fifo_ok = true;
  var want: Int = 11;
  var recvs: Int = 0;
  while recvs < 4 {
    match channel.channel_recv(&mut ch) {
      Some(v) => { got = got + 1; if v != want { fifo_ok = false; } want = want + 11; }
      None => { recvs = 4; }
    }
    recvs = recvs + 1;
  }
  fails = check(fifo_ok && got == 4, "channel: FIFO 11,22,33,44 for 4 recvs", fails);
  channel.channel_close(&mut ch);
  var none_ok = true;
  match channel.channel_recv(&mut ch) {
    Some(_) => { none_ok = false; }
    None => {}
  }
  var send_after_close = channel.channel_send(&mut ch, 66);
  var err_ok = false;
  match send_after_close { Ok(_) => {} Err(_) => { err_ok = true; } }
  fails = check(none_ok && err_ok && channel.channel_is_closed(&ch),
    "channel: close -> recv None, send Err", fails);

  io.println("");
  io.println("probe_thread_sync: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
