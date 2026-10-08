// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.query.search_request

// SearchRequest: the wire shape for request-driven search. Holds the query
// vector, top_k, the request's metric (validated against the active
// collection by engine_search_request), an optional filter clause, and the
// with_payload hydration flag. Rewritten against the real extracted types
// (the pre-extraction file carried inline mirrors).

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.payload.filter_ast;

pub type SearchRequest = {
  query: Vector;
  top_k: Int;
  metric: DistanceMetric;
  filter: Vec[FilterExpr];
  with_payload: Bool;
}

pub fn search_request_new(query: Vector, top_k: Int, metric: DistanceMetric) -> SearchRequest
  requires: top_k > 0
{
  var filter = Vec[FilterExpr].new();
  return SearchRequest{
    query: query,
    top_k: top_k,
    metric: metric,
    filter: filter,
    with_payload: false,
  };
}

// Replace the request's filter with a single clause ([] = no filter).
pub fn search_request_set_filter(req: &mut SearchRequest, expr: FilterExpr) {
  var filter = Vec[FilterExpr].new();
  filter.push(expr);
  req.filter = filter;
}

pub fn search_request_has_filter(req: &SearchRequest) -> Bool {
  return req.filter.len() > 0;
}

pub fn search_request_top_k(req: &SearchRequest) -> Int {
  return req.top_k;
}

// Toggle payload hydration on the request.
pub fn search_request_set_with_payload(req: &mut SearchRequest, on: Bool) {
  req.with_payload = on;
}
