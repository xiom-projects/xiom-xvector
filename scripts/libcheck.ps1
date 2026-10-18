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
# Exit 0 only when every module type-checks. WSL twin: scripts/libcheck.sh.

param(
  [int]$TimeoutSec = 120
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. "$PSScriptRoot/dev-env.ps1"
. "$PSScriptRoot/lib.ps1"

$src = Join-Path $repoRoot "src"
# The work tree lives OUTSIDE the repo: the compiler catalogs every .xi it
# finds under the project, so an out/libcheck copy would be scanned as a
# duplicate module set by every later build.
$work = Join-Path ([System.IO.Path]::GetTempPath()) "xvector-libcheck"
if (-not (Test-Path -LiteralPath $src)) { Write-Host "libcheck: FAILED -- src/ missing"; exit 1 }

# Package-import guard (the carve rule): src/ modules are package-internal and
# must use the vendored xiom.vector.primitives surface, never the public
# xiom.vectors module the package itself provides.
$guardHits = @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter *.xi |
  Where-Object { Select-String -LiteralPath $_.FullName -Pattern '^\s*use\s+xiom\.vectors\s*;' -Quiet })
if ($guardHits.Count -ne 0) {
  Write-Host "libcheck: FAILED -- src/ module(s) import the public xiom.vectors (use xiom.vector.primitives):"
  $guardHits | ForEach-Object { Write-Host "  $($_.FullName.Substring($repoRoot.Length + 1))" }
  exit 1
}

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -LiteralPath $src -Destination $work -Recurse

# The carve manifest: same project block, same deps, minus the registry
# xiom.vectors package (the package IS xiom.vectors, so it cannot depend on
# itself). Comments and every other dependency stay untouched.
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot "xiom.toml") |
  Where-Object { $_ -notmatch '^\s*xiom\.vectors\s*=' }
Set-Content -LiteralPath (Join-Path $work "xiom.toml") -Value $manifest
if ((Get-Content -LiteralPath (Join-Path $work "xiom.toml")) -match '^\s*xiom\.vectors\s*=') {
  Write-Host "libcheck: FAILED -- could not remove xiom.vectors from the package-mode manifest"
  exit 1
}

$files = @(Get-ChildItem -LiteralPath (Join-Path $work "src") -Recurse -File -Filter *.xi)
$realCount = @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter *.xi).Count
if ($files.Count -ne $realCount) {
  Write-Host "libcheck: FAILED -- copied $($files.Count) modules, src has $realCount"
  exit 1
}

$outFile = Join-Path $work "check.out"
$errFile = Join-Path $work "check.err"
$failures = @()

foreach ($f in $files) {
  $rel = $f.FullName.Substring($work.Length + 1)
  $r = Invoke-XvectorProcess -FilePath $env:XIOM_COMPILER `
    -Arguments ('--check "{0}"' -f $rel) `
    -WorkingDirectory $work -StdOutFile $outFile -StdErrFile $errFile -TimeoutSec $TimeoutSec
  if ($r.ExitCode -ne 0) {
    $detail = (($r.StdOut + $r.StdErr) -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 4) -join " | "
    $failures += [pscustomobject]@{ Module = $rel; Exit = $r.ExitCode; Detail = $detail }
  }
}

if ($failures.Count -ne 0) {
  Write-Host "libcheck: FAILED ($($failures.Count)/$($files.Count) module(s) red)"
  foreach ($f in $failures) { Write-Host "  $($f.Module) (exit $($f.Exit)): $($f.Detail)" }
  exit 1
}

Write-Host "libcheck: PASS ($($files.Count) modules type-check against the carve manifest; import guard clean)"
exit 0
