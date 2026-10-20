# ============================================================================
# XIOM XVECTOR capped runner -- start an app under a hard RAM cap.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Use this for the station / any long-running app check instead of launching
# the binary directly. The child runs in a Job Object with the cap and
# KILL_ON_JOB_CLOSE: if it exceeds the cap it dies (non-zero exit); if this
# wrapper is stopped, the app is killed with it. The host is never the OOM
# victim.
#
# Usage:
#   powershell -File scripts/run-capped.ps1 -FilePath .\out\xvectord.exe `
#     -WorkingDirectory . -MaxMemoryMB 8192

param(
  [Parameter(Mandatory = $true)][string]$FilePath,
  [string]$Arguments = "",
  [string]$WorkingDirectory = (Get-Location).Path,
  [int]$MaxMemoryMB = 0,
  [int]$TimeoutSec = 0
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/memcap.ps1"

$capMB = 8192
if ($MaxMemoryMB -gt 0) { $capMB = $MaxMemoryMB }
elseif ($env:XVECTOR_MEM_CAP_MB) { $capMB = [int]$env:XVECTOR_MEM_CAP_MB }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $FilePath
if ($Arguments) { $psi.Arguments = $Arguments }
$psi.WorkingDirectory = $WorkingDirectory
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false

$p = [System.Diagnostics.Process]::Start($psi)
$job = [IntPtr]::Zero
try {
  try { $job = Set-XvectorMemoryCap -Process $p -MaxMemoryMB $capMB }
  catch { Write-Warning "run-capped: $($_)" }

  if ($TimeoutSec -gt 0) { $exited = $p.WaitForExit($TimeoutSec * 1000) }
  else { $p.WaitForExit(); $exited = $true }

  if (-not $exited) {
    try { $p.Kill() } catch { }
    $p.WaitForExit(10000) | Out-Null
  }
  $code = $p.ExitCode
} finally {
  Close-XvectorMemoryCap -Job $job
  $p.Dispose()
}

if (-not $exited) { exit 124 }
exit $code
