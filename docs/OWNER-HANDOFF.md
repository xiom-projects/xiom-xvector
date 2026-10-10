<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Owner handoff -- xiom-xvector v1.0.0-rc.1 (PULSE-style)

The lane reports **ready for the owner's public release + benchmark**. The
repository stays private; nothing below happens until the owner greenlights.

## 1. State at handoff

- **Candidate:** `v1.0.0-rc.1` (annotated tag, local, no push). `VERSION` =
  `1.0.0-rc.1`. HEAD and pins are recorded in `SESSION.md`.
- **Batteries (at the candidate):** suite 171/171 x2 + SBOM/unsafe gate +
  32 probes x2 + bench smoke on Windows **and** WSL -- ALL GATES GREEN.
- **Readiness:** `docs/PRODUCTION-READINESS.md` -- weighted **80 %**
  ("hardened core"; remaining gaps are the gated durability primitives,
  concurrency, and release-runner activation, all documented).
- **Security:** `docs/SECURITY.md` + `docs/sbom-v1.0.0-rc.1.json`
  (44 modules, `unsafe` = 0, compiler v0.64.2, stdlib pin).
- **Benchmark:** `docs/BENCHMARKS.md` (baseline + protocol) with kernel
  fidelity pinned by `probe_reference_oracle`.

## 2. Owner actions (in order)

1. **Greenlight:** review `docs/RELEASE-NOTES-v1.0.0-rc.1.md`,
   `docs/PRODUCTION-READINESS.md`, `docs/SECURITY.md`,
   `docs/OPERATIONS.md`.
2. **Make the repository public** (owner-only). The lane never pushed.
3. **Runners:** register self-hosted runners labelled `xiom,windows` /
   `xiom,linux` (or adjust labels) so `.github/workflows/ci.yml`
   (SHA-pinned actions, runs `scripts/ci.ps1` / `ci.sh`) can execute.
4. **Branch rulesets:** protect `main` (require the CI matrix, signed-off
   commits, no force-push) on the owner's GitHub settings.
5. **Publish the release:** push the branch + the `v1.0.0-rc.1` tag (or a
   final `v1.0.0` after any last review), publish the release notes, and
   attach `docs/sbom-v1.0.0-rc.1.json`.
6. **Benchmark protocol (PULSE-style):** drive the DB through
   `docs/BENCHMARKS.md` -- `scripts/bench.ps1 -Mode quick|medium`
   (hard-capped loops; watch free memory). The PULSE prototype can consume
   the facade directly (`docs/PULSE-INTEGRATION.md`); the HTTP byte
   pipeline is consumable via an in-process adapter until the stdlib
   socket proof lands.
7. **Feedback loop:** file compiler/stdlib findings back through
   `docs/RELAY-COMPILER.md` / `docs/STDLIB-WISHLIST-XVECTOR.md` (they are
   written for the sibling lanes).

## 3. Gated pivots (re-check on every lane pass)

| Gate | Primitive | Unblocks |
|---|---|---|
| stdlib fsync/fdatasync/`truncate` + fd write path + `append_file_bytes` | still stubs at stdlib `d2b18dc` | D5 delta append log, D6 retention, fsync-grade durability (M2 exit) |
| stdlib `xiom.net` server proof (C-PULSE-02) | pending | binding the HTTP pipeline to a real socket; TLS/proxy deployment |
| stdlib `mmap` | pending | P5 memory-mapped reads |
| packages `xiom.wal` adoption | published 0.1.0 (registry-live) | single-WAL-home alignment; triage recorded in `docs/PACKAGE-WISHLIST-XVECTOR.md` |
| compiler archive > v0.64.2 | lane `d481c490` post-tag fixes | re-run repro bundles + batteries, then re-pin (XVC-C-13 is the open finding) |

## 4. Evidence index

| Claim | Artifact |
|---|---|
| Everything above | `SESSION.md` (STATE + green evidence + relay rows) |
| Gates | `scripts/ci.ps1` / `ci.sh` (suite x2 + sbom + 32 probes x2 + bench smoke) |
| Correctness | `tests/test_conformance.xi` (171), `tests/probes/*.xi` (32) |
| Crash safety | `probe_kill_recovery`, `probe_wal_file`, `probe_manifest_file`, `probe_segment_file` |
| Fidelity | `probe_reference_oracle`, `probe_hnsw_recall`, `probe_hnsw_codec`, `probe_fuzz_codecs` |
| Service | `probe_http_service`, `probe_service_limits`, `probe_service_auth`, `probe_http_fuzz`, `probe_metrics` |
| Compiler history | `docs/COMPILER-FINDINGS-XVECTOR.md`, `docs/repro/*` (re-run at rc: 9 green, 1 fixed-symptom, C-13 open by design) |
| Security/SBOM | `docs/SECURITY.md`, `docs/sbom-v1.0.0-rc.1.json`, `scripts/sbom.*` |
| Ops | `docs/OPERATIONS.md` |

## 5. Note on signing

No cryptographic signing key is configured on this machine
(`user.signingkey` empty, no `gpg`), so the candidate tag is **annotated,
not GPG-signed**; all commits carry DCO `Signed-off-by`. If the owner wants
signed tags, configure a key and re-tag before publishing.
