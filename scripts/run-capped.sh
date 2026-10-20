#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR capped runner (Linux/WSL) -- start an app under a RAM cap.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Use this for the station / any long-running app check instead of launching
# the binary bare. `ulimit -v` caps the virtual address space (default 8 GB;
# override with XVECTOR_MEM_CAP_MB). Exceeding it fails the child, not the
# host. Windows uses a Job Object instead (scripts/run-capped.ps1).
#
# Usage: scripts/run-capped.sh ./out/xvectord [args...]

set -u
cap_mb="${XVECTOR_MEM_CAP_MB:-8192}"
ulimit -v $((cap_mb * 1024)) 2>/dev/null || true
exec "$@"
