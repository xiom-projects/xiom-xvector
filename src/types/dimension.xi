// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.types.dimension

fn is_valid_dimension(v: Int) -> Bool {
  return v >= 1 && v <= 65536;
}

fn max_dimensions() -> Int {
  return 65536;
}

pub type Dimension = { value: Int; } derive[Clone, Eq]

pub fn dimension(v: Int) -> Dimension
  requires: v >= 1
{
  return Dimension{ value: v };
}

pub fn dimension_value(d: &Dimension) -> Int {
  return d.value;
}

pub fn dimension_eq(a: &Dimension, b: &Dimension) -> Bool {
  return a.value == b.value;
}

pub fn dimension_is_valid(v: Int) -> Bool {
  return is_valid_dimension(v);
}

pub fn dimension_within_limit(v: Int) -> Bool {
  return v >= 1 && v <= max_dimensions();
}