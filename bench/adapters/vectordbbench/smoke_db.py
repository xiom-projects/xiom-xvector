# Live smoke for the VectorDBBench adapter (direct mode; stdlib only).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Assumes a running `xvectord` (XVECTOR_URL overrides the default
# http://127.0.0.1:7707) and exercises the EXACT methods the VectorDBBench
# runner calls on the XvectorDB client: init/ready -> create_collection ->
# insert_embeddings (batched) -> search (topk, ordering, recall vs the
# brute-force oracle) -> ef sweep -> unsupported paths must fail loudly.
# Exit = failed checks.

import os
import random
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.dirname(_HERE))

from oracle import brute_force, recall
from xvector_db import XvectorDB
from xvector_client import XvectorError


def main():
    fails = [0]

    def check(ok, name, extra=""):
        if not ok:
            fails[0] += 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, extra))
        return ok

    db = XvectorDB(dim=16)
    try:
        db.init()
    except XvectorError as e:
        print("xvectord unreachable (%s)" % e)
        return 2
    check(db.ready, "init() -> ready")

    coll = "vdbbench_smoke"
    try:
        db.create_collection(coll, 16, drop_old=True)
    except XvectorError as e:
        print("create failed: %s" % e)
        print("(restart xvectord for a clean fit)")
        return 2
    check(True, "create_collection (strict; fresh server)")

    dim, n, nq, k = 16, 400, 20, 10
    random.seed(7)
    corpus = [[random.uniform(-1.0, 1.0) for _ in range(dim)] for _ in range(n)]
    queries = [[random.uniform(-1.0, 1.0) for _ in range(dim)] for _ in range(nq)]

    count, err = db.insert_embeddings(coll, corpus)
    check(err is None and count == n,
          "insert_embeddings -> (%d, None)" % count,
          "" if err is None else " got (%d, %s)" % (count, err))

    truths = [brute_force(corpus, q, k) for q in queries]

    res = db.search(coll, queries, k)
    check(len(res) == nq and all(len(r) == k for r in res),
          "search shape: %d queries x %d hits" % (len(res), k))
    order_ok = all(
        all(res[qi][j][0] <= res[qi][j + 1][0] for j in range(k - 1))
        for qi in range(nq)
    )
    check(order_ok, "search results distance-ascending")
    r = sum(recall([i for _, i in res[qi]], truths[qi], k) for qi in range(nq)) / nq
    check(r == 1.0, "recall@%d at the configured ef" % k, " = %.3f" % r)

    for ef, floor in ((8, 0.9), (128, 1.0)):
        db.set_query_ef(ef)
        res = db.search(coll, queries, k)
        r = sum(recall([i for _, i in res[qi]], truths[qi], k) for qi in range(nq)) / nq
        check(r >= floor, "ef=%d recall@%d" % (ef, k), " = %.3f" % r)

    c2, e2 = db.insert_embeddings(coll, corpus[:2], metadata=[{}, {}])
    check(c2 == 0 and isinstance(e2, NotImplementedError),
          "metadata insert -> (0, NotImplementedError)")
    try:
        db.search(coll, queries[:1], k, filters={"must": []})
        check(False, "filtered search raises")
    except NotImplementedError:
        check(True, "filtered search -> NotImplementedError")
    check(db.drop_collection(coll) is False,
          "drop_collection -> False with a warning (no route yet; tolerated)")

    db.disconnect()
    print("")
    print("smoke_db: exit=%d" % fails[0])
    return fails[0]


if __name__ == "__main__":
    sys.exit(main())
