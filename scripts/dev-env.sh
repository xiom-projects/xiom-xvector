#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR dev environment (Linux/WSL) -- dot-source in every terminal:
#   . scripts/dev-env.sh
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# VERSION POLICY: XVECTOR tracks the LATEST compiler / stdlib / packages
# (owner decision, inherited from PULSE). Record exact versions + lane hashes
# in SESSION.md at every wrap.
#
# As of 2026-10-08 (mirrors scripts/dev-env.ps1 on Windows):
#   compiler  xiom (Linux install, canonical layout ~/.local/share/xiom)
#   stdlib    $XIOM_STDLIB if set; else the WSL-mounted lane checkout
#             /mnt/e/xiom-lang/stdlib when present; else the compiler's
#             bundled lib/xiom tree (release-artifact behavior)
#   packages  <xiom_home>/packages (none consumed by xvector yet)
#
# XIOM_RUNTIME_DIR is RETIRED on v0.64.0 (verified env-free). Always cleared.
# Safe to source repeatedly; never exits the caller on warnings.
# ============================================================================

# --- compiler resolution ----------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ]; then
  if command -v xiom >/dev/null 2>&1; then
    XIOM_COMPILER="$(command -v xiom)"
  elif [ -x "$HOME/.local/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/bin/xiom"
  elif [ -x "$HOME/.local/share/xiom/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/share/xiom/bin/xiom"
  fi
fi
[ -n "${XIOM_COMPILER:-}" ] && export XIOM_COMPILER

# --- retired runtime override ----------------------------------------------
unset XIOM_RUNTIME_DIR

# --- stdlib -----------------------------------------------------------------
if [ -z "${XIOM_STDLIB:-}" ] && [ -d /mnt/e/xiom-lang/stdlib ]; then
  # WSL on the development machine: use the same lane checkout as Windows.
  XIOM_STDLIB=/mnt/e/xiom-lang/stdlib
fi
[ -n "${XIOM_STDLIB:-}" ] && export XIOM_STDLIB

# --- report -----------------------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'dev-env: WARNING XIOM_COMPILER not found (install the Linux toolchain or export XIOM_COMPILER)\n' >&2
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; else exit 0; fi
fi

_ver="$("$XIOM_COMPILER" --version 2>&1 | head -n 1)"
printf 'dev-env: %s\n' "$_ver"
printf 'dev-env: XIOM_COMPILER = %s\n' "$XIOM_COMPILER"
printf 'dev-env: XIOM_STDLIB   = %s\n' "${XIOM_STDLIB:-<unset: compiler bundled stdlib>}"
printf 'dev-env: XIOM_RUNTIME_DIR retired (v0.64.0 R65 install-layout fix)\n'
unset _ver
