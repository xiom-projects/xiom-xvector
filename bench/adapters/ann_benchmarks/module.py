# ann-benchmarks adapter for XIOM XVECTOR (xiom-xvector).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drop next to `xvector_client.py` inside ann-benchmarks:
#   ann_benchmarks/algorithms/xvector/module.py  (this file)
#   ann_benchmarks/algorithms/xvector/config.yml (the shipped config.yml)
#   ann_benchmarks/algorithms/xvector/xvector_client.py
# then run, e.g.:
#   python run.py --dataset glove-25-angular --algorithm xvector --local
#
# The adapter talks HTTP to a running `xvectord` (start it first; set
# XVECTOR_URL if it is not on 127.0.0.1:7707). Metrics map as:
#   angular -> cosine, euclidean -> euclidean, dot -> dot.
# The query argument is `ef_search` (per-request beam width on /search).

import os
import sys

import numpy as np

from ann_benchmarks.algorithms.base import BaseANN

# ann-benchmarks loads algorithms by file path (not as a package), so try
# the package-relative import first and fall back to a path lookup.
try:
    from .xvector_client import XvectorClient
except (ImportError, SystemError, ValueError):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from xvector_client import XvectorClient

_METRIC_TO_XVECTOR = {
    "angular": "cosine",
    "euclidean": "euclidean",
    "dot": "dot",
}

INSERT_BATCH = int(os.environ.get("XVECTOR_BATCH", "128"))
# 128 keeps both service defaults happy (64 KiB body cap, 256 max batch) for
# dims up to ~25. For real datasets raise the server caps and XVECTOR_BATCH:
#   XVECTOR_MAX_REQUEST_BYTES=33554432 XVECTOR_MAX_BATCH=1000 XVECTOR_BATCH=1000


class Xvector(BaseANN):
    def __init__(self, metric, method_param):
        if metric not in _METRIC_TO_XVECTOR:
            raise ValueError("xvector adapter: unsupported metric %r" % (metric,))
        self._metric_name = metric
        self._xmetric = _METRIC_TO_XVECTOR[metric]
        self._ef = int(method_param.get("ef_search", 64))
        self._client = XvectorClient(os.environ.get("XVECTOR_URL", "http://127.0.0.1:7707"))
        self._collection = "annbench_%s" % self._xmetric
        self._shape = None
        self.name = "xvector(ef=%d)" % self._ef

    def fit(self, X):
        X = np.asarray(X, dtype=np.float64)
        n, d = X.shape
        self._shape = (n, d)
        created, _ = self._client.create_collection(
            self._collection, d, self._xmetric,
            index="hnsw", m=16, ef_construction=200, ef_search=self._ef,
        )
        if not created:
            # A collection with the same name/shape exists (re-fit on a live
            # server). The starter path assumes ONE fit per server run;
            # restart xvectord for a clean dataset.
            raise RuntimeError(
                "xvector adapter: collection %r already exists -- restart "
                "xvectord for a fresh fit" % self._collection
            )
        ids = list(range(n))
        rows = X.tolist()
        for start in range(0, n, INSERT_BATCH):
            stop = min(start + INSERT_BATCH, n)
            self._client.upsert(self._collection, ids[start:stop], rows[start:stop])

    def query(self, v, n):
        hits = self._client.search(
            self._collection, np.asarray(v, dtype=np.float64).tolist(),
            int(n), ef_search=self._ef,
        )
        return [int(h["id"]) for h in hits]

    def set_query_arguments(self, ef_search):
        self._ef = int(ef_search)
        self.name = "xvector(ef=%d)" % self._ef

    def __str__(self):
        return self.name
