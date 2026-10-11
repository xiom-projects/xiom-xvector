# XIOM XVECTOR -- live smoke for the benchmark adapters (stdlib Python only).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Assumes a running `xvectord` (default http://127.0.0.1:7707; override
# with XVECTOR_URL). Runs the same calls the ann-benchmarks adapter makes:
# version -> create (index hnsw) -> batched upsert -> ef sweep -> search,
# with recall@10 checked against a brute-force cosine oracle.
# Exit = failed checks.

import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import brute_force, recall
from xvector_client import XvectorClient, XvectorError


def main():
    url = os.environ.get("XVECTOR_URL", "http://127.0.0.1:7707")
    client = XvectorClient(url)
    fails = [0]

    def check(ok, name, extra=""):
        if not ok:
            fails[0] += 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, extra))
        return ok

    try:
        v = client.version()
    except XvectorError as e:
        print("xvectord unreachable at %s (%s)" % (url, e))
        return 2
    check(v.get("name") == "xvector" and v.get("version"),
          "GET /version -> name/version", " (%s)" % v.get("version"))

    dim, n, nq, k = 16, 400, 20, 10
    random.seed(42)
    corpus = [[random.uniform(-1.0, 1.0) for _ in range(dim)] for _ in range(n)]
    queries = [[random.uniform(-1.0, 1.0) for _ in range(dim)] for _ in range(nq)]

    try:
        created, _ = client.create_collection(
            "bench_smoke", dim, "cosine",
            index="hnsw", m=16, ef_construction=200, ef_search=64,
        )
    except XvectorError as e:
        print("create failed: %s" % e)
        return 2
    check(created, "POST /collections (index hnsw) -> 201")

    ids = list(range(n))  # ann-benchmarks-style 0-based ids
    batch = int(os.environ.get("XVECTOR_BATCH", "128"))  # service defaults
    for start in range(0, n, batch):
        stop = min(start + batch, n)
        client.upsert("bench_smoke", ids[start:stop], corpus[start:stop])
    st = client.stats("bench_smoke")
    check(int(st.get("points", -1)) == n and st.get("index") == "hnsw",
          "upsert %d points, stats show hnsw" % n)

    truths = [brute_force(corpus, q, k) for q in queries]
    for ef in (8, 64, 256):
        total = 0.0
        for qi in range(nq):
            hits = [int(h["id"]) for h in client.search("bench_smoke", queries[qi], k, ef_search=ef)]
            total += recall(hits, truths[qi], k)
        r = total / nq
        check(r == 1.0 if ef >= 64 else r >= 0.9,
              "recall@10 at ef=%d" % ef, " = %.3f" % r)

    try:
        client.create_collection("bench_smoke", dim, "cosine", index="hnsw",
                                 ignore_exists=False)
        check(False, "duplicate create raises (409)")
    except XvectorError as e:
        check(e.status == 409, "duplicate create -> 409 (tolerated by client)")

    print("")
    print("smoke: exit=%d" % fails[0])
    return fails[0]


if __name__ == "__main__":
    sys.exit(main())
