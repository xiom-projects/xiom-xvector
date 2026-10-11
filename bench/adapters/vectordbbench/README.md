# XIOM XVECTOR (xiom-xvector) -- VectorDBBench client adapter

Integration for [VectorDBBench](https://github.com/zilliztech/VectorDBBench)
over the `xvectord` HTTP server. `xvector_db.py` implements the
framework's DB-client surface with the same calls the ann-benchmarks
adapter uses: create with `"index":"hnsw"`, batched upserts, `/search`
with a per-request `ef_search`.

## Drop-in

1. copy into your VectorDBBench checkout:

   - `vectordb_bench/backend/clients/xvector/xvector_db.py` (this dir)
   - `vectordb_bench/backend/clients/xvector/xvector_client.py` (from the
     adapters directory)
   - `vectordb_bench/backend/clients/xvector/config.py` -- minimal case
     config (adjust to your revision; pydantic v1 example):

     ```python
     from pydantic import BaseModel

     class XvectorConfig(BaseModel):
         metric_type: str = "COSINE"      # COSINE | L2 | IP
         index_type: str = "hnsw"
         m: int = 16
         ef_construction: int = 200
         ef_search: int = 64
     ```

2. register the client in `vectordb_bench/backend/clients/__init__.py`
   (and in the supported-clients map if your revision keeps one):

   ```python
   from .xvector.xvector_db import XvectorDB
   # add "Xvector": XvectorDB to the clients map
   ```

3. start `xvectord` with raised caps (`XVECTOR_MAX_REQUEST_BYTES=33554432
   XVECTOR_MAX_BATCH=1000 XVECTOR_BATCH=1000`; see the adapters README),
   then run VectorDBBench against the `Xvector` client with vector-only
   cases.

## Verified locally (direct mode)

`smoke_db.py` exercises the exact methods VectorDBBench calls without the
framework installed: init/ready -> create -> batched insert -> search
(topk, ordering, recall vs the brute-force oracle) -> ef sweep ->
unsupported paths (metadata/filters must fail loudly) -> drop fallback.
Exit = failed checks.

```powershell
python bench\adapters\vectordbbench\smoke_db.py
```

## Honest limitations

- **metadata / label filters are not exposed over HTTP yet** (the engine
  has payload support; the service routes do not): `insert_embeddings`
  with metadata returns `(0, NotImplementedError)` and `search` with
  filters raises -- run vector-only cases until the payload routes land.
- **no collection-drop route yet**: `drop_collection` warns once and
  returns False; restart `xvectord` for a clean fit (same discipline as
  the ann-benchmarks adapter). A future build exposing
  `DELETE /collections/{n}` is used automatically.
- **single-threaded server** (sequential accept): benchmark concurrency
  phases serialize; report numbers as a single-thread baseline (G phase
  of `docs/PRODUCTION-READINESS.md`).
- search results are `(distance, id)` tuples; if your VectorDBBench
  revision expects `(id, distance)`, swap the two fields in the one
  place (`xvector_db.py`, `search`).
- insert batch size defaults to `XVECTOR_BATCH` (128 keeps the service
  defaults happy; raise both the server caps and the batch for real
  datasets).
