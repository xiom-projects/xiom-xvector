// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_vector {
  name: "xiom-vector";
  version: "0.2.0";
  description: "XiomVector -- production-grade vector database engine on the XIOM shared durable core: dense vectors, distance metrics, flat + HNSW ANN, collections, segments, payload filtering, and a WAL-backed write path";
  authors: ["The XIOM Authors"];
  deps: {
    "xiom-std": "0.1.0",
    "xiom.math": ">=0.1.0",
    "xiom-core": "0.1.0"
  };
}
