<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# HNSW Design

`src/index/hnsw.xi` -- the approximate nearest-neighbour (ANN) index. This
documents the current (working, multi-layer) implementation and the
production TODOs from [`../ROADMAP.md`](../ROADMAP.md) (Phase 4).

## What HNSW is

Hierarchical Navigable Small World is a multi-layer proximity graph. Layer 0
holds every node; each higher layer holds an exponentially thinning random
subset. Search enters at the top, greedily descends to the closest node on each
layer, then does a wider search on layer 0. This yields sub-linear query time
with high recall.

## Current implementation: multi-layer, flat-array layout

The bootstrap's nested-graph attempt hit 15 T001 borrow errors (field access
on `&layer.nodes[i]` inside nested loops; see `AUDIT.md`). The working
implementation stores the graph as **flat parallel arrays**; no nested
aggregate struct is ever borrowed:

```
HNSWGraph {
  ids:     Vec[Int];      // position -> user id
  vectors: Vec[Vector];   // position -> vector (index-aligned with ids)
  levels:  Vec[Int];      // position -> assigned top layer (0..7)
  id_keys: Vec[Int];      // sorted unique ids (id map)
  id_vals: Vec[Int];      // id_keys[i] -> position
  adj:     Vec[Int];      // (pos, layer) rows, m slots each
  deg:     Vec[Int];      // one degree counter per (pos, layer) row
  m:       Int;           // max degree per layer
  ml:      Float32;       // level multiplier (probability 1/ml per level)
  entry:   Int;           // position of the highest-level node, -1 empty
}
```

Row/base math (fixed capacity of `hnsw_layer_capacity()` = 8 layers per
node): `row(pos, layer) = pos * 8 + layer` indexes `deg`; the adjacency
block for that row starts at `row * m`; live slots are `0 .. deg[row]`.
Rows above a node's assigned level keep degree 0. A full block is pruned by
**replacing its farthest live edge** when the incoming edge is closer.
Adjacency holds positions; `hnsw_search` maps to user ids on output
(`Neighbor.id`).

## Parameters

| Param | Meaning | Typical | Status |
|-------|---------|---------|--------|
| `m` | Max edges per node per layer. | 16 | enforced (`hnsw_new requires: m > 0`); production bound <= `core.limits.max_graph_degree()` (512) via `AnnParams` |
| `ml` | Level multiplier (P(level >= l) ~= `ml^(-l)`). | 4.0 | **honoured** by the deterministic level assignment |
| `ef` | Query-time beam width (`hnsw_search` arg). | 64 | **honoured**: breadth = `max(k, ef)` |
| `ef_construction` | Build-time beam width. | 200 | **honoured** by the construction beam (clamped to >= `m`) |

`AnnParams` (in `index/ann_index.xi`) carries `m`, `ef_construction`, and
`ef_search`; `ann_params_valid` bounds `m` by the shared core graph-degree limit.

## Parameter Tuning Ranges

The table above lists point defaults; production tuning moves within these
ranges. Each parameter trades off memory, construction cost, and runtime
recall/latency.

| Param | Range | Default | Effect of increasing |
|-------|-------|---------|----------------------|
| `M` (graph degree) | 16-32 | 16 | Better recall, more memory. |
| `ef_construction` | ~= 2xM, up to ~200 | 200 | Better graph quality, slower build. |
| `ef_search` (query breadth) | 64-128 | 64 | Better recall, higher latency. |

- **How to tune:** benchmark **recall@k** and **p99 latency** against your
  target workloads and adjust within these ranges. The recall harness
  (`tests/probes/probe_hnsw_recall.xi`) is the instrument: it prints
  recall@10 for ef=64 and ef=8 plus the average visited-node count against
  the flat oracle.

## Build path (`hnsw_insert`)

1. Append the node; assign its level from the `ml` geometric with a
   deterministic LCG seeded by the position. The test uses HIGH bits: the
   LCG's low bits are degenerate (after `s % 4 == 0` the next sample is
   always `1 mod 4`, making level >= 2 impossible).
2. Reserve 8 layer rows (degrees 0, slots zeroed). The first node becomes
   the entry.
3. **Greedy descent** from the top entry down to the new node's level + 1.
4. For every layer from `min(level, top)` down to 0: a **beam search**
   (`search_layer_build`, width = `max(m, ef_construction)`) collects
   candidates, the **diversified heuristic** (`select_diverse`) keeps up to
   `m` that are closer to the new node than to every already-selected
   neighbour, and edges are added bidirectionally. A full existing block is
   pruned with the same heuristic over (existing + incoming). The closest
   candidate becomes the entry for the next layer down.
5. Layers above the existing top have no peers yet (the node is alone
   there); if the new level exceeds the entry's, the node becomes the new
   entry.

`ef_construction` (default 200, `hnsw_set_ef_construction`; values < 1 are
ignored) trades build quality for cost; the engine seeds it from
`AnnParams`.

## Search path (`hnsw_search`)

1. Empty graph or dimension mismatch -> empty result (no contract trap).
2. **Greedy descent**: from `entry` (highest level), walk each layer above 0
   to its local minimum (`greedy_layer`); the node exists on every lower
   layer, so it carries into the next.
