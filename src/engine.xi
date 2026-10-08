// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.engine

// Public facade over the vector engine. Consumers call these functions; the
// engine_* orchestration lives in xiom.vector.engine.core and the xiom-core
// stand-ins in xiom.vector.core.shim. Dependency order is acyclic:
// core.shim <- engine.core <- engine (this file). Consumers that call
// engine_* symbols (engine_new/engine_size/engine_recover/...) import
// xiom.vector.engine.core in addition to this module.

use xiom.vector.engine.core;
use xiom.vector.core.shim;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.query.search_service;

pub fn create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  return engine_create_collection(eng, dim, metric);
}

pub fn upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError] {
  return engine_upsert(eng, point, vec);
}

pub fn search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[SearchHits, CoreError] {
  return engine_search(eng, query, k);
}

pub fn delete_point(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError] {
  return engine_delete(eng, point);
}

pub fn get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  return engine_get_point(eng, point);
}

pub fn set_payload(eng: &mut VectorEngine, point: Int, payload: Payload) -> Result[Bool, CoreError] {
  return engine_set_payload(eng, point, payload);
}

pub fn get_payload(eng: &VectorEngine, point: Int) -> Option[Payload] {
  return engine_get_payload(eng, point);
}

pub fn search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Result[SearchHits, CoreError] {
  return engine_search_filtered(eng, query, k, filter);
}
