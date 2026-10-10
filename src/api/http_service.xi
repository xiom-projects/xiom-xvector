// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.http_service

// In-repo HTTP/1.1 service skeleton (M-S1). Transport-agnostic: the whole
// service is `http_service_handle(eng, raw_bytes) -> response_bytes` -- a
// pure byte-in/byte-out pipeline (parse -> route -> JSON -> serialize), so
// it is fully deterministic and testable. Endpoints:
//
//   GET    /health                      -> {"status":"ok","service":"xvector"}
//   GET    /collections                 -> {"collections":[...]}
//   POST   /collections                 -> {"name","dim","metric"} -> 201
//   GET    /collections/{n}/points?id=  -> {"id","vector"}
//   POST   /collections/{n}/points      -> {"ids":[...],"vectors":[[...]]}
//   DELETE /collections/{n}/points?id=  -> {"removed":true}
//   GET    /stats?collection={n}        -> per-collection stats JSON
//   POST   /search                      -> knn/range/pagination; a
//                                          {"requests":[{...},{...}]} body
//                                          runs a batch
//
// Errors are {"error":"..."} with honest statuses (400/404/405/409/500).
// Requests are strict: CRLF framing, Content-Length must match the body
// exactly, unknown routes 404, wrong methods 405. Limits/config/auth (S2/S3)
// and the real socket adapter (stdlib `xiom.net`, gated on the C-PULSE-02
// proof) are deliberately out of this module: it stays transport-agnostic.

use xiom.convert;
use xiom.string.slice;
use xiom.serialize.json;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.core.shim;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.index.ann_index;
use xiom.vector.query.search_request;
use xiom.vector.query.search_service;
use xiom.vector.durability.wal_file;

// ---- Request model + parsing ----

pub type HttpRequest = {
  ok: Bool;
  incomplete: Bool;
  method: Str;
  path: Str;
  query: Str;
  header_names: Vec[Str];
  header_values: Vec[Str];
  body: Str;
}

fn bytes_to_str(b: &Vec[UInt8], from: Int, to: Int) -> Str {
  var acc = Vec[UInt8].new();
  var i: Int = from;
  while i < to {
    acc.push(b[i]);
    i = i + 1;
  }
  return Str::from_utf8(&acc);
}

// ASCII-lowercase (header names; requests are ASCII in practice).
fn ascii_lower(s: Str) -> Str {
  var b = slice.str_bytes(s);
  var i: Int = 0;
  while i < b.len() {
    if b[i] >= 65 && b[i] <= 90 { b[i] = b[i] + 32; }
    i = i + 1;
  }
  return Str::from_utf8(&b);
}

