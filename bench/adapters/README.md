# XIOM XVECTOR (xiom-xvector) -- benchmark adapters

Integration for the standard vector-DB benchmark suites, over the
`xvectord` HTTP server (see `SPEC.md`, section `xiom.vector.api.httpd`).
Everything here talks plain HTTP/1.1; nothing links the engine in-process.

## Quick start

```powershell
# 1) build + start the server (from the repo root)
. .\scripts\dev-env.ps1
.\scripts\build.ps1 src\api\httpd.xi -Name xvectord
# benchmark datasets: raise the service body caps (defaults 64 KiB / 256 rows)
$env:XVECTOR_MAX_REQUEST_BYTES = "33554432"
$env:XVECTOR_MAX_BATCH = "1000"
$env:XVECTOR_BATCH = "1000"     # adapter-side rows per upsert
.\out\xvectord.exe --port 7707

# 2) verify the adapter logic against the live server (stdlib Python only)
python bench\adapters\smoke.py
```

## ann-benchmarks

`ann_benchmarks/` is a drop-in algorithm for
[ann-benchmarks](https://github.com/erikbern/ann-benchmarks):

1. copy `ann_benchmarks/module.py` + `ann_benchmarks/config.yml` +
   `xvector_client.py` into `ann_benchmarks/algorithms/xvector/`
   (module.py imports `xvector_client` from the adapters directory, so
   keep both files together; see the README in that directory),
2. start `xvectord` (any port; set `XVECTOR_URL` to point elsewhere),
3. `python run.py --dataset glove-25-angular --algorithm xvector --local`.

The adapter maps ann-benchmarks metrics (`angular` -> our `cosine`,
`euclidean` -> `euclidean`, `dot` -> our `dot`) and sweeps `ef_search`
via the per-request beam on `/search` (query arguments 16/32/64/128/256
in the shipped config).

## VectorDBBench

VectorDBBench speaks per-database clients; the starter path is the same
HTTP surface (create with `"index":"hnsw"`, batched upserts, `/search`
with `ef_search`). A dedicated client module is the next adapter slice;
`xvector_client.py` carries all the calls it needs.

## Honest notes for benchmark runs

- the server is **single-threaded** (sequential accept): benchmark
  concurrency phases will serialize; report as a single-thread baseline
  (the G phase of `docs/PRODUCTION-READINESS.md` tracks this),
- durability: WAL/checkpoint exist, but the stdlib fsync chain is stubbed
  on the current pin -- do not expect crash-consistency claims yet
  (D phase),
- the ANN index is our HNSW (generous level 0): default `m=16`,
  `ef_construction=200`; `ef_search` per request via the API.
