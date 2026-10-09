#!/usr/bin/env bash
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Pre-release verification battery (WSL/Linux): conformance suite x2 plus
# every probe x2, using the standard scripts. Exit 0 only when all gates are
# green. Windows twin: scripts/ci.ps1.

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/dev-env.sh

probes=(
  probe_hello
  probe_bind_semantics
  probe_engine_import
  probe_vector_store
  probe_filtered_search
  probe_payload_recovery
  probe_floatval_roundtrip
  probe_search_request
  probe_payload_index
  probe_filter_plan
  probe_hnsw_recall
  probe_engine_hnsw
  probe_hnsw_codec
  probe_result_shapes
  probe_fuzz_codecs
  probe_soak_mixed
  probe_kill_recovery
)

failures=0

echo "ci: suite x2"
if ! bash scripts/run-suite.sh 2 240; then
  failures=$((failures + 1))
  echo "ci: SUITE FAILED"
fi

for p in "${probes[@]}"; do
  echo "ci: $p x2"
  if ! bash scripts/run-probe.sh "tests/probes/$p.xi" 2 > "out/ci_$p.log" 2>&1; then
    failures=$((failures + 1))
    echo "ci: PROBE FAILED: $p (see out/ci_$p.log)"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "ci: FAILED ($failures gate(s) red)"
  exit 1
fi
echo "ci: ALL GATES GREEN (suite x2 + ${#probes[@]} probes x2)"
exit 0
