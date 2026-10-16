// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.router

// Stateless lattice router (L-3, `docs/PRODUCT-ARCHITECTURE.md` 6/9/10).
//
// The router holds a MAPPING, never data state (P4): request bytes in,
// response bytes out -- the same byte-in/byte-out discipline as the
// service. Every request that names a collection is forwarded VERBATIM
// (headers and body included, so the client's key travels and the shard
// re-checks it: defense in depth) to the shard that owns that collection;
// everything else is router-level:
//
//   GET  /health        -> router identity + mapping version + shard count
//   GET  /version       -> router name/version/api + mapping version
//   GET  /cluster/mapping -> mapping view (admin scope)
//   GET  /cluster/stats   -> aggregate shard stats + mapping version (admin)
//   POST /cluster/move    -> online move {collection, to} (admin; L-5)
//   POST /cluster/drain   -> move every collection off {shard} (admin; L-5)
//   GET  /stats (no collection param) -> the same aggregate (admin scope
//                          per the L-3 checklist; with ?collection= it is a
//                          plain forward on read scope)
//   GET  /collections   -> the mapped collection names (mapping-derived;
//                          no per-request aggregation of shard state)
//   route set           -> POST /collections, /collections/{n}/points
//                          (GET/POST/DELETE), POST /search (knn/range/
//                          pagination/batch), GET /stats?collection={n}
//                          -- forwarded to the owner shard unchanged
//
// Mapping file (JSON; admin-tooling owned, read by routers):
//
//   { "version": <generation int >= 1>,
//     "shards":     [ {"id": "...", "url": "..."} ... ],
//     "collections": { "<name>": "<shard id>" } }
//
// `version` is the mapping GENERATION: every admin edit bumps it (the
// "flip mapping version" of the move protocol). Placement is EXPLICIT:
// a collection is routable only when the mapping declares it; a create
// for a mapped-but-not-yet-created collection is forwarded to its
// designated shard (the shard decides 201/409). Unmapped collections are
// invisible to the router (404, `kind: not_found`). Loading is strict:
// malformed structure, bad ids/names/urls, duplicate shard ids, or
// collection refs to unknown shards all REFUSE START (`ok == false`).
//
// Stale mapping (the move window): when a forwarded request comes back
// 404, the router re-reads the mapping file once; if a NEW mapping
// generation arrives and covers every referenced shard with a local
// context, the cache is replaced; the request is retried once -- but
// only when the owner actually CHANGED. Otherwise the original 404 is
// returned unchanged. Clients see at most one retry (documented window).
//
// Transport: v1 forwards IN-PROCESS to shard contexts (engine + service
// state) handed in by the embedder via `router_forward_direct`, which is
// the exact code path the socket transport replaces when the xiom.http
// client half lands (ask `REL-20261016-1129-xvector-2`); the mapping
// already carries per-shard urls for that hop. The in-process forward
// copies the shard record out and writes it back once (the same
// snapshot-copy discipline the engine uses for parked collections --
// the XVC-C-09/C-14 family makes nested-field mutation through refs a
// hazard).
//
// Auth: the router applies the SAME scope map / key lookup as the
// service (shared helpers), then forwards the raw request with the
// client's key so the shard re-checks independently. Router-initiated
// calls (the /cluster/stats aggregation) use `internal_key`.

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.serialize.json;
use xiom.time;
use xiom.vector.api.http_service;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.durability.wal_file;

// One shard context: the service state (config/auth/rate/metrics/log) plus
// the engine that serves it. Owned by the HOST (probe / future server);
// the router never stores data state of its own.
pub type RouterShard = {
  id: Str;
  engine: VectorEngine;
  state: ServiceState;
}

// A loaded mapping. Parallel vectors; `coll_shard[i]` indexes
// `shard_ids` for `coll_names[i]` (file order, deterministic).
pub type RouterMapping = {
  ok: Bool;
  err: Str;
  version: Int;
  shard_ids: Vec[Str];
  shard_urls: Vec[Str];
  coll_names: Vec[Str];
  coll_shard: Vec[Int];
}

// Router state: the mapping cache plus the router's own service surface
// (limits/auth/rate) and diagnostics. No data state (P4).
pub type RouterState = {
  ok: Bool;
  mapping_path: Str;
  mapping: RouterMapping;
  cfg: ServiceConfig;
  auth: ServiceAuth;
  rate: RateLimiter;
  internal_key: Str;
  artifact_dir: Str;
  requests: Int;
  errors: Int;
  forwarded: Int;
  refused_local: Int;
  reloads: Int;
  reload_refusals: Int;
}

// Name rule (shard ids + collection names), identical to the engine's
// manifest rule: 1..64 chars of [A-Za-z0-9_.-].
pub fn router_name_ok(name: Str) -> Bool {
  var b = slice.str_bytes(name);
  if b.len() < 1 || b.len() > 64 { return false; }
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    var okc: Bool = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 45 || c == 46;
    if !okc { return false; }
    i = i + 1;
  }
  return true;
}

fn router_mapping_err(msg: Str) -> RouterMapping {
  return RouterMapping{
    ok: false,
    err: msg,
    version: 0,
    shard_ids: Vec[Str].new(),
    shard_urls: Vec[Str].new(),
    coll_names: Vec[Str].new(),
    coll_shard: Vec[Int].new(),
  };
}

