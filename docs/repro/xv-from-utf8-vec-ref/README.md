<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-07 repro: `Str::from_utf8(&Vec[UInt8])` emits invalid LLVM IR

Compiler: **v0.64.0** (Windows; likely all platforms -- clang-stage bug).

Passing a **reference** to `Str::from_utf8` type-checks but dies in clang:

```
$ xiom -o out\p.exe docs\repro\xv-from-utf8-vec-ref\probe.xi
error: clang failed with exit code 1
  stderr: xiominput.ll:648:40: error: invalid getelementptr indices
  648 |   %tmp68 = getelementptr %struct.Vec*, %struct.Vec** %tmp67, i32 0, i32 0
```

The stdlib always passes the Vec **by value** (`convert/cstring.xi:47`,
`convert/escape.xi:577`, `compress/compress.xi:526`), and that form is
correct:

```xiom
var kb = Vec[UInt8].new();
kb.push(65u8);
var s = Str::from_utf8(&kb);   // clang exit 1 (invalid getelementptr)
var t = Str::from_utf8(kb);    // works
```

Found while implementing the XVECTOR payload WAL codec
(`src/engine.xi` `payload_decode`); the engine now passes by value.
No silent-wrong-code path observed -- the compile fails loudly.

Reproduce:

```powershell
. .\scripts\dev-env.ps1
& $env:XIOM_COMPILER -o out\p.exe docs\repro\xv-from-utf8-vec-ref\probe.xi   # clang exit 1
```
