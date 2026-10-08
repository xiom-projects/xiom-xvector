// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.query.search_service

// Exact top-k search: the k-bounded distance-sorted scan (unfiltered and
// filtered). Extracted from the consolidated engine (post-AUDIT module
// tree).

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.storage.vector_store;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.payload.filter_eval;

pub type SearchResult = {
  id: Int;
  distance: Float32;
} derive[Clone]

// Ok-payload wrapper for search results. Rationale: on compiler v0.64.0 a
// Result/Option whose payload is DIRECTLY a Vec[T] with non-scalar T loses
// element field data for the caller (len survives, fields read as zero /
// address-like; XVC-C-04, repro docs/repro/xv-result-vec-struct/).
// Wrapping the Vec in a struct preserves the payload. Unwrap this type when
// the compiler finding is fixed.
pub type SearchHits = {
  items: Vec[SearchResult];
}

// Push a hit into a distance-sorted bounded list (shared by the exact and
// filtered scans): insert sorted, then trim to k.
fn results_push_bounded(results: &mut Vec[SearchResult], item: SearchResult, k: Int) {
  results.push(item);
  var pos: Int = results.len() - 1;
  while pos > 0 && results[pos - 1].distance > results[pos].distance {
    var tmp = results[pos];
    results[pos] = results[pos - 1];
    results[pos - 1] = tmp;
    pos = pos - 1;
  }
  if results.len() > k {
    results.pop();
  }
}

pub fn search_knn(idx: &VectorIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    i = i + 1;
  }
  return results;
}

// Filtered exact scan: evaluate the filter per candidate BEFORE the distance
// compute (a pre-filter plan for the exact engine; a selectivity-based
// pre/post planner is a later Phase 3 deliverable).
pub fn search_knn_filtered(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    if payload_store_matches(payloads, idx.ids[i], filter) {
      var dist = vector_distance(&idx.vectors[i], query, metric);
      results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    }
    i = i + 1;
  }
  return results;
}

// ---- Payload hydration (SearchRequest.with_payload) ----
// A hydrated hit: the plain result plus its metadata. `has_payload` is false
// when hydration was not requested OR the point has no payload (`payload` is
// then an empty Payload). Kept separate from SearchResult so the plain search
// path and its XVC-C-04 wrapper stay untouched.
pub type SearchHit = {
  id: Int;
  distance: Float32;
  payload: Payload;
  has_payload: Bool;
}

// C-04 wrapper for hydrated hits (same rationale as SearchHits): a
// Result/Option whose payload is directly a Vec[non-scalar] loses element
// fields at the caller.
pub type HydratedHits = {
  items: Vec[SearchHit];
}

// Attach payloads to a result list when `with_payload`; otherwise every hit
// carries the empty payload and has_payload=false. Payloads are copied out
// of the store into the hit (no borrowed references escape).
pub fn hydrate_hits(items: &Vec[SearchResult], payloads: &PayloadStore, with_payload: Bool) -> Vec[SearchHit] {
  var out = Vec[SearchHit].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = payload_new();
    var have: Bool = false;
    if with_payload {
      match payload_store_get(payloads, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(SearchHit{ id: items[i].id, distance: items[i].distance, payload: pl, has_payload: have });
    i = i + 1;
  }
  return out;
}
