// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// L-6 phase B probe: intra-collection scatter-gather over a hash split.
//
// ARMS (each names its recall definition, reference study 04):
//   MAP:       split schema load/refuse/persist round-trip; owner = first part.
//   WRITE:     create fan-out + batch upsert fan-out (part header filtering);
//              point get/delete hash routing; per-part counts balanced.
//   FLAT:      ID-set equality vs a single-node exact oracle (VectorDBBench
//              style); offset and after_id pages reconstruct the merged
//              (distance asc, id asc) order, including an exact tie cursor.
//   HNSW:      ID-set recall AND distance-threshold recall (ann-benchmarks
//              style, epsilon 1e-3) vs the same flat oracle, measured for
//              oversample 1/2/3; the gate prints each arm and asserts floors.
//   FILTER:    wire filter pushdown (eq/range) compared to the exact oracle;
//              filtered HNSW recall measured with the same oversample knob.
//   MODES:     strict default -> 503 with a per-shard report; partial opt-in
//              -> live hits + "partial": true; range/batch split -> 501.
//   ADMIN:     split stats sum parts; move/drain refuse a split collection.
// Exit = failed checks.

module probe_scatter_gather

use xiom.vector.api.router;
use xiom.vector.api.http_service;
use xiom.vector.api.sharding;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.query.search_service;
use xiom.serialize.json;
use xiom.string;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// ---- request builders -----------------------------------------------------

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

