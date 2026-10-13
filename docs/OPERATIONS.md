<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Operations runbook -- xiom-xvector (M-O / O3)

How to run, monitor, back up, and recover the database. Commands are the
lane's scripts; all paths are relative to the repo root. The runnable
server (`out/xvectord.exe`, `api.httpd`) serves HTTP/1.1 on the stdlib
`xiom.net` socket layer and carries the `api.http_service` byte pipeline;
the embedded surface is `xiom.vector.engine`.

## 1. Start / stop

| Mode | How | Notes |
|---|---|---|
| Embedded | link `xiom.vector.engine`; `create_collection` -> `upsert`/`search` | trusted caller; auth off |
| Embedded + durable | `open_durable(ckpt, ckpt+".seg", manifest, dim, metric)` | fsync-on-ack; checkpoint + rotate on shutdown |
| Service (socket) | `out/xvectord.exe [--bind 127.0.0.1] [--port 7707]` | HTTP/1.1; auth/limits/metrics; quit: header `X-Xvector-Quit: 1` |
| Service + durable | `XVECTORD_WAL=home/xvector.ckpt [XVECTORD_MANIFEST=home/xvector.manifest] out/xvectord.exe` | every mutating request fsyncs before its response; clean quit persists the checkpoint and rotates the segment |

Shutdown (embedded): **always** call `http_service_shutdown(eng, wal_path)`
for a drain + whole-file WAL checkpoint; it returns `false` on an
unwritable path (treat as an alert, keep the old checkpoint). In durable
mode a hard kill is safe for every **acknowledged** write: records are
appended to the delta segment and fsynced before the ack (WAL-before-ack),
verified by the file-level kill matrix (`scripts/kill_matrix.ps1|.sh`).
The boundary that remains is power-loss fault injection (see §5).

## 2. Configuration reference

`ServiceConfig` (defaults): `max_request_bytes=65536`, `max_top_k=1000`,
`max_batch=256`, `max_dim=1024`.

| Source | Key | Notes |
|---|---|---|
| env | `XVECTOR_MAX_REQUEST_BYTES`, `XVECTOR_MAX_TOP_K`, `XVECTOR_MAX_BATCH`, `XVECTOR_MAX_DIM` | limits; malformed values ignored |
| env | `XVECTOR_API_KEYS="key1:admin,key2:read"` | enables auth; keys 8..128 `[A-Za-z0-9_.-]` |
| env | `XVECTORD_WAL=<ckpt path>` | durable home (M-D5): fsync-on-ack; `XVECTORD_MANIFEST=<path>` optional |
| env | `XVECTORD_CHECKPOINT_EVERY=<n>` | auto compact+swap every n commits (M-D6; 0/absent = off; clean quit always swaps) |
| file | `key=value` lines (`#` comments) via `service_config_load` | unknown keys ignored; malformed line -> `valid=false` |
| code | `service_config_apply`, `service_auth_add_key`, `rate_limiter_new(capacity, refill_per_sec)` | programmatic control |

Auth is **off** by default (embedded); the socket adapter must enable it
(register keys or set `XVECTOR_API_KEYS`). Scopes: read < write < admin;
`/health` and `/metrics` are public.

## 3. Monitoring

- `GET /health` -> `{"status":"ok","service":"xvector","ready":true}`
  (liveness/readiness).
- `GET /metrics` -> prometheus-style text:
  - counters `xvector_requests_total`, `xvector_errors_total`
    (status >= 400), `xvector_search_ops`, `xvector_upsert_ops`,
    `xvector_auth_failures`, `xvector_rate_limited`;
  - histograms `xvector_latency_ms` + `xvector_search_latency_ms`
    (buckets 1/5/10/50/100/500/1000 ms + `+Inf`, `_sum`, `_count`,
    `_p50`/`_p95`/`_p99` as bucket upper bounds);
  - gauges `xvector_collections`, `xvector_points_active`, `xvector_lsn`.
- Structured logs: bounded JSON-line ring (`ServiceState.log`, default
  256 lines, `slow_ms=250`): `{"method","path","status","ms","slow"}`;
  `log.dropped` counts evictions. Pipe the ring to stdout/file in the
  adapter; keys never appear in logs.
