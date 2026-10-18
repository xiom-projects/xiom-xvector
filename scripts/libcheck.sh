#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR library type-check gate -- type-check src/ as a PACKAGE.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Why this gate exists (SESSION.md section 1 item 0): the probes and the
# conformance suite compile ROOT PROGRAMS that see the registry `xiom.vectors`
# dependency, so they never exercised src/ the way the packages-lane carve
# does. A carve of src/ into the xiom.vectors package cannot depend on itself,
# and the first carve found four real gaps (internal `use xiom.vectors`, a
# dangling `xiom.core.ids` import, a missing core.shim import for a contract,
# and the xiom.http dependency). This gate reproduces the carve's library
# mode: a temp copy of src/ is compiled module-by-module against a manifest
# with `xiom.vectors` REMOVED from [dependencies], reproducing the carve's
# self-contained shape. Unresolved imports and undefined names in module
# bodies fail as they did in the carve.
#
# The type-check alone is NOT sufficient for the self-import rule: a module
# that also imports the vendored primitives type-checked green while importing
# the public module (negative-tested 2026-10-18), because every symbol it
# needed was already in scope. The explicit import guard below closes that
# hole.
#
# Exit 0 only when every module type-checks. Windows twin: scripts/libcheck.ps1.

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/dev-env.sh

timeout_sec="${1:-120}"
src="$repo_root/src"
work="$repo_root/out/libcheck"

if [ ! -d "$src" ]; then
  echo "libcheck: FAILED -- src/ missing"
  exit 1
fi

# Package-import guard (the carve rule): src/ modules are package-internal and
# must use the vendored xiom.vector.primitives surface, never the public
# xiom.vectors module the package itself provides.
guard_hits="$(grep -rlE '^[[:space:]]*use[[:space:]]+xiom\.vectors[[:space:]]*;' "$src" || true)"
if [ -n "$guard_hits" ]; then
  echo "libcheck: FAILED -- src/ module(s) import the public xiom.vectors (use xiom.vector.primitives):"
  printf '%s\n' "$guard_hits" | sed "s|^$repo_root/|  |"
  exit 1
fi

rm -rf "$work"
mkdir -p "$work"
cp -R "$src" "$work/src"

# The carve manifest: same project block, same deps, minus the registry
# xiom.vectors package (the package IS xiom.vectors, so it cannot depend on
# itself). Comments and every other dependency stay untouched.
grep -vE '^[[:space:]]*xiom\.vectors[[:space:]]*=' xiom.toml > "$work/xiom.toml"
if grep -qE '^[[:space:]]*xiom\.vectors[[:space:]]*=' "$work/xiom.toml"; then
  echo "libcheck: FAILED -- could not remove xiom.vectors from the package-mode manifest"
  exit 1
fi

real_count="$(find "$src" -type f -name '*.xi' | wc -l | tr -d ' ')"
files="$(find "$work/src" -type f -name '*.xi' | sort)"
file_count="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
if [ "$file_count" != "$real_count" ]; then
  echo "libcheck: FAILED -- copied $file_count modules, src has $real_count"
  exit 1
fi

failures=0
first_failures=""

while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#"$work"/}"
  log="$work/check.log"
  if ! (cd "$work" && "$XIOM_COMPILER" --check "$rel" > "$log" 2>&1); then
    failures=$((failures + 1))
    detail="$(grep -m 4 -E 'error|note|help' "$log" | tr '\n' ' ')"
    first_failures="${first_failures}
  ${rel}: ${detail}"
  fi
done <<< "$files"

if [ "$failures" -ne 0 ]; then
  echo "libcheck: FAILED ($failures/$file_count module(s) red)"
  printf '%s\n' "$first_failures"
  exit 1
fi

echo "libcheck: PASS ($file_count modules type-check against the carve manifest; import guard clean)"
exit 0
