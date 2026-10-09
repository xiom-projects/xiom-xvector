// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM XVECTOR benchmark harness (M-G2). Deterministic workloads over the
// real modules. Numbers are integers (us / counts / permille / ns) so the
// report needs no float formatting.
//
// Timing model: `xiom.time.monotonic_ms()` (QPC / CLOCK_MONOTONIC, ms).
// Per-query workloads first CALIBRATE a group size (double until one group
// takes >= 2 ms), then take 21 timed groups of that size (queries cycled);
// each sample stores per-op microseconds (ms*1000/group). p50/p95/p99 are
// the 11th/20th/21st sorted samples (approximate tail, documented). QPS is
// derived from p50. Whole-run workloads (ingest, build, recovery) are timed
// directly.
//
//   W1 ingest (Flat store, single upserts)
//   W2 exact KNN latency (Flat)
//   W3 HNSW build + recall vs the exact flat oracle + latency per ef_search
//   W4 filtered search (Flat planner 50%/10%, Hnsw ANN+fallback)
//   W5 batch ops (upsert_many/search_many vs single calls, ratio)
//   W6 range search (two radii, counts + latency)
//   W7 recovery (checkpoint write, load+recover, bytes/vector proxy)
//
// Mode via env XV_BENCH_MODE = quick | medium | full (default medium).
// Report: human table on stdout + JSON at out/bench_report.json
// (XV_BENCH_OUT overrides). Exit nonzero when a sanity gate fails.

module bench_main

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.query.search_service;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.io;
use xiom.convert;
use xiom.time;

fn int_to_str(n: Int) -> Str {
  return convert.int_to_string(n);
}

fn now_ms() -> Int {
  return time.monotonic_ms();
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn rand_coords(state: Int, dim: Int, coords: &mut Vec[Float32]) -> Int {
  var s = state;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var c = (s % 4001) as Float32;
    coords.push(c / 1000.0 - 2.0);
    i = i + 1;
  }
  return s;
}

fn vec_from_coords(coords: &Vec[Float32]) -> Vector {
  var v = Vector.new(coords.len());
  var i: Int = 0;
  while i < coords.len() {
    v.set(i, coords[i]);
    i = i + 1;
  }
  return v;
}

fn sort_ints(v: &mut Vec[Int]) {
  var i: Int = 1;
  while i < v.len() {
    var x = v[i];
    var j: Int = i - 1;
    while j >= 0 && v[j] > x {
      v[j + 1] = v[j];
      j = j - 1;
    }
    v[j + 1] = x;
    i = i + 1;
  }
}

fn sum_ints(v: &Vec[Int]) -> Int {
  var s: Int = 0;
  var i: Int = 0;
  while i < v.len() {
    s = s + v[i];
    i = i + 1;
  }
  return s;
}

// Percentile on a sorted vector of 21 samples: 50 -> index 10, 95 -> 19,
// 99 -> 20 (approximate tails; documented in docs/BENCHMARKS.md).
fn pct(v: &Vec[Int], p: Int) -> Int {
  if v.len() == 0 { return 0; }
  var idx = v.len() * p / 100;
  if idx >= v.len() { idx = v.len() - 1; }
  return v[idx];
}

fn qps_from_us(us: Int) -> Int {
  if us <= 0 { return 0; }
  return 1000000 / us;
}

fn recall_permille(eng: &VectorEngine, queries: &Vec[Vector], k: Int) -> Int {
  var hits_total: Int = 0;
  var overlap_total: Int = 0;
  var qi: Int = 0;
  while qi < queries.len() {
    match search(eng, &queries[qi], k) {
      Ok(approx) => {
        var exact = search_knn(&eng.store, &queries[qi], k, eng.metric);
        var ai: Int = 0;
        while ai < approx.items.len() {
          var ei: Int = 0;
          while ei < exact.len() {
            if approx.items[ai].id == exact[ei].id { overlap_total = overlap_total + 1; }
            ei = ei + 1;
          }
          ai = ai + 1;
        }
        hits_total = hits_total + approx.items.len();
      }
      Err(_) => {}
    }
    qi = qi + 1;
  }
  if hits_total == 0 { return 0; }
  return overlap_total * 1000 / hits_total;
}

