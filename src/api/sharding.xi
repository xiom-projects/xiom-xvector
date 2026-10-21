// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.sharding

// Stable intra-collection placement (L-6 phase B). A split collection lists
// its shards in mapping order; slot = point_id mod part_count. The router
// and every shard share this function so write routing (the upsert part
// header) and search fan-out agree exactly. Negative ids normalize into
// [0, part_count) even though the engine treats non-positive ids as
// deleted; refusing to rely on that convention keeps the mapping honest.
pub fn shard_slot(point_id: Int, part_count: Int) -> Int
  requires: part_count > 0
{
  if part_count <= 1 { return 0; }
  var m = point_id % part_count;
  if m < 0 { m = m + part_count; }
  return m;
}

// True when a slot is inside a mapping's part list.
pub fn shard_slot_ok(slot: Int, part_count: Int) -> Bool
  requires: part_count > 0
{
  return slot >= 0 && slot < part_count;
}
