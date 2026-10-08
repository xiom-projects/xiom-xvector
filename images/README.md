<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# images/

Brand assets for the xiom-xvector project live here.

## Expected files (owner drops them in)

| File | Purpose |
|------|---------|
| `xvector-icon.ico` | Windows executable icon for `out\xvector_app.exe` (build script sets it via `rcedit` when the file exists; same hook as the PULSE lane, retired when `xiom --icon` ships) |
| `xvector-icon.png` | 512x512 master icon (docs, README, future web/landing, registry listing) |

Notes:
- The build hook (`scripts/build.ps1`) looks for `images\xvector-icon.ico`; it is
  not an error when the file is missing (the runner serves the same art later).
- The `.png` master is the source of truth; export `.ico` from it.
- Do not commit generated icon variants (`favicon-*.png` etc.) until a
  public/landing build needs them.
