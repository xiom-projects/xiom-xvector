<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Owner handoff -- xiom-xvector v1.0.0-rc.1 (PULSE-style)

The lane reports **ready for the owner's public release + benchmark**. The
repository stays private; nothing below happens until the owner greenlights.

## 1. State at handoff

- **Candidate:** `v1.0.0-rc.1` (annotated tag, local, no push). `VERSION` =
  `1.0.0-rc.1`. HEAD and pins are recorded in `SESSION.md`.
- **Batteries (at the candidate pin, v0.64.8):** Windows suite 177/177 x2 +
  SBOM/unsafe gate (47 modules) + 56 probes x2 + bench smoke + kill matrix
  -- **ALL GATES GREEN**; WSL suite 177/177 x2 + `probe_ui` /
  `probe_concurrency` / service family x2 green; WSL long sweeps were
  environment-interrupted by repeated VM restarts (0-min uptime), so the
  full WSL sweep and targeted re-runs are queued for a quiet window (logs
  in SESSION section 0).
- **Station UI:** read-only web admin at `/ui` (sampled active-store
  scatter + point inspector + search hit highlighting; `probe_ui`); the
  editor/three.js upgrade is a later slice (`docs/UI.md`).
- **SQ sealed read path:** Q-a2b landed -- sealed Flat segments with SQ
  codes use the quantized coarse scan + exact f32 rescore; the filtered
  path stays exact (`probe_sq_sealed`, 56th).
- **Readiness:** `docs/PRODUCTION-READINESS.md` -- weighted **90 %**
  today (81 % at the candidate; "release-grade"; remaining gaps are G-3/G-4
  concurrency, L-6 scope, and release-runner activation, all documented).
- **Security:** `docs/SECURITY.md` + `docs/sbom-v1.0.0-rc.1.json`
  (47 modules, `unsafe` = 0, compiler v0.64.8, stdlib pin).
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
6. **Benchmark protocol (PULSE-style):** two paths, both ready today:
   (a) in-repo deterministic harness -- `scripts/bench.ps1 -Mode quick|medium`
   (hard-capped loops; watch free memory) -> `out/bench_report.json`
   (`docs/BENCHMARKS.md`); (b) external suites over the live server --
   `out\xvectord.exe` speaks HTTP/1.1 on a real socket (stdlib `xiom.net`),
   with drop-in adapters for ann-benchmarks (`bench/adapters/ann_benchmarks/`)
   and VectorDBBench (`bench/adapters/vectordbbench/`); both live smokes
   are green on the current pin (re-run 2026-10-12: recall@10 1.000 at
   ef>=64; insert 400/400). Run with raised caps
   (`XVECTOR_MAX_REQUEST_BYTES=33554432`, `XVECTOR_MAX_BATCH=1000`) and read
   the honest notes in `bench/adapters/README.md` (single-threaded server;
   no fsync-grade durability claims yet; metadata/filter routes not exposed).
7. **Feedback loop:** file compiler/stdlib findings back through
   `docs/RELAY-COMPILER.md` / `docs/STDLIB-WISHLIST-XVECTOR.md` (they are
   written for the sibling lanes).

**Registry publish (mote tier):** the packages lane has the PREP item
(`REL-20261018-1520-xvector`): freeze pin `c858ec1` + proposed candidate
`xiom.vectors` 0.2.0 (engine + in-process HTTP; lattice modules excluded),
carve/validate running now, **publish held for your greenlight** (then it
ships in the next eco batch). The npm-style registry artifact is separate
from the GitHub release set below.

## 3. Gated pivots (re-check on every lane pass)

| Gate | Primitive | Unblocks |
|---|---|---|
| stdlib fsync/fdatasync/`truncate` + fd write path + `append_file_bytes` | **LANDED** (waves 115/117, verified in-lane) -- **D5 + D6 shipped on them** (fsync-on-ack + kill matrix + compact/swap + snapshots) | **M-D remaining: multi-segment read path + power-loss injection** |
| stdlib `xiom.net` socket layer | CLOSED for the lane -- `xvectord` ships on it (sequential accept; 2026-10-11) | TLS/proxy deployment (ops-side) |
| stdlib `mmap` | pending (`mmap_anonymous` still an Err stub at `cd281b7`) | P5 memory-mapped reads |
| packages adoptions | `xiom.wal` + `xiom.metrics` + `xiom.rate` + `xiom.http` (status subset) + `xiom.vectors` all wired + gated; **`xiom.vectors` internals swap EXECUTED** (2026-10-10); **`xiom.ann` 0.2.0 live + verified** | the `xiom.ann` swap awaits owner greenlight (`REL-20261011-1308-xvector`) |
| compiler archive | **v0.64.8 pinned 2026-10-19 -- re-pin COMPLETE on BOTH platforms** (release 2026-10-19T17:49Z, tag `4d040604b`, run 39296778685; win sha `c31d9c46`, linux sha `a8c003c0`, both installed lane-local incl. WSL; v0.64.7 kept as rollback; stdlib pin `stdlib-v0.64.8`; registry publish blocked upstream `publisher_not_mapped`); **C-19 + C-20 repros GREEN both platforms; G-2b threaded accept loop landed; station web UI `/ui`; Q-a2b sealed SQ rescore; 56 probes**; Windows full 56-probe battery ALL GATES GREEN; WSL long sweeps environment-interrupted, queued | keep the latest-toolchain protocol: re-run repros -> suite -> probes -> bench at each archive |

## 4. Evidence index

| Claim | Artifact |
|---|---|
| Everything above | `SESSION.md` (STATE + green evidence + relay rows) |
| Gates | `scripts/ci.ps1` / `ci.sh` (suite x2 + sbom + 41 probes x2 + bench smoke) |
| Correctness | `tests/test_conformance.xi` (177), `tests/probes/*.xi` (41) |
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
