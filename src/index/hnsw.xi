// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.index.hnsw

// Navigable small-world ANN index (the HNSW layer-0 core). The bootstrap
// attempt used nested Vec[Struct-with-Vec] graphs and hit 15 T001 borrow
// errors (AUDIT.md, "HNSW index"): field access on `&layer.nodes[i]` inside
// nested loops. This implementation stores the graph as FLAT PARALLEL
// ARRAYS instead: adjacency is row-major with capacity `m` per node
// (`adj[pos * m + slot]`, live slots are `0 .. deg[pos]`), so no nested
// aggregate structures are ever borrowed. Levels/multi-layer search are the
// next hardening step (see docs/hnsw-design.md).
//
// Build: each insert brute-force selects the `m` nearest existing nodes and
// connects bidirectionally, pruning a full adjacency block by replacing its
// farthest edge when the new edge is closer (the standard simple heuristic).
// Search: best-first beam from the entry point, breadth = max(k, ef), with
// the usual "closest frontier candidate farther than the current worst
// result" termination. Results are `Vec[Neighbor]` -- the index layer never
// references the query layer.

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.types.neighbor;

pub type HNSWGraph = {
  ids: Vec[Int];
  vectors: Vec[Vector];
  adj: Vec[Int];
  deg: Vec[Int];
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
  var adj = Vec[Int].new();
  var deg = Vec[Int].new();
  return HNSWGraph{
    ids: ids,
    vectors: vectors,
    adj: adj,
    deg: deg,
    m: m,
    ml: ml,
    entry: -1,
  };
}

pub fn hnsw_size(g: &HNSWGraph) -> Int {
  return g.ids.len();
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

// Slot of `b` in `a`'s adjacency block, or -1.
fn edge_slot(g: &HNSWGraph, a: Int, b: Int) -> Int {
  var i: Int = 0;
  while i < g.deg[a] {
    if g.adj[a * g.m + i] == b { return i; }
    i = i + 1;
  }
  return -1;
}

// Farthest live slot in `a`'s adjacency block (-1 when empty).
fn farthest_slot(g: &HNSWGraph, a: Int, metric: DistanceMetric) -> Int {
  var f: Int = -1;
  var worst: Float32 = 0.0;
  var i: Int = 0;
  while i < g.deg[a] {
    var nb = g.adj[a * g.m + i];
    var d = vector_distance(&g.vectors[a], &g.vectors[nb], metric);
    if f < 0 || d > worst {
      f = i;
      worst = d;
    }
    i = i + 1;
  }
  return f;
}

// Add a directed edge a -> b, pruning by "replace farthest when closer".
fn add_edge(g: &mut HNSWGraph, a: Int, b: Int, metric: DistanceMetric) {
  if a == b { return; }
  if edge_slot(g, a, b) >= 0 { return; }
  if g.deg[a] < g.m {
    g.adj[a * g.m + g.deg[a]] = b;
    g.deg[a] = g.deg[a] + 1;
    return;
  }
  var f: Int = farthest_slot(g, a, metric);
  if f < 0 { return; }
  var far_id = g.adj[a * g.m + f];
  var d_new = vector_distance(&g.vectors[a], &g.vectors[b], metric);
  var d_far = vector_distance(&g.vectors[a], &g.vectors[far_id], metric);
  if d_new < d_far {
    g.adj[a * g.m + f] = b;
  }
}

// Insert a point. A dimension mismatch (vs the first inserted vector) is
// ignored; the engine validates dimensions before calling.
pub fn hnsw_insert(g: &mut HNSWGraph, id: Int, vec: Vector, metric: DistanceMetric) {
  if g.ids.len() > 0 {
    if vec.dimension != g.vectors[0].dimension { return; }
  }
  var pos: Int = g.ids.len();
  g.ids.push(id);
  g.vectors.push(vec);
  var slot: Int = 0;
  while slot < g.m {
    g.adj.push(0);
    slot = slot + 1;
  }
  g.deg.push(0);
  if g.entry < 0 {
    g.entry = pos;
    return;
  }
  // Brute-force the m nearest existing nodes (positions 0 .. pos-1).
  var best = Vec[Neighbor].new();
  var i: Int = 0;
  while i < pos {
    var dist = vector_distance(&g.vectors[i], &g.vectors[pos], metric);
    neighbor_push_bounded(&mut best, i as UInt64, dist, g.m);
    i = i + 1;
  }
  var c: Int = 0;
  while c < best.len() {
    var cid = best[c].id as Int;
    add_edge(g, pos, cid, metric);
    add_edge(g, cid, pos, metric);
    c = c + 1;
  }
}

// Best-first beam search. Returns up to k ascending-by-distance neighbors
// (`ensures: result.len() <= k`); empty graph or dimension mismatch -> empty.
pub fn hnsw_search(g: &HNSWGraph, query: &Vector, k: Int, ef: Int, metric: DistanceMetric) -> Vec[Neighbor]
  requires: k > 0
  ensures: result.len() <= k
{
  var out = Vec[Neighbor].new();
  if g.ids.len() == 0 { return out; }
  if query.dimension != g.vectors[0].dimension { return out; }
  var breadth: Int = ef;
  if breadth < k { breadth = k; }

  var visited = Vec[Bool].new();
  var i: Int = 0;
  while i < g.ids.len() {
    visited.push(false);
    i = i + 1;
  }
  var results = Vec[Neighbor].new();
  var frontier = Vec[Neighbor].new();
  // NOTE: `frontier` entries carry node POSITIONS (internal expansion),
  // `results` entries carry USER ids (returned to the caller).
  var entry = g.entry;
  var d0 = vector_distance(&g.vectors[entry], query, metric);
  visited[entry] = true;
  neighbor_push_bounded(&mut results, g.ids[entry] as UInt64, d0, breadth);
  neighbor_push_bounded(&mut frontier, entry as UInt64, d0, breadth);

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
      var j: Int = 0;
      while j < g.deg[cpos] {
        var npos = g.adj[cpos * g.m + j];
        if !visited[npos] {
          visited[npos] = true;
          var dist = vector_distance(&g.vectors[npos], query, metric);
          if results.len() < breadth {
            neighbor_push_bounded(&mut results, g.ids[npos] as UInt64, dist, breadth);
            neighbor_push_bounded(&mut frontier, npos as UInt64, dist, breadth);
          } else {
            var worst2 = results[results.len() - 1].distance;
            if dist < worst2 {
              neighbor_push_bounded(&mut results, g.ids[npos] as UInt64, dist, breadth);
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
  return out;
}
