<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-06 repro: Float32 enum payloads read as 0 in some builds

Compiler: **v0.64.0** (Windows; WSL reported the same family via XVC-C-05).
Same family as XVC-C-05: the failure is decided **per compilation unit /
build**, tag preserved, payload zeroed. No diagnostic.

## Observed shapes (2026-10-08)

1. **Suite unit** (`tests/test_conformance.xi`, 156 checks): a directly
   constructed FloatVal extracted as 0.0. Temporarily instrumented
   `run_filter_range_inclusive`:

   ```
   DBG direct_f=0        # float_bits(FieldValue.FloatVal(10.0)) -> 0
   DBG stored_f=0        # same after payload_set + payload_get
   DBG kind=float        # the enum TAG is intact
   ```

   All TextVal/IntVal/BoolVal payload checks in the same unit were green.
2. **Engine-import probe unit** (`tests/probes/probe_filtered_search.xi`):
   with FloatVal prices, 2 of 3 fresh builds failed the FloatVal
   Range/And checks with wrong results; the current build prints the
   diagnostic line

   ```
   diag FloatVal(2.5) roundtrip bits=0 (expected 4612811918334230528)
   ```

   while the IntVal/TextVal/Bool checks pass. Rebuilds can flip green/red
   (XVC-C-05 behaviour).
3. A small standalone probe with the same filter code was green in several
   builds — the trigger needs the larger unit; a minimal standalone repro is
   not yet found (compiler-lane reduction requested).

## Reproduce

```powershell
. .\scripts\dev-env.ps1
# 1) run the engine-import probe a few builds; watch the diag line
1..3 | % { & $env:XIOM_COMPILER -o "out\pfs$_.exe" tests\probes\probe_filtered_search.xi; & "out\pfs$_.exe" | Select-String "FloatVal|failed checks" }
```

To re-observe the suite-unit form, add a temporary block to
`run_filter_range_inclusive` (kept out of the tree now):

```xiom
var direct = FieldValue.FloatVal(10.0);
match direct { FloatVal(df) => { io.println("DBG direct_f=" + int_to_str(float.float_bits(df as Float64))); } _ => {} }
```

## Lane workaround (adopted)

- Payload gating assertions use IntVal / TextVal / BoolVal fields.
- FloatVal roundtrip is a **diagnostic print, not a gate**, in
  `probe_filtered_search.xi` until the compiler fix lands.
- Every evidence build is re-verified (XVC-C-05 build-rejection rule).
