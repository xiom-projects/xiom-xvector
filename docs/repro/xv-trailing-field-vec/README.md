<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-08 -- trailing scalar after a Vec-bearing field reads as garbage

**Status: OPEN on compiler v0.64.1** (Windows + WSL; found 2026-10-08 by the
XVECTOR lane while adding `with_payload` hydration).

## Summary

In a `Vec[Struct]` where the element struct has a trailing scalar field after
a Vec-bearing field (`has_payload: Bool` after `payload: Payload` / `Vec[T]`),
reading that trailing field **can return uninitialized garbage** (observed:
`true`) instead of the stored value -- depending on the surrounding
compilation unit. The same source (`src/query/search_service.xi`
`hydrate_hits`) is correct in its own unit (`tests/probes/probe_search_request.xi`
green 8/8 fresh builds) but miscompiles in the big conformance-suite unit
(reads `true` for a hit that was never hydrated) and in this bundle.

It is a **silent wrong-result** defect: hydration flags (and by extension any
trailing scalar after a Vec field in a Vec element) cannot be trusted in
affected units.

## Bundle

- `probe.xi` -- the full `hydrate_hits` shape. With `with_payload=false` no
  hit may carry a payload, yet one reads as payload-bearing.
  Expected: exit 0. Observed: **exit 1 (`BAD detach count`), 5/5 builds.**
- `variants.xi` -- the minimization matrix. Exit code names the first failing
  variant. Observed on v0.64.1 (Windows, 1 build, deterministic):

  | Variant | Shape | Verdict |
  |---|---|---|
  | V1 scalar | `{ id; flag }` | green |
  | V2 bool-first | `{ id; flag; nodes: Vec }` | green |
  | V3 vec-first (no f32) | `{ id; nodes: Vec; flag }` | green |
  | V4 wrap-first | `{ id; wrap: Wrap; flag }` | green |
  | V5 hydrate-off | `{ id; distance; payload: Vec; flag }` + dead `if/match` | **RED (code 2)** |
  | V6 shape-only | V5 literal, no `if/match` | green |
  | V7 hydrate-wrapped | V5 with `payload: Wrap` | **RED (code 2)** |
  | V8 simple-if | `var have=false; if cond { have=true; }` | green |
  | V10 branch-split | pushes inside `if/match` branches | **RED (code 2)** |
  | V11 index-lookup | `if` + `if pos >= 0` (no Option/match) | **RED (code 2)** |
  | V12 two-phase | plain pushes + second attach loop | **RED (code 2)** |
  | V13 flag-first | `{ id; distance; flag; payload }` | green (in this unit) |
  | V14 int-flag | `{ id; distance; payload; flag: Int }` | **RED (code 2)** |

  `code 2` = the **second** element's flag reads `true`; the first reads
  correctly. V14 shows the trigger is not Bool-specific.
- `min.xi` -- scalar-only control (`Int` + `Bool`), green: plain struct
  pushes are fine; the defect needs the Vec-bearing field.

## Workaround (adopted by the lane)

- Do not assert trailing-scalar reads in affected units. The engine's
  hydration gate is the real-module probe
  (`tests/probes/probe_search_request.xi`, green 8/8 fresh builds); the
  conformance-suite mirror no longer asserts hydration flags and documents
  the defect instead (XVC-C-08 note in `tests/test_conformance.xi`).
- Declaring the scalar **before** the Vec field (V13) is green in this bundle,
  but NOT a general fix: applying that reorder to the suite unit produced an
  access violation (`0xC0000005`) instead. The defect is context-sensitive in
  both directions, so any layout workaround must be verified per unit.

## Repro recipe

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-trailing-field-vec\probe.xi -Name t08 -NoIcon
.\out\t08.exe; "exit=$LASTEXITCODE"      # expect 1 (BAD detach count)
.\scripts\build.ps1 docs\repro\xv-trailing-field-vec\variants.xi -Name t08v -NoIcon
.\out\t08v.exe; "exit=$LASTEXITCODE"     # expect 5 (first failing variant)
```

WSL: `bash scripts/build.sh docs/repro/xv-trailing-field-vec/probe.xi t08` then
`./out/t08`.

## Impact

Silent wrong query metadata: a hydrated search result can report a payload it
does not have (or read any trailing scalar after a Vec-bearing field
incorrectly), with no compiler diagnostic.
