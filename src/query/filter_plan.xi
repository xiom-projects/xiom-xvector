// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.query.filter_plan

// Selectivity-based filter planner (Phase 3 refinement). Uses the sorted
// payload key index for EXACT match counts of index-answerable single
// predicates (Eq / Range / Exists). Boolean combinations, In, and any other
// shape report "unknown" (-1) and take the pre-filter scan.
//
// Plan contract:
//   1 = pre-filter scan   (filter first, distance on survivors) -- default
//   2 = post-filter       (top-k overall, then keep matches; the caller MUST
//                          fall back to the scan when fewer than k matches
//                          survive -- see search_service.search_knn_filtered)
// Plan 2 is chosen only when the exact match count is known, is >= k, and a
// majority of the store matches: then the k nearest matches almost certainly
// sit inside the global top-k.

use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;

// Exact number of stored points the filter matches, or -1 when the shape is
// not index-answerable (boolean combinations, In, missing-field Eq included
// in the count when 0).
pub fn filter_matching_count(payloads: &PayloadStore, expr: &FilterExpr) -> Int {
  match expr {
    Eq(field, value) => { return payload_store_index_count_eq(payloads, field, value); }
    Range(field, lo, hi) => { return payload_store_index_count_range(payloads, field, lo, hi); }
    Exists(field) => { return payload_store_index_field_count(payloads, field); }
    _ => { return -1; }
  }
}

// Plan kinds (stable codes; the probe/consumers compare against these).
pub fn filter_plan_scan() -> Int {
  return 1;
}

pub fn filter_plan_post() -> Int {
  return 2;
}

// Choose the plan for a filtered exact search over `total` stored points at
// top-k `k`. Unknown selectivity -> scan; fewer than k matches -> scan (the
// scan is cheaper than a fallback round-trip); otherwise post only when the
// matches are a majority.
pub fn choose_filter_plan(payloads: &PayloadStore, expr: &FilterExpr, total: Int, k: Int) -> Int {
  var est: Int = filter_matching_count(payloads, expr);
  if est < 0 { return filter_plan_scan(); }
  if est < k { return filter_plan_scan(); }
  if est * 2 < total { return filter_plan_scan(); }
  return filter_plan_post();
}
