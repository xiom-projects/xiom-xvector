# XIOM XVECTOR -- minimal stdlib HTTP client for a running `xvectord`.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Pure stdlib (urllib) so it runs on any Python 3.6+; no numpy, no
# requests. Used by the ann-benchmarks adapter and by `smoke.py`.

import json
import urllib.error
import urllib.request


class XvectorError(Exception):
    def __init__(self, status, body):
        super().__init__("xvector HTTP %s: %s" % (status, body))
        self.status = status
        self.body = body


class XvectorClient(object):
    def __init__(self, url="http://127.0.0.1:7707", timeout=300):
        self.url = url.rstrip("/")
        self.timeout = timeout

    def _request(self, method, path, body=None):
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(
            self.url + path, data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                parsed = json.loads(raw)
            except ValueError:
                parsed = {"error": raw}
            raise XvectorError(e.code, parsed)

    # ---- server surface ----

    def health(self):
        return self._request("GET", "/health")[1]

    def version(self):
        return self._request("GET", "/version")[1]

    def create_collection(self, name, dim, metric="cosine", index=None,
                          m=None, ef_construction=None, ef_search=None,
                          ignore_exists=True):
        """Create a collection. Returns (created_bool, body). A 409 means
        'already exists' and is tolerated when ignore_exists (re-fit on a
        live server)."""
        body = {"name": name, "dim": int(dim), "metric": metric}
        if index is not None:
            body["index"] = index
        if m is not None:
            body["m"] = int(m)
        if ef_construction is not None:
            body["ef_construction"] = int(ef_construction)
        if ef_search is not None:
            body["ef_search"] = int(ef_search)
        try:
            status, out = self._request("POST", "/collections", body)
            return True, out
        except XvectorError as e:
            if e.status == 409 and ignore_exists:
                return False, e.body
            raise

    def upsert(self, name, ids, vectors):
        return self._request("POST", "/collections/%s/points" % name,
                             {"ids": list(ids), "vectors": [list(v) for v in vectors]})[1]

    def search(self, name, vector, k, ef_search=None, metric=None):
        body = {"collection": name, "k": int(k), "vector": list(vector)}
        if ef_search is not None:
            body["ef_search"] = int(ef_search)
        if metric is not None:
            body["metric"] = metric
        return self._request("POST", "/search", body)[1].get("hits", [])

    def stats(self, name):
        return self._request("GET", "/stats?collection=%s" % name)[1]

    def drop_collection(self, name):
        """DELETE /collections/{n}. The route may not exist on the current
        service build: callers should tolerate 404/405 (the VectorDBBench
        client does) and restart xvectord for a clean fit instead."""
        return self._request("DELETE", "/collections/%s" % name)[1]
