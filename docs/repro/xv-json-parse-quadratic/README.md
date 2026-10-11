<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# stdlib `json_parse` is superlinear on large numeric payloads

Found 2026-10-11 by the xvector lane while running the first end-to-end
benchmark through `xvectord` (compiler v0.64.3, stdlib `2ab2a13`).

## Symptom (measured)

- `json_parse` of a **382,397-byte** body (50,000 numbers, the
  `{"ids":[...],"vectors":[[...]]}` upsert shape): **83.7 s**.
- Full in-process service handle on the same body: **94.9 s** — the
  parser is ~88% of the cost; the engine itself inserts 2,000 dim-25
  vectors in ~4 s (2 ms/insert).
- Scaling sweep (this repro, `probe.xi`, 2026-10-11 v0.64.3:
  2,500 numbers / 22 KB -> **299 ms**; 5,000 / 44 KB -> **1.07 s**;
  10,000 / 88 KB -> **4.56 s**; 20,000 / 175 KB -> **~18 s**. 2x input
  -> ~3.6-4.3x time: **quadratic**.
- Server impact: a 1,000-point dim-25 upsert (25,000 numbers) takes
  ~112 s through `xvectord` (~9 points/s); a 5,000-point fit takes
  661 s. Benchmark integration (ann-benchmarks/VectorDBBench) is
  blocked on this: real datasets (10k-1M vectors) are unusable.

## Repro (revision-pinned, self-contained)

```
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-json-parse-quadratic\probe.xi -Name repro_json_quad
.\out\repro_json_quad.exe
```

Pre-fix status: the sweep prints as above and exits **1** (the largest
parse exceeds the 5 s gate; the whole run takes ~2 minutes).
Post-fix expectation: ms-scale parses, exit **0**.

## Hypotheses for the fixer

- number/token lexing that scans or rebuilds the remaining input per
  token (quadratic token pointer handling), and/or
- per-token `Str` concatenation (allocating a fresh string per number),
  and/or
- array push into a structure whose append is linear (copying the array
  per element).
A quick discriminator: parse one equally-large JSON *string* value vs
many small tokens -- if the string case is fast, the cost is per-token.

## Lane status while this is open

- All workarounds stay: small upsert batches; benchmark docs marked
  "single-writer, parser-blocked" until fixed.
- The xvector lane is evaluating a lane-local fast numeric-array scanner
  for the upsert hot path (recognize the common body shape and skip the
  generic parser) so benchmarks can run before the stdlib fix lands.
