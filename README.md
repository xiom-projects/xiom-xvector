<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# xiom-vector

> Production-grade vector database engine for XIOM -- dense vectors, distance metrics, flat + HNSW ANN search, collections, segments, and a WAL-backed durable write path, built on the shared `xiom-core` durable-systems substrate.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-vector is organized as a **layered engine** rather than a flat set of files. It reuses `xiom-core` (errors, ids, config, limits, contracts, WAL, metrics) as its durable-systems substrate and adds the vector-specific layers on top: types, storage, indexes, query, collections, payload/filtering, segments, durability, and a public API facade.

The engine's working core -- dense-vector math, the three distance metrics, the exact flat/brute-force search, and the in-memory HNSW graph -- is fully implemented today. Higher layers (collections, segments, payload filtering, durable recovery) are typed and scaffolded against the roadmap.

See:
- [`ARCHITECTURE.md`](ARCHITECTURE.md) -- the shared-core + vector-layer model, module tree, write/search paths, failure domains.
- [`ROADMAP.md`](ROADMAP.md) -- the Phase 0-10 plan and honest status of every capability.
- [`COLLECTIONS.md`](COLLECTIONS.md) -- the user-facing collection schema model.
- [`SPEC.md`](SPEC.md) -- module-by-module reference.
- [`docs/`](docs/) -- deep dives (engine, core-vs-vector, metrics, HNSW, segments, filtering, query execution, contracts, errors).

## Installation
```bash
xiom install xiom-vector
```

## Quick Start
```xiom
use xiom.vector.engine;

fn main() -> Int {
  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);

  var v = Vector.new(3);
  v.set(0, 1.0); v.set(1, 0.0); v.set(2, 0.0);
  upsert(&mut eng, 1, v);

  var q = Vector.new(3);
  q.set(0, 0.9); q.set(1, 0.1); q.set(2, 0.0);
  var hits = search(&eng, &q, 5);   // Result[SearchHits, CoreError]
  return 0;
}
```

## Module Tree

```
src/
|-- error.xi                  VectorError taxonomy (-> CoreError)
|-- ids.xi                    PointId + reuse of core Collection/Vector/SegmentId
|-- engine.xi                 VectorEngine orchestrator (real dispatch)
|-- types/                    dense_vector - metric - neighbor - dimension
|-- collection/               schema - collection - validator
|-- payload/                  payload - filter_ast - filter_eval
|-- storage/                  vector_store - id_map
|-- segment/                  segment_state - segment - manifest
|-- index/                    ann_index - flat_index - hnsw
|-- distance/                 cosine - dot - l2
|-- query/                    search_request - topk_heap - search_service
|-- durability/               write_ahead_events
`-- api/                      vector_api (public facade)
```

## Public API (`xiom.vector.engine`)
| Function | Description |
|----------|-------------|
| `create_collection(eng, dim, metric)` | Create the active collection; fixes dimension + metric |
| `upsert(eng, point, vec)` | WAL-durable insert/update of a point (payload-encoded vector in the record) |
| `search(eng, query, k)` | Exact top-k nearest neighbours; returns `Result[SearchHits, CoreError]` (`SearchHits { items: Vec[SearchResult] }`) |
| `delete_point(eng, point)` | Remove a point |
| `get_point(eng, point)` | Fetch a stored vector by id |
| `engine_recover(wal, dim, metric)` | Recovery/reopen: replay a WAL, rebuild the store, continue the log (compacted checkpoint) |

All fallible calls return `Result[T, CoreError]`. The `SearchHits` struct
wrapper is required by compiler finding XVC-C-04
(`Result[Vec[non-scalar]]` payloads lose element fields on v0.64.0).

## Production Readiness
| Capability | Status |
|-----------|--------|
| Dense vector math (dot/cosine/euclidean/normalize/...) | [OK] Done |
| Distance metrics + dispatch | [OK] Done |
| Flat exact KNN + range search | [OK] Done |
| In-memory HNSW graph (insert + greedy search) | [OK] Done |
| Bounded top-K heap | [OK] Done |
| Engine orchestration (create/upsert/search/delete) | [OK] Done |
| WAL-before-ack write path | [YELLOW] In progress (in-memory WAL + payload-encoded vectors + recovery replay; `fsync` blocked on the stdlib fd-syscall gap) |
| Collections / schema / validator | [YELLOW] In progress (single active collection) |
| Segments + lifecycle state machine | [ORANGE] Scaffold (types + transitions) |
| Payload + metadata filtering | [ORANGE] Scaffold (AST + fail-open eval) |
| Durable recovery / manifest | [ORANGE] Scaffold (WAL replay + compacted checkpoint done in-memory; durable manifest pending) |
| IVF / PQ / disk-backed / SIMD | [STOP] Not started |

Full detail in [`ROADMAP.md`](ROADMAP.md).

## Dependencies
- `xiom-std` -- standard library
- `xiom.math` -- `sqrt` for magnitude/euclidean/cosine
- `xiom-core` -- shared errors, ids, config, limits, contracts, WAL, metrics

## Links: [github.com/xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/XIOM-lang/XIOM.git )
## License: MIT OR Apache-2.0