// Byte index of "\r\n\r\n" or -1.
fn find_head_end(b: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

pub fn http_parse_request(raw: &Vec[UInt8]) -> HttpRequest {
  var req = HttpRequest{
    ok: false,
    incomplete: false,
    method: "",
    path: "",
    query: "",
    header_names: Vec[Str].new(),
    header_values: Vec[Str].new(),
    body: "",
  };
  var term = find_head_end(raw);
  if term < 0 {
    req.incomplete = true;
    return req;
  }
  // Request line: METHOD SP PATH [SP HTTP/x.y]
  var line_end: Int = 0;
  while line_end < term && !(raw[line_end] == 13 && raw[line_end + 1] == 10) {
    line_end = line_end + 1;
  }
  if line_end >= term { return req; }
  var sp1: Int = -1;
  var i: Int = 0;
  while i < line_end {
    if raw[i] == 32 {
      sp1 = i;
      i = line_end;
    } else {
      i = i + 1;
    }
  }
  if sp1 <= 0 { return req; }
  var sp2: Int = -1;
  i = sp1 + 1;
  while i < line_end {
    if raw[i] == 32 {
      sp2 = i;
      i = line_end;
    } else {
      i = i + 1;
    }
  }
  var path_end: Int = line_end;
  if sp2 > 0 { path_end = sp2; }
  // The head is ASCII in practice: materialize it once and slice.
  var full = Str::from_utf8(raw);
  var method = slice.str_slice(full, 0, sp1);
  if !(method == "GET") && !(method == "POST") && !(method == "PUT") && !(method == "DELETE") {
    return req;
  }
  req.method = method;
  var raw_path = slice.str_slice(full, sp1 + 1, path_end);
  // Split optional query.
  var qpos: Int = -1;
  var pb = slice.str_bytes(raw_path);
  i = 0;
  while i < pb.len() {
    if pb[i] == 63 {
      qpos = i;
      i = pb.len();
    } else {
      i = i + 1;
    }
  }
  if qpos >= 0 {
    req.path = slice.str_slice(raw_path, 0, qpos);
    req.query = slice.str_slice(raw_path, qpos + 1, pb.len());
  } else {
    req.path = raw_path;
  }
  // Header lines. NOTE: the LAST header's CRLF is the head terminator, so
  // the scan must be allowed to reach `term` (a `lend < term` bound drops
  // the final header, e.g. Content-Length).
  var pos: Int = line_end + 2;
  while pos < term {
    var lend: Int = pos;
    while lend + 1 < raw.len() && !(raw[lend] == 13 && raw[lend + 1] == 10) {
      lend = lend + 1;
    }
    if lend + 1 >= raw.len() { break; }
    if lend > term { break; }
    // name ":" value
    var colon: Int = -1;
    i = pos;
    while i < lend {
      if raw[i] == 58 {
        colon = i;
        i = lend;
      } else {
        i = i + 1;
      }
    }
    if colon > pos {
      var name = ascii_lower(slice.str_slice(full, pos, colon));
      var vfrom: Int = colon + 1;
      while vfrom < lend && raw[vfrom] == 32 { vfrom = vfrom + 1; }
      var vto: Int = lend;
      while vto > vfrom && raw[vto - 1] == 32 { vto = vto - 1; }
      req.header_names.push(name);
      req.header_values.push(slice.str_slice(full, vfrom, vto));
    }
    pos = lend + 2;
  }
  // Body per Content-Length (strict: no trailing bytes).
  var cl: Int = 0;
  var hl = http_header(&req, "content-length");
  var clerr: Bool = false;
  match hl {
    Some(v) => {
      var vb = slice.str_bytes(v);
      var r = parse_int_at(vb, 0);
      if r.ok && r.pos == vb.len() && vb.len() > 0 {
        cl = r.value;
      } else {
        clerr = true;
      }
    }
    None => {}
  }
  if clerr { return req; }
  var body_len: Int = raw.len() - (term + 4);
  if body_len < cl {
    req.incomplete = true;
    return req;
  }
  if body_len > cl { return req; }
  req.body = slice.str_slice(full, term + 4, slice.str_bytes(full).len());
  req.ok = true;
  return req;
}

pub fn http_header(req: &HttpRequest, name: Str) -> Option[Str] {
  var i: Int = 0;
  while i < req.header_names.len() {
    if req.header_names[i] == name {
      return Some(req.header_values[i]);
    }
    i = i + 1;
  }
  return None;
}

// ---- Response writing ----

fn status_text(status: Int) -> Str {
  if status == 200 { return "OK"; }
  if status == 201 { return "Created"; }
  if status == 400 { return "Bad Request"; }
  if status == 404 { return "Not Found"; }
  if status == 405 { return "Method Not Allowed"; }
  if status == 409 { return "Conflict"; }
  if status == 500 { return "Internal Server Error"; }
  return "Error";
}

pub fn http_response(status: Int, doc: JsonValue) -> Vec[UInt8] {
  var body = json.json_stringify(doc);
  var bb = slice.str_bytes(body);
  var out = Vec[UInt8].new();
  append_bytes(&mut out, "HTTP/1.1 ");
  append_bytes(&mut out, convert.int_to_string(status));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, status_text(status));
  append_bytes(&mut out, "\r\nContent-Type: application/json\r\nContent-Length: ");
  append_bytes(&mut out, convert.int_to_string(bb.len()));
  append_bytes(&mut out, "\r\nConnection: close\r\n\r\n");
  var i: Int = 0;
  while i < bb.len() {
    out.push(bb[i]);
    i = i + 1;
  }
  return out;
}

fn jerror(status: Int, msg: Str) -> Vec[UInt8] {
  var o = json.json_object_new();
  o = json.json_set(o, "error", json.json_string(msg));
  return http_response(status, o);
}

// ---- JSON field helpers (copy out of Option before matching) ----

