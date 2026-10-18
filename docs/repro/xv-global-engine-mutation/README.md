<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xv-global-engine-mutation -- module-level engine global loses mutations (v0.64.7)

**Symptom:** a module-level `var G_ENGINE: VectorEngine` can be assigned and
read, but mutations made through `&mut G_ENGINE` do not persist:

- `engine_create_named(&mut G_ENGINE, "scratch", 3, Cosine)` returns `Ok`;
- `engine_collection_count(&G_ENGINE)` still returns `0`;
- a second `engine_create_named` with the **same name** also returns `Ok`
  (the first collection vanished);
- a later `engine_upsert(&mut G_ENGINE, ...)` violates the engine's
  active-collection contract (`engine/core.xi:1297`).

**Witness (v0.64.7 Windows, 2026-10-18):**

- `probe.xi`: prints `count after create = 0 (expected 1)` and
  `second create = Ok (BUG: the first create vanished)`; exit 1.
- A global `Vec[Mini]` / `Vec[VectorEngine]` holder (tried as a workaround)
  crashes before `main` with exit `-2147483645` (0x80000003) and no output;
  globals of user-defined struct types with a `Vec` field are in the same
  XVC-C-19 family.
- A heap-cell workaround (typed pointer in a global + `ptr.read`/`ptr.write`)
  requires `ptr as *mut T`, which the compiler rejects outside `unsafe`; the
  lane's SBOM gate forbids adding `unsafe` to `src/`.

**Impact:** G-2b (in-process accept-loop threads, `XVECTORD_THREADS`) is
**BLOCKED**: worker threads cannot share the engine. The G-1 globals
(`SyncMutex`/`AtomicInt`, small pointer wrappers) still work; this defect is
specific to the large imported-type engine global (nested container fields).

**Expected:** count after create = 1; the second create fails with
"collection exists"; exit 0.

**Run:**

```
.\scripts\build.ps1 docs\repro\xv-global-engine-mutation\probe.xi -Name repro_global_engine_mutation
.\out\repro_global_engine_mutation.exe
```

**Filed:** bus item `REL-20261018-1815-xvector` (compiler lane).