3. **Layer-0 beam**: best-first expansion from the descended node;
   `frontier` (positions) and `results` (user ids), both bounded by
   `breadth = max(k, ef)`; stop when the closest frontier candidate is
   farther than the current worst result and the beam is full (done-flag;
   the language has no `break`).
4. Return the first `k` results as `Vec[Neighbor]` (`ensures: len <= k`).
   `hnsw_search_visited` exposes the touched-node count (latency proxy).

## Deletes (`hnsw_delete`)

Tombstones: `hnsw_delete(id)` marks the position dead (the `deleted`
vector); the node keeps its edges and keeps routing traffic, but
`hnsw_search` never adds it to results. Deleting an unknown or
already-deleted id returns `false`. `hnsw_live_count` reports the
non-deleted node count. Re-inserting an id updates the vector in place and
revives the node, and **refreshes its edges** for the new vector (per-layer
beam through the old structure, diversified replacement, bidirectional
re-link; landed 2026-10-09). `hnsw_compact(g, metric)` rebuilds the graph
from the live nodes only (same
`m`/`ml`, insertion order preserved): tombstones are dropped, edges are
rebuilt around the survivors, and their slots are reclaimed. The engine
wrapper is `compact_index` (Flat -> 0 reclaimed).

## Persistence (graph codec)

`hnsw_encode(g) -> Vec[Int]` / `hnsw_decode(words) -> Option[HNSWGraph]` is
a deterministic word codec mirroring the WAL style: header
(`version=2, m, ml_bits, ef_construction, layer_capacity, entry,
node_count`), then per node`id, level, deleted, vector words` (via `storage.vector_store.vector_encode`)
followed by every layer row's degree + neighbor positions. Decode is
strict: truncated, tampered, out-of-range, or trailing-junk input returns
`None` (torn-record tolerance), `m > 512` (AnnParams max degree) and
`count > words.len()` are rejected, and the pad step lives behind
`pad_adj_slots` (XVC-C-10: the inline loop segfaulted at larger `m`). The
codec is the step before file-backed graph segments (stdlib fd/fsync
pending); today the engine still rebuilds the graph from the flat store on
load, which the codec will replace.

## Contracts

- `hnsw_new` -- `m > 0`, `ml > 0.0`.
- `hnsw_search` -- `k > 0`, and `result.len() <= k`.
- Neighbour selection caps adjacency at `m` per layer (the graph-degree
  invariant; see [`contracts-and-invariants.md`](contracts-and-invariants.md)).
- Cold/empty graph returns an empty result -- never panics.

## Harness results (2026-10-08, compiler v0.64.1)

`tests/probes/probe_hnsw_recall.xi` (deterministic LCG data, dim=8, k=10):

| Dataset | ef | recall@10 | notes |
|---|---|---|---|
| n=200 | 64 | 300/300 | avg visited 170/200; levels L0=149 L1=40 L2=9 L4=2 |
| n=200 | 8 | 296/300 | beam clamped to breadth 10 |
| n=200 cosine | 64 | 100/100 | metric-agnostic smoke |
| n=800 | 64 | 200/200 | avg visited 299/800, top level 4 |
| n=200, id 42 deleted | 64 | 300/300 | stray42=0, live 199 (flat oracle also removed 42) |
| n=200, 50 ids deleted + compacted | 64 | 200/200 | size/live 150, stray_deleted=0; engine-level `compact_index` reclaims 1 with post-compact recall holding |

Gates: recall >= 0.85 (ef=64), >= 0.50 (ef=8), >= 0.60 (cosine), >= 0.80
(n=800). Delete checks: tombstone semantics, idempotent delete, never
returned, recall-after-delete, revive on re-insert, delete-all -> live 0 and
empty search. Full run ~2.4s.

Latency proxies: `hnsw_build_ops` counts construction distance ops (n=200:
62,129 ops, bounded by 4*n^2) and `hnsw_search_visited` feeds a per-ef table
(10 queries each): ef=8 -> 97/100 recall @ 63 visited; ef=16 -> 100/100 @
84; ef=32 -> 100/100 @ 126; ef=64 -> 100/100 @ 171; ef=128 -> 100/100 @
196 (of n=200).

## Current simplifications (and the production TODOs)

| Area | Now (working) | Production (Phase 4) |
|------|---------------|----------------------|
| Layers | **multi-layer** (8-layer capacity, geometric `ml`, greedy descent) | adaptive capacity / higher levels for very large n |
| Build | **beam insertion honouring `ef_construction` + diversified pruning; in-place update re-linking** | parallel/adaptive build, quantized distance |
| Search | greedy descent + beam honouring `ef`; per-ef visited/recall table | adaptive `ef`, latency budget |
| Metric | metric-agnostic via `vector_distance` | unchanged (done) |
| Node position lookup | **O(log n) sorted id map** (`id_keys`/`id_vals`; duplicates rejected) | unchanged |
| Deletes | **tombstones + `hnsw_compact`** (rebuild from live nodes, reclaim) | background/automatic compaction policy |
| Persistence | **word codec** (`hnsw_encode`/`hnsw_decode`, strict roundtrip) | file-backed graph segments (stdlib I/O), engine load path |
| Engine wiring | module + harness only | `search_execute` Hnsw route / collection index kind |

The flat index remains the truth oracle; the recall harness validates the
graph against it at every build.