- Suggested alerts: `errors_total` rate, `auth_failures > 0`, p99 above
  your SLO, `rate_limited` sustained, `log.dropped` growing.

## 4. Backup / restore drill (embedded)

```text
checkpoint: http_service_shutdown(eng, "backup/xvector.wal")      # whole-file persist (no compaction)
            engine_checkpoint_swap(eng)                            # M-D6: compact + fsync-ordered swap + segment rotate
            engine_manifest_save(eng, "backup/xvector.manifest")   # registry
            seal_segment(eng, seg_id, "backup/segment-N.seg")      # optional per collection
snapshot:   snapshot_create(eng, "backup", "nightly")              # M-D6: compacts, then writes
                                                                   # backup/nightly.{ckpt,manifest,meta}
restore:    snapshot_load("backup/nightly", "import/xvector.seg", dim, metric)  # meta-gated
            (or manually: wr = wal_load("backup/xvector.wal")
             eng = open_engine(wr, "backup/xvector.manifest", dim, metric)
             per collection: restore_segment(eng, "backup/segment-N.seg") when sealed segments were used)
verify:  engine_size / search sanity; collection_stats per collection;
         xvector_lsn gauge monotonic; snapshot: engine_list_collections matches source
```

All file formats are torn-tail safe (longest-valid-prefix load) and
atomically written (temp+rename); the D6 checkpoint and snapshot persists
additionally fsync the temp BEFORE the rename (`wal_persist_sync`), so a
crash never leaves the target replaced by non-durable content.
`engine_manifest_save` is the registry of record; without it, recovery
falls back to the in-WAL manifests. Retention guidance: set
`XVECTORD_CHECKPOINT_EVERY` so the checkpoint stays near live-state size
and recovery stays bounded (measured: 4000 points reload in ~10 ms; a
128k-commit smoke log would otherwise be replayed in full); snapshots are
point-in-time files -- rotate them yourself with your backup tooling (no
in-repo retention/delete policy by design).

## 5. Failure domains (known, honest)

| Domain | Behavior today | Mitigation / status |
|---|---|---|
| Process kill (no drain) | **durable mode: every acknowledged write survives** (fsync-on-ack delta segment; kill matrix 6/6 Windows + 6/6 WSL); in-memory mode: prefix recovery only | set `XVECTORD_WAL` / `open_durable`; `scripts/kill_matrix.ps1|.sh` |
| Machine crash / power loss | **fsync-on-ack flushes acknowledged bytes to stable storage**, but power-loss safety is not fault-injected in CI (process-kill durability is what the matrix proves) | OS-level fault injection is future work; `docs/PRODUCTION-READINESS.md` D-phase states the boundary |
| Torn checkpoint / segment / manifest | prefix/line-safe load keeps all complete records; malformed lines skipped (segment), torn tails healed | `probe_wal_file`, `probe_manifest_file`, `probe_segment_file`, `probe_wal_segment` |
| Checkpoint swap fails (disk full / locked) | the ack is unaffected (already fsynced in the segment); the swap is retried on the next commit and at quit; the segment is never reset | `probe_snapshot` (swap failure ordering), alert on the quit-path warning |
| Corrupt/missing snapshot meta | `snapshot_load` refuses (meta-gated); the ckpt/manifest are not touched | `snapshot_valid`, `probe_snapshot` |
| Deep-nested JSON body | rejected 400 by `json_depth_ok` (64) before the parser | stdlib `json_parse` depth cap filed in the wishlist |
| Oversized / abusive requests | 413/400/405 by limits; fuzz gate green | `probe_service_limits`, `probe_http_fuzz` |
| Brute force / key guessing | 401/403 with constant-time compare; token bucket 429 | `probe_service_auth` |
| Disk full / unwritable path | persist returns false; old file intact | alert on `false`; never leave a rebuilt binary from a red build |
| Compiler/stdlib regression | full batteries (suite x2 + sbom + 42 probes x2 + bench smoke + kill matrix) on Windows + WSL | `scripts/ci.ps1` / `ci.sh`; red build = rejection |

## 6. Upgrade / migration notes

