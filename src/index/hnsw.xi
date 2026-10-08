// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.index.hnsw

// Navigable small-world ANN index (multi-layer HNSW, flat-array layout).
// The graph is stored as FLAT PARALLEL ARRAYS -- the bootstrap's nested
// Vec[Struct-with-Vec] graph hit 15 T001 borrow errors (AUDIT.md, "HNSW
// index"), so this implementation never borrows a nested aggregate.
//
// Layout: a fixed capacity of `hnsw_layer_capacity()` layers per node.
//   row(pos, layer) = pos * layer_capacity + layer      (into `deg`)
//   adj row base    = row(pos, layer) * m               (into `adj`)
// Live adjacency slots are `0 .. deg[row]`; unused (too-high) layers keep
// deg 0. Levels are assigned deterministically per insert (LCG seeded by the
// node's position): level 0 with probability 1 - 1/ml, then geometric.
//
// Build: for every layer the node belongs to (up to the existing top), the
// `m` nearest layer members are selected exactly and connected
// bidirectionally; a full adjacency block is pruned by replacing its
// farthest edge when the incoming edge is closer. Search: greedy descent on
// each layer above 0, then a best-first beam on layer 0 with breadth =
// max(k, ef). Results are `Vec[Neighbor]` with USER ids.

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.types.neighbor;

// Fixed layer capacity (levels 0..7; p(level >= l) ~ ml^-l, so > 3 is rare).
pub fn hnsw_layer_capacity() -> Int {
  return 8;
}

pub type HNSWGraph = {
  ids: Vec[Int];
  vectors: Vec[Vector];
  levels: Vec<Int];
  adj: Vec[Int];
  deg: Vec<Int];
  deleted: Vec[Bool];
  m: Int;
  ml: Float32;
  entry: Int;
}

pub fn hnsw_new(m: Int, ml: Float32) -> HNSWGraph
  requires: m > 0
  requires: ml > 0.0
{
  var ids = Vec[Int].new();
  var vectors = Vec[Vector].new();
  var levels = Vec[Int].new();
  var adj = Vec[Int].new();
  var deg = Vec[Int].new();
  var deleted = Vec[Bool].new();
  return HNSWGraph{
    ids: ids,
    vectors: vectors,
    levels: levels,
    adj: adj,
    deg: deg,
    deleted: deleted,
    m: m,
    ml: ml,
    entry: -1,
  };
}

pub fn hnsw_size(g: &HNSWGraph) -> Int {
  return g.ids.len();
}

pub fn hnsw_level_of(g: &HNSWGraph, pos: Int) -> Int {
  return g.levels[pos];
}

