<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# images/

Brand assets for the xiom-xvector project live here.

## Expected files (owner drops them in)

| File | Purpose |
|------|---------|
| `xvector-icon.ico` | Windows executable icon, embedded natively by `scripts\build.ps1` via `xiom --icon` (compiler m214/v0.64.2, llvm-rc; a requested icon that fails to embed is a hard compiler error). Dropped in 2026-10-09 from the owner's asset folder. |
| `xvector-icon.png` | 512x512 master icon (docs, README, future web/landing, registry listing) -- still pending (only the .ico exists today) |

Notes:
- The build hook (`scripts/build.ps1`) passes `--icon` whenever
  `images\xvector-icon.ico` exists; `-NoIcon` opts a build out. The Linux
  builder (`scripts/build.sh`) does not pass it (Windows resources).
- The `.png` master is the source of truth when it lands; export `.ico` from it.
- Do not commit generated icon variants (`favicon-*.png` etc.) until a
  public/landing build needs them.