// Load + validate the mapping file (byte-level read with the file_size
// guard used across the lane's loaders; refusals never throw).
pub fn router_mapping_load(path: Str) -> RouterMapping {
  if !io.file_exists(path) { return router_mapping_err("mapping file missing"); }
  var fs = io.file_size(path);
  var sz: Int = -1;
  match fs {
    Some(n) => { sz = n; }
    None => { return router_mapping_err("mapping file unreadable"); }
  }
  if sz < 16 { return router_mapping_err("mapping file too small"); }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return router_mapping_err("mapping file unreadable"); }
  }
  var text = Str::from_utf8(&b);
  var parsed = json.json_parse(text);
  var doc = json.json_null();
  match parsed {
    Ok(v) => { doc = v; }
    Err(_) => { return router_mapping_err("mapping is not valid json"); }
  }
  if json.json_type(doc) != "object" { return router_mapping_err("mapping must be a json object"); }
  // version: integral, >= 1
  var version: Int = 0;
  var vo = json.json_get(doc, "version");
  var have_version: Bool = false;
  match vo {
    Some(vv) => {
      if json.json_type(vv) == "number" {
        var n: Float64 = 0.0;
        match vv {
          Number(x) => { n = x; }
          _ => {}
        }
        var vi = n as Int;
        if (vi as Float64) != n { return router_mapping_err("version must be an integer"); }
        version = vi;
        have_version = true;
      }
    }
    None => {}
  }
  if !have_version { return router_mapping_err("missing version"); }
  if version < 1 { return router_mapping_err("version must be >= 1"); }
  // shards: non-empty array of {id, url}, unique valid ids
  var ids = Vec[Str].new();
  var urls = Vec[Str].new();
  var so = json.json_get(doc, "shards");
  var have_shards: Bool = false;
  match so {
    Some(sv) => {
      if json.json_type(sv) != "array" { return router_mapping_err("shards must be an array"); }
      match sv {
        Array(items) => {
          var i: Int = 0;
          while i < items.len() {
            var it = items[i];
            if json.json_type(it) != "object" { return router_mapping_err("shard entry must be an object"); }
            var ido = json.json_get(it, "id");
            var id: Str = "";
            var have_id: Bool = false;
            match ido {
              Some(x) => {
                match x {
                  String(s) => { id = s; have_id = true; }
                  _ => {}
                }
              }
              None => {}
            }
            if !have_id { return router_mapping_err("shard entry missing id"); }
            if !router_name_ok(id) { return router_mapping_err("shard id invalid"); }
            var uo = json.json_get(it, "url");
            var url: Str = "";
            var have_url: Bool = false;
            match uo {
              Some(x) => {
                match x {
                  String(s) => { url = s; have_url = true; }
                  _ => {}
                }
              }
              None => {}
            }
            if !have_url { return router_mapping_err("shard entry missing url"); }
            if url.len() < 1 || url.len() > 256 { return router_mapping_err("shard url invalid"); }
            var d: Int = 0;
            while d < ids.len() {
              if ids[d] == id { return router_mapping_err("duplicate shard id"); }
              d = d + 1;
            }
            ids.push(id);
            urls.push(url);
            i = i + 1;
          }
        }
        _ => {}
      }
      have_shards = true;
    }
    None => {}
  }
  if !have_shards { return router_mapping_err("missing shards"); }
  if ids.len() == 0 { return router_mapping_err("at least one shard is required"); }
  // collections: object of valid name -> known shard id
  var names = Vec[Str].new();
  var shard_of = Vec[Int].new();
  var co = json.json_get(doc, "collections");
  var have_colls: Bool = false;
  match co {
    Some(cv) => {
      if json.json_type(cv) != "object" { return router_mapping_err("collections must be an object"); }
      match cv {
        Object(entries) => {
          // Copy the map's vectors out before iterating (XVC-C-09/C-16
          // discipline: reads through a nested enum binding can lower
          // wrong in some function contexts; the locals are the safe seam).
          var ks = entries.keys;
          var vs = entries.values;
          var i: Int = 0;
          while i < ks.len() {
            var name = ks[i];
            if !router_name_ok(name) { return router_mapping_err("collection name invalid"); }
            var target = vs[i];
            if json.json_type(target) != "string" { return router_mapping_err("collection shard must be a string"); }
            var sid: Str = "";
            match target {
              String(s) => { sid = s; }
              _ => {}
            }
            var d: Int = 0;
            var si: Int = -1;
            while d < ids.len() {
              if ids[d] == sid { si = d; }
              d = d + 1;
            }
            if si < 0 { return router_mapping_err("collection references unknown shard"); }
            names.push(name);
            shard_of.push(si);
            i = i + 1;
          }
        }
        _ => {}
      }
      have_colls = true;
    }
    None => {}
  }
  if !have_colls { return router_mapping_err("missing collections"); }
  return RouterMapping{
    ok: true,
    err: "",
    version: version,
    shard_ids: ids,
    shard_urls: urls,
    coll_names: names,
    coll_shard: shard_of,
  };
}

