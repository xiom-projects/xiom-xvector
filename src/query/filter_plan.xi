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

// Index-driven plan: enumerate the exact candidate ids from the sorted
// payload index (single Eq/Range predicates) and compute distances only for
// those -- the store's id -> slot map makes each lookup O(log n).
pub fn filter_plan_index() -> Int {
  return 3;
}

// Upper bound on the matching-point count for compound shapes (used to plan
// when no exact count exists). Returns -1 when no bound is available.
// And: intersection is contained in every child -> min of the known bounds.
// Or: union is contained in the sum (clamped to total) -> needs all bounds.
// Not: exact when the child is a single predicate, otherwise unknown.
pub fn filter_matching_upper(payloads: &PayloadStore, expr: &FilterExpr, total: Int) -> Int {
  match expr {
    Eq(field, value) => { return payload_store_index_count_eq(payloads, field, value); }
    Range(field, lo, hi) => { return payload_store_index_count_range(payloads, field, lo, hi); }
    Exists(field) => { return payload_store_index_field_count(payloads, field); }
    And(children) => {
      if children.len() == 0 { return total; }
      var best: Int = total;
      var known: Bool = false;
      var i: Int = 0;
      while i < children.len() {
        var b = filter_matching_upper(payloads, &children[i], total);
        if b >= 0 {
          if !known || b < best { best = b; }
          known = true;
        }
        i = i + 1;
      }
      if !known { return -1; }
      return best;
    }
    Or(children) => {
      if children.len() == 0 { return 0; }
      var sum: Int = 0;
      var i: Int = 0;
      while i < children.len() {
        var b = filter_matching_upper(payloads, &children[i], total);
        if b < 0 { return -1; }
        sum = sum + b;
        i = i + 1;
      }
      if sum > total { sum = total; }
      return sum;
    }
    Not(clauses) => {
      if clauses.len() == 0 { return total; }
      var c = filter_matching_count(payloads, &clauses[0]);
      if c >= 0 { return total - c; }
      return -1;
    }
    _ => { return -1; }
  }
}

// Exact candidate ids for the index plan (Eq/Range/Exists; [] otherwise --
// the planner chooses the index plan exclusively for those shapes).
pub fn filter_plan_candidates(payloads: &PayloadStore, expr: &FilterExpr) -> Vec[Int] {
  match expr {
    Eq(field, value) => { return payload_store_index_eq(payloads, field, value); }
    Range(field, lo, hi) => { return payload_store_index_range(payloads, field, lo, hi); }
    Exists(field) => { return payload_store_index_field_ids(payloads, field); }
    _ => { return Vec[Int].new(); }
  }
}

// Choose the plan for a filtered exact search over `total` stored points at
// top-k `k`. Exact single-predicate counts: index when clearly selective
// (fewer than a quarter), post for a known k-or-more majority, scan
// otherwise (including empty-match, which the index answers trivially empty).
// Compound shapes use the upper bound (post may under-fill -> the caller
// falls back); unknown shapes scan.
pub fn choose_filter_plan(payloads: &PayloadStore, expr: &FilterExpr, total: Int, k: Int) -> Int {
  var exact: Int = filter_matching_count(payloads, expr);
  if exact >= 0 {
    if exact == 0 { return filter_plan_index(); }
    if exact * 4 < total { return filter_plan_index(); }
    if exact >= k && exact * 2 >= total { return filter_plan_post(); }
    return filter_plan_scan();
  }
  var upper: Int = filter_matching_upper(payloads, expr, total);
  if upper < 0 { return filter_plan_scan(); }
  if upper < k { return filter_plan_scan(); }
  if upper * 2 < total { return filter_plan_scan(); }
  return filter_plan_post();
}