// Extra headers must end with CRLF; the router appends its internal hints
// after them, so the LAST match is the router's decision.
fn mk_req_h(method: Str, path: Str, body: Str, extra: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\n" + extra
    + "Content-Length: " + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn write_text(path: Str, s: Str) -> Bool {
  var b = slice.str_bytes(s);
  match io.write_file_bytes(path, &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn find_term(b: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

fn resp_body(resp: &Vec[UInt8]) -> Str {
  var t = find_term(resp);
  if t < 0 { return ""; }
  var acc = Vec[UInt8].new();
  var i: Int = t + 4;
  while i < resp.len() { acc.push(resp[i]); i = i + 1; }
  return Str::from_utf8(&acc);
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

fn body_json(resp: &Vec[UInt8]) -> JsonValue {
  match json.json_parse(resp_body(resp)) {
    Ok(v) => { return v; }
    Err(_) => {}
  }
  return json.json_null();
}

fn jnum(resp: &Vec[UInt8], key: Str) -> Float64 {
  match json.json_get(body_json(resp), key) {
    Some(x) => {
      match x {
        Number(n) => { return n; }
        _ => {}
      }
    }
    None => {}
  }
  return -999999.0;
}

fn jbool(resp: &Vec[UInt8], key: Str) -> Bool {
  match json.json_get(body_json(resp), key) {
    Some(x) => {
      match x {
        Bool(b) => { return b; }
        _ => {}
      }
    }
    None => {}
  }
  return false;
}

fn jstr(resp: &Vec[UInt8], key: Str) -> Str {
  match json.json_get(body_json(resp), key) {
    Some(x) => {
      match x {
        String(s) => { return s; }
        _ => {}
      }
    }
    None => {}
  }
  return "";
}

fn jpath_str(resp: &Vec[UInt8], k1: Str, k2: Str) -> Str {
  var path = Vec[Str].new();
  path.push(k1);
  path.push(k2);
  match json.json_get_path(body_json(resp), &path) {
    Some(x) => {
      match x {
        String(s) => { return s; }
        _ => {}
      }
    }
    None => {}
  }
  return "";
}

fn jpath_arr_len(resp: &Vec[UInt8], k1: Str, k2: Str) -> Int {
  var path = Vec[Str].new();
  path.push(k1);
  path.push(k2);
  match json.json_get_path(body_json(resp), &path) {
    Some(x) => {
      match x {
        Array(items) => { return items.len(); }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

fn jfail_has(resp: &Vec[UInt8], want: Str) -> Bool {
  match json.json_get(body_json(resp), "failed_shards") {
    Some(x) => {
      match x {
        Array(items) => {
          var i: Int = 0;
          while i < items.len() {
            match json.json_get(items[i], "id") {
              Some(iv) => {
                match iv {
                  String(s) => { if s == want { return true; } }
                  _ => {}
                }
              }
              None => {}
            }
            i = i + 1;
          }
        }
        _ => {}
      }
    }
    None => {}
  }
  return false;
}

fn jhits_len(resp: &Vec[UInt8]) -> Int {
  match json.json_get(body_json(resp), "hits") {
    Some(x) => {
      match x {
        Array(items) => { return items.len(); }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

fn jhits_id(resp: &Vec[UInt8], idx: Int) -> Int {
  match json.json_get(body_json(resp), "hits") {
    Some(x) => {
      match x {
        Array(items) => {
          if idx >= 0 && idx < items.len() {
            match json.json_get(items[idx], "id") {
              Some(iv) => {
                match iv {
                  Number(n) => { return n as Int; }
                  _ => {}
                }
              }
              None => {}
            }
          }
        }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

fn jhits_dist(resp: &Vec[UInt8], idx: Int) -> Float32 {
  match json.json_get(body_json(resp), "hits") {
    Some(x) => {
      match x {
        Array(items) => {
          if idx >= 0 && idx < items.len() {
            match json.json_get(items[idx], "distance") {
              Some(dv) => {
                match dv {
                  Number(n) => { return n as Float32; }
                  _ => {}
                }
              }
              None => {}
            }
          }
        }
        _ => {}
      }
    }
    None => {}
  }
  return -1.0;
}

fn hit_ids(resp: &Vec[UInt8]) -> Vec[Int] {
  var out = Vec[Int].new();
  var n = jhits_len(resp);
  var i: Int = 0;
  while i < n { out.push(jhits_id(resp, i)); i = i + 1; }
  return out;
}

fn ids_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn ids_text(a: &Vec[Int]) -> Str {
  var s = "[";
  var i: Int = 0;
  while i < a.len() {
    if i > 0 { s = s + ","; }
    s = s + convert.int_to_string(a[i]);
    i = i + 1;
  }
  return s + "]";
}

fn id_in(a: &Vec[Int], id: Int) -> Bool {
  var i: Int = 0;
  while i < a.len() {
    if a[i] == id { return true; }
    i = i + 1;
  }
  return false;
}

// ---- dataset --------------------------------------------------------------

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn rand_vec(state: &mut Int, dim: Int) -> Vector {
  var v = Vector.new(dim);
  var i: Int = 0;
  while i < dim {
    state = lcg_next(state);
    var c = (state % 4001) as Float32;
    v.set(i, c / 1000.0 - 2.0);
    i = i + 1;
  }
  return v;
}

fn dup_vec(v: &Vector) -> Vector {
  var out = Vector.new(v.dimension);
  var i: Int = 0;
  while i < v.dimension { out.set(i, v.data[i]); i = i + 1; }
  return out;
}

// Positive-coordinate copy (DotProduct distances become negative for a
// ones query, which is exactly the sentinel case the flag must represent).
fn abs_vec(v: &Vector) -> Vector {
  var out = Vector.new(v.dimension);
  var i: Int = 0;
  while i < v.dimension {
    var x = v.data[i];
    if x < 0.0 { x = 0.0 - x; }
    out.set(i, x + 0.1);
    i = i + 1;
  }
  return out;
}

fn ones_vec(dim: Int) -> Vector {
  var out = Vector.new(dim);
  var i: Int = 0;
  while i < dim { out.set(i, 1.0); i = i + 1; }
  return out;
}

fn vec_json(v: &Vector) -> Str {
  var s = "[";
  var i: Int = 0;
  while i < v.dimension {
    if i > 0 { s = s + ","; }
    s = s + convert.float_to_string(v.data[i] as Float64);
    i = i + 1;
  }
  return s + "]";
}

fn upsert_body(ids: &Vec[Int], vecs: &Vec[Vector]) -> Str {
  var s = "{\"ids\":[";
  var i: Int = 0;
  while i < ids.len() {
    if i > 0 { s = s + ","; }
    s = s + convert.int_to_string(ids[i]);
    i = i + 1;
  }
  s = s + "],\"vectors\":[";
  i = 0;
  while i < vecs.len() {
    if i > 0 { s = s + ","; }
    s = s + vec_json(&vecs[i]);
    i = i + 1;
  }
  return s + "]}";
}

fn search_body(coll: Str, q: &Vector, k: Int) -> Str {
  return "{\"collection\":\"" + coll + "\",\"vector\":" + vec_json(q)
    + ",\"top_k\":" + convert.int_to_string(k) + "}";
}

fn search_body_page(coll: Str, q: &Vector, k: Int, offset: Int) -> Str {
  return "{\"collection\":\"" + coll + "\",\"vector\":" + vec_json(q)
    + ",\"top_k\":" + convert.int_to_string(k)
    + ",\"offset\":" + convert.int_to_string(offset) + "}";
}

fn search_body_after(coll: Str, q: &Vector, k: Int, after_id: Int) -> Str {
  return "{\"collection\":\"" + coll + "\",\"vector\":" + vec_json(q)
    + ",\"top_k\":" + convert.int_to_string(k)
    + ",\"after_id\":" + convert.int_to_string(after_id) + "}";
}

fn search_body_partial(coll: Str, q: &Vector, k: Int, on: Bool) -> Str {
  var p = "false";
  if on { p = "true"; }
  return "{\"collection\":\"" + coll + "\",\"vector\":" + vec_json(q)
    + ",\"top_k\":" + convert.int_to_string(k) + ",\"partial\":" + p + "}";
}

fn search_body_filter(coll: Str, q: &Vector, k: Int, filter: Str) -> Str {
  return "{\"collection\":\"" + coll + "\",\"vector\":" + vec_json(q)
    + ",\"top_k\":" + convert.int_to_string(k) + ",\"filter\":" + filter + "}";
}

// ---- mapping fixtures -----------------------------------------------------

fn shard_entry(id: Str, port: Int) -> Str {
  return "{\"id\":\"" + id + "\",\"url\":\"http://127.0.0.1:" + convert.int_to_string(port) + "\"}";
}

fn mapping_text(ver: Int, docs_parts: Str, hdocs_parts: Str) -> Str {
  return "{\"version\":" + convert.int_to_string(ver)
    + ",\"shards\":[" + shard_entry("s1", 7711) + "," + shard_entry("s2", 7712) + ","
    + shard_entry("s3", 7713) + "],\"collections\":{\"docs\":\"s1\",\"hdocs\":\"s1\",\"dotdocs\":\"s1\"}"
    + ",\"split\":{\"docs\":" + docs_parts + ",\"hdocs\":" + hdocs_parts
    + ",\"dotdocs\":[\"s1\",\"s2\",\"s3\"]}}";
}

fn mapping_text_missing(ver: Int) -> Str {
  return "{\"version\":" + convert.int_to_string(ver)
    + ",\"shards\":[" + shard_entry("s1", 7711) + "," + shard_entry("s2", 7712) + ","
    + shard_entry("s3", 7713) + "," + shard_entry("s4", 7714)
    + "],\"collections\":{\"docs\":\"s1\"},\"split\":{\"docs\":[\"s1\",\"s2\",\"s3\",\"s4\"]}}";
}

// ---- shard context helpers ------------------------------------------------

fn shard_engine_get(shards: &mut Vec[RouterShard], idx: Int) -> VectorEngine {
  return shards[idx].engine;
}

fn shard_engine_set(shards: &mut Vec[RouterShard], idx: Int, e: VectorEngine) {
  var sh = shards[idx];
  sh.engine = e;
  shards[idx] = sh;
}

fn truth_page_ids(eng: &VectorEngine, q: &Vector, k: Int, offset: Int) -> Vec[Int] {
  var ids = Vec[Int].new();
  match search_page(eng, q, k, offset) {
    Ok(h) => { var i: Int = 0; while i < h.items.len() { ids.push(h.items[i].id); i = i + 1; } }
    Err(_) => {}
  }
  return ids;
}

fn truth_page(eng: &VectorEngine, q: &Vector, k: Int) -> SearchHits {
  match search_page(eng, q, k, 0) {
    Ok(h) => { return h; }
    Err(_) => {}
  }
  return SearchHits{ items: Vec[SearchResult].new() };
}

fn truth_filtered_ids(eng: &VectorEngine, q: &Vector, k: Int, f: &FilterExpr) -> Vec[Int] {
  var ids = Vec[Int].new();
  match search_filtered(eng, q, k, f) {
    Ok(h) => { var i: Int = 0; while i < h.items.len() { ids.push(h.items[i].id); i = i + 1; } }
    Err(_) => {}
  }
  return ids;
}

fn attach_payloads(eng: &mut VectorEngine, coll: Str, ids: &Vec[Int]) {
  match select_collection(eng, coll) {
    Ok(_) => {}
    Err(_) => { return; }
  }
  var i: Int = 0;
  while i < ids.len() {
    var p = payload_new();
    var bucket: Str = "blue";
    if ids[i] % 2 == 0 { bucket = "red"; }
    payload_set(&mut p, "bucket", FieldValue.TextVal(bucket));
    payload_set(&mut p, "rank", FieldValue.IntVal(ids[i] % 10));
    let _ = set_payload(eng, ids[i], p);
    i = i + 1;
  }
}

// Expected number of ids on part `slot` of `count`.
fn expected_part_count(ids: &Vec[Int], slot: Int, count: Int) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < ids.len() {
    if sharding.shard_slot(ids[i], count) == slot { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn main() -> Int {
  io.println("=== xvector probe: L-6 scatter-gather (hash split) ===");
  var fails: Int = 0;

  var p_map = "out/scatter_probe_mapping.json";
  var p_bad = "out/scatter_probe_bad.json";
  var p_persist = "out/scatter_probe_persist.json";
  var p_missing = "out/scatter_probe_missing.json";
  let _c0 = io.remove_file(p_map);
  let _c1 = io.remove_file(p_bad);
  let _c2 = io.remove_file(p_persist);
  let _c3 = io.remove_file(p_missing);

  // ---- mapping schema -----------------------------------------------------
  var parts3 = "[\"s1\",\"s2\",\"s3\"]";
  let _w0 = write_text(p_map, mapping_text(1, parts3, parts3));
  var m1 = router_mapping_load(p_map);
  fails = check(m1.ok && m1.version == 1 && m1.coll_names.len() == 3
    && router_mapping_split_count(&m1, 0) == 3
    && router_mapping_split_count(&m1, 2) == 3
    && router_mapping_part_at(&m1, 0, 0) == 0
    && router_mapping_part_for_id(&m1, 0, 7) == sharding.shard_slot(7, 3),
    "map: split v1 loads (docs/hdocs/dotdocs x3; owner first part)", fails);
  fails = check(router_mapping_owner(&m1, "docs") == 0, "map: docs owner is s1", fails);

  var bads = Vec[Str].new();
  var badn = Vec[Str].new();
  bads.push(mapping_text(1, "[\"s1\",\"zz\"]", parts3)); badn.push("split unknown shard refused");
  bads.push(mapping_text(1, "[\"s1\"]", parts3)); badn.push("split single part refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"u\"},{\"id\":\"s2\",\"url\":\"v\"}],\"collections\":{\"docs\":\"s2\"},\"split\":{\"docs\":[\"s1\",\"s2\"]}}");
  badn.push("split owner must be first part");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"u\"},{\"id\":\"s2\",\"url\":\"v\"}],\"collections\":{\"docs\":\"s1\"},\"split\":{\"logs\":[\"s1\",\"s2\"]}}");
  badn.push("split collection not mapped");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"u\"},{\"id\":\"s2\",\"url\":\"v\"}],\"collections\":{\"docs\":\"s1\"},\"split\":{\"docs\":[\"s1\",\"s1\"]}}");
  badn.push("duplicate split part");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"u\"},{\"id\":\"s2\",\"url\":\"v\"}],\"collections\":{\"docs\":\"s1\"},\"split\":[]}");
  badn.push("split must be an object");
  var bi: Int = 0;
  while bi < bads.len() {
    let _wb = write_text(p_bad, bads[bi]);
    var mb = router_mapping_load(p_bad);
    fails = check(!mb.ok, "map: " + badn[bi], fails);
    bi = bi + 1;
  }
  let _c4 = io.remove_file(p_bad);

  // Persist must round-trip the split arrays (admin edits use this path).
  let _wp = io.remove_file(p_persist);
  fails = check(router_mapping_persist(&m1, p_persist), "map: split persist writes", fails);
  var mp = router_mapping_load(p_persist);
  fails = check(mp.ok && mp.version == 1 && router_mapping_split_count(&mp, 0) == 3
    && router_mapping_part_at(&mp, 0, 1) == 1, "map: split persist reloads byte-equivalent parts", fails);

  // ---- shard contexts + router -------------------------------------------
  var shards = Vec[RouterShard].new();
  var e1 = engine_new();
  var e2 = engine_new();
  var e3 = engine_new();
  var st1 = service_state_new();
  var st2 = service_state_new();
  var st3 = service_state_new();
  shards.push(RouterShard{ id: "s1", engine: e1, state: st1 });
  shards.push(RouterShard{ id: "s2", engine: e2, state: st2 });
  shards.push(RouterShard{ id: "s3", engine: e3, state: st3 });
  var rt = router_state_new(p_map);
  fails = check(rt.ok && rt.mapping.version == 1, "router: starts on the split mapping", fails);

  // ---- create fan-out -----------------------------------------------------
  var c_docs = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":12,\"metric\":\"euclidean\"}"));
  fails = check(status_of(&c_docs) == 201, "create: docs fan-out -> 201", fails);
  var c_hdocs = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/collections", "{\"name\":\"hdocs\",\"dim\":12,\"metric\":\"euclidean\",\"index\":\"hnsw\",\"m\":8,\"ef_construction\":64,\"ef_search\":8}"));
  fails = check(status_of(&c_hdocs) == 201, "create: hdocs HNSW fan-out -> 201", fails);
  var c_dot = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/collections", "{\"name\":\"dotdocs\",\"dim\":12,\"metric\":\"dot\"}"));
  fails = check(status_of(&c_dot) == 201, "create: dotdocs (DotProduct) fan-out -> 201", fails);
  var all_created: Bool = true;
  var si: Int = 0;
  while si < 3 {
    var lr = router_forward_direct(&mut shards, rt.mapping.shard_ids[si], &mk_req("GET", "/collections", ""));
    var lb = resp_body(&lr);
    if !(str_contains(lb, "docs") && str_contains(lb, "hdocs") && str_contains(lb, "dotdocs")) { all_created = false; }
    si = si + 1;
  }
  fails = check(all_created, "create: all three collections exist on all parts", fails);

  // Client-supplied part hints must not shadow the router's appended hints
  // (http_header_last). A spoofed slot=0/count=3 would otherwise put the
  // whole batch on s1 and fail the per-part count below.
  var spoof_ids = Vec[Int].new();
  var spoof_vecs = Vec[Vector].new();
  var spoof_state: Int = 777;
  var spoof_dim: Int = 12;
  var spoof_i: Int = 0;
  while spoof_i < 6 {
    spoof_ids.push(spoof_i + 1);
    spoof_vecs.push(rand_vec(&mut spoof_state, spoof_dim));
    spoof_i = spoof_i + 1;
  }
  var spoof_req = mk_req_h("POST", "/collections/docs/points", upsert_body(&spoof_ids, &spoof_vecs),
    "X-XVector-Part-Slot: 0\r\nX-XVector-Part-Count: 3\r\n");
  var spoof_up = router_handle(&mut rt, &mut shards, &spoof_req);
  var spoof_ok: Bool = status_of(&spoof_up) == 200 && jnum(&spoof_up, "count") == 6.0;
  si = 0;
  while si < 3 {
    var es = shard_engine_get(&mut shards, si);
    if engine_size(&es) != 2 { spoof_ok = false; }
    si = si + 1;
  }
  fails = check(spoof_ok, "write: client part headers cannot shadow router placement", fails);

  // ---- dataset + writes ---------------------------------------------------
  var n: Int = 120;
  var dim: Int = 12;
  var ids = Vec[Int].new();
  var vecs = Vec[Vector].new();
  var state: Int = 424242;
  var i: Int = 0;
  while i < n {
    ids.push(i + 1);
    vecs.push(rand_vec(&mut state, dim));
    i = i + 1;
  }
  // Exact-distance tie across parts: ids 2 and 3 share id 1's vector.
  vecs[2] = dup_vec(&vecs[1]);

  var ub = upsert_body(&ids, &vecs);
  var up_docs = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections/docs/points", ub));
  fails = check(status_of(&up_docs) == 200 && jnum(&up_docs, "count") == n as Float64,
    "write: docs batch fan-out sums to 120", fails);
  var up_hdocs = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections/hdocs/points", ub));
  fails = check(status_of(&up_hdocs) == 200 && jnum(&up_hdocs, "count") == n as Float64,
    "write: hdocs batch fan-out sums to 120", fails);

  var balanced: Bool = true;
  si = 0;
  while si < 3 {
    var e = shard_engine_get(&mut shards, si);
    var got = engine_size(&e);
    var want = expected_part_count(&ids, si, 3);
    if got != want { balanced = false; }
    si = si + 1;
  }
  fails = check(balanced, "write: hash parts hold exactly their id slices (no duplicates)", fails);

  // DotProduct split arm: positive-coordinate points + an all-ones query
  // make the cursor distances negative (the old -1 sentinel would fail).
  var dot_ids = Vec[Int].new();
  var dot_vecs = Vec[Vector].new();
  i = 0;
  while i < 30 {
    dot_ids.push(ids[i]);
    dot_vecs.push(abs_vec(&vecs[i]));
    i = i + 1;
  }
  var dot_ub = upsert_body(&dot_ids, &dot_vecs);
  var up_dot = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/collections/dotdocs/points", dot_ub));
  fails = check(status_of(&up_dot) == 200 && jnum(&up_dot, "count") == 30.0,
    "write: dotdocs batch fan-out sums to 30", fails);

  // Single-node exact oracles.
  var truth = engine_new();
  let _tc = create_named_collection(&mut truth, "docs", dim, DistanceMetric.Euclidean);
  let _tu = upsert_many(&mut truth, &ids, &vecs);
  var truth_h = engine_new();
  let _thc = create_named_collection(&mut truth_h, "hdocs", dim, DistanceMetric.Euclidean);
  let _thi = set_index(&mut truth_h, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 64, ef_search: 8 });
  let _thu = upsert_many(&mut truth_h, &ids, &vecs);
  var truth_dot = engine_new();
  let _tdc = create_named_collection(&mut truth_dot, "dotdocs", dim, DistanceMetric.DotProduct);
  let _tdu = upsert_many(&mut truth_dot, &dot_ids, &dot_vecs);

  // ---- point hash routing -------------------------------------------------
  var probe_id: Int = 777;
  var pv = rand_vec(&mut state, dim);
  var pv_ids = Vec[Int].new();
  var pv_vecs = Vec[Vector].new();
  pv_ids.push(probe_id);
  pv_vecs.push(dup_vec(&pv));
  var pv_body = upsert_body(&pv_ids, &pv_vecs);
  var pv_up = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections/docs/points", pv_body));
  fails = check(status_of(&pv_up) == 200 && jnum(&pv_up, "count") == 1.0,
    "write: single point 777 routes to one part", fails);
  var pv_get = router_handle(&mut rt, &mut shards,
    &mk_req("GET", "/collections/docs/points?id=777", ""));
  fails = check(status_of(&pv_get) == 200, "get: split point routed by hash -> 200", fails);
  var pv_del = router_handle(&mut rt, &mut shards,
    &mk_req("DELETE", "/collections/docs/points?id=777", ""));
  fails = check(status_of(&pv_del) == 200 && jbool(&pv_del, "removed"),
    "delete: split point routed by hash -> removed", fails);
  var pv_gone = router_handle(&mut rt, &mut shards,
    &mk_req("GET", "/collections/docs/points?id=777", ""));
  fails = check(status_of(&pv_gone) == 404, "get: deleted split point -> 404", fails);

  // ---- Flat exactness + pagination ---------------------------------------
  router_set_oversample(&mut rt, 1);
  var qstate: Int = 909090;
  var queries = Vec[Vector].new();
  i = 0;
  while i < 12 { queries.push(rand_vec(&mut qstate, dim)); i = i + 1; }
  // Query equal to point 2's vector: ids 2 and 3 tie at distance 0.
  queries.push(dup_vec(&vecs[1]));

  var flat_ok: Bool = true;
  var qi: Int = 0;
  while qi < queries.len() {
    var q = queries[qi];
    var want = truth_page_ids(&truth, &q, 10, 0);
    var rr = router_handle(&mut rt, &mut shards,
      &mk_req("POST", "/search", search_body("docs", &q, 10)));
    if status_of(&rr) != 200 || !ids_eq(&hit_ids(&rr), &want) { flat_ok = false; }
    qi = qi + 1;
  }
  fails = check(flat_ok, "flat: ID-set equality vs single-node exact oracle (12 queries)", fails);

  // Offset pages reconstruct the full order.
  var q0 = queries[0];
  var full = truth_page_ids(&truth, &q0, n, 0);
  var walked = Vec[Int].new();
  var off: Int = 0;
  var off_ok: Bool = true;
  while off < full.len() {
    var rr2 = router_handle(&mut rt, &mut shards,
      &mk_req("POST", "/search", search_body_page("docs", &q0, 7, off)));
    if status_of(&rr2) != 200 { off_ok = false; }
    var h = hit_ids(&rr2);
    var j: Int = 0;
    while j < h.len() {
      if off + j >= full.len() || h[j] != full[off + j] { off_ok = false; }
      walked.push(h[j]);
      j = j + 1;
    }
    off = off + 7;
  }
  fails = check(off_ok && ids_eq(&walked, &full), "flat: offset pages are gap-free and reconstruct the order", fails);

  // After-id pages, including the 2/3 tie cursor.
  var tie_q = queries[12];
  var tie_page = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/search", search_body_page("docs", &tie_q, 2, 0)));
  fails = check(status_of(&tie_page) == 200 && jhits_len(&tie_page) == 2
    && jhits_id(&tie_page, 0) == 2 && jhits_id(&tie_page, 1) == 3,
    "flat: exact tie ordered by id ascending (2 then 3)", fails);
  var tie_next = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/search", search_body_after("docs", &tie_q, 2, 3)));
  fails = check(status_of(&tie_next) == 200 && jhits_len(&tie_next) == 2
    && jhits_id(&tie_next, 0) > 3, "flat: after_id 3 continues strictly after the tie", fails);

  var cursor_ok: Bool = true;
  var page_ids = truth_page_ids(&truth, &q0, 7, 0);
  var cursor: Int = page_ids[page_ids.len() - 1];
  var rec = Vec[Int].new();
  var pj: Int = 0;
  while pj < page_ids.len() { rec.push(page_ids[pj]); pj = pj + 1; }
  var round: Int = 0;
  while round < 3 {
    var rr3 = router_handle(&mut rt, &mut shards,
      &mk_req("POST", "/search", search_body_after("docs", &q0, 7, cursor)));
    if status_of(&rr3) != 200 { cursor_ok = false; }
    var h3 = hit_ids(&rr3);
    pj = 0;
    while pj < h3.len() { rec.push(h3[pj]); pj = pj + 1; }
    if h3.len() > 0 { cursor = h3[h3.len() - 1]; }
    round = round + 1;
  }
  var want3 = truth_page_ids(&truth, &q0, 28, 0);
  if !ids_eq(&rec, &want3) {
    io.println("    diag after rec(" + convert.int_to_string(rec.len()) + ")=" + ids_text(&rec));
    io.println("    diag after want(" + convert.int_to_string(want3.len()) + ")=" + ids_text(&want3));
  }
  fails = check(cursor_ok && ids_eq(&rec, &want3), "flat: after_id chained pages match exact ranks 0..27", fails);

  // DotProduct cursor: the cursor's distance is NEGATIVE, so this arm fails
  // if any layer still treats -1 as "no cursor" or rejects d < 0.
  var dot_q = ones_vec(dim);
  var dot_head = truth_page(&truth_dot, &dot_q, 4);
  var dot_cursor: Int = -1;
  var dot_cursor_d: Float32 = 0.0;
  if dot_head.items.len() == 4 {
    dot_cursor = dot_head.items[3].id;
    dot_cursor_d = dot_head.items[3].distance;
  }
  var dot_want = truth_page_ids(&truth_dot, &dot_q, 6, 4);
  var dot_rr = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/search", search_body_after("dotdocs", &dot_q, 6, dot_cursor)));
  fails = check(dot_cursor >= 0 && dot_cursor_d < 0.0
    && status_of(&dot_rr) == 200 && ids_eq(&hit_ids(&dot_rr), &dot_want),
    "flat: DotProduct negative-distance cursor advances exactly", fails);

  // ---- HNSW recall arms ---------------------------------------------------
  var qn: Int = 12;
  var os: Int = 1;
  var id_recall1: Float64 = 0.0;
  var dist_recall1: Float64 = 0.0;
  var id_recall3: Float64 = 0.0;
  var dist_recall3: Float64 = 0.0;
  while os <= 3 {
    router_set_oversample(&mut rt, os);
    var id_hits: Int = 0;
    var dist_hits: Int = 0;
    var qj: Int = 0;
    while qj < qn {
      var qq = queries[qj];
      var truth_hits = truth_page(&truth, &qq, 10);
      var rr4 = router_handle(&mut rt, &mut shards,
        &mk_req("POST", "/search", search_body("hdocs", &qq, 10)));
      var got = hit_ids(&rr4);
      var truth_ids = Vec[Int].new();
      var t: Int = 0;
      while t < truth_hits.items.len() { truth_ids.push(truth_hits.items[t].id); t = t + 1; }
      t = 0;
      while t < got.len() {
        if id_in(&truth_ids, got[t]) { id_hits = id_hits + 1; }
        t = t + 1;
      }
      var kth_d: Float32 = 0.0;
      if truth_hits.items.len() >= 10 { kth_d = truth_hits.items[9].distance; }
      var thresh: Float32 = kth_d + 0.001;
      t = 0;
      while t < got.len() {
        var hd = jhits_dist(&rr4, t);
        if hd >= 0.0 && hd <= thresh { dist_hits = dist_hits + 1; }
        t = t + 1;
      }
      qj = qj + 1;
    }
    var denom: Float64 = (qn * 10) as Float64;
    var idr: Float64 = (id_hits as Float64) / denom;
    var dr: Float64 = (dist_hits as Float64) / denom;
    io.println("    diag hnsw oversample=" + convert.int_to_string(os)
      + " id_recall=" + convert.float_to_string(idr)
      + " dist_recall=" + convert.float_to_string(dr));
    if os == 1 { id_recall1 = idr; dist_recall1 = dr; }
    if os == 3 { id_recall3 = idr; dist_recall3 = dr; }
    os = os + 1;
  }
  fails = check(id_recall3 >= 0.80 && dist_recall3 >= 0.80,
    "hnsw: oversample 3 clears the ID-set and distance-threshold floors", fails);
  fails = check(id_recall3 >= id_recall1 - 0.05,
    "hnsw: oversample 3 does not regress ID-set recall vs 1", fails);

  // ---- filtered pushdown --------------------------------------------------
  si = 0;
  while si < 3 {
    var e = shard_engine_get(&mut shards, si);
    attach_payloads(&mut e, "docs", &ids);
    attach_payloads(&mut e, "hdocs", &ids);
    shard_engine_set(&mut shards, si, e);
    si = si + 1;
  }
  attach_payloads(&mut truth, "docs", &ids);
  attach_payloads(&mut truth_h, "hdocs", &ids);
  router_set_oversample(&mut rt, 1);
  var f_red = filter_eq("bucket", FieldValue.TextVal("red"));
  var filter_json = "{\"field\":\"bucket\",\"eq\":\"red\"}";
  var filter_ok: Bool = true;
  qi = 0;
  while qi < 8 {
    var qf = queries[qi];
    var wantf = truth_filtered_ids(&truth, &qf, 10, &f_red);
    var rrf = router_handle(&mut rt, &mut shards,
      &mk_req("POST", "/search", search_body_filter("docs", &qf, 10, filter_json)));
    if status_of(&rrf) != 200 || !ids_eq(&hit_ids(&rrf), &wantf) { filter_ok = false; }
    qi = qi + 1;
  }
  fails = check(filter_ok, "filter: eq pushdown exact vs single-node (8 queries)", fails);

  var f_range = filter_range("rank", 3.0, 5.0);
  var range_json = "{\"field\":\"rank\",\"range\":[3,5]}";
  var want_r = truth_filtered_ids(&truth, &queries[0], 10, &f_range);
  var rr_r = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/search", search_body_filter("docs", &queries[0], 10, range_json)));
  fails = check(status_of(&rr_r) == 200 && ids_eq(&hit_ids(&rr_r), &want_r),
    "filter: range pushdown exact vs single-node", fails);

  // Remaining wire shapes: exists / in / and / not, each vs the exact oracle.
  var fjsons = Vec[Str].new();
  var fexprs = Vec[FilterExpr].new();
  var fnames = Vec[Str].new();
  fjsons.push("{\"field\":\"rank\",\"exists\":true}");
  fexprs.push(filter_exists("rank")); fnames.push("filter: exists pushdown exact");
  fjsons.push("{\"field\":\"rank\",\"in\":[1,2]}");
  var fvals = Vec[FieldValue].new();
  fvals.push(FieldValue.IntVal(1)); fvals.push(FieldValue.IntVal(2));
  fexprs.push(filter_in("rank", fvals)); fnames.push("filter: in pushdown exact");
  fjsons.push("{\"and\":[{\"field\":\"bucket\",\"eq\":\"red\"},{\"field\":\"rank\",\"range\":[3,5]}]}");
  var fands = Vec[FilterExpr].new();
  fands.push(filter_eq("bucket", FieldValue.TextVal("red")));
  fands.push(filter_range("rank", 3.0, 5.0));
  fexprs.push(filter_and(fands)); fnames.push("filter: and pushdown exact");
  fjsons.push("{\"not\":{\"field\":\"bucket\",\"eq\":\"red\"}}");
  fexprs.push(filter_not(filter_eq("bucket", FieldValue.TextVal("red"))));
  fnames.push("filter: not pushdown exact");
  var fi: Int = 0;
  while fi < fjsons.len() {
    var qfx = queries[fi];
    var wantx = truth_filtered_ids(&truth, &qfx, 10, &fexprs[fi]);
    var rrx = router_handle(&mut rt, &mut shards,
      &mk_req("POST", "/search", search_body_filter("docs", &qfx, 10, fjsons[fi])));
    fails = check(status_of(&rrx) == 200 && ids_eq(&hit_ids(&rrx), &wantx),
      fnames[fi], fails);
    fi = fi + 1;
  }

  // Filtered HNSW recall with the same oversample knob.
  var fid1: Float64 = 0.0;
  var fid3: Float64 = 0.0;
  os = 1;
  while os <= 3 {
    router_set_oversample(&mut rt, os);
    var hits_f: Int = 0;
    qi = 0;
    while qi < 8 {
      var qh = queries[qi];
      var truthf = truth_filtered_ids(&truth, &qh, 10, &f_red);
      var rrh = router_handle(&mut rt, &mut shards,
        &mk_req("POST", "/search", search_body_filter("hdocs", &qh, 10, filter_json)));
      var gotf = hit_ids(&rrh);
      var t2: Int = 0;
      while t2 < gotf.len() {
        if id_in(&truthf, gotf[t2]) { hits_f = hits_f + 1; }
        t2 = t2 + 1;
      }
      qi = qi + 1;
    }
    var fr: Float64 = (hits_f as Float64) / 80.0;
    io.println("    diag filtered hnsw oversample=" + convert.int_to_string(os)
      + " id_recall=" + convert.float_to_string(fr));
    if os == 1 { fid1 = fr; }
    if os == 3 { fid3 = fr; }
    os = os + 1;
  }
  fails = check(fid3 >= 0.75, "filter: HNSW filtered recall floor at oversample 3", fails);
  fails = check(fid3 >= fid1 - 0.05, "filter: oversample 3 does not regress filtered recall vs 1", fails);

  // ---- stats ---------------------------------------------------------------
  var sdoc = router_handle(&mut rt, &mut shards,
    &mk_req("GET", "/stats?collection=docs", ""));
  fails = check(status_of(&sdoc) == 200 && jnum(&sdoc, "points") == n as Float64
    && jbool(&sdoc, "split") && jnum(&sdoc, "parts") == 3.0,
    "stats: split /stats sums parts (120, parts=3)", fails);
  var cs = router_handle(&mut rt, &mut shards, &mk_req("GET", "/cluster/stats", ""));
  fails = check(status_of(&cs) == 200 && jnum(&cs, "points_total") == (n * 2 + 30) as Float64
    && jnum(&cs, "collections_total") == 3.0,
    "stats: aggregate dedupes split collection names (3 collections, 270 points)", fails);
  var cm = router_handle(&mut rt, &mut shards, &mk_req("GET", "/cluster/mapping", ""));
  fails = check(status_of(&cm) == 200 && jpath_arr_len(&cm, "split", "docs") == 3
    && jpath_str(&cm, "collections", "docs") == "s1",
    "admin: /cluster/mapping surfaces split parts + owner", fails);

  // ---- strict vs partial ---------------------------------------------------
  let _wm = write_text(p_missing, mapping_text_missing(1));
  var rt_missing = router_state_new(p_missing);
  var qq0 = queries[0];
  var strict = router_handle(&mut rt_missing, &mut shards,
    &mk_req("POST", "/search", search_body("docs", &qq0, 5)));
  fails = check(status_of(&strict) == 503, "mode: strict default -> 503 when a part has no context", fails);
  var part = router_handle(&mut rt_missing, &mut shards,
    &mk_req("POST", "/search", search_body_partial("docs", &qq0, 5, true)));
  fails = check(status_of(&part) == 200 && jbool(&part, "partial")
    && jfail_has(&part, "s4"), "mode: partial opt-in -> live hits + partial=true + s4 report", fails);
  var partial_all = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/search", search_body_partial("docs", &qq0, 5, true)));
  fails = check(status_of(&partial_all) == 200 && !jbool(&partial_all, "partial"),
    "mode: partial opt-in with all parts live -> partial=false", fails);
  let _cm = io.remove_file(p_missing);

  // ---- explicit v1 limits -------------------------------------------------
  var range_body = "{\"collection\":\"docs\",\"vector\":" + vec_json(&qq0)
    + ",\"top_k\":5,\"mode\":\"range\",\"radius\":1.0}";
  var range_r = router_handle(&mut rt, &mut shards, &mk_req("POST", "/search", range_body));
  fails = check(status_of(&range_r) == 501, "limit: range mode on a split collection -> 501", fails);
  var batch_body = "{\"collection\":\"docs\",\"requests\":[{\"vector\":" + vec_json(&qq0)
    + ",\"top_k\":1}]}";
  var batch_r = router_handle(&mut rt, &mut shards, &mk_req("POST", "/search", batch_body));
  fails = check(status_of(&batch_r) == 501, "limit: batch search on a split collection -> 501", fails);
  rt.artifact_dir = "out";
  var move_r = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/cluster/move", "{\"collection\":\"docs\",\"to\":\"s2\"}"));
  fails = check(status_of(&move_r) == 409, "limit: split collection move refused (409)", fails);
  var drain_r = router_handle(&mut rt, &mut shards,
    &mk_req("POST", "/cluster/drain", "{\"shard\":\"s1\"}"));
  fails = check(status_of(&drain_r) == 501, "limit: drain with a split collection refused (501)", fails);

  io.println("");
  io.println("probe_scatter_gather: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