fn jget_str(v: JsonValue, key: Str) -> Option[Str] {
  match json.json_get(v, key) {
    Some(f) => {
      match f {
        String(s) => { return Some(s); }
        _ => {}
      }
    }
    None => {}
  }
  return None;
}

fn jget_num(v: JsonValue, key: Str) -> Option[Float64] {
  match json.json_get(v, key) {
    Some(f) => {
      match f {
        Number(n) => { return Some(n); }
        _ => {}
      }
    }
    None => {}
  }
  return None;
}

fn jv_to_vector(arr: JsonValue) -> Option[Vector] {
  match arr {
    Array(items) => {
      if items.len() == 0 { return None; }
      var v = Vector.new(items.len());
      var i: Int = 0;
      while i < items.len() {
        match items[i] {
          Number(n) => { v.set(i, n as Float32); }
          _ => { return None; }
        }
        i = i + 1;
      }
      return Some(v);
    }
    _ => {}
  }
  return None;
}

fn jv_to_int_array(arr: JsonValue) -> Option[Vec[Int]] {
  match arr {
    Array(items) => {
      var out = Vec[Int].new();
      var i: Int = 0;
      while i < items.len() {
        match items[i] {
          Number(n) => { out.push(n as Int); }
          _ => { return None; }
        }
        i = i + 1;
      }
      return Some(out);
    }
    _ => {}
  }
  return None;
}

pub fn metric_from_name(s: Str) -> Option[DistanceMetric] {
  if s == "cosine" { return Some(DistanceMetric.Cosine); }
  if s == "dot" { return Some(DistanceMetric.DotProduct); }
  if s == "euclidean" { return Some(DistanceMetric.Euclidean); }
  return None;
}

fn metric_name_of(m: DistanceMetric) -> Str {
  if m == DistanceMetric.Cosine { return "cosine"; }
  if m == DistanceMetric.DotProduct { return "dot"; }
  return "euclidean";
}

fn index_kind_name_of(k: AnnIndexKind) -> Str {
  if k == AnnIndexKind.Hnsw { return "hnsw"; }
  if k == AnnIndexKind.Ivf { return "ivf"; }
  return "flat";
}

// ---- Path / query helpers ----

