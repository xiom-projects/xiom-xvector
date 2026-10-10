// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.observability.metrics

// In-repo observability primitives (M-O / O1). `xiom.metrics` is planned
// for a later phase (and the compiler does not map registry deps yet), so
// the lane keeps a small, dependency-free surface behind the same idea:
// shim counters (the xiom.core.metrics stand-in), fixed-bucket histograms,
// and a bounded structured-log ring. The service exposes them via
// `GET /metrics` and the JSON log lines; the socket adapter can pipe the
// ring to stdout/file unchanged.
//
// This module is pure (no engine/no io): everything is probe-able with
// plain function calls, and the numbers are deterministic.

use xiom.convert;
use xiom.string.slice;
use xiom.vector.core.shim;

// ---- Histogram (fixed upper bounds in ms; last bucket is +Inf) ----

pub type Histogram = {
  bounds: Vec[Int];
  counts: Vec[Int];
  total_ms: Int;
  observations: Int;
}

pub fn histogram_new() -> Histogram {
  var bounds = Vec[Int].new();
  bounds.push(1);
  bounds.push(5);
  bounds.push(10);
  bounds.push(50);
  bounds.push(100);
  bounds.push(500);
  bounds.push(1000);
  var counts = Vec[Int].new();
  var i: Int = 0;
  while i <= bounds.len() {
    counts.push(0);
    i = i + 1;
  }
  return Histogram{ bounds: bounds, counts: counts, total_ms: 0, observations: 0 };
}

pub fn histogram_observe(h: &mut Histogram, ms: Int) {
  var v: Int = ms;
  if v < 0 { v = 0; }
  var b: Int = 0;
  var placed: Bool = false;
  while b < h.bounds.len() && !placed {
    if v <= h.bounds[b] {
      h.counts[b] = h.counts[b] + 1;
      placed = true;
    } else {
      b = b + 1;
    }
  }
  if !placed {
    h.counts[h.bounds.len()] = h.counts[h.bounds.len()] + 1;
  }
  h.total_ms = h.total_ms + v;
  h.observations = h.observations + 1;
}

// Percentile as the upper bound of the bucket where the rank falls
// (rank = ceil(p/100 * observations)); 0 when empty. The +Inf bucket
// reports as `last bound + 1` (documented sentinel).
pub fn histogram_percentile(h: &Histogram, p: Int) -> Int {
  if h.observations == 0 { return 0; }
  var rank: Int = (p * h.observations + 99) / 100;
  if rank < 1 { rank = 1; }
  var cum: Int = 0;
  var b: Int = 0;
  while b < h.counts.len() {
    cum = cum + h.counts[b];
    if cum >= rank {
      if b < h.bounds.len() { return h.bounds[b]; }
      return h.bounds[h.bounds.len() - 1] + 1;
    }
    b = b + 1;
  }
  return h.bounds[h.bounds.len() - 1] + 1;
}

// ---- Service metrics bundle ----

pub type ServiceMetrics = {
  requests_total: Counter;
  errors_total: Counter;
  search_ops: Counter;
  upsert_ops: Counter;
  auth_failures: Counter;
  rate_limited: Counter;
  latency_ms: Histogram;
  search_latency_ms: Histogram;
}

pub fn service_metrics_new() -> ServiceMetrics {
  return ServiceMetrics{
    requests_total: counter_new("xvector.requests_total"),
    errors_total: counter_new("xvector.errors_total"),
    search_ops: counter_new("xvector.search_ops"),
    upsert_ops: counter_new("xvector.upsert_ops"),
    auth_failures: counter_new("xvector.auth_failures"),
    rate_limited: counter_new("xvector.rate_limited"),
    latency_ms: histogram_new(),
    search_latency_ms: histogram_new(),
  };
}

// ---- Bounded structured-log ring (JSON lines) ----

pub type LogRing = {
  lines: Vec[Str];
  capacity: Int;
  slow_ms: Int;
  dropped: Int;
}

pub fn log_ring_new(capacity: Int, slow_ms: Int) -> LogRing {
  var cap: Int = capacity;
  if cap < 1 { cap = 1; }
  return LogRing{ lines: Vec[Str].new(), capacity: cap, slow_ms: slow_ms, dropped: 0 };
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

pub fn log_ring_push(r: &mut LogRing, method: Str, path: Str, status: Int, ms: Int) {
  var slow: Bool = ms >= r.slow_ms;
  var line = "{\"method\":\"" + log_safe(method)
    + "\",\"path\":\"" + log_safe(path)
    + "\",\"status\":" + convert.int_to_string(status)
    + ",\"ms\":" + convert.int_to_string(ms)
    + ",\"slow\":" + (if slow { "true" } else { "false" }) + "}";
  r.lines.push(line);
  while r.lines.len() > r.capacity {
    var i: Int = 0;
    while i < r.lines.len() - 1 {
      r.lines[i] = r.lines[i + 1];
      i = i + 1;
    }
    r.lines.pop();
    r.dropped = r.dropped + 1;
  }
}
