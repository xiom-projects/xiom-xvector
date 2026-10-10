<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Operations runbook -- xiom-xvector (M-O / O3)

How to run, monitor, back up, and recover the database. Commands are the
lane's scripts; all paths are relative to the repo root. The HTTP surface
is the in-repo byte pipeline (`api.http_service`); binding a real socket is
gated on the stdlib `xiom.net` proof (C-PULSE-02), so "service mode" below
describes the request/response contract the adapter will carry.

## 1. Start / stop

| Mode | How | Notes |
|---|---|---|
| Embedded | link `xiom.vector.engine`; `create_collection` -> `upsert`/`search` | trusted caller; auth off |
| Service (byte pipeline) | `http_service_handle_state(eng, raw, state)` per request | state = `ServiceState` (config/auth/rate/metrics/log) |
| Service (socket, pending) | stdlib `xiom.net` adapter feeding the same handle | C-PULSE-02 gated |

Shutdown: **always** call `http_service_shutdown(eng, wal_path)` (embedded)
for a drain + whole-file WAL checkpoint; it returns `false` on an
unwritable path (treat as an alert, keep the old checkpoint). A hard kill
is safe for data at the WAL-model level (prefix recovery), but the fsync
gap means the last writes can be lost on machine crash (see §5).

## 2. Configuration reference

`ServiceConfig` (defaults): `max_request_bytes=65536`, `max_top_k=1000`,
`max_batch=256`, `max_dim=1024`.

| Source | Key | Notes |
|---|---|---|
| env | `XVECTOR_MAX_REQUEST_BYTES`, `XVECTOR_MAX_TOP_K`, `XVECTOR_MAX_BATCH`, `XVECTOR_MAX_DIM` | malformed values ignored |
| env | `XVECTOR_API_KEYS="key1:admin,key2:read"` | enables auth; keys 8..128 `[A-Za-z0-9_.-]` |
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
backup:  http_service_shutdown(eng, "backup/xvector.wal")      # checkpoint
         engine_manifest_save(eng, "backup/xvector.manifest")   # registry
         seal_segment(eng, seg_id, "backup/segment-N.seg")      # optional per collection
restore: wr = wal_load("backup/xvector.wal")
         eng = open_engine(wr, "backup/xvector.manifest", dim, metric)
         (per collection: restore_segment(eng, "backup/segment-N.seg") when sealed segments were used)
verify:  engine_size / search sanity; collection_stats per collection;
         xvector_lsn gauge monotonic
```

All file formats are torn-tail safe (longest-valid-prefix load) and
atomically written (temp+rename), so a backup interrupted mid-write leaves
the previous file intact. `engine_manifest_save` is the registry of
record; without it, recovery falls back to the in-WAL manifests.

## 5. Failure domains (known, honest)

| Domain | Behavior today | Mitigation / status |
|---|---|---|
| Process kill (no drain) | WAL-model prefix recovery; acknowledged-but-unpersisted writes may be lost | run the drain+checkpoint on SIGTERM in the adapter |
| Machine crash / power loss | **fsync gap**: `wal_persist` is atomic but not fsync'd (stdlib stub) | documented; D5/D6 gated on the stdlib fsync chain |
| Torn checkpoint / segment / manifest | prefix load keeps all complete records; malformed tail ignored | `probe_wal_file`, `probe_manifest_file`, `probe_segment_file` |
| Deep-nested JSON body | rejected 400 by `json_depth_ok` (64) before the parser | stdlib `json_parse` depth cap filed in the wishlist |
| Oversized / abusive requests | 413/400/405 by limits; fuzz gate green | `probe_service_limits`, `probe_http_fuzz` |
| Brute force / key guessing | 401/403 with constant-time compare; token bucket 429 | `probe_service_auth` |
| Disk full / unwritable path | persist returns false; old file intact | alert on `false`; never leave a rebuilt binary from a red build |
| Compiler/stdlib regression | full batteries (suite x2 + sbom + 31 probes x2 + bench smoke) on Windows + WSL | `scripts/ci.ps1` / `ci.sh`; red build = rejection |

## 6. Upgrade / migration notes

- On-disk format versions: WAL magic `xvector-wal 1` (ManifestUpdate v1/v2/v3
  families), manifest `xvector-manifest 1`, segment `xvector-segment 1`.
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
| Reopen shows fewer points than expected | last writes not drained? check `xvector_lsn` before shutdown; `wal_load` returns a prefix by design |
| 401 on every call | `XVECTOR_API_KEYS` set? key scope vs route (read vs write vs admin) |
| 413/400 on valid-looking payloads | `max_request_bytes` / `max_batch` / `max_top_k` / `max_dim` env overrides |
| 429 bursts | `rate_limiter` capacity/refill or a misbehaving client; counters show `xvector_rate_limited` |
| Slow tail | `xvector_latency_ms_p99`, `slow:true` log lines, `selection` of Hnsw `ef` params |
| Battery red | rerun `scripts/ci.ps1`; per-probe logs in `out/ci_<probe>.log`; crash forensics in `out/fuzz_mark.txt` |
