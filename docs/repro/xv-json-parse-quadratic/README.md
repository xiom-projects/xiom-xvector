<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# stdlib `json_parse` is superlinear on large numeric payloads

Found 2026-10-11 by the xvector lane while running the first end-to-end
benchmark through `xvectord` (compiler v0.64.3, stdlib `2ab2a13`).

**ROOT CAUSE (same day, deeper bisect): `slice.str_bytes(Str)` is
superlinear in string size.** Sweep (`probe_strbytes.xi`):
50 KB -> 88 ms, 100 KB -> 324 ms, 200 KB -> 939 ms, 400 KB -> 3685 ms
(2x size -> ~3.5-4x time: quadratic). `str_slice` of a small window is
cheap, so the class is the full-string/char-stepped conversion and the
char-indexed accesses the JSON parser uses per token (`_json_get_char`,
per-number substring slices) -- each token access costs O(offset), which
makes a document with N numbers O(N^2). `http_parse_request` showed the
same shape (8.5 s of its own on a 382 KB request) before the lane moved
the body to bytes.

## xvector lane mitigation (shipped 2026-10-11, 72nd pass)

The service no longer round-trips bodies through `Str`:
- `HttpRequest.body_bytes` (linear byte copy from the request buffer)
  + `body` (one `from_utf8`, which is linear-fast);
- the canonical upsert body is scanned directly on bytes
  (`api.json_fast.json_fast_upsert_bytes`), with a byte-for-byte
  fast-vs-strict equivalence gate (228 cases incl. mutations);
- measured effect: a 5,000 x dim-25 fit through `xvectord` went from
  661 s to 120 s (now HNSW-build-bound, not parser-bound); a 352 KB
  single request handles in ~1.7-2.9 s (strict: ~84 s).

The stdlib fix should make `str_bytes`/`str_slice` linear and the JSON
token accesses O(1); the lane re-runs both probes + the batteries on the
fix.

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

## Ask for the stdlib lane (confirmed, not hypotheses any more)

1. `slice.str_bytes(Str)` / full-string conversions: linear
   (O(n)) with one pass; the sweep above is the acceptance (`probe_strbytes.xi`).
2. Character access used by the JSON parser (`_json_get_char` and the
   per-token `str_slice`): O(1) per access, so the existing
   `probe.xi` (10,000-number parse) returns to ms scale.
3. `http_parse_request`'s body extraction in xvector is already patched
   (bytes); the stdlib-side readiness matters for other consumers
   (pulse HTTP paths, orbitdb payloads).

## Lane status while this is open

- All workarounds stay: small upsert batches; benchmark docs marked
  "single-writer, parser-blocked" until fixed.
- The xvector lane is evaluating a lane-local fast numeric-array scanner
  for the upsert hot path (recognize the common body shape and skip the
  generic parser) so benchmarks can run before the stdlib fix lands.
