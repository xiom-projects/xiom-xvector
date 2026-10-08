// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.types.neighbor

// Low-level graph edge type used by the ANN indexes.
// Extracted from the consolidated engine (post-AUDIT module tree).

pub type Neighbor = {
  id: UInt64;
  distance: Float32;
} derive[Clone]

pub fn neighbor_new(id: UInt64, distance: Float32) -> Neighbor {
  return Neighbor{ id: id, distance: distance };
}