// Linear id -> position lookup (hardening: id -> position map).
pub fn hnsw_find_node_pos(g: &HNSWGraph, id: Int) -> Int {
  var i: Int = 0;
  while i < g.ids.len() {
    if g.ids[i] == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Tombstone a node by id. The node stays in the graph as a routing node
// (its edges are kept) but `hnsw_search` never returns it. Idempotent:
// returns false for an unknown id or an already-deleted node.
pub fn hnsw_delete(g: &mut HNSWGraph, id: Int) -> Bool {
  var pos: Int = hnsw_find_node_pos(g, id);
  if pos < 0 { return false; }
  if g.deleted[pos] { return false; }
  g.deleted[pos] = true;
  return true;
}

// Live (non-tombstoned) node count.
pub fn hnsw_live_count(g: &HNSWGraph) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < g.deleted.len() {
    if !g.deleted[i] { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn adj_row(pos: Int, layer: Int) -> Int {
  return pos * hnsw_layer_capacity() + layer;
}

// Deterministic level assignment (LCG seeded by the node position).
fn assign_level(salt: Int, ml: Float32) -> Int {
  var s: Int = (salt + 1) * 2654435761;
  if s < 0 { s = 0 - s; }
  var den: Int = ml as Int;
  if den < 2 { den = 2; }
  var lv: Int = 0;
  var top: Int = hnsw_layer_capacity() - 1;
  while lv < top {
    s = (s * 1103515245 + 12345) % 2147483648;
    // Test HIGH bits: LCG low bits are degenerate (after s % 4 == 0 the next
    // sample is always 1 mod 4, so level >= 2 would be impossible).
    if (s / 65536) % den == 0 {
      lv = lv + 1;
    } else {
      return lv;
    }
  }
  return lv;
}

// Sorted (ascending) bounded insert of a Neighbor, capacity `cap`.
fn neighbor_push_bounded(list: &mut Vec[Neighbor], id: UInt64, distance: Float32, cap: Int) {
  list.push(Neighbor{ id: id, distance: distance });
  var pos: Int = list.len() - 1;
  while pos > 0 && list[pos - 1].distance > list[pos].distance {
    var tmp = list[pos];
    list[pos] = list[pos - 1];
    list[pos - 1] = tmp;
    pos = pos - 1;
  }
  if list.len() > cap {
    list.pop();
  }
}

// Slot of `b` in `a`'s block on `layer`, or -1.
fn edge_slot(g: &HNSWGraph, a: Int, layer: Int, b: Int) -> Int {
  var row = adj_row(a, layer);
  var i: Int = 0;
  while i < g.deg[row] {
    if g.adj[row * g.m + i] == b { return i; }
    i = i + 1;
  }
  return -1;
}

// Farthest live slot in `a`'s block on `layer` (-1 when empty).
fn farthest_slot(g: &HNSWGraph, a: Int, layer: Int, metric: DistanceMetric) -> Int {
  var row = adj_row(a, layer);
  var f: Int = -1;
  var worst: Float32 = 0.0;
  var i: Int = 0;
  while i < g.deg[row] {
    var nb = g.adj[row * g.m + i];
    var d = vector_distance(&g.vectors[a], &g.vectors[nb], metric);
    if f < 0 || d > worst {
      f = i;
      worst = d;
    }
    i = i + 1;
  }
  return f;
}

// Add a directed edge a -> b on `layer`, pruning by "replace farthest when
// closer".
fn add_edge(g: &mut HNSWGraph, a: Int, layer: Int, b: Int, metric: DistanceMetric) {
  if a == b { return; }
  if edge_slot(g, a, layer, b) >= 0 { return; }
  var row = adj_row(a, layer);
  if g.deg[row] < g.m {
    g.adj[row * g.m + g.deg[row]] = b;
    g.deg[row] = g.deg[row] + 1;
    return;
  }
  var f: Int = farthest_slot(g, a, layer, metric);
  if f < 0 { return; }
  var far_id = g.adj[row * g.m + f];
  var d_new = vector_distance(&g.vectors[a], &g.vectors[b], metric);
  var d_far = vector_distance(&g.vectors[a], &g.vectors[far_id], metric);
  if d_new < d_far {
    g.adj[row * g.m + f] = b;
  }
}

// Insert a point. Re-inserting an existing id updates the vector in place
// and revives a tombstoned node (edges are kept; re-linking on update is a
// hardening TODO). A dimension mismatch (vs the first inserted vector) is
// ignored; the engine validates dimensions before calling.
pub fn hnsw_insert(g: &mut HNSWGraph, id: Int, vec: Vector, metric: DistanceMetric) {
  if g.ids.len() > 0 {
    if vec.dimension != g.vectors[0].dimension { return; }
  }
  var existing: Int = hnsw_find_node_pos(g, id);
  if existing >= 0 {
    g.vectors[existing] = vec;
    g.deleted[existing] = false;
    return;
  }
  var pos: Int = g.ids.len();
  g.ids.push(id);
  g.vectors.push(vec);
  g.deleted.push(false);
  var lv: Int = assign_level(pos, g.ml);
  g.levels.push(lv);
  var i: Int = 0;
  while i < hnsw_layer_capacity() {
    g.deg.push(0);
    i = i + 1;
  }
  i = 0;
  while i < hnsw_layer_capacity() * g.m {
    g.adj.push(0);
    i = i + 1;
  }
  if g.entry < 0 {
    g.entry = pos;
    return;
  }
  var top: Int = g.levels[g.entry];
  var lc: Int = lv;
  if lc > top { lc = top; }
  var l: Int = lc;
  while l >= 0 {
    // Exact k-NN among the layer's existing members.
    var best = Vec[Neighbor].new();
    var j: Int = 0;
    while j < pos {
      if g.levels[j] >= l {
        var d = vector_distance(&g.vectors[j], &g.vectors[pos], metric);
        neighbor_push_bounded(&mut best, j as UInt64, d, g.m);
      }
      j = j + 1;
    }
    var c: Int = 0;
    while c < best.len() {
      var cid = best[c].id as Int;
      add_edge(g, pos, l, cid, metric);
      add_edge(g, cid, l, pos, metric);
      c = c + 1;
    }
    l = l - 1;
  }
  if lv > top { g.entry = pos; }
}

// Greedy descent on one layer: walk to the local minimum from `start`.
fn greedy_layer(g: &HNSWGraph, query: &Vector, start: Int, layer: Int, metric: DistanceMetric) -> Int {
  var cur: Int = start;
  var cur_d = vector_distance(&g.vectors[cur], query, metric);
  var improved: Bool = true;
  while improved {
    improved = false;
    var row = adj_row(cur, layer);
    var j: Int = 0;
    while j < g.deg[row] {
      var nb = g.adj[row * g.m + j];
      var d = vector_distance(&g.vectors[nb], query, metric);
      if d < cur_d {
        cur = nb;
        cur_d = d;
        improved = true;
      }
      j = j + 1;
    }
  }
  return cur;
}

// Shared search: greedy descent above layer 0, then a best-first beam on
// layer 0 into `out`. Returns the number of visited nodes.
fn hnsw_search_core(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric, out: &mut Vec[Neighbor]) -> Int {
  if g.ids.len() == 0 { return 0; }
  if query.dimension != g.vectors[0].dimension { return 0; }
  var breadth: Int = ef;
  if breadth < k { breadth = k; }

  var start: Int = g.entry;
  var l: Int = g.levels[start];
  while l > 0 {
    start = greedy_layer(g, query, start, l, metric);
    l = l - 1;
  }

  var visited = Vec[Bool].new();
  var i: Int = 0;
  while i < g.ids.len() {
    visited.push(false);
    i = i + 1;
  }
  var seen: Int = 0;
  var results = Vec[Neighbor].new();
  var frontier = Vec[Neighbor].new();
  // NOTE: `frontier` entries carry node POSITIONS (internal expansion),
  // `results` entries carry USER ids (returned to the caller).
  var d0 = vector_distance(&g.vectors[start], query, metric);
  visited[start] = true;
  seen = seen + 1;
  // Tombstoned nodes stay in the graph as routers but are never returned.
  if !g.deleted[start] {
    neighbor_push_bounded(&mut results, g.ids[start] as UInt64, d0, breadth);
  }
  neighbor_push_bounded(&mut frontier, start as UInt64, d0, breadth);

  var done: Bool = false;
  while frontier.len() > 0 && !done {
    var cur = frontier[0];
    var s: Int = 1;
    while s < frontier.len() {
      frontier[s - 1] = frontier[s];
      s = s + 1;
    }
    frontier.pop();
    if results.len() >= breadth {
      var worst = results[results.len() - 1].distance;
      if cur.distance > worst { done = true; }
    }
    if !done {
      var cpos = cur.id as Int;
      var crow = adj_row(cpos, 0);
      var j: Int = 0;
      while j < g.deg[crow] {
        var npos = g.adj[crow * g.m + j];
        if !visited[npos] {
          visited[npos] = true;
          seen = seen + 1;
          var dist = vector_distance(&g.vectors[npos], query, metric);
          if results.len() < breadth {
            if !g.deleted[npos] {
              neighbor_push_bounded(&mut results, g.ids[npos] as UInt64, dist, breadth);
            }
            neighbor_push_bounded(&mut frontier, npos as UInt64, dist, breadth);
          } else {
            var worst2 = results[results.len() - 1].distance;
            if dist < worst2 {
              if !g.deleted[npos] {
                neighbor_push_bounded(&mut results, g.ids[npos] as UInt64, dist, breadth);
              }
              neighbor_push_bounded(&mut frontier, npos as UInt64, dist, breadth);
            }
          }
        }
        j = j + 1;
      }
    }
  }

  var limit: Int = k;
  if results.len() < k { limit = results.len(); }
  var t: Int = 0;
  while t < limit {
    out.push(Neighbor{ id: results[t].id, distance: results[t].distance });
    t = t + 1;
  }
  return seen;
}

// Copy-insert variant for callers that must keep their vector value (the
// engine feeds both the flat store and the graph from one upsert).
pub fn hnsw_insert_ref(g: &mut HNSWGraph, id: Int, vec: &Vector, metric: DistanceMetric) {
  var d: Int = vec.dimension as Int;
  var copy = Vector.new(d);
  var i: Int = 0;
  while i < d {
    copy.set(i, vec.get(i));
    i = i + 1;
  }
  hnsw_insert(g, id, copy, metric);
}

// Best-first search. Returns up to k ascending-by-distance neighbors
// (`ensures: result.len() <= k`); empty graph or dimension mismatch -> empty.
pub fn hnsw_search(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric) -> Vec[Neighbor]
  requires: k > 0
  ensures: result.len() <= k
{
  var out = Vec[Neighbor].new();
  var seen = hnsw_search_core(g, query, k, ef, metric, &mut out);
  return out;
}

// Visited-node count of the last search shape (latency proxy for the
// harness): number of distinct nodes the descent+beam touched.
pub fn hnsw_search_visited(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric) -> Int
  requires: k > 0
{
  var out = Vec[Neighbor].new();
  return hnsw_search_core(g, query, k, ef, metric, &mut out);
}