- On-disk format versions: checkpoint/WAL magic `xvector-wal 1`
  (ManifestUpdate v1/v2/v3 families), manifest `xvector-manifest 1`,
  sealed segment `xvector-segment 1`, snapshot meta
  `xvector-snapshot 1 <lsn> <collections>`, and the **D5 delta segment**
  (`<ckpt>.seg`, `xiom.wal` codec v1 lines
  `lsn|op|key|value|timestamp[|p0,p1,...]`; append-only, fsync-on-ack,
  line-tolerant replay with LSN-gap stop, heal-on-open, checkpoint-deduped
  merge; rotated empty after every clean checkpoint). The
  checkpoint file remains a `xvector-wal 1` whole-file compaction output,
  so pre-D5 readers keep working; a delta segment is ignored by pre-D5
  readers (old process = old behavior, no silent misread).
  Loaders accept older records (v1 WAL manifests migrate to the `default`
  collection) and reject unknown headers as invalid rather than guessing.
- Compiler/toolchain pins live in `SESSION.md` + `out/sbom.json`; re-run
  the batteries after any toolchain change and re-record the pins.
- Rollback: checkpoints/manifests/segments are plain text; the previous
  release's loader reads them unchanged as long as the format version
  stays 1 (or the new version ships a migration note here).

## 7. Quick diagnostics

| Symptom | Check |
|---|---|
| Reopen shows fewer points than expected | durable mode: the `.seg` beside your checkpoint missing/stale? recovery = checkpoint + segment merge; in-memory mode: last writes not drained -- check `xvector_lsn` before shutdown (`wal_load` returns a prefix by design) |
| 401 on every call | `XVECTOR_API_KEYS` set? key scope vs route (read vs write vs admin) |
| 413/400 on valid-looking payloads | `max_request_bytes` / `max_batch` / `max_top_k` / `max_dim` env overrides |
| 429 bursts | `rate_limiter` capacity/refill or a misbehaving client; counters show `xvector_rate_limited` |
| Slow tail | `xvector_latency_ms_p99`, `slow:true` log lines, `selection` of Hnsw `ef` params |
| Checkpoint file keeps growing / slow restart | set `XVECTORD_CHECKPOINT_EVERY` (compact+swap); the swap fires at the next commit threshold or clean quit |
| Battery red | rerun `scripts/ci.ps1`; per-probe logs in `out/ci_<probe>.log`; crash forensics in `out/fuzz_mark.txt` |

## 8. Memory budget (M-P P2)

The engine exposes a documented accounting estimate per collection:
`GET /stats?collection={n}` carries `mem_store`, `mem_graph`,
`mem_payloads`, `mem_total` (per-collection) and `mem_wal`
(engine-wide, the shared log; **not** part of `mem_total`). Model
constants live in `hnsw_memory_estimate` (`src/index/hnsw.xi`); deltas
are exact, absolutes are within struct-padding tolerance (gate:
`probe_memory_estimate`).

Sizing rules of thumb (model-derived, 64-bit):

- **HNSW adjacency dominates**: all `hnsw_layer_capacity()` (=8) row
  slots are allocated per node, each `m0` Ints wide -> `adj` alone is
  `64 * m0` bytes/point (2 KiB/point at the generous default
  m0 = 2m, m = 16). Vector data is stored twice (flat store + graph
  copy): `56 + 8*dim` bytes/point across both.
- 5k x dim-25 HNSW (m = 16): ~10.9 MiB graph + ~0.76 MiB store
  (~2.3 KiB/point); the WAL estimate grows with the un-checkpointed
  record buffer (64 B/record + 8 B/word payload).
- Budget check: estimate `mem_total` for the largest collection, add
  `mem_wal`, and keep 2-3x headroom for the WAL buffer before a
  checkpoint. Re-check after bulk loads.
- **Seal/compact thresholds**: `compact_index` reclaims tombstoned
  graph nodes; the estimate makes the loss visible (`mem_graph` vs the
  live-node model). Recommended trigger: tombstones > 25% of nodes
  (`/stats` `tombstones`/`nodes`) or `mem_graph` > 1.5x the live-node
  model; seal a segment (`seal_segment`) before compaction when a
  durable copy is wanted. Compaction cost is a full HNSW rebuild, so
  batch it (admin path), not per-delete.
