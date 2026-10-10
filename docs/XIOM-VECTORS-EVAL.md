<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.vectors 0.1.0 evaluation + wiring -- 2026-10-10

`xiom.vectors` 0.1.0 is the registry extraction of this lane's own
primitives ("dense vectors, cosine/dot/L2 distance, normalization,
bounded top-K, WAL value codec"), published by the packages lane from
XVECTOR at commit `8a8b0ff` (the rate-adoption wrap). This slice wired
the dependency, verified extraction fidelity, and gated the package
surface. **Verdict: wired + gated now; the internals swap is scheduled
as its own migration slice (below).**

## 1. Fidelity -- extraction pins all match

The package SPEC pins the SHA256 of every extracted source file at
extraction time. All six match the current tree byte-for-byte:

| XVECTOR source | Pin vs tree |
| --- | --- |
| `src/types/dense_vector.xi` | MATCH (`02ed09a1...`) |
| `src/types/metric.xi` | MATCH (`af18ae1c...`) |
| `src/types/neighbor.xi` | MATCH (`ba6d9ade...`) |
| `src/types/dimension.xi` | MATCH (`9c1e7e33...`) |
| `src/query/topk_heap.xi` | MATCH (`5a2863a0...`) |
| `src/storage/vector_store.xi` (codec, L156/L169) | MATCH (`d20f5c26...`) |

The package is therefore **a byte-exact carve of our code**: adopting it
is behavior-identical by construction (same pure-XIOM arithmetic, same
Float32 bit paths, same metric codes 1/2/3, same codec layout
`[dim, bits...]`). Reference-only patterns (recovery replay loop, probe
template, suite acceptance sections) keep their local forms.

## 2. What this slice did

- `xiom.toml`: `[dependencies] xiom.vectors = "0.1.0"`; installed into
  the lane-local package home on Windows and WSL.
- New gate `tests/probes/probe_package_vectors.xi` (**13 checks**):
  exact dot/magnitude/euclidean/cosine/dot-product distance on
  exactly-representable corpora, normalize zero/unit behavior, metric
  code round-trip + unknown fallback, dimension validity 1..65536,
  bounded top-K ordering + eviction (worst moves 10 -> 11 on a 0.5
  arrival), codec shape + element-exact round-trip, torn-skip replay.
  Wired into both batteries -- **37 probes** now.
- Ran the package's own `tests/probes/probe_codec_roundtrip.xi` from the
  lane home: **GREEN** (4/4 elements bit-exact including -0.0, a
  denormal and Float32 max; `encode(decode(encode(v)))` idempotent; torn
  payload rejected).
- Evidence: suite 171/171 x2 + sbom + **37 probes x2** + bench smoke,
  Windows AND WSL, ALL GATES GREEN.

The lane probes (through the local modules) and `probe_package_vectors`
(through the package) assert the **same arithmetic constants** -- the
cross-check without importing both same-named surfaces into one unit.

## 3. Internals swap -- migration plan (future slice)

**Atomicity constraint (XVC-C-14, found while planning):** the package
defines `Vector`, `DistanceMetric`, `Neighbor`, `Dimension` and
`TopKHeap` -- the same short names as the local modules. A **partial**
swap (e.g. only `Neighbor` switched to the package while local
`Vector`/`dense_vector` is still compiled) puts two same-named type
families into one program: exactly the short-name layout-shadow shape
that cost a build in the xiom.metrics adoption. The migration therefore
swaps **every extracted surface in one atomic step** -- never a partial
introduction of `xiom.vectors` alongside the local modules, in any
program.

Adopting the package's code in place of the local copies is a
mechanical, behavior-identical refactor, but it touches ~45 files
(every consumer's import line; the type is used across
engine/HNSW/payloads/probes), so it runs as its own atomic slice:

1. Replace the local-module imports (`xiom.vector.types.dense_vector`,
   `types.metric`, `types.neighbor`, `types.dimension`,
   `query.topk_heap`, `storage.vector_store` codec) with
   `use xiom.vectors;` in every consumer, in one change set.
2. Delete the local bodies: `types/dense_vector.xi`, `types/metric.xi`,
   `types/neighbor.xi`, `types/dimension.xi`, `query/topk_heap.xi`
   (already unused in-lane -- nothing but the package probe calls its
   functions), and strip the codec functions from
   `storage/vector_store.xi` (its internal encode/decode calls resolve
   to the package through the new import).
3. The extraction pins guarantee no semantic delta; the full batteries +
   suite keep every numeric gate (169-check suite, 37 probes).
4. The recovery replay loop can delegate to `vectors_replay_into` at
   value level when the store migration (D-ledger) lands.
5. Preconditions: owner greenlight (`-12`) and a **quiet battery
   window** (the change set is tree-wide: no long-lived broken
   intermediate state), single signed commit.

## 4. Notes

- Module-shape: consumer units import only one side of the same-named
  surface at a time (lane facades or the package), consistent with the
  `xiom.metrics` adoption note; `probe_package_vectors` is a
  single-import unit.
- The package carries no contracts/clauses, no externs, no unsafe
  (SPEC); our lane modules keep their existing comments until the
  facade swap.