fn main() -> Int {
  var mode: Str = "medium";
  match io.env_var("XV_BENCH_MODE") {
    Some(m) => { mode = m; }
    None => {}
  }
  var n: Int = 5000;
  var queries: Int = 200;
  var k: Int = 10;
  // Loop budgets: hard caps so a run can never explode in time or memory
  // (each search allocates; C-PULSE-14-family growth makes huge op counts
  // dangerous). max_group caps the calibration; max_passes caps repeat
  // timing; samples_per is the percentile sample count.
  var max_group: Int = 256;
  var max_passes: Int = 8;
  var samples_per: Int = 21;
  var efs = Vec[Int].new();
  efs.push(32);
  efs.push(64);
  efs.push(128);
  if mode == "micro" {
    n = 64;
    queries = 8;
    max_group = 64;
    max_passes = 2;
    samples_per = 5;
    efs = Vec[Int].new();
    efs.push(32);
  } elif mode == "quick" {
    n = 500;
    queries = 64;
    max_group = 128;
    max_passes = 4;
    efs = Vec[Int].new();
    efs.push(32);
    efs.push(64);
  } elif mode == "full" {
    n = 20000;
    queries = 400;
    efs = Vec[Int].new();
    efs.push(32);
    efs.push(64);
    efs.push(128);
    efs.push(256);
  }
  var dim: Int = 4;
  var out_path: Str = "out/bench_report.json";
  match io.env_var("XV_BENCH_OUT") {
    Some(p) => { out_path = p; }
    None => {}
  }
  // XV_BENCH_STAGE=w1|w2|w4a|w6|w3|w4b|w5 stops after that stage (diagnostic).
  var stage: Str = "";
  match io.env_var("XV_BENCH_STAGE") {
    Some(st) => { stage = st; }
    None => {}
  }

  io.println("=== xvector bench (" + mode + ": n=" + int_to_str(n)
    + " queries=" + int_to_str(queries) + " k=" + int_to_str(k) + ") ===");

  // Deterministic points + queries.
  var s: Int = 97531;
  var pts = Vec[Vector].new();
  var i: Int = 0;
  while i < n {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    pts.push(vec_from_coords(&c));
    i = i + 1;
  }
  var qs = Vec[Vector].new();
  i = 0;
  while i < queries {
    var qc = Vec[Float32].new();
    s = rand_coords(s, dim, &mut qc);
    qs.push(vec_from_coords(&qc));
    i = i + 1;
  }

  var eng = engine_new();
  match create_collection(&mut eng, dim, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { io.println("bench: create_collection failed"); return 2; }
  }

  // ---- W1 ingest (single upserts; repeat the pass until measurable) ----
  var passes: Int = 1;
  var ingest_ms: Int = 0;
  while true {
    var t0 = now_ms();
    i = 0;
    while i < n {
      match upsert(&mut eng, i + 1, pts[i]) {
        Ok(_) => {}
        Err(_) => { io.println("bench: upsert failed"); return 3; }
      }
      i = i + 1;
    }
    ingest_ms = now_ms() - t0;
    if ingest_ms >= 2 || passes >= max_passes { break; }
    passes = passes + 1;
  }
  var ingest_ops = n * passes;
  var ingest_pps = 0;
  if ingest_ms > 0 { ingest_pps = ingest_ops * 1000 / ingest_ms; }
  var ingest_us = 0;
  if ingest_ops > 0 { ingest_us = ingest_ms * 1000 / ingest_ops; }
  io.println("W1 ingest: " + int_to_str(ingest_us) + "us/op ("
    + int_to_str(ingest_ms) + "ms, " + int_to_str(ingest_pps)
    + " points/s, " + int_to_str(passes) + " pass(es))");
  if stage == "w1" { io.println("bench: stop at w1"); return 0; }

  // Payloads for filtered workloads: bucket = id % 10.
  i = 0;
  while i < n {
    var p = payload_new();
    payload_set(&mut p, "bucket", FieldValue.IntVal((i + 1) % 10));
    match set_payload(&mut eng, i + 1, p) {
      Ok(_) => {}
      Err(_) => { io.println("bench: set_payload failed"); return 4; }
    }
    i = i + 1;
  }

  // ---- W2 exact KNN (Flat): calibrate a group, sample 21 groups ----
  io.println("bench: W2 flat knn (calibrating, max group " + int_to_str(max_group) + ")");
  var grp: Int = 32;
  var cal_ms: Int = 0;
  var errs: Int = 0;
  while cal_ms < 2 && grp < max_group {
    var tc = now_ms();
    var ci: Int = 0;
    while ci < grp {
      match search(&eng, &qs[ci % queries], k) {
        Ok(_) => {}
        Err(_) => { errs = errs + 1; }
      }
      ci = ci + 1;
    }
    cal_ms = now_ms() - tc;
    if cal_ms < 2 { grp = grp * 2; }
  }
  var flat_samples = Vec[Int].new();
  var si: Int = 0;
  while si < samples_per {
    var ts = now_ms();
    var oi: Int = 0;
    while oi < grp {
      match search(&eng, &qs[oi % queries], k) {
        Ok(_) => {}
        Err(_) => { errs = errs + 1; }
      }
      oi = oi + 1;
    }
    flat_samples.push((now_ms() - ts) * 1000 / grp);
    si = si + 1;
  }
  sort_ints(&mut flat_samples);
  if errs != 0 { io.println("bench: flat errors"); return 5; }
  if stage == "w2" { io.println("bench: stop at w2"); return 0; }
  var flat_p50 = pct(&flat_samples, 50);
  io.println("W2 flat knn: " + int_to_str(flat_p50) + "us/op (group "
    + int_to_str(grp) + ") p95=" + int_to_str(pct(&flat_samples, 95))
    + "us p99=" + int_to_str(pct(&flat_samples, 99)) + "us qps~"
    + int_to_str(qps_from_us(flat_p50)));

  // ---- W4a filtered (Flat planner): 50% In and 10% Eq ----
  io.println("bench: W4 flat filtered");
  var vals = Vec[FieldValue].new();
  vals.push(FieldValue.IntVal(0));
  vals.push(FieldValue.IntVal(1));
  vals.push(FieldValue.IntVal(2));
  vals.push(FieldValue.IntVal(3));
  vals.push(FieldValue.IntVal(4));
  var f50 = filter_in("bucket", vals);
  var f10 = filter_eq("bucket", FieldValue.IntVal(3));
  var filt50_samples = Vec[Int].new();
  var filt10_samples = Vec[Int].new();
  si = 0;
  while si < samples_per {
    var ts5 = now_ms();
    var oi5: Int = 0;
    while oi5 < grp {
      match search_filtered(&eng, &qs[oi5 % queries], k, &f50) {
        Ok(h) => { if h.items.len() > k || h.items.len() == 0 { errs = errs + 1; } }
        Err(_) => { errs = errs + 1; }
      }
      oi5 = oi5 + 1;
    }
    filt50_samples.push((now_ms() - ts5) * 1000 / grp);
    var ts1 = now_ms();
    oi5 = 0;
    while oi5 < grp {
      match search_filtered(&eng, &qs[oi5 % queries], k, &f10) {
        Ok(h) => { if h.items.len() > k || h.items.len() == 0 { errs = errs + 1; } }
        Err(_) => { errs = errs + 1; }
      }
      oi5 = oi5 + 1;
    }
    filt10_samples.push((now_ms() - ts1) * 1000 / grp);
    si = si + 1;
  }
  sort_ints(&mut filt50_samples);
  sort_ints(&mut filt10_samples);
  if errs != 0 { io.println("bench: filtered errors"); return 6; }
  if stage == "w4a" { io.println("bench: stop at w4a"); return 0; }
  io.println("W4 flat filtered: 50%=" + int_to_str(pct(&filt50_samples, 50))
    + "us/op 10%=" + int_to_str(pct(&filt10_samples, 50)) + "us/op");

  // ---- W6 range (Flat, two radii; counts + latency) ----
  io.println("bench: W6 range");
  var r06_counts = Vec[Int].new();
  var r12_counts = Vec[Int].new();
  var r06_samples = Vec[Int].new();
  var r12_samples = Vec[Int].new();
  si = 0;
  while si < samples_per {
    var tr6 = now_ms();
    var oi6: Int = 0;
    while oi6 < grp {
      match search_range(&eng, &qs[oi6 % queries], 0.6, 10000) {
        Ok(h) => { if si == 0 && oi6 < queries { r06_counts.push(h.items.len()); } }
        Err(_) => { errs = errs + 1; }
      }
      oi6 = oi6 + 1;
    }
    r06_samples.push((now_ms() - tr6) * 1000 / grp);
    var tr2 = now_ms();
    oi6 = 0;
    while oi6 < grp {
      match search_range(&eng, &qs[oi6 % queries], 1.2, 10000) {
        Ok(h) => { if si == 0 && oi6 < queries { r12_counts.push(h.items.len()); } }
        Err(_) => { errs = errs + 1; }
      }
      oi6 = oi6 + 1;
    }
    r12_samples.push((now_ms() - tr2) * 1000 / grp);
    si = si + 1;
  }
  sort_ints(&mut r06_samples);
  sort_ints(&mut r12_samples);
  var r06_avg = sum_ints(&r06_counts) / queries;
  var r12_avg = sum_ints(&r12_counts) / queries;
  io.println("W6 range: r0.6 avg_count=" + int_to_str(r06_avg)
    + " " + int_to_str(pct(&r06_samples, 50)) + "us/op; r1.2 avg_count="
    + int_to_str(r12_avg) + " " + int_to_str(pct(&r12_samples, 50)) + "us/op");
  if errs != 0 || r06_avg == 0 || r12_avg < r06_avg {
    io.println("bench: range sanity failed");
    return 7;
  }
  if stage == "w6" { io.println("bench: stop at w6"); return 0; }

  // ---- W3 HNSW build + recall/latency per ef (exact oracle = store scan) ----
  io.println("bench: W3 hnsw build (can take seconds)");
  var tb = now_ms();
  match set_index(&mut eng, AnnIndexKind.Hnsw, ann_params_default()) {
    Ok(_) => {}
    Err(_) => { io.println("bench: set_index failed"); return 8; }
  }
  var build_ms = now_ms() - tb;
  io.println("W3 hnsw build: " + int_to_str(build_ms) + "ms");

  var ef_i: Int = 0;
  var rec_max: Int = 0;
  var hnsw_line = "";
  while ef_i < efs.len() {
    io.println("bench: W3 ef=" + int_to_str(efs[ef_i]) + " (recall + latency)");
    eng.ann.ef_search = efs[ef_i];
    var rec = recall_permille(&eng, &qs, k);
    if rec > rec_max { rec_max = rec; }
    var hns = Vec[Int].new();
    // Recalibrate the group for this ef (Hnsw is faster than the flat scan).
    var hgrp: Int = 32;
    var hcal: Int = 0;
    while hcal < 2 && hgrp < max_group {
      var thc = now_ms();
      var hci: Int = 0;
      while hci < hgrp {
        match search(&eng, &qs[hci % queries], k) {
          Ok(_) => {}
          Err(_) => { errs = errs + 1; }
        }
        hci = hci + 1;
      }
      hcal = now_ms() - thc;
      if hcal < 2 { hgrp = hgrp * 2; }
    }
    si = 0;
    while si < samples_per {
      var th = now_ms();
      var oi: Int = 0;
      while oi < hgrp {
        match search(&eng, &qs[oi % queries], k) {
          Ok(_) => {}
          Err(_) => { errs = errs + 1; }
        }
        oi = oi + 1;
      }
      hns.push((now_ms() - th) * 1000 / hgrp);
      si = si + 1;
    }
    sort_ints(&mut hns);
    var hp50 = pct(&hns, 50);
    io.println("W3 hnsw ef=" + int_to_str(efs[ef_i]) + ": recall="
      + int_to_str(rec) + "permille " + int_to_str(hp50) + "us/op p95="
      + int_to_str(pct(&hns, 95)) + "us p99=" + int_to_str(pct(&hns, 99))
      + "us qps~" + int_to_str(qps_from_us(hp50)));
    if ef_i > 0 { hnsw_line = hnsw_line + ","; }
    hnsw_line = hnsw_line + "{\"ef\":" + int_to_str(efs[ef_i])
      + ",\"recall_permille\":" + int_to_str(rec)
      + ",\"p50_us\":" + int_to_str(hp50)
      + ",\"p95_us\":" + int_to_str(pct(&hns, 95))
      + ",\"p99_us\":" + int_to_str(pct(&hns, 99))
      + ",\"qps\":" + int_to_str(qps_from_us(hp50)) + "}";
    ef_i = ef_i + 1;
  }
  if errs != 0 { io.println("bench: hnsw errors"); return 9; }
  if rec_max < 850 { io.println("bench: recall gate failed"); return 9; }
  if stage == "w3" { io.println("bench: stop at w3"); return 0; }

  // ---- W4b filtered on Hnsw ----
  io.println("bench: W4 hnsw filtered");
  var hf_samples = Vec[Int].new();
  si = 0;
  while si < samples_per {
    var thf = now_ms();
    var oi: Int = 0;
    while oi < grp {
      match search_filtered(&eng, &qs[oi % queries], k, &f10) {
        Ok(h) => { if h.items.len() > k || h.items.len() == 0 { errs = errs + 1; } }
        Err(_) => { errs = errs + 1; }
      }
      oi = oi + 1;
    }
    hf_samples.push((now_ms() - thf) * 1000 / grp);
    si = si + 1;
  }
  sort_ints(&mut hf_samples);
  if errs != 0 { io.println("bench: hnsw filtered errors"); return 10; }
  io.println("W4 hnsw filtered 10%: " + int_to_str(pct(&hf_samples, 50)) + "us/op");
  if stage == "w4b" { io.println("bench: stop at w4b"); return 0; }

  // ---- W5 batch vs single (total wall over m ops) ----
  io.println("bench: W5 batch ops");
  var m: Int = 1000;
  if n < 1000 { m = n; }
  var eng_s = engine_new();
  match create_collection(&mut eng_s, dim, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { io.println("bench: batch engine failed"); return 11; }
  }
  var ts = now_ms();
  i = 0;
  while i < m {
    match upsert(&mut eng_s, i + 1, pts[i]) { Ok(_) => {} Err(_) => { return 11; } }
    i = i + 1;
  }
  var single_ms = now_ms() - ts;
  var sp: Int = 1;
  while single_ms < 2 && sp < max_passes {
    var tsr = now_ms();
    i = 0;
    while i < m {
      match upsert(&mut eng_s, i + 1, pts[i]) { Ok(_) => {} Err(_) => { return 11; } }
      i = i + 1;
    }
    single_ms = single_ms + (now_ms() - tsr);
    sp = sp + 1;
  }

  var eng_b = engine_new();
  match create_collection(&mut eng_b, dim, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { io.println("bench: batch engine failed"); return 11; }
  }
  var batch_ms: Int = 0;
  var bp: Int = 1;
  var chunk: Int = 100;
  while true {
    var tb2 = now_ms();
    var off: Int = 0;
    while off < m {
      var cnt: Int = chunk;
      if off + cnt > m { cnt = m - off; }
      var bids = Vec[Int].new();
      var bvecs = Vec[Vector].new();
      var bi: Int = 0;
      while bi < cnt {
        bids.push(off + bi + 1);
        bvecs.push(pts[off + bi]);
        bi = bi + 1;
      }
      match upsert_many(&mut eng_b, &bids, &bvecs) { Ok(_) => {} Err(_) => { return 11; } }
      off = off + cnt;
    }
    batch_ms = now_ms() - tb2;
    if batch_ms >= 2 || bp >= max_passes { break; }
    bp = bp + 1;
  }
  // Per-op ratio: (batch_ms / bp) vs (single_ms / sp), as permille.
  var up_ratio = 0;
  if single_ms > 0 && bp > 0 { up_ratio = (batch_ms * sp * 1000) / (single_ms * bp); }
  io.println("W5 batch upsert: single=" + int_to_str(single_ms)
    + "ms/" + int_to_str(sp) + "p batch=" + int_to_str(batch_ms)
    + "ms/" + int_to_str(bp) + "p ratio=" + int_to_str(up_ratio) + "permille");

  var bq: Int = 100;
  if queries < 100 { bq = queries; }
  var qsub = Vec[Vector].new();
  i = 0;
  while i < bq {
    qsub.push(qs[i]);
    i = i + 1;
  }
  var tss = now_ms();
  i = 0;
  while i < bq {
    match search(&eng_b, &qsub[i], k) { Ok(_) => {} Err(_) => { return 11; } }
    i = i + 1;
  }
  var ssing_ms = now_ms() - tss;
  var tsm = now_ms();
  match search_many(&eng_b, &qsub, k) { Ok(_) => {} Err(_) => { return 11; } }
  var smany_ms = now_ms() - tsm;
  var se_ratio = 0;
  if ssing_ms > 0 { se_ratio = smany_ms * 1000 / ssing_ms; }
  io.println("W5 batch search: single=" + int_to_str(ssing_ms)
    + "ms many=" + int_to_str(smany_ms) + "ms ratio=" + int_to_str(se_ratio) + "permille");
  if stage == "w5" { io.println("bench: stop at w5"); return 0; }

  // ---- W7 recovery + bytes/vector ----
  io.println("bench: W7 recovery");
  var walp = "out/bench_report.wal";
  var tr = now_ms();
  if !wal_persist(&eng.wal, walp) { io.println("bench: persist failed"); return 12; }
  var ckpt_ms = now_ms() - tr;
  var file_bytes: Int = 0;
  match io.file_size(walp) {
    Some(sz) => { file_bytes = sz; }
    None => {}
  }
  var tl = now_ms();
  var wr = wal_load(walp);
  var rec_eng = engine_recover(&wr, dim, DistanceMetric.Cosine);
  var load_ms = now_ms() - tl;
  if engine_size(&rec_eng) != engine_size(&eng) {
    io.println("bench: recovery size mismatch");
    return 13;
  }
  var bpv: Int = 0;
  if n > 0 { bpv = file_bytes / n; }
  io.println("W7 recovery: checkpoint=" + int_to_str(ckpt_ms)
    + "ms load+recover=" + int_to_str(load_ms)
    + "ms checkpoint_bytes=" + int_to_str(file_bytes) + " bytes/vector=" + int_to_str(bpv));

  // ---- JSON report ----
  var j = "{\n";
  j = j + "  \"mode\": \"" + mode + "\",\n";
  j = j + "  \"n\": " + int_to_str(n) + ", \"queries\": " + int_to_str(queries)
    + ", \"k\": " + int_to_str(k) + ", \"dim\": " + int_to_str(dim)
    + ", \"samples_per\": " + int_to_str(samples_per)
    + ", \"group\": " + int_to_str(grp) + ",\n";
  j = j + "  \"ingest\": {\"us_per_point\": " + int_to_str(ingest_us)
    + ", \"ms\": " + int_to_str(ingest_ms)
    + ", \"points_per_sec\": " + int_to_str(ingest_pps) + "},\n";
  j = j + "  \"flat\": {\"p50_us\": " + int_to_str(flat_p50)
    + ", \"p95_us\": " + int_to_str(pct(&flat_samples, 95))
    + ", \"p99_us\": " + int_to_str(pct(&flat_samples, 99))
    + ", \"qps\": " + int_to_str(qps_from_us(flat_p50)) + "},\n";
  j = j + "  \"hnsw\": {\"build_ms\": " + int_to_str(build_ms)
    + ", \"efs\": [" + hnsw_line + "]},\n";
  j = j + "  \"filtered\": {\"flat50_p50_us\": " + int_to_str(pct(&filt50_samples, 50))
    + ", \"flat10_p50_us\": " + int_to_str(pct(&filt10_samples, 50))
    + ", \"hnsw10_p50_us\": " + int_to_str(pct(&hf_samples, 50)) + "},\n";
  j = j + "  \"batch\": {\"upsert_single_ms\": " + int_to_str(single_ms)
    + ", \"upsert_batch_ms\": " + int_to_str(batch_ms)
    + ", \"upsert_ratio_permille\": " + int_to_str(up_ratio)
    + ", \"search_single_ms\": " + int_to_str(ssing_ms)
    + ", \"search_many_ms\": " + int_to_str(smany_ms)
    + ", \"search_ratio_permille\": " + int_to_str(se_ratio) + "},\n";
  j = j + "  \"range\": {\"r06_us\": " + int_to_str(pct(&r06_samples, 50))
    + ", \"r06_avg_count\": " + int_to_str(r06_avg)
    + ", \"r12_us\": " + int_to_str(pct(&r12_samples, 50))
    + ", \"r12_avg_count\": " + int_to_str(r12_avg) + "},\n";
  j = j + "  \"recovery\": {\"checkpoint_ms\": " + int_to_str(ckpt_ms)
    + ", \"load_recover_ms\": " + int_to_str(load_ms)
    + ", \"checkpoint_bytes\": " + int_to_str(file_bytes)
    + ", \"bytes_per_vector\": " + int_to_str(bpv) + "}\n";
  j = j + "}\n";
  match io.write_file(out_path, j) {
    Ok(_) => {}
    Err(_) => { io.println("bench: report write failed"); return 14; }
  }
  io.println("bench: report written to " + out_path);
  io.remove_file(walp);
  return 0;
}
