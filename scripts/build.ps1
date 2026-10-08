#!/usr/bin/env pwsh
# ============================================================================
# XIOM XVECTOR builder -- compile one XIOM file to out\<name>.exe under the
# pinned toolchain, with a hard compile watchdog.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\build.ps1 tests\probes\probe_vector_store.xi
#   .\scripts\build.ps1 tests\test_conformance.xi -Name conf
# Exit code: compiler exit code (0 = built); 124 = watchdog timeout.
#
# -Sequential: A/B DIAGNOSTIC switch for XVC-C-05 (per-build nondeterministic
# lowering of Float32 arithmetic to integer bit-pattern ops). It is NOT a
# reliable workaround -- correctness flips per build with the flag in both
# directions. Every evidence build must run its own numeric assertions;
# treat a red check as a build rejection and rebuild.
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$File,
    [string]$Name = "",
    [int]$TimeoutSec = 240,
    [switch]$NoIcon,
    [switch]$Sequential
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved; check scripts\dev-env.ps1" }
}
. (Join-Path $PSScriptRoot "lib.ps1")

$filePath = (Resolve-Path -LiteralPath $File).Path
if (-not $Name) { $Name = [System.IO.Path]::GetFileNameWithoutExtension($filePath) }
$outDir = Join-Path $repoRoot "out"
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outExe = Join-Path $outDir "$Name.exe"

# A stale binary from a previous run is worse than no binary: it can be
# silently executed as "fresh". Remove before compiling.
if (Test-Path -LiteralPath $outExe) { Remove-Item -LiteralPath $outExe -Force }

$outFile = Join-Path $env:TEMP ("xvector-build-" + [guid]::NewGuid().ToString("N") + ".out")
$errFile = Join-Path $env:TEMP ("xvector-build-" + [guid]::NewGuid().ToString("N") + ".err")

Write-Host "build: $filePath -> $outExe"
$buildArgs = ""
if ($Sequential) { $buildArgs = "--sequential " }
$buildArgs += ('-o "{0}" "{1}"' -f $outExe, $filePath)
if ($Sequential) { Write-Host "build: --sequential (XVC-C-05 A/B diagnostic)" }
$result = Invoke-XvectorProcess -FilePath $env:XIOM_COMPILER `
    -Arguments $buildArgs `
    -WorkingDirectory $repoRoot -StdOutFile $outFile -StdErrFile $errFile -TimeoutSec $TimeoutSec

$output = "$($result.StdOut)$($result.StdErr)"
if ($output.Trim().Length -gt 0) { Write-Host $output.TrimEnd() }
Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue

if ($result.TimedOut) {
    Write-Host "build: TIMEOUT after ${TimeoutSec}s -- process tree killed"
    exit 124
}
if ($result.ExitCode -ne 0) {
    Write-Host "build: FAILED (compiler exit $($result.ExitCode))"
    exit $result.ExitCode
}
if (-not (Test-Path -LiteralPath $outExe)) {
    Write-Host "build: compiler exit 0 but $outExe missing"
    exit 1
}

# --- Windows exe icon (workaround until `xiom --icon` ships) ----------------
# Uses rcedit when available and images\xvector-icon.ico exists; not an error
# when missing. Same hook as the PULSE lane.
if (-not $NoIcon) {
    $iconPath = Join-Path $repoRoot "images\xvector-icon.ico"
    if (Test-Path -LiteralPath $iconPath) {
        $rcedit = Get-Command rcedit -ErrorAction SilentlyContinue
        if ($null -eq $rcedit) { $rcedit = Get-Command rcedit-x64 -ErrorAction SilentlyContinue }
        if ($null -ne $rcedit) {
            & $rcedit.Source $outExe --set-icon $iconPath 2>&1 | Out-Null
            if ($?) {
                Write-Host "build: exe icon set via rcedit ($iconPath)"
            } else {
                Write-Host "build: WARNING rcedit failed to set the icon"
            }
        } else {
            Write-Host "build: rcedit not found -- exe icon not set (install rcedit or wait for 'xiom --icon')"
        }
    }
}

Write-Host "build: OK $outExe"
exit 0