fn path_segments(path: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var b = slice.str_bytes(path);
  var start: Int = 0;
  var i: Int = 0;
  while i <= b.len() {
    if i == b.len() || b[i] == 47 {
      if i > start {
        out.push(bytes_to_str(&b, start, i));
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return out;
}

fn query_param(query: Str, key: Str) -> Option[Str] {
  var b = slice.str_bytes(query);
  var start: Int = 0;
  var i: Int = 0;
  while i <= b.len() {
    if i == b.len() || b[i] == 38 {
      // segment [start, i): key=value
      var eq: Int = -1;
      var j: Int = start;
      while j < i {
        if b[j] == 61 {
          eq = j;
          j = i;
        } else {
          j = j + 1;
        }
      }
      if eq > start {
        var k = bytes_to_str(&b, start, eq);
        if k == key {
          return Some(bytes_to_str(&b, eq + 1, i));
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return None;
}

// ---- Search request from JSON ----

fn search_req_from_json(body: JsonValue) -> Option[SearchRequest] {
  var is_range: Bool = false;
  var mo = json.json_get(body, "mode");
  match mo {
    Some(mv) => {
      match mv {
        String(m) => {
          if m == "range" {
            is_range = true;
          } else if !(m == "knn") {
            return None;
          }
        }
        _ => { return None; }
      }
    }
    None => {}
  }
  var vec_opt = json.json_get(body, "vector");
  var vec = Vector.new(1);
  var have_vec: Bool = false;
  match vec_opt {
    Some(va) => {
      match jv_to_vector(va) {
        Some(v) => { vec = v; have_vec = true; }
        None => {}
      }
    }
    None => {}
  }
  if !have_vec { return None; }
  var k: Int = 10;
  var tk_opt = json.json_get(body, "top_k");
  match tk_opt {
    Some(tk) => {
      match tk {
        Number(n) => { k = n as Int; }
        _ => { return None; }
      }
    }
    None => {}
  }
  if k < 1 || k > 10000 { return None; }
  // metric defaults to the collection's metric at dispatch time; use
  // euclidean as a placeholder and overwrite in the router.
  var req = search_request_new(vec, k, DistanceMetric.Euclidean);
  if is_range {
    var radius: Float64 = 0.0;
    var ropt = json.json_get(body, "radius");
    match ropt {
      Some(rv) => {
        match rv {
          Number(r) => { radius = r; }
          _ => { return None; }
        }
      }
      None => {}
    }
    search_request_set_range(&mut req, radius as Float32);
  } else {
    var offset: Int = 0;
    var oopt = json.json_get(body, "offset");
    match oopt {
      Some(ov) => {
        match ov {
          Number(o) => { offset = o as Int; }
          _ => { return None; }
        }
      }
      None => {}
    }
    if offset > 0 { search_request_set_page(&mut req, offset); }
    var after: Int = -1;
    var aopt = json.json_get(body, "after_id");
    match aopt {
      Some(av) => {
        match av {
          Number(a) => { after = a as Int; }
          _ => { return None; }
        }
      }
      None => {}
    }
    if after >= 0 { search_request_set_after(&mut req, after); }
  }
  return Some(req);
}

fn hits_json(hits: &Vec[SearchHit]) -> JsonValue {
  var arr = json.json_array_new();
  var i: Int = 0;
  while i < hits.len() {
    var hit = json.json_object_new();
    hit = json.json_set(hit, "id", json.json_number(hits[i].id as Float64));
    hit = json.json_set(hit, "distance", json.json_number(hits[i].distance as Float64));
    arr = json.json_array_push(arr, hit);
    i = i + 1;
  }
  return arr;
}

// Dispatch a parsed request on the engine. `fallback` metric is used when
// the request body does not carry one (the body's metric must match the
// collection anyway; we always overwrite with the collection's).
fn run_search(eng: &mut VectorEngine, collection: Str, body: JsonValue) -> Vec[UInt8] {
  var sel = select_collection(eng, collection);
  match sel {
    Ok(_) => {}
    Err(_) => { return jerror(404, "unknown collection"); }
  }
  // Batch form?
  var batch_opt = json.json_get(body, "requests");
  var is_batch: Bool = false;
  var batch_items = Vec[JsonValue].new();
  match batch_opt {
    Some(b) => {
      match b {
        Array(items) => {
          if items.len() == 0 { return jerror(400, "empty batch"); }
          batch_items = items;
          is_batch = true;
        }
        _ => {}
      }
    }
    None => {}
  }
  if is_batch {
    var sets = Vec[HydratedHits].new();
    var i: Int = 0;
    while i < batch_items.len() {
      match search_req_from_json(batch_items[i]) {
        Some(r) => {
          var rr = mutate_req(r, eng.metric);
          match search_with_request(eng, &rr) {
            Ok(h) => { sets.push(h); }
            Err(e) => { return core_err_response(e); }
          }
        }
        None => { return jerror(400, "bad request element"); }
      }
      i = i + 1;
    }
    var out = json.json_object_new();
    var arr = json.json_array_new();
    var j: Int = 0;
    while j < sets.len() {
      arr = json.json_array_push(arr, hits_json(&sets[j].items));
      j = j + 1;
    }
    out = json.json_set(out, "results", arr);
    return http_response(200, out);
  }
  match search_req_from_json(body) {
    Some(r) => {
      var rr = mutate_req(r, eng.metric);
      match search_with_request(eng, &rr) {
        Ok(h) => {
          var out = json.json_object_new();
          out = json.json_set(out, "hits", hits_json(&h.items));
          return http_response(200, out);
        }
        Err(e) => { return core_err_response(e); }
      }
    }
    None => {}
  }
  return jerror(400, "bad search body");
}

fn mutate_req(r: SearchRequest, metric: DistanceMetric) -> SearchRequest {
  var out = r;
  out.metric = metric;
  return out;
}

fn core_err_response(e: CoreError) -> Vec[UInt8] {
  match e {
    NotFound => { return jerror(404, "not found"); }
    InvalidInput(msg) => { return jerror(400, msg); }
    _ => { return jerror(500, "internal error"); }
  }
}

// ---- Route handlers ----

fn handle_create_collection(eng: &mut VectorEngine, body: JsonValue) -> Vec[UInt8] {
  var name_opt = jget_str(body, "name");
  var name: Str = "";
  var have_name: Bool = false;
  match name_opt {
    Some(n) => { name = n; have_name = true; }
    None => {}
  }
  if !have_name { return jerror(400, "missing name"); }
  var dim: Int = 0;
  match jget_num(body, "dim") {
    Some(d) => { dim = d as Int; }
    None => {}
  }
  var mname_opt = jget_str(body, "metric");
  var metric: DistanceMetric = DistanceMetric.Euclidean;
  match mname_opt {
    Some(mn) => {
      match metric_from_name(mn) {
        Some(m) => { metric = m; }
        None => { return jerror(400, "unknown metric"); }
      }
    }
    None => { return jerror(400, "missing metric"); }
  }
  var res = create_named_collection(eng, name, dim, metric);
  match res {
    Ok(_) => {
      var out = json.json_object_new();
      out = json.json_set(out, "ok", json.json_bool(true));
      out = json.json_set(out, "name", json.json_string(name));
      return http_response(201, out);
    }
    Err(e) => {
      match e {
        InvalidInput(msg) => {
          if msg == "collection exists" { return jerror(409, msg); }
          return jerror(400, msg);
        }
        _ => { return jerror(500, "create failed"); }
      }
    }
  }
}

fn handle_upsert(eng: &mut VectorEngine, name: Str, body: JsonValue) -> Vec<UInt8> {
  var sel = select_collection(eng, name);
  match sel {
    Ok(_) => {}
    Err(_) => { return jerror(404, "unknown collection"); }
  }
  var ids_opt = json.json_get(body, "ids");
  var ids = Vec[Int].new();
  var have_ids: Bool = false;
  match ids_opt {
    Some(ia) => {
      match jv_to_int_array(ia) {
        Some(x) => { ids = x; have_ids = true; }
        None => {}
      }
    }
    None => {}
  }
  var vecs_opt = json.json_get(body, "vectors");
  var vecs = Vec[Vector].new();
  var have_vecs: Bool = false;
  match vecs_opt {
    Some(va) => {
      match va {
        Array(items) => {
          var i: Int = 0;
          var okall: Bool = true;
          while i < items.len() {
            match jv_to_vector(items[i]) {
              Some(v) => { vecs.push(v); }
              None => { okall = false; }
            }
            i = i + 1;
          }
          have_vecs = okall;
        }
        _ => {}
      }
    }
    None => {}
  }
  if !have_ids || !have_vecs || ids.len() == 0 { return jerror(400, "bad points body"); }
  var res = upsert_many(eng, &ids, &vecs);
  match res {
    Ok(n) => {
      var out = json.json_object_new();
      out = json.json_set(out, "count", json.json_number(n as Float64));
      return http_response(200, out);
    }
    Err(e) => { return core_err_response(e); }
  }
}

fn handle_stats(eng: &VectorEngine, query: Str) -> Vec[UInt8] {
  var name_opt = query_param(query, "collection");
  var name = eng.active_name;
  var have_name: Bool = eng.active_idx >= 0;
  match name_opt {
    Some(n) => { name = n; have_name = true; }
    None => {}
  }
  if !have_name { return jerror(400, "missing collection"); }
  var res = collection_stats(eng, name);
  match res {
    Ok(st) => {
      var out = json.json_object_new();
      out = json.json_set(out, "name", json.json_string(st.name));
      out = json.json_set(out, "dim", json.json_number(st.dimension as Float64));
      out = json.json_set(out, "metric", json.json_string(metric_name_of(st.metric)));
      out = json.json_set(out, "index", json.json_string(index_kind_name_of(st.index_kind)));
      out = json.json_set(out, "points", json.json_number(st.points as Float64));
      out = json.json_set(out, "payloads", json.json_number(st.payloads as Float64));
      out = json.json_set(out, "nodes", json.json_number(st.nodes as Float64));
      out = json.json_set(out, "tombstones", json.json_number(st.tombstones as Float64));
      out = json.json_set(out, "lsn", json.json_number(st.wal_lsn as Float64));
      return http_response(200, out);
    }
    Err(_) => { return jerror(404, "unknown collection"); }
  }
}

// ---- The router (transport-agnostic entry point) ----

pub fn http_service_handle(eng: &mut VectorEngine, raw: &Vec[UInt8]) -> Vec[UInt8] {
  var req = http_parse_request(raw);
  if !req.ok {
    if req.incomplete { return jerror(400, "incomplete request"); }
    return jerror(400, "malformed request");
  }
  var segs = path_segments(req.path);
  if segs.len() == 1 && segs[0] == "health" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    var out = json.json_object_new();
    out = json.json_set(out, "status", json.json_string("ok"));
    out = json.json_set(out, "service", json.json_string("xvector"));
    return http_response(200, out);
  }
  if segs.len() == 1 && segs[0] == "collections" {
    if req.method == "GET" {
      var cl = list_collections(eng);
      var arr = json.json_array_new();
      var i: Int = 0;
      while i < cl.names.len() {
        arr = json.json_array_push(arr, json.json_string(cl.names[i]));
        i = i + 1;
      }
      var out = json.json_object_new();
      out = json.json_set(out, "collections", arr);
      return http_response(200, out);
    }
    if req.method == "POST" {
      var parsed = json.json_parse(req.body);
      match parsed {
        Ok(body) => { return handle_create_collection(eng, body); }
        Err(_) => { return jerror(400, "bad json"); }
      }
    }
    return jerror(405, "method not allowed");
  }
  if segs.len() == 3 && segs[0] == "collections" && segs[2] == "points" {
    var name = segs[1];
    if req.method == "POST" {
      var parsed = json.json_parse(req.body);
      match parsed {
        Ok(body) => { return handle_upsert(eng, name, body); }
        Err(_) => { return jerror(400, "bad json"); }
      }
    }
    if req.method == "GET" {
      var id_opt = query_param(req.query, "id");
      var id: Int = -1;
      var have_id: Bool = false;
      match id_opt {
        Some(s) => {
          var vb = slice.str_bytes(s);
          var r = parse_int_at(vb, 0);
          if r.ok && r.pos == vb.len() && vb.len() > 0 {
            id = r.value;
            have_id = true;
          }
        }
        None => {}
      }
      if !have_id { return jerror(400, "missing id"); }
      var sel = select_collection(eng, name);
      match sel {
        Ok(_) => {}
        Err(_) => { return jerror(404, "unknown collection"); }
      }
      match get_point(eng, id) {
        Some(v) => {
          var arr = json.json_array_new();
          var i: Int = 0;
          while i < v.dimension {
            arr = json.json_array_push(arr, json.json_number(v.data[i] as Float64));
            i = i + 1;
          }
          var out = json.json_object_new();
          out = json.json_set(out, "id", json.json_number(id as Float64));
          out = json.json_set(out, "vector", arr);
          return http_response(200, out);
        }
        None => { return jerror(404, "unknown point"); }
      }
    }
    if req.method == "DELETE" {
      var id_opt2 = query_param(req.query, "id");
      var id2: Int = -1;
      var have_id2: Bool = false;
      match id_opt2 {
        Some(s) => {
          var vb = slice.str_bytes(s);
          var r = parse_int_at(vb, 0);
          if r.ok && r.pos == vb.len() && vb.len() > 0 {
            id2 = r.value;
            have_id2 = true;
          }
        }
        None => {}
      }
      if !have_id2 { return jerror(400, "missing id"); }
      var sel2 = select_collection(eng, name);
      match sel2 {
        Ok(_) => {}
        Err(_) => { return jerror(404, "unknown collection"); }
      }
      match delete_point(eng, id2) {
        Ok(removed) => {
          var out = json.json_object_new();
          out = json.json_set(out, "removed", json.json_bool(removed));
          return http_response(200, out);
        }
        Err(e) => { return core_err_response(e); }
      }
    }
    return jerror(405, "method not allowed");
  }
  if segs.len() == 1 && segs[0] == "search" {
    if !(req.method == "POST") { return jerror(405, "method not allowed"); }
    var parsed2 = json.json_parse(req.body);
    match parsed2 {
      Ok(body) => {
        var coll_opt = jget_str(body, "collection");
        var coll: Str = "";
        var have_coll: Bool = false;
        match coll_opt {
          Some(c) => { coll = c; have_coll = true; }
          None => {}
        }
        if !have_coll {
          if eng.active_idx >= 0 {
            coll = eng.active_name;
            have_coll = true;
          }
        }
        if !have_coll { return jerror(400, "missing collection"); }
        return run_search(eng, coll, body);
      }
      Err(_) => { return jerror(400, "bad json"); }
    }
  }
  if segs.len() == 1 && segs[0] == "stats" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    return handle_stats(eng, req.query);
  }
  return jerror(404, "unknown route");
}
