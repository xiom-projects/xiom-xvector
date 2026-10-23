// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.observability.metrics

// In-repo observability surface (M-O / O1), now backed by the registry
// package `xiom.metrics` 0.2.0 (adoption slice 2026-10-10; see
// docs/XIOM-METRICS-ADOPTION.md). The exported surface is unchanged for
// consumers: fixed-bucket latency histograms + a percentile view, the
// ServiceMetrics bundle, and the bounded structured-log ring. The value
// types and the bucket mechanics come from the package; percentiles, the
// Prometheus histogram block, and the log ring stay lane-owned (the
// package deliberately excludes percentile estimation and log storage --
// see its SPEC Non-goals).
//
// This module is pure (no engine/no io): everything is probe-able with
// plain function calls, and the numbers are deterministic.

use xiom.convert;
use xiom.string.slice;
use xiom.metrics;
use xiom.sync.atomics;

// ---- Histogram (fixed upper bounds in ms; last bucket is +Inf) ----

// The lane's fixed latency bounds; passed to the package histogram so the
// bucket layout stays a lane decision (same 7 bounds as pre-adoption).
fn histogram_lane_bounds() -> Vec[Int] {
  var bounds = Vec[Int].new();
  bounds.push(1);
  bounds.push(5);
  bounds.push(10);
  bounds.push(50);
  bounds.push(100);
  bounds.push(500);
  bounds.push(1000);
  return bounds;
}

pub fn histogram_new() -> Histogram {
  var bounds = histogram_lane_bounds();
  return metric_histogram_new(&bounds);
}

// Record one observation; negative values clamp to 0 (lane contract; the
// package records the given value verbatim).
pub fn histogram_observe(h: &mut Histogram, ms: Int) {
  var v: Int = ms;
  if v < 0 { v = 0; }
  metric_histogram_observe(h, v);
}

// ---- Lane accessors over the package histogram. Consumers (http_service,
// probes) read through these so the module stays the only seam that names
// the package value types. ----

pub fn histogram_count(h: &Histogram) -> Int {
  return metric_histogram_count(h);
}

pub fn histogram_sum(h: &Histogram) -> Int {
  return metric_histogram_sum(h);
}

pub fn histogram_min(h: &Histogram) -> Int {
  return metric_histogram_min(h);
}

pub fn histogram_max(h: &Histogram) -> Int {
  return metric_histogram_max(h);
}

pub fn histogram_mean(h: &Histogram) -> Int {
  return metric_histogram_mean(h);
}

pub fn histogram_bucket_len(h: &Histogram) -> Int {
  return metric_histogram_bucket_len(h);
}

pub fn histogram_bucket_count(h: &Histogram, index: Int) -> Int {
  return metric_histogram_bucket_count(h, index);
}

pub fn histogram_bounds_len(h: &Histogram) -> Int {
  return h.bounds.len();
}

// Upper bound of bucket window `i`; callers pass a valid index
// (0 <= i < histogram_bounds_len).
pub fn histogram_bound(h: &Histogram, i: Int) -> Int {
  return h.bounds[i];
}

// Percentile as the upper bound of the bucket where the rank falls
// (rank = ceil(p/100 * observations)); 0 when empty. The +Inf bucket
// reports as `last bound + 1` (documented sentinel). Lane-owned: the
// package exposes raw bucket counts only (SPEC Non-goals).
pub fn histogram_percentile(h: &Histogram, p: Int) -> Int {
  var n: Int = histogram_count(h);
  if n == 0 { return 0; }
  var rank: Int = (p * n + 99) / 100;
  if rank < 1 { rank = 1; }
  var nbounds: Int = histogram_bounds_len(h);
  var cum: Int = 0;
  var b: Int = 0;
  while b < histogram_bucket_len(h) {
    cum = cum + histogram_bucket_count(h, b);
    if cum >= rank {
      if b < nbounds { return histogram_bound(h, b); }
      return histogram_bound(h, nbounds - 1) + 1;
    }
    b = b + 1;
  }
  return histogram_bound(h, nbounds - 1) + 1;
}

// Prometheus histogram block (moved here from http_service in the adoption
// slice so consumers never name the package types): # TYPE, cumulative
// bucket lines incl. the +Inf bucket, _sum/_count, and the lane's
// p50/p95/p99 percentile lines. Byte-identical to the pre-adoption render.
pub fn histogram_render_lines(name: Str, h: &Histogram) -> Str {
  var out = "# TYPE " + name + " histogram\n";
  var cum: Int = 0;
  var b: Int = 0;
  while b < histogram_bucket_len(h) {
    cum = cum + histogram_bucket_count(h, b);
    if b < histogram_bounds_len(h) {
      out = out + name + "_bucket{le=\"" + convert.int_to_string(histogram_bound(h, b)) + "\"} " + convert.int_to_string(cum) + "\n";
    } else {
      out = out + name + "_bucket{le=\"+Inf\"} " + convert.int_to_string(cum) + "\n";
    }
    b = b + 1;
  }
  out = out + name + "_sum " + convert.int_to_string(histogram_sum(h)) + "\n";
  out = out + name + "_count " + convert.int_to_string(histogram_count(h)) + "\n";
  out = out + name + "_p50 " + convert.int_to_string(histogram_percentile(h, 50)) + "\n";
  out = out + name + "_p95 " + convert.int_to_string(histogram_percentile(h, 95)) + "\n";
  out = out + name + "_p99 " + convert.int_to_string(histogram_percentile(h, 99)) + "\n";
  return out;
}

