# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-07 (bootstrap by the PULSE lane, owner request).
**Project:** production-grade vector database engine for XIOM (dense
vectors, distance metrics, flat + HNSW ANN, collections, segments,
WAL-backed durable writes; built on the shared `xiom-core` durable-systems
substrate per README/SPEC).

## 0. STATE (2026-10-07, BOOTSTRAP -- nothing verified yet)

- **Repo:** `E:\xiom-projects\xiom-xvector` (formerly xiom-vector).
  Identity `Lefteris Notas <lefterisnotas@gmail.com>`; repo stays
  **PRIVATE**; do not push/create remotes without owner approval;
  conventional commits with DCO sign-off (`git commit -s`).
- **VERSION POLICY (owner decision): track the LATEST compiler / stdlib /
  packages** -- this lane exists to harden the ecosystem by real-world use.
  Record exact versions and lane hashes in this file at every wrap.
  - compiler: `%LOCALAPPDATA%\xiom.new\bin\xiom.exe` (**v0.64.0**)
  - stdlib: `E:\xiom-lang\stdlib` (stdlib-lane checkout = latest)
  - `XIOM_RUNTIME_DIR` is **retired** on v0.64.0 (release R65 links the
    installed `lib\runtime` + `lib\xiom`; verified env-free by PULSE).
  - registry: `%LOCALAPPDATA%\xiom\packages`; consumption needs
    `xiom.toml` `[project].source-roots` per installed package src/ (open
    compiler gap C-PULSE-02; see PULSE relay docs).
- **First actions for the lane (Step 0, do in order):**
  1. Read `README.md`, `SPEC.md`, `ARCHITECTURE.md`, `ROADMAP.md`,
     `AUDIT.md`, `COLLECTIONS.md`, `docs/` -- this SESSION.md only carries
     environment + process, not the product design.
  2. Create `scripts\dev-env.ps1` **and** `scripts\dev-env.sh` (owner
     requirement: every script ships as both .ps1 and .sh for Linux
     contributors). Set `XIOM_COMPILER`/`XIOM_STDLIB` as above; never rely
     on PATH (a stale xiom staging dir shadows it).
  3. Verify `xiom --version` = v0.64.0, `xiom doctor` clean, hello-world
     probe x2, and a first probe of the project's critical primitive
     (e.g. vector store open/write/reopen) with a watchdog + exit-code
     gate. Stage probes **in-repo** (never `%TEMP%\kilo`).
  4. Create the three relay documents (pattern from PULSE,
     `E:\xiom-projects\xiom-pulse\docs\`):
     `docs/COMPILER-FINDINGS-XVECTOR.md` (one finding per defect + minimal
     repro bundle under `docs/repro/<name>/`), `docs/STDLIB-WISHLIST-XVECTOR.md`
     (`| Need | Evidence | Workaround | Blocks |`),
     `docs/PACKAGE-WISHLIST-XVECTOR.md`
     (`| Proposed name | Purpose | Why not stdlib | Deps | Evidence |`).
  5. Write the first real STATE block here + a fresh paste prompt.

## 1. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Report upstream only through the three relay docs + SESSION rows; the
  owner relays to the stdlib/packages/compiler lanes.
- Consume packages from the registry only; never vendor a package copy.
  Reusable primitives this lane grows should be **proposed as packages**
  in the package wishlist.

## 2. Pin discipline that bites (v0.64.0, inherited from PULSE)

- Initialize every local at declaration (`var x: T = <default>;`); every
  **struct literal must list every field** -- a missing field reads
  uninitialized garbage and can crash (PULSE open finding C-PULSE-06).
- Never initialize module-scope variables with **cross-package
  constructor calls** -- accepted by the checker, emits an undefined call
  or crashes at module init (C-PULSE-07). Keep package aggregates
  caller-owned.
- Never call `.to_str()` on a module-`const` receiver -- W005 stub; on
  v0.64.0 it aborts (`convert.int_to_string` is the workaround,
  C-PULSE-05). Explicit `*p` for every `&mut Int` read (C-PULSE-04).
- Types are `Vec[T]` / `Result[T, Err]`; after every write run the
  byte-level grep for `Vec<|Result<|Option<`.
- Parenthesize every bitwise & additive mix; `fn`, `as`, `use` reserved;
  no overloading; cross-module helpers need `pub`; submodule functions
  need submodule imports (`xiom.string.slice.str_bytes`, etc.).
- Keep a `-TimeoutSec` watchdog on every run/suite and gate on exit code;
  run every green suite x2; soak anything long-running.
- Start long-running processes with output redirected to **files** (never
  an undrained PowerShell pipe -- a chatty child holding inherited pipes
  hangs the caller; PULSE lost hours to this).

## 3. Known ecosystem status (2026-10-07)

- Fixed in v0.64.0: C-PULSE-01 (`read` method elision), runtime-link,
  crypto-link (SHA-256/HMAC usable env-free).
- Open: C-PULSE-02 (registry deps -> catalog roots; workaround
  `source-roots`), C-PULSE-04, C-PULSE-05, C-PULSE-06, C-PULSE-07; the
  `fsync`/durability gap (no `FlushFileBuffers` wrapper in the runtime).
- Registry ready for consumers: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.metrics` 0.2.0, `xiom.router` 0.1.0,
  `xiom.http.middleware` 0.1.0, `xiom.session` 0.1.0, `xiom.static`
  0.1.0, `xiom.kv` 0.1.0. PULSE may have newer findings -- read
  `E:\xiom-projects\xiom-pulse\SESSION.md` + its three relay docs before
  filing anything new (do not rediscover).

## 4. Paste prompt for the next XVECTOR session

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/. Consumer lane: never
edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages.
Repo stays PRIVATE; no pushes without owner approval. Identity
"Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Toolchain: latest-tracking -- compiler v0.64.0
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe), stdlib E:\xiom-lang\stdlib,
XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1 (and its .sh
twin). Registry consumption needs xiom.toml source-roots (C-PULSE-02).

Continue per SESSION.md: if the bootstrap steps are not done, do them
(env scripts both languages, hello + first critical-primitive probe x2
with watchdog, three relay docs). Then advance the product along
ROADMAP phases: implement, prove with tests/probes x2 + a soak for
anything long-running, update SESSION.md STATE + relay rows (compiler
findings/stdlib wishlist/package wishlist), and commit signed at every
step wrap. Keep every script as both .ps1 and .sh.
```
