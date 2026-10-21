<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xv-pq-second-call -- second `Option[PQ]` return crashes (v0.64.8)

**STATUS (2026-10-21): OPEN on v0.64.8.** The P4 IVF-PQ prototype was
implemented and exposed a compiler memory bug; the prototype code is
reverted and this repro is retained.

## Symptom

The self-contained `probe.xi` trains a deterministic PQ codebook twice on
the same 2000x32 corpus:

- prints `built 2000`, then `first ok m=8`;
- the **second** `pq_train` call never completes: exit `-1073741819`
  (`0xC0000005`, access violation).

One call is green. A one-call `ivf_pq_build` (which calls `pq_train`
internally once) + search also runs, but the **nested codebook in the
returned index is corrupted** in the P4 probe: the codebook checksum
changed between two builds of the same data (`370608086` -> `534399819`),
the mean reconstruction L2 exploded (`0.84` -> `4.48e28`), and the
exact-rescore mode at `nprobe=nlist` returned recall `0.958-0.964` instead
of 1.0. The exact same source changed only by removing an unrelated Vec
field, which points at layout-sensitive aggregate/Vec handling.

## What does NOT reproduce

- A minimal `Option[Book]` where `Book` has one `Vec[Float32]`, called
  twice: green.
- A nested `Option[Outer{ inner: Inner{ xs: Vec }, ys: Vec }]`: green.
- The trigger is the PQ/k-means shape (multiple Float32/Int Vec
  allocations per call and a returned `Option[PQ]` with a Vec), not a
  generic Option/Vec return.

## Expected (fixed compiler)

The second call returns the same deterministic codebook; the program
prints `second ok m=8` and exits 0.

## Run

```
.\scripts\build.ps1 docs\repro\xv-pq-second-call\probe.xi -Name repro_pq_second_call
.\out\repro_pq_second_call.exe
```

**Filed:** bus item `REL-20261021-...-xvector` (compiler lane); P4 is
blocked until the fix (see SESSION section 1 / the production checklist).
