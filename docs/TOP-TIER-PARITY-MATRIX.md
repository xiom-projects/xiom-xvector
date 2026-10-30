<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# TOP-TIER PARITY -- working unit matrix (seed v0)

**Status:** seed matrix; not a frozen parity score.
**As of:** 2026-10-30
**Method and rules:** [`TOP-TIER-PARITY.md`](TOP-TIER-PARITY.md)

This file is the working table behind the parity vision. It starts with the
highest-signal units so the gap is actionable. The freeze pass expands it to
every unit the pinned references expose and replaces `candidate X` with the
per-reference `X_pkg` / `X_srv`.

**Reference commits:** FAISS `cec5702`, DiskANN `177c03b`, sqlite-vec
`04d28bd`, ann-benchmarks `2e081ad`, VectorDBBench `139f8a3`,
vector-db-benchmark `acedefd`. Standalone clones (Qdrant, Milvus, Weaviate,
pgvector/pgvectorscale, Vespa) are **pending** and must be pinned before
their `X` is final.

**Legend:** `Ref` = `P` package, `S` standalone, `B` both.
`P` = priority. `Pkg` / `Srv` = xvector status. `Have` requires evidence;
`Partial` counts as 0.5 until the owner sets a fraction; `N/A` = surface not
applicable.

| ID | Domain | Capability | Ref | P | Pkg | Srv | Evidence / gap |
|---|---|---|---|---|---|---|---|
| D1.VEC.F32 | Data model | Float32 dense vectors | B | P0 | Have | Have | suite + probe_reference_oracle |
| D1.VEC.F16 | Data model | Float16 vectors | P/S | P2 | Missing | Missing | add vector type + numeric tests |
| D1.VEC.I8 | Data model | Int8 vectors | B | P1 | Missing | Missing | add vector type + rescore semantics |
| D1.VEC.BIN | Data model | Binary/bit vectors | B | P1 | Missing | Missing | add type + Hamming/Jaccard |
| D1.VEC.SPARSE | Data model | Sparse vectors | S | P1 | Missing | Missing | inverted index + hybrid search |
| D1.VEC.NAMED | Data model | Named/multi-vector per point | S | P1 | Missing | Missing | multi-vector storage + query |
| D1.META.PAYLOAD | Data model | Typed payload/metadata | B | P0 | Have | Have | suite + probe_filtered_search |
| D1.META.PARTITION | Data model | Partition/namespace keys | B | P1 | Missing | Missing | partition key + pruning |
| D1.META.AUX | Data model | Auxiliary scalar columns | P/S | P2 | Missing | Missing | scalar columns independent of payload |
| D2.IDX.FLAT | Index | Exact Flat | B | P0 | Have | Have | suite + probe_reference_oracle |
| D2.IDX.HNSW | Index | HNSW ANN | B | P0 | Have | Have | probe_hnsw_recall + codec |
| D2.IDX.FILTER_AWARE | Index | Filter-aware search | B | P0 | Have | Have | probe_filter_plan |
| D2.IDX.SQ | Index | Scalar quantization | B | P1 | Partial | Partial | SQ8 only; add SQ4/SQ6 options |
| D2.IDX.IVF_FLAT | Index | IVF-Flat | P | P1 | Missing | Missing | reference-clone inventory first |
| D2.IDX.IVF_PQ | Index | IVF-PQ | P | P1 | Missing | Missing | P4 experimental; not shipped |
| D2.IDX.PQ_OPQ | Index | PQ/OPQ | P | P1 | Missing | Missing | add codec + rotation |
| D2.IDX.DISKANN | Index | DiskANN/Vamana / disk index | P/S | P1 | Missing | Missing | DiskANN clone is the reference |
| D2.IDX.GPU | Index | GPU indexes | P | P2 | Missing | Missing | no GPU path |
| D2.IDX.BINARY | Index | Binary indexes | P | P2 | Missing | Missing | after binary vectors |
| D2.IDX.SPARSE | Index | Sparse inverted index | S | P1 | Missing | Missing | hybrid/sparse search |
| D2.IDX.FULLTEXT | Index | Full-text index | S | P1 | Missing | Missing | BM25/full-text |
| D2.IDX.MULTIVEC | Index | Multi-vector/late interaction | S | P2 | Missing | Missing | ColBERT-style |
| D2.IDX.MMAP | Index | mmap/on-disk index | P/S | P1 | Partial | Partial | segments on disk, not mmap |
| D3.Q.KNN | Search | KNN top-k | B | P0 | Have | Have | suite + all probes |
| D3.Q.RANGE | Search | Range search | B | P0 | Have | Have | probe_range_search |
| D3.Q.BATCH | Search | Batch search | B | P0 | Have | Have | probe_batch_ops |
| D3.Q.PAGINATION | Search | Offset/cursor pagination | B | P0 | Have | Have | probe_pagination |
| D3.Q.SCORE_THRESHOLD | Search | Score/radius threshold | B | P0 | Have | Have | range path |
| D3.Q.NAMED_VECTOR | Search | Named-vector query | S | P1 | Missing | Missing | after named vectors |
| D3.Q.HYBRID | Search | Dense+sparse hybrid | S | P1 | Missing | Missing | fusion + rerank |
| D3.Q.RERANK | Search | Reranking | S | P1 | Missing | Missing | second-stage scorer |
| D3.Q.RECOMMEND | Search | Recommend/discover | S | P2 | Missing | Missing | positive/negative examples |
| D3.Q.GROUP_DIVERSITY | Search | Group-by/diversity | S | P2 | Missing | Missing | MMR/grouping |
| D3.Q.AGGREGATIONS | Search | Aggregations/facets | S | P2 | Missing | Missing | facet counts |
| D3.Q.SCROLL_EXPORT | Search | Scroll/export | S | P2 | Missing | Missing | bulk export |
| D4.F.EQ_RANGE_IN | Filtering | Equality/range/in/not | B | P0 | Have | Have | suite + probe_filtered_search |
| D4.F.NESTED_ARRAY_GEO | Filtering | Nested/array/geo filters | B | P1 | Partial | Partial | nested payloads exist; geo TBD |
| D4.F.FULLTEXT | Filtering | Full-text filter | S | P1 | Missing | Missing | shares full-text index |
| D4.F.PAYLOAD_INDEX | Filtering | Payload field indexes | B | P0 | Have | Have | probe_payload_index |
| D4.F.PARTITION_PRUNING | Filtering | Partition pruning | S | P1 | Missing | Missing | after partition keys |
| D5.P.WAL | Durability | WAL/fsync | B | P0 | Have | Have | probe_wal_file + kill matrix |
| D5.P.CHECKPOINT | Durability | Checkpoints | B | P0 | Have | Have | probe_wal_file |
| D5.P.SNAPSHOT | Durability | Snapshots | B | P0 | Have | Have | probe_snapshot |
| D5.P.COMPACTION | Durability | Segment compaction | B | P0 | Have | Have | probe_multisegment |
| D5.P.CRASH_RECOVERY | Durability | Crash recovery | B | P0 | Have | Have | probe_kill_recovery |
| D5.P.REPLICATION_LOG | Durability | Replication log/ship | S | P1 | N/A | Have | async replicas |
| D5.P.BACKUP_RESTORE | Durability | Backup/restore | S | P1 | N/A | Partial | snapshot files; no online backup |
| D5.P.PITR | Durability | Point-in-time recovery | S | P1 | N/A | Missing | needs a log/backup policy |
| D5.P.OBJECT_TIER | Durability | Object-store tiering | S | P2 | N/A | Missing | cold tier |
| D5.P.SCHEMA_MIGRATION | Durability | Schema migrations | S | P2 | N/A | Missing | collection schema evolution |
| D6.C.MVCC | Concurrency | MVCC/read snapshots | S | P0 | N/A | Missing | G-3; read-snapshot handle |
| D6.C.SNAPSHOT_ISOLATION | Concurrency | Snapshot isolation | S | P1 | N/A | Missing | after MVCC |
| D6.C.LINEARIZABLE | Concurrency | Linearizable writes | S | P1 | N/A | Partial | single-writer shard; no consensus |
| D6.C.TRANSACTIONS | Concurrency | Multi-point transactions | S | P2 | N/A | Missing | no transaction API |
| D6.C.VERSIONING | Concurrency | Optimistic versioning | S | P1 | N/A | Missing | point version/CAS |
| D6.C.GRACEFUL | Concurrency | Graceful shutdown/join | B | P0 | Have | Have | probe_concurrency |
| D6.C.BACKPRESSURE | Concurrency | Backpressure/bounded queues | S | P1 | N/A | Partial | bounded in-flight workers |
| D7.D.SHARDING | Distribution | Sharding | S | P0 | N/A | Have | hash split; L-6 |
| D7.D.REPLICATION | Distribution | Replication | S | P0 | N/A | Have | async replicas |
| D7.D.ROUTER | Distribution | Multi-node routing | S | P0 | N/A | Have | router v1 |
| D7.D.CONSENSUS | Distribution | Consensus/leader election | S | P1 | N/A | Missing | no Raft/Paxos |
| D7.D.RESHARDING | Distribution | Automatic rebalance | S | P1 | N/A | Partial | move/drain exists; no auto rebalance |
| D7.D.FAILOVER | Distribution | Automatic failover | S | P1 | N/A | Partial | manual promotion |
| D7.D.MULTI_REGION | Distribution | Multi-region | S | P2 | N/A | Missing | geo replication |
| D7.D.BILLION_DISK | Distribution | Billion-scale disk index | P/S | P1 | Missing | Missing | DiskANN-class index |
| D8.I.UPSERT | Ingestion | Upsert | B | P0 | Have | Have | suite + HTTP |
| D8.I.DELETE | Ingestion | Delete | B | P0 | Have | Have | suite + HTTP |
| D8.I.DELETE_FILTER | Ingestion | Delete-by-filter | B | P0 | Have | Have | probe_delete_filter |
| D8.I.BATCH | Ingestion | Batch operations | B | P0 | Have | Have | probe_batch_ops |
| D8.I.STREAMING | Ingestion | Streaming ingest | S | P1 | N/A | Missing | no stream/CDC |
| D8.I.TTL | Ingestion | TTL/retention | S | P2 | N/A | Missing | expiry policy |
| D8.I.ALIASES | Ingestion | Collection aliases | S | P2 | N/A | Missing | alias swap |
| D8.I.SCHEMA_EVOLUTION | Ingestion | Schema evolution | S | P2 | N/A | Missing | add/drop fields |
| D8.I.COMPACTION_POLICY | Ingestion | Compaction policy | B | P1 | Have | Have | seal/threshold policy |
| D8.I.UNLOAD | Ingestion | Unload/idle collection | S | P2 | N/A | Missing | memory lifecycle |
| D9.O.METRICS | Observability | Prometheus metrics | B | P0 | Have | Have | probe_metrics |
| D9.O.LOGS | Observability | Structured logs | S | P0 | N/A | Have | log ring |
| D9.O.HEALTH | Observability | Health/readiness | S | P0 | N/A | Have | /health |
| D9.O.SLOW_LOG | Observability | Slow-query log | S | P0 | N/A | Have | log ring ts ordering |
| D9.O.STATS | Observability | Stats/introspection | S | P0 | N/A | Have | /stats |
| D9.O.OTLP | Observability | OTLP tracing | S | P1 | N/A | Missing | tracing exporter |
| D9.O.DASHBOARDS | Observability | Dashboards/alerts | S | P1 | N/A | Missing | deployment wiring |
| D9.O.BACKUP_AUTO | Observability | Backup automation | S | P1 | N/A | Missing | scheduler |
| D9.O.ROLLING_UPGRADE | Observability | Rolling upgrades | S | P1 | N/A | Missing | orchestration |
| D9.O.CLI_ADMIN | Observability | CLI/admin API | S | P1 | N/A | Partial | tools exist; not a unified CLI |
| D10.S.API_KEY | Security | API-key auth | S | P0 | N/A | Have | probe_service_auth |
| D10.S.RBAC | Security | RBAC/scopes | S | P1 | N/A | Partial | read/write/admin scopes only |
| D10.S.TLS | Security | TLS | S | P0 | N/A | Missing | external proxy required |
| D10.S.ENCRYPTION | Security | Encryption at rest | S | P1 | N/A | Missing | WAL/segments not encrypted |
| D10.S.AUDIT | Security | Audit log | S | P1 | N/A | Missing | admin/action audit |
| D10.S.RATE_LIMIT | Security | Rate limiting | S | P1 | N/A | Have | token bucket |
| D10.S.QUOTAS | Security | Quotas | S | P2 | N/A | Missing | per-key/tenant quotas |
| D10.S.MULTI_TENANCY | Security | Multi-tenancy | S | P1 | N/A | Missing | tenant isolation |
| D10.S.COMPLIANCE | Security | Compliance/attestations | S | P2 | N/A | Missing | SOC2-style controls |
| D10.S.SBOM | Security | SBOM/supply chain | B | P1 | Have | Have | sbom gate |
| D11.I.EMBEDDED | Interfaces | Embedded package API | P | P0 | Have | N/A | xiom.vectors 0.2.0 |
| D11.I.REST | Interfaces | REST/HTTP API | S | P0 | N/A | Have | http_service probes |
| D11.I.GRPC | Interfaces | gRPC API | S | P1 | N/A | Missing | add protocol |
| D11.I.GRAPHQL | Interfaces | GraphQL | S | P2 | N/A | Missing | optional |
| D11.I.SQL | Interfaces | SQL interface | P/S | P1 | Missing | Missing | no SQL surface |
| D11.I.PY_SDK | Interfaces | Python SDK | B | P1 | Missing | Missing | no SDK |
| D11.I.OTHER_SDK | Interfaces | Rust/Go/JS SDKs | S | P2 | N/A | Missing | no SDKs |
| D11.I.LANGCHAIN | Interfaces | LangChain/LlamaIndex | S | P2 | N/A | Missing | integration |
| D11.I.SQLITE_EXT | Interfaces | SQLite extension | P | P2 | Missing | N/A | sqlite-vec reference |
| D11.I.KAFKA_CDC | Interfaces | Kafka/CDC | S | P2 | N/A | Missing | streaming |
| D11.I.K8S | Interfaces | Kubernetes operator/Helm | S | P2 | N/A | Missing | deployment |
| D11.I.CLOUD | Interfaces | Cloud control plane | S | P2 | N/A | Missing | managed service |
| D12.B.RECALL_LATENCY | Evidence | Recall/latency/QPS harness | B | P0 | Have | Have | internal bench + probes |
| D12.B.ANN_BENCH | Evidence | ANN-Benchmarks compatibility | B | P1 | Missing | Missing | harness adapter |
| D12.B.VDB_BENCH | Evidence | VectorDBBench compatibility | S | P1 | N/A | Missing | harness adapter |
| D12.B.BILLION | Evidence | Billion-scale benchmark | P/S | P1 | Missing | Missing | scale evidence |
| D12.B.INDEPENDENT | Evidence | Independent third-party benchmark | S | P1 | N/A | Missing | external publication |
| D12.B.CHAOS | Evidence | Chaos/fault injection | B | P1 | Partial | Partial | kill matrix only |
| D12.B.LOAD_SOAK | Evidence | Load/soak tests | B | P1 | Have | Have | probe_soak_mixed |
| D12.B.UPGRADE | Evidence | Upgrade tests | S | P1 | N/A | Missing | rolling upgrade |
| D12.B.SECURITY_AUDIT | Evidence | Security audit | S | P2 | N/A | Missing | external audit |
| D12.B.REPRO_ARTIFACTS | Evidence | Reproducible artifacts | B | P1 | Partial | Partial | docs/benchmarks; needs SHA/run |

