<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Benchmarks -- xiom-xvector (M-G)

Methodology, the in-repo harness, and the committed baseline. Every number
here names the workload, dataset configuration, platform and toolchain (the
honesty rule from `docs/PRODUCTION-PLAN.md` §5).

## How to run

- Windows: `.\scripts\bench.ps1 -Mode quick|medium|full` (default medium)
- WSL: `bash scripts/bench.sh quick|medium|full`
- CI smoke: `-Mode quick` runs inside `scripts/ci.ps1` / `scripts/ci.sh`
  as an additional gate.
- Env knobs: `XV_BENCH_MODE` (mode), `XV_BENCH_OUT` (JSON path, default
  `out/bench_report.json`), `XV_BENCH_STAGE=w1|w2|w4a|w6|w3|w4b|w5`
  (diagnostic: stop after that workload).
- Output: human table on stdout + a JSON report with integer units only
  (us, counts, permille, bytes).

## Method (honest notes)

- **Clock:** `xiom.time.monotonic_ms` (QPC on Windows, CLOCK_MONOTONIC on
  Linux; ms resolution). `xiom.time.Instant` is second-resolution by
  design and is NOT used.
- **Per-query workloads** (flat knn, filtered, range, hnsw per ef): a group
  size is calibrated (double until one group takes >= 2 ms, capped at 256),
  then 21 timed groups run; each sample stores per-op microseconds
  (`ms*1000/group`). p50/p95/p99 are the 11th/20th/21st sorted samples
  (approximate tails). QPS is derived from p50.
- **Whole-run workloads** (ingest, HNSW build, recovery): the full loop is
  timed; short loops repeat passes (capped) until >= 2 ms.
- **Recall:** overlap@k against the exact flat store scan on the same query
  set, per-mille.
- **bytes/vector:** checkpoint file bytes / n (disk proxy, not RSS).
- **Inputs:** deterministic LCG; the same mode reproduces identical data.
- **Memory safety:** all loop budgets are hard-capped; the harness is
  monitored during development. A full medium run peaks ~287 MB RSS.
- **Kernel fidelity (M-G1):** `probe_reference_oracle` cross-checks the
  distance kernels against an independent Float64 oracle on seeded data;
  measured deviations are Float32-ulp scale and bit-identical across
  platforms (cosine 1.70e-07, dot 9.83e-07, euclidean 5.06e-07), so the
  measured numbers below are kernel-faithful, not kernel-dependent.

## Baseline (2026-10-09)

- **Host:** DESKTOP-0OJEN1F -- AMD Ryzen 9 3950X (16C/32T), 128 GB RAM,
  Windows 11 Pro 26200. WSL2 (kernel 6.6.87.2-microsoft-standard-WSL2) for
  the Linux spot.
- **Toolchain:** compiler v0.64.2 (tag `c51170a6`); stdlib lane `1b85edb`;
  xvector state: range M-Q1 + batch M-Q2 + the M-G `wal_persist` linear
  builder fix (`src/durability/wal_file.xi`).
- **Configuration:** dim=4, Cosine; Flat for exact workloads, Hnsw (default
  params, m=16) for ANN; k=10; ef sweep {32, 64, 128}; n=5000; 200 queries.
- **Units:** p50/p95/p99 in milliseconds (ms) or microseconds (us) as noted.

| Workload | Result |
|---|---|
| W1 ingest (Flat, single upserts) | ~2.5M points/s (2 ms / 5000; ~0.4 us/point) |
| W2 exact KNN (Flat, k=10) | p50 **10.7 ms**, p95 12.1 ms, p99 13.2 ms (~93 qps) |
| W4 filtered (Flat, 50% `In`) | p50 **65.9 ms** (linear fit) |
| W4 filtered (Flat, 10% `Eq`, index plan) | p50 **1.13 ms** (~58x faster than the 50% scan) |
| W6 range r=0.6 | p50 **18.8 ms**, avg 198 hits |
| W6 range r=1.2 | p50 **62.3 ms**, avg 505 hits |
| W3 HNSW build (5000 x dim-4) | **13.0 s** |
| W3 HNSW ef=32 | recall **1.000**, p50 **0.44 ms** (~2288 qps) |
| W3 HNSW ef=64 | recall **1.000**, p50 **0.63 ms** (~1600 qps) |
| W3 HNSW ef=128 | recall **1.000**, p50 **1.03 ms** (~969 qps) |
| W4 filtered on Hnsw (10% `Eq`) | p50 **2.81 ms** |
| W5 batch upsert (1000 pts) | single ~0.5 us/op vs `upsert_many` < 0.125 us/op (per-op, quantized) |
| W5 batch search (100 queries) | 211 ms single vs 220 ms `search_many` (~1.0x) |
| W7 recovery | checkpoint 1.68 s / 762 KB; load+recover 12.6 s (HNSW rebuild dominates); 152 bytes/vector |

**Reading the numbers (honest):**

- These are **pure-XIOM, single-threaded, unoptimized-kernel** numbers --
  a baseline, not a finished performance story. The flat scan costs about
  ~2 us per candidate at dim 4; at n=5000 HNSW is ~10-24x faster than the
  exact scan with perfect recall on this synthetic set.
- Filtered `Eq` uses the sorted payload index (58x faster than the linear
  majority scan); range search is exact (linear scan) by construction.
- HNSW build (13 s / 5k) is the main build-time cost; SIMD/BLAS (M-P3)
  and index tuning target it.
- `upsert_many` amortizes per-op overhead (sub-0.125 us/op at 100-pt
  chunks); `search_many` is a convenience batching (no throughput win).
- Recovery includes rebuilding the HNSW graph from the replayed log
  (12.6 s / 5k); checkpoint write is 1.68 s for 762 KB.

## Fixed while building this (M-G finding)

`wal_persist` built the checkpoint with repeated `text = text + ...`
concatenation -- **O(L^2) total allocations** in a runtime whose allocator
retains temporaries long enough to thrash (the C-PULSE-14 family). At
~150 KB checkpoints this drove the machine into multi-GB paging (observed
during harness bring-up; killed at a 2 GB guard). It now appends into a
`Vec[UInt8]` linearly (`append_bytes`); `probe_wal_file` gained 4 scale
checks (1200-record append/persist/load/roundtrip). Checkpoint time is
~1.7 s / 762 KB on this host -- linear, still unoptimized.

## Cross-platform spot (WSL)

The quick mode runs green on WSL2 (same workloads, same recall); quick
checkpoint 762 ms / 225 KB vs 473 ms Windows. Full WSL parity is enforced
by `scripts/ci.sh` (bench smoke + suite x2 + all probes x2).

## What the owner's benchmark can use

- Deterministic modes + JSON report (`out/bench_report.json`) today.
- Dataset shape: synthetic LCG is built in; real-data importers
  (fvecs/JSONL/CSV) and the HTTP service protocol arrive with M-S/M-G
  follow-ups (`docs/PRODUCTION-PLAN.md` §5).