// Owner shard index for a collection, or -1 (linear; mappings are small
// and the file order is the deterministic truth of the mapping).
pub fn router_mapping_owner(m: &RouterMapping, name: Str) -> Int {
  var i: Int = 0;
  while i < m.coll_names.len() {
    if m.coll_names[i] == name { return m.coll_shard[i]; }
    i = i + 1;
  }
  return -1;
}

// Collection index in the mapping, or -1.
fn router_mapping_index(m: &RouterMapping, name: Str) -> Int {
  var i: Int = 0;
  while i < m.coll_names.len() {
    if m.coll_names[i] == name { return i; }
    i = i + 1;
  }
  return -1;
}

// Minimal JSON string escaping for the persist renderer (\" \\ \n \r \t).
fn router_json_esc(out: &mut Vec[UInt8], s: Str) {
  var b = slice.str_bytes(s);
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    if c == 34u8 {
      out.push(92u8);
      out.push(34u8);
    } elif c == 92u8 {
      out.push(92u8);
      out.push(92u8);
    } elif c == 10u8 {
      out.push(92u8);
      out.push(110u8);
    } elif c == 13u8 {
      out.push(92u8);
      out.push(114u8);
    } elif c == 9u8 {
      out.push(92u8);
      out.push(116u8);
    } else {
      out.push(c);
    }
    i = i + 1;
  }
}

