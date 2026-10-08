<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# RELAY -> COMPILER (from XVECTOR, 2026-10-08)

**From:** XVECTOR lane, `E:\xiom-projects\xiom-xvector` (private; owner relays).
**Toolchain:** XIOM Compiler v0.64.0 on Windows (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`)
and WSL Ubuntu (`~/.local/bin/xiom`); stdlib lane `E:\xiom-lang\stdlib` (`9e64302`).

**Please read:** `docs/COMPILER-FINDINGS-XVECTOR.md` in the xvector repo, with
minimal repro bundles under `docs/repro/`:
- `docs/repro/xv-fnptr-call-inttoptr/`
- `docs/repro/contract-trap-exit0/`
- `docs/repro/xv-result-vec-struct/`
- `docs/repro/xv-f32-int-miscompile/` (includes a WSL matrix runner)

**Five findings, all reproducible on the shipped v0.64.0:**

| ID | One-liner | Severity |
|---|---|---|
| XVC-C-01 | `fn(f: &fn() -> T)` called as `f()` -> invalid IR (`inttoptr ptr to ptr`, clang exit 1); `(*f)()` -> runtime access violation. Struct-field fn pointers are green. | high |
| XVC-C-02 | A runtime `requires` violation prints `contract violated: ...` and **exits 0** (silent-green CI; our suite died mid-run once). | high |
| XVC-C-03 | W004 "unreachable match arm" false-positive on every unit-enum arm after the first (18+ in our suite). | low (noise) |
| XVC-C-04 | `Result[Vec[non-scalar], E]` / `Option[Vec[non-scalar]]` payload loses element fields (structs read 0, Str address-like); wrapping the Vec in a struct is green. | high |
| XVC-C-05 | **Priority.** Per-build nondeterministic lowering: Float32 arithmetic on `Vec[Float32]` becomes **integer arithmetic on the IEEE-754 bit patterns** (red build computes `0x3F666666 x 0x3F800000`); flips green/red with irrelevant byte changes and with `--sequential` in both directions, Windows and WSL. | critical |

**Re-run recipe (Windows, from the repo root):**

```powershell
. .\scripts\dev-env.ps1
1..3 | % { & $env:XIOM_COMPILER -o "out\pf$_.exe" docs\repro\xv-f32-int-miscompile\probe_failing.xi; & "out\pf$_.exe" | Select-String "diag p2 dot" }
```

plus the per-bundle READMEs. WSL: `bash docs/repro/xv-f32-int-miscompile/linux_matrix.sh 3`.

**Asks:** (1) triage XVC-C-05 first (silent wrong numerics; we suspect a
unit-hash/emission-order dependency in the int/float lowering decision);
(2) re-test all five bundles at the next archive so XVECTOR can re-pin and
report per-row deltas. No XVECTOR-side changes are needed to reproduce.

Context: the lane builds a durable vector database; its distance kernel is
exactly the XVC-C-05 shape, and its test harness was exactly the XVC-C-01
shape (both worked around, see SESSION.md).
