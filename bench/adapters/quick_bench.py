# XIOM XVECTOR -- quick benchmark through the HTTP adapter path.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Stdlib-only (no numpy). Measures the full user path: create (HNSW) ->
# batched upsert -> per-ef search QPS + recall@k against a brute-force
# cosine oracle. Same client calls the ann-benchmarks adapter uses.
#
#   .\out\xvectord.exe --port 7714      (start with raised caps; see README)
#   python bench\adapters\quick_bench.py
#
# Env: XVECTOR_URL, XVECTOR_BENCH_N (default 5000), XVECTOR_BENCH_DIM (25),
# XVECTOR_BENCH_NQ (100), XVECTOR_BATCH (1000), XVECTOR_BENCH_COLL (bench_q).

import math
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xvector_client import XvectorClient, XvectorError


def cos_dist(a, b):
    dot = 0.0
    ma = 0.0
    mb = 0.0
    for i in range(len(a)):
        dot += a[i] * b[i]
        ma += a[i] * a[i]
        mb += b[i] * b[i]
    if ma == 0.0 or mb == 0.0:
        return 1.0
    return 1.0 - dot / (math.sqrt(ma) * math.sqrt(mb))


def brute_force(corpus, q, k):
    ranked = sorted((cos_dist(v, q), i) for i, v in enumerate(corpus))
    return set(i for _, i in ranked[:k])


def main():
    url = os.environ.get("XVECTOR_URL", "http://127.0.0.1:7707")
    n = int(os.environ.get("XVECTOR_BENCH_N", "5000"))
    dim = int(os.environ.get("XVECTOR_BENCH_DIM", "25"))
    nq = int(os.environ.get("XVECTOR_BENCH_NQ", "100"))
    k = int(os.environ.get("XVECTOR_BENCH_K", "10"))
    batch = int(os.environ.get("XVECTOR_BATCH", "1000"))
    coll = os.environ.get("XVECTOR_BENCH_COLL", "bench_q")
    efs = [int(x) for x in os.environ.get("XVECTOR_BENCH_EFS", "8,32,128").split(",")]

    client = XvectorClient(url)
    v = client.version()
    print("xvectord %s at %s" % (v.get("version"), url))

    random.seed(7)
    corpus = [[random.uniform(-1.0, 1.0) for _ in range(dim)] for _ in range(n)]
    queries = [[random.uniform(-1.0, 1.0) for _ in range(dim)] for _ in range(nq)]

    t0 = time.time()
    client.create_collection(coll, dim, "cosine", index="hnsw",
                             m=16, ef_construction=200, ef_search=64)
    ids = list(range(n))
    for start in range(0, n, batch):
        stop = min(start + batch, n)
        client.upsert(coll, ids[start:stop], corpus[start:stop])
    t_upsert = time.time() - t0
    print("upsert: %d points dim=%d in %.2fs (%.0f points/s, batch=%d)"
          % (n, dim, t_upsert, n / t_upsert, batch))

    print("ground truth: %d queries x brute force..." % nq)
    t0 = time.time()
    truths = [brute_force(corpus, q, k) for q in queries]
    print("ground truth: %.2fs" % (time.time() - t0))

    print("")
    print("| ef | recall@%d | QPS | mean ms |" % k)
    print("|---|---|---|---|")
    for ef in efs:
        t0 = time.time()
        hit = 0
        for qi in range(nq):
            hits = client.search(coll, queries[qi], k, ef_search=ef)
            got = set(int(h["id"]) for h in hits)
            hit += len(got & truths[qi])
        dt = time.time() - t0
        qps = nq / dt
        print("| %d | %.3f | %.0f | %.2f |"
              % (ef, hit / float(nq * k), qps, 1000.0 * dt / nq))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except XvectorError as e:
        print("error: %s" % e)
        sys.exit(2)