// Persist the mapping (admin writes; the caller has already applied the
// version bump): render the versioned JSON, write `<path>.tmp`, swap with
// io.rename (the lane's atomic whole-file discipline). False on any IO
// error; the target file is left untouched on failure.
pub fn router_mapping_persist(m: &RouterMapping, path: Str) -> Bool {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, "{\"version\":");
  append_bytes(&mut out, convert.int_to_string(m.version));
  append_bytes(&mut out, ",\"shards\":[");
  var i: Int = 0;
  while i < m.shard_ids.len() {
    if i > 0 { out.push(44u8); }
    append_bytes(&mut out, "{\"id\":\"");
    router_json_esc(&mut out, m.shard_ids[i]);
    append_bytes(&mut out, "\",\"url\":\"");
    router_json_esc(&mut out, m.shard_urls[i]);
    append_bytes(&mut out, "\"}");
    i = i + 1;
  }
  append_bytes(&mut out, "],\"collections\":{");
  var j: Int = 0;
  while j < m.coll_names.len() {
    if j > 0 { out.push(44u8); }
    append_bytes(&mut out, "\"");
    router_json_esc(&mut out, m.coll_names[j]);
    append_bytes(&mut out, "\":\"");
    var oi = m.coll_shard[j];
    router_json_esc(&mut out, m.shard_ids[oi]);
    append_bytes(&mut out, "\"");
    j = j + 1;
  }
  append_bytes(&mut out, "}}");
  var tmp = path + ".tmp";
  var wres = io.write_file_bytes(tmp, &out);
  match wres {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  var rres = io.rename(tmp, path);
  match rres {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Local shard-context index for a shard id, or -1.
fn router_shard_find(shards: &mut Vec[RouterShard], id: Str) -> Int {
  var i: Int = 0;
  while i < shards.len() {
    if shards[i].id == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Every shard id referenced by the mapping has a local context.
fn router_mapping_contexts_ok(m: &RouterMapping, shards: &mut Vec[RouterShard]) -> Bool {
  var i: Int = 0;
  while i < m.shard_ids.len() {
    if router_shard_find(shards, m.shard_ids[i]) < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// New router state: loads the mapping; `ok == false` means START MUST BE
// REFUSED (the embedder checks it; requests answered anyway get 503).
pub fn router_state_new(mapping_path: Str) -> RouterState {
  var m = router_mapping_load(mapping_path);
  return RouterState{
    ok: m.ok,
    mapping_path: mapping_path,
    mapping: m,
    cfg: service_config_default(),
    auth: service_auth_new(),
    rate: rate_limiter_disabled(),
    internal_key: "",
    artifact_dir: "",
    requests: 0,
    errors: 0,
    forwarded: 0,
    refused_local: 0,
    reloads: 0,
    reload_refusals: 0,
  };
}

// Forward raw request bytes to a local shard context: copy the shard
// record out, run the full service pipeline (the shard re-checks auth and
// limits independently), write the record back once.
fn router_shard_forward(shards: &mut Vec[RouterShard], idx: Int, raw: &Vec[UInt8]) -> Vec[UInt8] {
  var sh = shards[idx];
  var eng = sh.engine;
  var st = sh.state;
  var resp = http_service_handle_state(&mut eng, raw, &mut st);
  sh.engine = eng;
  sh.state = st;
  shards[idx] = sh;
  return resp;
}

// The transport seam: forward to a named shard (no routing). Used by the
// router itself and by the gates as the "direct to the owning shard"
// reference path; the socket transport (follow-up, gated on the xiom.http
// client half) plugs in at this boundary.
pub fn router_forward_direct(shards: &mut Vec<RouterShard>, id: Str, raw: &Vec[UInt8]) -> Vec[UInt8] {
  var idx = router_shard_find(shards, id);
  if idx < 0 { return jerror(503, "shard not configured"); }
  return router_shard_forward(shards, idx, raw);
}

// Router scope map: /cluster/* is admin; a bare /stats is the aggregate
// (admin) while /stats?collection= is a read-scope forward; everything
// else keeps the service's exact map (shared helper).
pub fn router_required_scope(method: Str, path: Str, query: Str) -> Option[ApiScope] {
  var segs = path_segments(path);
  if segs.len() == 2 && segs[0] == "cluster" { return Some(ApiScope.Admin); }
  if segs.len() == 1 && segs[0] == "stats" {
    match query_param(query, "collection") {
      Some(_) => { return Some(ApiScope.Read); }
      None => { return Some(ApiScope.Admin); }
    }
  }
  return required_scope(method, path);
}

// Router-owned responses ---------------------------------------------------

fn router_health(rt: &RouterState) -> Vec[UInt8] {
  var out = json.json_object_new();
  out = json.json_set(out, "status", json.json_string("ok"));
  out = json.json_set(out, "service", json.json_string("xvector-lattice-router"));
  out = json.json_set(out, "ready", json.json_bool(true));
  out = json.json_set(out, "mapping_version", json.json_number(rt.mapping.version as Float64));
  out = json.json_set(out, "shards", json.json_number(rt.mapping.shard_ids.len() as Float64));
  return http_response(200, out);
}

fn router_version_json(rt: &RouterState) -> Vec[UInt8] {
  var out = json.json_object_new();
  out = json.json_set(out, "name", json.json_string("xvector-lattice-router"));
  out = json.json_set(out, "version", json.json_string("1.0.0-rc.1"));
  out = json.json_set(out, "api", json.json_number(1.0));
  out = json.json_set(out, "mapping_version", json.json_number(rt.mapping.version as Float64));
  return http_response(200, out);
}

fn router_collections_list(rt: &RouterState) -> Vec[UInt8] {
  var arr = json.json_array_new();
  var i: Int = 0;
  while i < rt.mapping.coll_names.len() {
    arr = json.json_array_push(arr, json.json_string(rt.mapping.coll_names[i]));
    i = i + 1;
  }
  var out = json.json_object_new();
  out = json.json_set(out, "collections", arr);
  return http_response(200, out);
}

fn router_cluster_mapping(rt: &RouterState) -> Vec[UInt8] {
  var sa = json.json_array_new();
  var i: Int = 0;
  while i < rt.mapping.shard_ids.len() {
    var item = json.json_object_new();
    item = json.json_set(item, "id", json.json_string(rt.mapping.shard_ids[i]));
    item = json.json_set(item, "url", json.json_string(rt.mapping.shard_urls[i]));
    sa = json.json_array_push(sa, item);
    i = i + 1;
  }
  var colls = json.json_object_new();
  var j: Int = 0;
  while j < rt.mapping.coll_names.len() {
    var oi = rt.mapping.coll_shard[j];
    colls = json.json_set(colls, rt.mapping.coll_names[j], json.json_string(rt.mapping.shard_ids[oi]));
    j = j + 1;
  }
  var out = json.json_object_new();
  out = json.json_set(out, "mapping_version", json.json_number(rt.mapping.version as Float64));
  out = json.json_set(out, "shards", sa);
  out = json.json_set(out, "collections", colls);
  return http_response(200, out);
}

// Response body extraction for router-initiated calls (the aggregate).
fn resp_body_str(resp: &Vec[UInt8]) -> Str {
  var t: Int = -1;
  var i: Int = 0;
  while i + 3 < resp.len() {
    if resp[i] == 13 && resp[i + 1] == 10 && resp[i + 2] == 13 && resp[i + 3] == 10 {
      t = i;
      i = resp.len();
    } else {
      i = i + 1;
    }
  }
  if t < 0 { return ""; }
  var acc = Vec[UInt8].new();
  var j: Int = t + 4;
  while j < resp.len() {
    acc.push(resp[j]);
    j = j + 1;
  }
  return Str::from_utf8(&acc);
}

fn jnum_of(v: JsonValue, key: Str) -> Int {
  var o = json.json_get(v, key);
  match o {
    Some(x) => {
      match x {
        Number(n) => { return n as Int; }
        _ => {}
      }
    }
    None => {}
  }
  return 0;
}

// Router-initiated GET bytes (adds the internal key when configured).
fn internal_get(path: Str, key: Str) -> Vec[UInt8] {
  var s = "GET " + path + " HTTP/1.1\r\nHost: router\r\nConnection: close\r\n";
  if key.len() > 0 { s = s + "X-Api-Key: " + key + "\r\n"; }
  s = s + "\r\n";
  return slice.str_bytes(s);
}

// Aggregate /stats: sum of shard stats + mapping version, gathered
// through the shard endpoints themselves (what a socket router would do):
// per shard, GET /collections, then GET /stats?collection= per name;
// unreachable/unparseable shards report reachable=false with zeros.
fn router_cluster_stats(rt: &mut RouterState, shards: &mut Vec<RouterShard>) -> Vec[UInt8] {
  var sa = json.json_array_new();
  var total_colls: Int = 0;
  var total_points: Int = 0;
  var i: Int = 0;
  while i < rt.mapping.shard_ids.len() {
    var sid = rt.mapping.shard_ids[i];
    var item = json.json_object_new();
    item = json.json_set(item, "id", json.json_string(sid));
    item = json.json_set(item, "url", json.json_string(rt.mapping.shard_urls[i]));
    var colls: Int = 0;
    var points: Int = 0;
    var max_lsn: Int = 0;
    var reachable: Bool = false;
    var idx = router_shard_find(shards, sid);
    if idx >= 0 {
      var lr = router_shard_forward(shards, idx, &internal_get("/collections", rt.internal_key));
      if response_status(&lr) == 200 {
        var lv = json.json_null();
        var lp = json.json_parse(resp_body_str(&lr));
        var lok: Bool = false;
        match lp {
          Ok(v) => { lv = v; lok = true; }
          Err(_) => {}
        }
        if lok {
          var lo = json.json_get(lv, "collections");
          match lo {
            Some(arr) => {
              match arr {
                Array(items) => {
                  reachable = true;
                  colls = items.len();
                  var j: Int = 0;
                  while j < items.len() {
                    var cname: Str = "";
                    match items[j] {
                      String(s) => { cname = s; }
                      _ => {}
                    }
                    if cname.len() > 0 {
                      var sr = router_shard_forward(shards, idx, &internal_get("/stats?collection=" + cname, rt.internal_key));
                      if response_status(&sr) == 200 {
                        var sv = json.json_null();
                        var sp = json.json_parse(resp_body_str(&sr));
                        var sok: Bool = false;
                        match sp {
                          Ok(v) => { sv = v; sok = true; }
                          Err(_) => {}
                        }
                        if sok {
                          points = points + jnum_of(sv, "points");
                          var l = jnum_of(sv, "lsn");
                          if l > max_lsn { max_lsn = l; }
                        }
                      }
                    }
                    j = j + 1;
                  }
                }
                _ => {}
              }
            }
            None => {}
          }
        }
      }
    }
    item = json.json_set(item, "reachable", json.json_bool(reachable));
    item = json.json_set(item, "collections", json.json_number(colls as Float64));
    item = json.json_set(item, "points", json.json_number(points as Float64));
    item = json.json_set(item, "max_lsn", json.json_number(max_lsn as Float64));
    sa = json.json_array_push(sa, item);
    total_colls = total_colls + colls;
    total_points = total_points + points;
    i = i + 1;
  }
  var out = json.json_object_new();
  out = json.json_set(out, "mapping_version", json.json_number(rt.mapping.version as Float64));
  out = json.json_set(out, "shards", sa);
  out = json.json_set(out, "collections_total", json.json_number(total_colls as Float64));
  out = json.json_set(out, "points_total", json.json_number(total_points as Float64));
  return http_response(200, out);
}

// Collection name extraction for forwarded routes --------------------------

type RouterPick = {
  err: Str;
  name: Str;
}

fn router_pick_search_collection(req: &HttpRequest) -> RouterPick {
  if !json_depth_ok(req.body, 64) { return RouterPick{ err: "json nesting exceeds service limit", name: "" }; }
  var parsed = json.json_parse(req.body);
  var doc = json.json_null();
  match parsed {
    Ok(v) => { doc = v; }
    Err(_) => { return RouterPick{ err: "bad json", name: "" }; }
  }
  var co = json.json_get(doc, "collection");
  match co {
    Some(cv) => {
      match cv {
        String(s) => {
          if s.len() > 0 { return RouterPick{ err: "", name: s }; }
        }
        _ => {}
      }
    }
    None => {}
  }
  return RouterPick{ err: "missing collection", name: "" };
}

fn router_pick_create_name(req: &HttpRequest) -> RouterPick {
  if !json_depth_ok(req.body, 64) { return RouterPick{ err: "json nesting exceeds service limit", name: "" }; }
  var parsed = json.json_parse(req.body);
  var doc = json.json_null();
  match parsed {
    Ok(v) => { doc = v; }
    Err(_) => { return RouterPick{ err: "bad json", name: "" }; }
  }
  var no = json.json_get(doc, "name");
  match no {
    Some(nv) => {
      match nv {
        String(s) => {
          if !router_name_ok(s) { return RouterPick{ err: "invalid name", name: "" }; }
          return RouterPick{ err: "", name: s };
        }
        _ => {}
      }
    }
    None => {}
  }
  return RouterPick{ err: "missing name", name: "" };
}

// Dispatch: resolve owner -> forward -> stale-mapping retry-on-404 -------

fn router_dispatch(rt: &mut RouterState, shards: &mut Vec[RouterShard], coll: Str, raw: &Vec<UInt8]) -> Vec[UInt8] {
  var owner = router_mapping_owner(&rt.mapping, coll);
  if owner < 0 {
    rt.refused_local = rt.refused_local + 1;
    return jerror(404, "collection not mapped");
  }
  var sid = rt.mapping.shard_ids[owner];
  var idx = router_shard_find(shards, sid);
  if idx < 0 { return jerror(503, "shard not configured"); }
  var resp = router_shard_forward(shards, idx, raw);
  rt.forwarded = rt.forwarded + 1;
  if response_status(&resp) == 404 {
    // Stale mapping: re-read once; accept a NEW generation only when every
    // referenced shard has a local context; retry once when the owner moved.
    var reloaded = router_mapping_load(rt.mapping_path);
    if reloaded.ok && reloaded.version != rt.mapping.version {
      if router_mapping_contexts_ok(&reloaded, shards) {
        rt.mapping = reloaded;
        rt.reloads = rt.reloads + 1;
        var owner2 = router_mapping_owner(&rt.mapping, coll);
        if owner2 >= 0 {
          var sid2 = rt.mapping.shard_ids[owner2];
          if sid2 != sid {
            var idx2 = router_shard_find(shards, sid2);
            if idx2 >= 0 { resp = router_shard_forward(shards, idx2, raw); }
          }
        }
      } else {
        rt.reload_refusals = rt.reload_refusals + 1;
      }
    }
  }
  return resp;
}

// Cluster admin (L-5): online collection move + node drain ----------------

type RouterMoveBody = {
  err: Str;
  collection: Str;
  to: Str;
}

fn router_pick_move(req: &HttpRequest) -> RouterMoveBody {
  if !json_depth_ok(req.body, 64) { return RouterMoveBody{ err: "json nesting exceeds service limit", collection: "", to: "" }; }
  var parsed = json.json_parse(req.body);
  var doc = json.json_null();
  match parsed {
    Ok(v) => { doc = v; }
    Err(_) => { return RouterMoveBody{ err: "bad json", collection: "", to: "" }; }
  }
  var coll: Str = "";
  var to: Str = "";
  var co = json.json_get(doc, "collection");
  match co {
    Some(cv) => {
      match cv {
        String(s) => { coll = s; }
        _ => {}
      }
    }
    None => {}
  }
  if coll.len() == 0 { return RouterMoveBody{ err: "missing collection", collection: "", to: "" }; }
  var to_o = json.json_get(doc, "to");
  match to_o {
    Some(tv) => {
      match tv {
        String(s) => { to = s; }
        _ => {}
      }
    }
    None => {}
  }
  if to.len() == 0 { return RouterMoveBody{ err: "missing to", collection: "", to: "" }; }
  return RouterMoveBody{ err: "", collection: coll, to: to };
}

fn router_pick_drain(req: &HttpRequest) -> RouterPick {
  if !json_depth_ok(req.body, 64) { return RouterPick{ err: "json nesting exceeds service limit", name: "" }; }
  var parsed = json.json_parse(req.body);
  var doc = json.json_null();
  match parsed {
    Ok(v) => { doc = v; }
    Err(_) => { return RouterPick{ err: "bad json", name: "" }; }
  }
  var so = json.json_get(doc, "shard");
  match so {
    Some(sv) => {
      match sv {
        String(s) => {
          if s.len() > 0 { return RouterPick{ err: "", name: s }; }
        }
        _ => {}
      }
    }
    None => {}
  }
  return RouterPick{ err: "missing shard", name: "" };
}

// Outcome of one move attempt (code = HTTP status for the route wrapper).
type RouterMoveResult = {
  ok: Bool;
  code: Int;
  msg: Str;
  from_id: Str;
}

// One online move (admin): compaction-aware export on the source ->
// fresh collection + attach on the destination -> drop on the source ->
// mapping flip + atomic persist (version bump). A failed mapping persist
// reinstalls the source from the artifact (best effort) and reports
// loudly. Single-writer semantics: every write acked before the export
// is inside the artifact (bit-exact union); writes after the flip route
// to the new owner; the stale-cache window is one bounded retry
// (probe-gated).
fn router_move_core(rt: &mut RouterState, shards: &mut Vec[RouterShard], coll: Str, to_id: Str) -> RouterMoveResult {
  if rt.artifact_dir.len() == 0 {
    return RouterMoveResult{ ok: false, code: 500, msg: "artifact dir not configured", from_id: "" };
  }
  var owner = router_mapping_owner(&rt.mapping, coll);
  if owner < 0 { return RouterMoveResult{ ok: false, code: 404, msg: "collection not mapped", from_id: "" }; }
  var from_id = rt.mapping.shard_ids[owner];
  if to_id == from_id { return RouterMoveResult{ ok: false, code: 400, msg: "destination equals source", from_id: from_id }; }
  var to_idx = router_shard_find(shards, to_id);
  if to_idx < 0 { return RouterMoveResult{ ok: false, code: 404, msg: "destination shard not configured", from_id: from_id }; }
  var from_idx = router_shard_find(shards, from_id);
  if from_idx < 0 { return RouterMoveResult{ ok: false, code: 503, msg: "source shard not configured", from_id: from_id }; }
  var art = rt.artifact_dir + "/xvmove_" + coll + ".seg";
  // 1. source: select (dim/metric) + compaction-aware export.
  var sh = shards[from_idx];
  var eng = sh.engine;
  match select_collection(&mut eng, coll) {
    Ok(_) => {}
    Err(_) => {
      sh.engine = eng;
      shards[from_idx] = sh;
      return RouterMoveResult{ ok: false, code: 404, msg: "source collection missing", from_id: from_id };
    }
  }
  var dim: Int = eng.dimension;
  var metric: DistanceMetric = eng.metric;
  var exr = export_collection(&mut eng, coll, art);
  var ex_ok: Bool = false;
  match exr {
    Ok(_) => { ex_ok = true; }
    Err(_) => {}
  }
  sh.engine = eng;
  shards[from_idx] = sh;
  if !ex_ok { return RouterMoveResult{ ok: false, code: 500, msg: "source export failed", from_id: from_id }; }
  // 2. destination: fresh collection + attach (config travels in the artifact).
  var th = shards[to_idx];
  var teng = th.engine;
  var cr_ok: Bool = false;
  match create_named_collection(&mut teng, coll, dim, metric) {
    Ok(_) => { cr_ok = true; }
    Err(_) => {}
  }
  if !cr_ok {
    th.engine = teng;
    shards[to_idx] = th;
    return RouterMoveResult{ ok: false, code: 409, msg: "destination create failed", from_id: from_id };
  }
  var at_ok: Bool = false;
  match attach_segment(&mut teng, art) {
    Ok(_) => { at_ok = true; }
    Err(_) => {}
  }
  th.engine = teng;
  shards[to_idx] = th;
  if !at_ok {
    // Best-effort cleanup: remove the half-created destination collection.
    var th2 = shards[to_idx];
    var teng2 = th2.engine;
    let _d1 = drop_collection(&mut teng2, coll);
    th2.engine = teng2;
    shards[to_idx] = th2;
    return RouterMoveResult{ ok: false, code: 500, msg: "destination attach failed", from_id: from_id };
  }
  // 3. source: drop (the artifact file stays; ops cleans it).
  var sh2 = shards[from_idx];
  var eng2 = sh2.engine;
  var dr_ok: Bool = false;
  match drop_collection(&mut eng2, coll) {
    Ok(_) => { dr_ok = true; }
    Err(_) => {}
  }
  sh2.engine = eng2;
  shards[from_idx] = sh2;
  if !dr_ok {
    return RouterMoveResult{ ok: false, code: 500, msg: "source drop failed (both sides hold the collection)", from_id: from_id };
  }
  // 4. mapping flip + persist (version bump). On persist failure,
  //    reinstall the source from the artifact (best effort) and report.
  var m = rt.mapping;
  var ci = router_mapping_index(&m, coll);
  if ci < 0 {
    return RouterMoveResult{ ok: false, code: 500, msg: "mapping lost the collection during the move", from_id: from_id };
  }
  m.coll_shard[ci] = to_idx;
  m.version = m.version + 1;
  if !router_mapping_persist(&m, rt.mapping_path) {
    var sh3 = shards[from_idx];
    var eng3 = sh3.engine;
    var rc_ok: Bool = false;
    match create_named_collection(&mut eng3, coll, dim, metric) {
      Ok(_) => {
        match attach_segment(&mut eng3, art) {
          Ok(_) => { rc_ok = true; }
          Err(_) => {}
        }
      }
      Err(_) => {}
    }
    sh3.engine = eng3;
    shards[from_idx] = sh3;
    var msg2 = "mapping persist failed (destination copy remains; manual cleanup)";
    if rc_ok { msg2 = "mapping persist failed; source reinstalled from the artifact (destination copy remains)"; }
    return RouterMoveResult{ ok: false, code: 500, msg: msg2, from_id: from_id };
  }
  rt.mapping = m;
  return RouterMoveResult{ ok: true, code: 200, msg: "", from_id: from_id };
}

// Drain: move every collection owned by `shard_id` off it, round-robin
// over the remaining shards (no new placement on the drained node; the
// node stays configured until the mapping is edited). Stops at the first
// failed move and reports it (nothing silent).
fn router_cluster_drain(rt: &mut RouterState, shards: &mut Vec[RouterShard], shard_id: Str) -> Vec[UInt8] {
  var sidx = -1;
  var i: Int = 0;
  while i < rt.mapping.shard_ids.len() {
    if rt.mapping.shard_ids[i] == shard_id { sidx = i; }
    i = i + 1;
  }
  if sidx < 0 { return jerror(404, "unknown shard"); }
  var dests = Vec[Str].new();
  var j: Int = 0;
  while j < rt.mapping.shard_ids.len() {
    if j != sidx { dests.push(rt.mapping.shard_ids[j]); }
    j = j + 1;
  }
  if dests.len() == 0 { return jerror(400, "no destination shard"); }
  var names = Vec[Str].new();
  var k: Int = 0;
  while k < rt.mapping.coll_names.len() {
    if rt.mapping.coll_shard[k] == sidx { names.push(rt.mapping.coll_names[k]); }
    k = k + 1;
  }
  var moved: Int = 0;
  var failed: Str = "";
  var di: Int = 0;
  var n: Int = 0;
  while n < names.len() {
    var res = router_move_core(rt, shards, names[n], dests[di]);
    if !res.ok {
      failed = names[n] + ": " + res.msg;
      n = names.len();
    } else {
      moved = moved + 1;
      di = di + 1;
      if di >= dests.len() { di = 0; }
    }
    n = n + 1;
  }
  var out = json.json_object_new();
  out = json.json_set(out, "drained", json.json_string(shard_id));
  out = json.json_set(out, "moved", json.json_number(moved as Float64));
  out = json.json_set(out, "mapping_version", json.json_number(rt.mapping.version as Float64));
  if failed.len() > 0 {
    out = json.json_set(out, "failed", json.json_string(failed));
    return http_response(500, out);
  }
  return http_response(200, out);
}

// Route table --------------------------------------------------------------

fn router_route(rt: &mut RouterState, shards: &mut Vec[RouterShard], req: &HttpRequest, raw: &Vec[UInt8]) -> Vec[UInt8] {
  var segs = path_segments(req.path);
  if segs.len() == 1 && segs[0] == "health" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    return router_health(rt);
  }
  if segs.len() == 1 && segs[0] == "version" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    return router_version_json(rt);
  }
  if segs.len() == 2 && segs[0] == "cluster" && segs[1] == "mapping" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    return router_cluster_mapping(rt);
  }
  if segs.len() == 2 && segs[0] == "cluster" && segs[1] == "stats" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    return router_cluster_stats(rt, shards);
  }
  if segs.len() == 2 && segs[0] == "cluster" && segs[1] == "move" {
    if !(req.method == "POST") { return jerror(405, "method not allowed"); }
    var mv = router_pick_move(req);
    if mv.err.len() > 0 { return jerror(400, mv.err); }
    var res = router_move_core(rt, shards, mv.collection, mv.to);
    if !res.ok { return jerror(res.code, res.msg); }
    var out = json.json_object_new();
    out = json.json_set(out, "moved", json.json_bool(true));
    out = json.json_set(out, "collection", json.json_string(mv.collection));
    out = json.json_set(out, "from", json.json_string(res.from_id));
    out = json.json_set(out, "to", json.json_string(mv.to));
    out = json.json_set(out, "mapping_version", json.json_number(rt.mapping.version as Float64));
    return http_response(200, out);
  }
  if segs.len() == 2 && segs[0] == "cluster" && segs[1] == "drain" {
    if !(req.method == "POST") { return jerror(405, "method not allowed"); }
    var dv = router_pick_drain(req);
    if dv.err.len() > 0 { return jerror(400, dv.err); }
    return router_cluster_drain(rt, shards, dv.name);
  }
  if segs.len() == 1 && segs[0] == "stats" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    var sco = query_param(req.query, "collection");
    match sco {
      Some(c) => { return router_dispatch(rt, shards, c, raw); }
      None => { return router_cluster_stats(rt, shards); }
    }
  }
  if segs.len() == 1 && segs[0] == "collections" {
    if req.method == "GET" { return router_collections_list(rt); }
    if req.method == "POST" {
      var pick = router_pick_create_name(req);
      if pick.err.len() > 0 { return jerror(400, pick.err); }
      return router_dispatch(rt, shards, pick.name, raw);
    }
    return jerror(405, "method not allowed");
  }
  if segs.len() == 3 && segs[0] == "collections" && segs[2] == "points" {
    return router_dispatch(rt, shards, segs[1], raw);
  }
  if segs.len() == 1 && segs[0] == "search" {
    if !(req.method == "POST") { return jerror(405, "method not allowed"); }
    var pick2 = router_pick_search_collection(req);
    if pick2.err.len() > 0 { return jerror(400, pick2.err); }
    return router_dispatch(rt, shards, pick2.name, raw);
  }
  return jerror(404, "unknown route");
}

