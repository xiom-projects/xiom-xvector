<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Reference study 01 -- FAISS HNSW mechanics vs. xvector (2026-10-11)

Owner-granted study area (`E:\repos`); FAISS is MIT (LICENSE verified
in-clone, `Copyright (c) Facebook, Inc.`). **No code is vendored and no
build dependency is added**: everything below is ideas/patterns to
re-implement in `src/index/hnsw.xi` under our license, each gated by our
own probes. Citations are `faiss/<path>:<line>` at the shallow-clone
revision (`--depth 1`, 2026-10-11).

## What was examined

| Area | FAISS source | xvector today |
|---|---|---|
| Level assignment | `faiss/impl/HNSW.cpp:63` `set_default_probas(M, 1.0/log(M))`; `:67` `random_level()` draws from a precomputed `assign_probas` table (float subtract loop) | deterministic per-insert LCG seeded by node position; `p(level >= l) ~ ml^-l`, fixed layer capacity 0..7 (documented in `src/index/hnsw.xi`) |
| Visited set | `faiss/impl/VisitedTable.h` + `:428` (subclass + comparator, `vt.set/advance` inlined; generation-tag reuse) | per-search visited tracking in the beam loop (re-allocated per call) |
| Neighbor selection | `faiss/impl/HNSW.cpp:245` `shrink_neighbor_list` (relative-neighborhood diversify; `keep_max_size_level0` keeps level-0 degree >= 2*M) | diversified pruning at build; level-0 degree bounded by M (tombstones excluded) |
| Memory mapping / zero-copy IO | `faiss/impl/mapped_io.h`, `zerocopy_io.h`, `io.h` (`IO_FLAG_MMAP` read path) | none (P5 gated on stdlib mmap) |
| Quantization | `faiss/impl/ProductQuantizer.*`, `ScalarQuantizer.*` | none (full-precision store + Float64 WAL codec) |

## Findings and proposals (ranked; none applied in this slice)

**F1 -- Level-0 degree generosity (`keep_max_size_level0`).** FAISS
deliberately avoids shrinking level-0 adjacency below `2*M` because
over-pruned level-0 links hurt connectivity/recall on hard queries.
*Ours:* level-0 is pruned like every layer (bounded by M, tombstones
excluded). *Proposal P-a:* allow generous level-0 degree (or `2*M` at
level 0 only) and re-measure with `probe_hnsw_recall` (n=200/800 corpora
+ the per-ef trade table in `docs/BENCHMARKS.md`). Cheap, measurable.

**F2 -- Generation-tag visited sets.** FAISS reuses one `VisitedTable`
per thread with tag increments, avoiding allocation per search; also
templates the table type + comparator for inlined checks
(`HNSW.cpp:428`). *Ours:* beam loop tracks visited per call. *Proposal
P-b:* an integer "visit epoch" array on the graph (no free-list clears)
before any concurrency work (M-P); gate: behavior-identical results on
`probe_engine_hnsw` + latency delta in the bench.

**F3 -- Precomputed cumulative level table.** *Ours:* per-node LCG with a
geometric draw is already deterministic and cheap; FAISS's table is a
micro-optimization. *Proposal P-c (low):* only if insert micro-benchmarks
(the per-build work counter exists) show the draw as material.

**F4 -- mmap/zero-copy IO design notes.** `mapped_io.h` documents the read
path (mmap + alignment + fallback), directly reusable as *design input*
for P5 once stdlib mmap lands. *Proposal P-d:* capture in the P5 slice's
design; do not pre-build.

**F5 -- Quantization path.** FAISS's SQ/PQ split (per-vector scalar codes
vs product codebooks + ADC tables) is the reference for compaction work
(study item 2). *Proposal P-e:* next study slice compares
`ScalarQuantizer`/`ProductQuantizer` against `sqlite-vec`'s quantized
brute-force kernels and writes a proposal for segment-size reduction
(D4/D6 territory; must keep `probe_reference_oracle` fidelity claims
honest under quantization error bounds).

**F6 -- Search templating (informational).** Compile-time dispatch over
distance comparators keeps FAISS's inner loops monomorphic. XIOM generics
are limited; noted as a reason our kernels stay simple scalar loops until
the compiler grows (no action).

## Explicit non-actions

- No PQ/SQ adoption before a quantized-fidelity story exists (our oracle
  gate demands documented error bounds).
- No lock-free/thread code (single-threaded engine; M-P owns concurrency).
- No vendoring: any adopted pattern lands as an original implementation in
  our tree with the usual probe gates, LICENSE unchanged, commit noting
  this study as the source.

## Next

1. P-a (level-0 degree) is the first candidate slice: implement behind the
   existing API, gate with `probe_hnsw_recall` + the per-ef table.
2. Study item 2: quantization reconnaissance (FAISS SQ/PQ + sqlite-vec) ->
   `docs/REFERENCE-STUDY-02-QUANTIZATION.md`.
3. Study items 3-4 (sqlite-vec kernels, DiskANN layout) remain queued.