---

## Backlog (candidate units not yet rowed)

The 131-candidate seed in `TOP-TIER-PARITY.md` still has units to expand,
including:

- D1: tenant columns, schema typing/validation, vector dimension limits.
- D2: NSG/LSH, ScaNN/other graph families, quantizer variants
  (MinMax/Spherical), index build params, index stats/health.
- D3: query explain/plan, score functions, diversity/MMR details, negative
  examples, cursor semantics per reference.
- D4: geo predicates, array contains/all, is-null/missing, nested object
  paths, filter cardinality/explain.
- D5: fsync policies per reference, manifest/versioning, remote backup,
  restore verification, torn-tail policies, offline repair.
- D6: read-your-writes, session consistency, isolation levels, lock
  fairness, request cancellation, deadline propagation.
- D7: membership/health, quorum, split-brain behavior, topology changes,
  zone awareness, rebalancing policy, read replicas.
- D8: idempotency, dedupe, bulk import formats, upsert conflict policy,
  async indexing/visibility, drop/rename semantics.
- D9: per-collection metrics, cardinality controls, log redaction,
  trace sampling, audit integration, SLO/error budget.
- D10: key rotation, mTLS, per-tenant keys, policy engine, data
  residency, deletion/erasure, vulnerability response.
- D11: SDK idempotency/retries, pagination helpers, async clients,
  OpenAPI/schema, embeddings integrations, migration tools.
- D12: reference hardware/software matrix, dataset licensing, percentile
  methodology, cold/warm cache, filtered-search benchmarks, cost/QPS.

---

## Row template

```markdown
| D0.XXX | Domain | One testable capability | B | P1 | Missing | Missing | evidence or gap + milestone |
```

## How this file is scored

1. Freeze the reference commit/tag and mark `X_pkg` / `X_srv` in
   `TOP-TIER-PARITY.md`.
2. Replace every `Missing`/`Partial` with evidence or keep the gap.
3. Compute:
   - `P_pkg = sum(weight x matched_pkg) / sum(weight x X_pkg)`
   - `P_srv = sum(weight x matched_srv) / sum(weight x X_srv)`
   - weights: P0=3, P1=2, P2=1; `Partial`=0.5 unless owner sets otherwise.
4. Report per reference and composite; never blend with the 91 % v1 score.
5. No `Have` without an evidence path. No parity percentage before the
   freeze.
