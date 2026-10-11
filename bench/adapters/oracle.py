# XIOM XVECTOR -- shared brute-force oracle helpers for the adapters
# (stdlib only; no numpy).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Used by smoke.py, quick_bench.py and vectordbbench/smoke_db.py so the
# exact-scan ground truth has exactly one implementation.

import math


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
    """Ranked ids of the k nearest corpus rows (cosine ground truth)."""
    ranked = sorted((cos_dist(v, q), i) for i, v in enumerate(corpus))
    return [i for _, i in ranked[:k]]


def recall(hits, truth, k):
    return len(set(hits[:k]) & set(truth[:k])) / float(k)
