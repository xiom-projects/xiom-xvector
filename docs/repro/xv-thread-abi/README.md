<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.thread real-spawn gate -- compiles green, AVs at the runtime entrypoint (v0.64.3)

Found 2026-10-11 (G-phase groundwork pass) by the xvector lane while
probing the threading primitives for the concurrency phase.

## Question

Can a consumer start REAL OS threads through `xiom.thread`'s
extern-backed `spawn[T]` / `JoinHandle.join`? The `xiom.thread.spawn`
module documents a simulation ("the current toolchain cannot start real
OS threads -- fn-to-pointer casts are rejected and the runtime thread
entrypoint AVs"), so the lane pinned the real path as a gate probe for
the G phase.

## Result on v0.64.3 (installed lane-local)

- **Compile: GREEN** -- `let raw_fn = f as *UInt8;` (thread.xi:46) is
  accepted; the unit builds on Windows and WSL.
- **Run: ACCESS VIOLATION** -- exit `-1073741819` (`0xC0000005`) on
  Windows; `Segmentation fault (core dumped)` on WSL.
- **Fault localization (`probe_marks.xi`)** -- marks rewrite
  `out/thread_abi_mark.txt` at each stage; the last surviving mark is
  **`M2: spawn returned`**: the handle IS created, then `join` (worker
  entry / completion path) never yields `M3`, and the worker's own
  `W0: worker entered` mark never appears. The AV is in the
  worker-entry/join machinery, not in the cast or the spawn call.
- The pure-math variant (`probe.xi`, no marks) crashes identically
  (stdout buffering hides it; the marks variant proves the stages).

## Acceptance (exit 0)

- 3 workers return exact distinct sums through `JoinHandle.join`;
- a worker's `current_thread_id()` differs from the main thread's id
  (real OS thread, not inline simulation);
- `available_parallelism() >= 1`.

## Re-run trigger

The next compiler archive install. The in-flight fn-value ABI batch
(m263-m265 / `fde5548e`, "fn-typed values survive every marshal (f as
Int = address, re-pass to extern...)") is the expected unblocker for the
marshal half; the runtime thread entrypoint may need a runtime-side fix
in the same release. On green: promote `probe.xi` into `tests/probes/` +
both batteries and flip the lane's G-phase plan from gated to
actionable (it also gates the stdlib's `xiom.thread.spawn` simulation
flip).

## Files

- `probe.xi` -- the acceptance probe (exit = failed checks; compiles
  green, AVs at run on v0.64.3; bus witness
  `REL-20261011-1627-xvector`).
- `probe_marks.xi` -- forensics variant writing
  `out/thread_abi_mark.txt` (last mark: `M2: spawn returned`).
