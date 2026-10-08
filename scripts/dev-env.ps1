# XIOM XVECTOR dev environment -- dot-source in every terminal:
#   . .\scripts\dev-env.ps1
#
# VERSION POLICY (owner decision, inherited from PULSE): XVECTOR tracks the
# LATEST compiler / stdlib / packages to harden the ecosystem by real-world
# use. Record the exact versions and lane hashes in SESSION.md at every wrap.
#
# As of 2026-10-08:
#   compiler  v0.64.1  %LOCALAPPDATA%\xiom.new\bin\xiom.exe
#   stdlib    E:\xiom-lang\stdlib (stdlib-lane checkout = latest lane work)
#   packages  %LOCALAPPDATA%\xiom\packages (none consumed by xvector yet)
#
# XIOM_RUNTIME_DIR is retired since v0.64.0: release R65 makes the installed
# compiler link lib\runtime and lib\xiom without overrides (verified env-free
# by PULSE 2026-10-05).
#
# PATH warning: a v0.62.3 staging dir shadows xiom.new in PATH -- always set
# XIOM_COMPILER explicitly instead of relying on `xiom` from PATH.

$ErrorActionPreference = "Stop"

$env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
$env:XIOM_STDLIB   = "E:\xiom-lang\stdlib"
Remove-Item Env:XIOM_RUNTIME_DIR -ErrorAction SilentlyContinue   # retired

$missing = @()
if (-not (Test-Path -LiteralPath $env:XIOM_COMPILER)) { $missing += "XIOM_COMPILER ($env:XIOM_COMPILER)" }
if (-not (Test-Path -LiteralPath $env:XIOM_STDLIB))   { $missing += "XIOM_STDLIB   ($env:XIOM_STDLIB)" }

if ($missing.Count -gt 0) {
    Write-Warning "dev-env: missing toolchain paths:"
    $missing | ForEach-Object { Write-Warning "  $_" }
    return
}

$ver = (& $env:XIOM_COMPILER --version 2>&1 | Select-Object -First 1)
Write-Host "dev-env: $ver"
Write-Host "dev-env: XIOM_STDLIB = $env:XIOM_STDLIB"
Write-Host "dev-env: XIOM_RUNTIME_DIR retired (v0.64.1 R65 install-layout fix)"
