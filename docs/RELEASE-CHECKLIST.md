<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# Release checklist (XVECTOR)

The repo is **private by default**; a release only happens on explicit owner
greenlight. Nothing here authorizes a push.

## Preconditions

- Working tree clean; all slices committed signed (`-s`).
- Quiet machine (check free memory; a concurrent heavy build can produce
  spurious reds).
- Toolchain hashes recorded in `SESSION.md` (compiler, stdlib, packages).

## Steps

1. **Freeze**: no uncommitted changes; note HEAD.
2. **Full battery, both platforms**:
   - Windows: `./scripts/ci.ps1` (suite x2 + all 16 probes x2)
   - WSL: `bash scripts/ci.sh`
   - Both must print `ALL GATES GREEN` and exit 0.
3. **Repro bundles** (`docs/repro/*/README.md`): re-run the revision-pinned
   probes at the current compiler; update status rows.
4. **Compiler findings**: re-test the OPEN rows (C-07/C-08/C-09/C-10) against
   the release compiler; refresh `docs/COMPILER-FINDINGS-XVECTOR.md` and
   `docs/RELAY-COMPILER.md`.
5. **Readiness**: recompute `docs/PRODUCTION-READINESS.md`; never raise a
   score without evidence.
6. **SESSION**: update STATE, green evidence, relay rows, next tasks.
7. **Version**: bump `VERSION` (e.g. `0.1.0-dev` -> `0.1.0`), commit
   `chore(release): vX.Y.Z`.
8. **Tag**: `git tag -s vX.Y.Z -m "xvector vX.Y.Z"` (signed; no push yet).
9. **Release notes**: summarize from SESSION + the readiness change log.
10. **Owner gate**: the owner approves and pushes the branch/tag and
    publishes the release. Until then everything stays local.

## CI

`.github/workflows/ci.yml` runs the same battery once self-hosted runners
labelled `xiom,windows` / `xiom,linux` exist (SHA-pinned actions only).