// Entry point: limits -> rate -> parse -> auth/scope (same map as the
// service) -> route; forwarded requests carry the client's bytes so the
// shard re-checks everything itself.
pub fn router_handle(rt: &mut RouterState, shards: &mut Vec[RouterShard], raw: &Vec[UInt8]) -> Vec[UInt8] {
  rt.requests = rt.requests + 1;
  if !rt.ok {
    rt.errors = rt.errors + 1;
    return jerror(503, "router not started (invalid mapping)");
  }
  if raw.len() > rt.cfg.max_request_bytes {
    rt.errors = rt.errors + 1;
    return jerror(413, "request exceeds service limit");
  }
  var now = time.monotonic_ms();
  if !rate_limiter_allow(&mut rt.rate, now) {
    rt.errors = rt.errors + 1;
    return jerror(429, "rate limit exceeded");
  }
  var req = http_parse_request(raw);
  if !req.ok {
    rt.errors = rt.errors + 1;
    if req.incomplete { return jerror(400, "incomplete request"); }
    return jerror(400, "malformed request");
  }
  if rt.auth.enabled {
    var need_opt = router_required_scope(req.method, req.path, req.query);
    match need_opt {
      Some(need) => {
        var presented: Str = "";
        var have: Bool = false;
        match http_header(&req, "x-api-key") {
          Some(k) => {
            presented = k;
            have = true;
          }
          None => {}
        }
        if !have {
          rt.errors = rt.errors + 1;
          return jerror(401, "missing api key");
        }
        var looked = auth_lookup(&rt.auth, presented);
        match looked {
          Some(got) => {
            if scope_code(got) < scope_code(need) {
              rt.errors = rt.errors + 1;
              return jerror(403, "insufficient scope");
            }
          }
          None => {
            rt.errors = rt.errors + 1;
            return jerror(401, "invalid api key");
          }
        }
      }
      None => {}
    }
  }
  var resp = router_route(rt, shards, &req, raw);
  if response_status(&resp) >= 400 { rt.errors = rt.errors + 1; }
  return resp;
}