// ---- Service metrics bundle (G-4: atomics for the counters) ----
//
// The counters are heap-cell atomics (`xiom.sync.atomics`), not the
// package `Counter` (a plain Int): the threaded service updates them from
// several workers, and an atomic fetch_add cannot lose an increment even
// when two threads copy the state struct concurrently. Copying
// `ServiceMetrics` copies the handle (the pointer), so the shared cell is
// the one that advances. The histograms stay mutable values and are
// updated under the server's state lock (the `/metrics` scrape reads them
// under the same lock), so their bucket counts are exact too.
pub type ServiceMetrics = {
  requests_total: atomics.AtomicInt;
  errors_total: atomics.AtomicInt;
  search_ops: atomics.AtomicInt;
  upsert_ops: atomics.AtomicInt;
  auth_failures: atomics.AtomicInt;
  rate_limited: atomics.AtomicInt;
  latency_ms: Histogram;
  search_latency_ms: Histogram;
}

pub fn service_metrics_new() -> ServiceMetrics {
  return ServiceMetrics{
    requests_total: atomics.atomic_int_new(0),
    errors_total: atomics.atomic_int_new(0),
    search_ops: atomics.atomic_int_new(0),
    upsert_ops: atomics.atomic_int_new(0),
    auth_failures: atomics.atomic_int_new(0),
    rate_limited: atomics.atomic_int_new(0),
    latency_ms: histogram_new(),
    search_latency_ms: histogram_new(),
  };
}

// Counter seam. The names cannot be the package's own (`metric_counter_*`:
// a module-level definition would shadow the import) and cannot be the
// core shim's `counter_inc` (http_service imports the shim for CoreError
// alongside this module), hence the service_* spelling. The atomic handle
// is mutated through its pointee, so a nested-field `&mut` copy (the
// XVC-C-09 family) cannot drop the update.
pub fn service_counter_inc(c: &mut atomics.AtomicInt) {
  let _ = atomics.atomic_add(c, 1);
}

pub fn service_counter_value(c: &atomics.AtomicInt) -> Int {
  return atomics.atomic_load(c);
}

// ---- Bounded structured-log ring (JSON lines, wall-clock ordered) ----
//
// G-4: each line carries a monotonic completion timestamp (`ts`, ms) and
// the ring is kept sorted by it, so the slow-query view is ordered by wall
// clock even when concurrent workers finish out of lock-acquisition order.
// `stamps[i]` is the timestamp of `lines[i]`; capacity eviction drops the
// oldest line (index 0) and counts it in `dropped`.

pub type LogRing = {
  lines: Vec[Str];
  stamps: Vec[Int];
  capacity: Int;
  slow_ms: Int;
  dropped: Int;
}

pub fn log_ring_new(capacity: Int, slow_ms: Int) -> LogRing {
  var cap: Int = capacity;
  if cap < 1 { cap = 1; }
  return LogRing{ lines: Vec[Str].new(), stamps: Vec[Int].new(), capacity: cap, slow_ms: slow_ms, dropped: 0 };
}

// Next implicit timestamp for callers that do not supply one: one past the
// newest line, so `log_ring_push` keeps the historical append behavior.
fn log_ring_next_ts(r: &LogRing) -> Int {
  if r.stamps.len() == 0 { return 1; }
  return r.stamps[r.stamps.len() - 1] + 1;
}

// Timestamp of line `i` (0 for an out-of-range index).
pub fn log_ring_stamp(r: &LogRing, i: Int) -> Int {
  if i < 0 || i >= r.stamps.len() { return 0; }
  return r.stamps[i];
}

// Sanitize a string for a JSON line (requests can carry arbitrary bytes):
// quote, backslash, and control characters become '_'.
fn log_safe(s: Str) -> Str {
  var b = slice.str_bytes(s);
  var out = Vec[UInt8].new();
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    if c == 34 || c == 92 || c < 32 {
      out.push(95);
    } else {
      out.push(c);
    }
    i = i + 1;
  }
  return Str::from_utf8(&out);
}

// Record one request line at completion timestamp `ts`. The line is
// inserted at its wall-clock position (equal stamps keep arrival order),
// then the oldest line is evicted while the ring is over capacity.
pub fn log_ring_push_at(r: &mut LogRing, ts: Int, method: Str, path: Str, status: Int, ms: Int) {
  var slow: Bool = ms >= r.slow_ms;
  var line = "{\"method\":\"" + log_safe(method)
    + "\",\"path\":\"" + log_safe(path)
    + "\",\"status\":" + convert.int_to_string(status)
    + ",\"ms\":" + convert.int_to_string(ms)
    + ",\"ts\":" + convert.int_to_string(ts)
    + ",\"slow\":" + (if slow { "true" } else { "false" }) + "}";
  var at: Int = r.stamps.len();
  var i: Int = 0;
  while i < r.stamps.len() {
    if r.stamps[i] > ts {
      at = i;
      i = r.stamps.len();
    } else {
      i = i + 1;
    }
  }
  r.lines.insert(at, line);
  r.stamps.insert(at, ts);
  while r.lines.len() > r.capacity {
    r.lines.remove(0);
    r.stamps.remove(0);
    r.dropped = r.dropped + 1;
  }
}

// Append at the next implicit timestamp (historical callers/tests).
pub fn log_ring_push(r: &mut LogRing, method: Str, path: Str, status: Int, ms: Int) {
  let ts = log_ring_next_ts(r);
  log_ring_push_at(r, ts, method, path, status, ms);
}
