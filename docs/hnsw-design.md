<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# HNSW Design

`src/index/hnsw.xi` -- the approximate nearest-neighbour (ANN) index. This
documents the current (working, layer-0) implementation and the production
TODOs from [`../ROADMAP.md`](../ROADMAP.md) (Phase 4).

## What HNSW is

Hierarchical Navigable Small World is a multi-layer proximity graph. Layer 0
holds every node; each higher layer holds an exponentially thinning random
subset. Search enters at the top, greedily descends to the closest node on each
layer, then does a wider search on layer 0. This yields sub-linear query time
with high recall.

## Current implementation (v0.64.1 era): the layer-0 core

The bootstrap's nested-graph attempt hit 15 T001 borrow errors (field access
on `&layer.nodes[i]` inside nested loops; see `AUDIT.md`). The working
implementation stores the graph as **flat parallel arrays** instead; no nested
aggregate struct is ever borrowed:

```
HNSWGraph {
  ids:     Vec[Int];      // position -> user id
  vectors: Vec[Vector];   // position -> vector (index-aligned with ids)
  adj:     Vec[Int];      // row-major m slots per node: adj[pos*m + slot]
  deg:     Vec[Int];      // live slots are 0 .. deg[pos]
  m:       Int;           // max degree (hnsw_new requires m > 0)
  ml:      Float32;       // reserved for level assignment (requires > 0.0)
  entry:   Int;           // entry position, -1 when empty
}
```

Adjacency rows are fixed-capacity: a full block is pruned by **replacing its
farthest live edge** when the incoming edge is closer (the standard simple
heuristic). `adj`/`deg` hold positions; results and `best` lists hold
positions internally, and `hnsw_search` maps them to user ids on output
(`Neighbor.id`).

## Parameters

| Param | Meaning | Typical | Status |
|-------|---------|---------|--------|
| `m` | Max edges per node. | 16 | enforced: `hnsw_new requires: m > 0`; production bound <= `core.limits.max_graph_degree()` (512) via `AnnParams` |
| `ml` | Level multiplier (P(level >= l) ~= `ml^(-l)`). | 4.0 | reserved for level assignment (next hardening step) |
| `ef` | Query-time beam width (`hnsw_search` arg). | 64 | **honoured**: breadth = `max(k, ef)` |
| `ef_construction` | Build-time beam width. | 200 | not needed yet: construction is exact k-NN (see below) |

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
  recall@10 for ef=64 and ef=8 against the flat oracle.

## Build path (`hnsw_insert`)

1. Append the node (`ids`/`vectors`), reserve `m` adjacency slots, `deg = 0`.
2. First node becomes the entry point.
3. **Exact k-NN selection** -- brute-force the `m` nearest existing nodes
   (positions), bounded-insert into a sorted best list.
4. **Connect bidirectionally** -- for each selected position, add directed
   edges both ways; each side prunes a full block by replacing its farthest
   edge when the new edge is closer.
5. A dimension mismatch vs the first inserted vector is ignored (the engine
   validates dimensions upstream).

This build is O(n^2) in the same sense as a brute-force k-NN graph build, but
it produces high-quality layer-0 edges; recall on the harness workload is
100% at ef=64. `ef_construction` becomes meaningful once construction switches
to beam-based insertion (multi-layer hardening).

## Search path (`hnsw_search`)

1. Empty graph or dimension mismatch -> empty result (no contract trap).
2. Best-first beam from `entry`: `frontier` (positions, ascending) and
   `results` (user ids, ascending), both bounded by `breadth = max(k, ef)`.
3. Pop the closest frontier candidate; when `results` is full and the popped
   candidate is farther than the current worst result, stop (done-flag; the
   language has no `break`).
4. Expand unvisited neighbours; push into `results`/`frontier` when the beam
   is not full or the candidate beats the worst result.
5. Return the first `k` results as `Vec[Neighbor]` (`ensures: len <= k`).

## Contracts

- `hnsw_new` -- `m > 0`, `ml > 0.0`.
- `hnsw_search` -- `k > 0`, and `result.len() <= k`.
- Neighbour selection caps adjacency at `m` (the graph-degree invariant; see
  [`contracts-and-invariants.md`](contracts-and-invariants.md)).
- Cold/empty graph returns an empty result -- never panics.

## Current simplifications (and the production TODOs)

| Area | Now (working) | Production (Phase 4) |
|------|---------------|----------------------|
| Layers | single layer (layer-0 core); `ml` reserved | level assignment + top-down descent |
| Build | brute-force exact k-NN per insert + farthest-edge prune | beam insertion honouring `ef_construction`, diversified pruning (`neighbor_closer`) |
| Search | best-first beam honouring `ef` | top-layer greedy descent, adaptive ef |
| Metric | metric-agnostic via `vector_distance` | unchanged (done) |
| Node position lookup | linear `hnsw_find_node_pos` | id -> position map |
| Deletes | not supported | tombstones + edge repair |
| Persistence | in-memory only | serialized into sealed segments |
| Engine wiring | module + harness only | `search_execute` Hnsw route / collection index kind |

The flat index remains the truth oracle; the recall harness validates the
graph against it at every build (gates: recall@10 >= 0.85 at ef=64, >= 0.50
at ef=8, cosine >= 0.60).
