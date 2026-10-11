# VectorDBBench client for XIOM XVECTOR (xiom-xvector).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drop next to `xvector_client.py` inside VectorDBBench:
#   vectordb_bench/backend/clients/xvector/xvector_db.py   (this file)
#   vectordb_bench/backend/clients/xvector/xvector_client.py (copy)
# then register `XvectorDB` in the clients map (see README.md in this
# directory for the exact spots and a suggested case-config module).
#
# The client talks HTTP to a running `xvectord` (default
# http://127.0.0.1:7707; XVECTOR_URL overrides). Inside VectorDBBench it
# subclasses the framework's DB client; standalone (direct mode, used by
# `smoke_db.py`) it degrades to a plain object so the exact same methods
# can be exercised locally with nothing but stdlib Python.
#
# Honest limitations (documented in README.md):
#   - metadata / label filters are not exposed over the HTTP service yet:
#     `insert_embeddings(metadata=...)` reports the unsupported error and
#     `search(filters=...)` raises NotImplementedError (never silent);
#   - collection drop is not exposed on the current service build:
#     `drop_collection` tries `DELETE /collections/{n}` and otherwise
#     warns and returns False (restart `xvectord` for a clean fit);
#   - search returns (distance, id) tuples (swap the two fields in one
#     place if your VectorDBBench revision expects (id, distance)).

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.dirname(_HERE))  # sibling xvector_client.py

try:
    from .xvector_client import XvectorClient, XvectorError
except (ImportError, SystemError, ValueError):
    from xvector_client import XvectorClient, XvectorError

try:  # present only inside a VectorDBBench checkout
    from vectordb_bench.backend.clients import api as _vdb_api

    _VDB_BASE = _vdb_api.DB
except Exception:  # pragma: no cover - direct mode
    _vdb_api = None
    _VDB_BASE = object

_METRIC_MAP = {
    "COSINE": "cosine",
    "L2": "euclidean",
    "IP": "dot",
    "angular": "cosine",
    "cosine": "cosine",
    "euclidean": "euclidean",
    "l2": "euclidean",
    "dot": "dot",
    "ip": "dot",
}

# 128 keeps both service defaults happy (64 KiB body cap, 256 max batch)
# for dims up to ~25. For real datasets raise the server caps and
# XVECTOR_BATCH (see the adapters README quick start).
INSERT_BATCH = int(os.environ.get("XVECTOR_BATCH", "128"))


def _metric_to_xvector(value):
    if value is None:
        return "cosine"
    raw = getattr(value, "value", value)  # enum -> str
    key = str(raw)
    if key not in _METRIC_MAP:
        raise ValueError("xvector client: unsupported metric %r" % (raw,))
    return _METRIC_MAP[key]


def _rows_as_lists(vectors):
    """Normalize rows to plain float lists (handles numpy arrays and
    numpy scalars; the HTTP client serializes with json)."""
    return [[float(x) for x in row] for row in vectors]


class XvectorDB(_VDB_BASE):
    name = "Xvector"

    def __init__(self, dim, db_config=None, case_config=None, **kwargs):
        self.dim = int(dim)
        self._db_config = db_config if db_config is not None else case_config
        if self._db_config is None and kwargs.get("config") is not None:
            self._db_config = kwargs["config"]
        self._ready = False

        url = os.environ.get("XVECTOR_URL", "http://127.0.0.1:7707")
        self._client = XvectorClient(url, timeout=300)
        self._url = url

        self._metric = _metric_to_xvector(self._cfg("metric_type", "COSINE"))
        self._index = str(self._cfg("index_type", os.environ.get("XVECTOR_INDEX", "hnsw")))
        self._m = int(self._cfg("m", os.environ.get("XVECTOR_M", "16")))
        self._ef_construction = int(
            self._cfg("ef_construction", os.environ.get("XVECTOR_EFC", "200"))
        )
        self._ef_search = int(self._cfg("ef_search", os.environ.get("XVECTOR_EF", "64")))
        self._drop_unsupported_warned = False

    # ---- config plumbing (tolerant across VectorDBBench revisions) ----

    def _cfg(self, name, default):
        cfg = self._db_config
        if cfg is None:
            return default
        value = getattr(cfg, name, None)
        if value is None and hasattr(cfg, "dict"):  # pydantic v1
            try:
                value = cfg.dict().get(name)
            except Exception:
                value = None
        return default if value is None else value

    # ---- lifecycle ----

    @property
    def ready(self):
        return self._ready

    @ready.setter
    def ready(self, value):
        self._ready = bool(value)

    def init(self):
        self._client.health()
        self._ready = True

    def disconnect(self):
        # HTTP is stateless; writes are WAL-before-ack on the server.
        self._ready = False

    # ---- collection lifecycle ----

    def create_collection(self, collection_name, dim=None, drop_old=False, **kwargs):
        """Create the HNSW collection. `drop_old=True` attempts a drop
        first (best effort -- the route may not exist); a 409 afterwards
        raises unless `ignore_exists=True` is passed explicitly."""
        if drop_old:
            self.drop_collection(collection_name)
        dim = int(dim if dim is not None else self.dim)
        created, body = self._client.create_collection(
            collection_name,
            dim,
            self._metric,
            index=self._index,
            m=self._m,
            ef_construction=self._ef_construction,
            ef_search=self._ef_search,
            ignore_exists=bool(kwargs.get("ignore_exists", False)),
        )
        return created

    def drop_collection(self, collection_name):
        """Best effort: the current service build has no drop route, so
        this warns once and returns False (restart `xvectord` for a clean
        fit). A future build exposing DELETE /collections/{n} is used
        automatically."""
        try:
            self._client.drop_collection(collection_name)
            return True
        except XvectorError as e:
            if e.status in (404, 405, 501):
                if not self._drop_unsupported_warned:
                    print(
                        "xvector client: collection drop is not exposed by "
                        "this xvectord build (HTTP %s); restart the server "
                        "for a clean fit" % e.status
                    )
                    self._drop_unsupported_warned = True
                return False
            raise

    # ---- data path ----

    def insert_embeddings(self, collection_name, embeddings, metadata=None, **kwargs):
        """Batched upsert. Returns (inserted_count, error) -- the
        VectorDBBench convention. Metadata is not exposed over HTTP yet:
        it reports the unsupported error instead of silently dropping it."""
        if metadata is not None:
            return 0, NotImplementedError(
                "xvector HTTP service does not expose payload/metadata "
                "routes yet; run vector-only cases"
            )
        rows = _rows_as_lists(embeddings)
        n = len(rows)
        ids = list(range(n))
        done = 0
        try:
            for start in range(0, n, INSERT_BATCH):
                stop = min(start + INSERT_BATCH, n)
                self._client.upsert(collection_name, ids[start:stop], rows[start:stop])
                done = stop
        except XvectorError as e:
            return done, e
        return done, None

    def search(self, collection_name, data, topk, filters=None, **kwargs):
        """Return [query][topk] -> [(distance, id)]. Filters are not
        supported over HTTP yet: raise (never return silently wrong)."""
        if filters is not None or kwargs.get("filter") is not None:
            raise NotImplementedError(
                "xvector HTTP service does not expose filter routes yet; "
                "run vector-only cases"
            )
        out = []
        for row in _rows_as_lists(data):
            hits = self._client.search(
                collection_name, row, int(topk), ef_search=self._ef_search
            )
            out.append([(float(h["distance"]), int(h["id"])) for h in hits])
        return out

    def set_query_ef(self, ef):
        """Lane helper for ef sweeps in local/direct runs (VectorDBBench
        drives ef through the case config instead)."""
        self._ef_search = int(ef)

    def query(self, collection_name, query, topk, **kwargs):
        # VectorDBBench uses `query` mainly for metadata/filter retrieval;
        # the HTTP surface does not expose filters yet.
        raise NotImplementedError(
            "xvector HTTP service does not expose filter/query routes yet"
        )

    def flush(self, collection_name):
        # All writes are WAL-before-ack on the server side.
        return None
