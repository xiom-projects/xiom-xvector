# XIOM XVECTOR -- D5 kill matrix (Windows).
# Spawns tests/harness/kill_writer.exe, kills it mid-stream, then verifies
# every acknowledged record survives recovery (tests/harness/kill_check.exe).
# Usage: .\scripts\kill_matrix.ps1 [-Iters 6]
param([int]$Iters = 6)

$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

. .\scripts\dev-env.ps1
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'memcap.ps1')

$capMB = 8192
if ($env:XVECTOR_MEM_CAP_MB) { $capMB = [int]$env:XVECTOR_MEM_CAP_MB }

& .\scripts\build.ps1 tests\harness\kill_writer.xi -Name kill_writer -NoIcon | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "kill-matrix: kill_writer build FAILED"; exit 1 }
& .\scripts\build.ps1 tests\harness\kill_check.xi -Name kill_check -NoIcon | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "kill-matrix: kill_check build FAILED"; exit 1 }

$writer = (Resolve-Path "out\kill_writer.exe").Path
$checker = (Resolve-Path "out\kill_check.exe").Path
$fails = 0

for ($i = 1; $i -le $Iters; $i++) {
  $hpath = "out\kill_$i"
  Remove-Item "$hpath.seg", "$hpath.ack", "$hpath.ckpt" -ErrorAction SilentlyContinue

  $p = Start-Process -FilePath $writer -ArgumentList @("$hpath.seg", "$hpath.ack", "1000000") -PassThru -WindowStyle Hidden
  $wjob = [IntPtr]::Zero
  try { $wjob = Set-XvectorMemoryCap -Process $p -MaxMemoryMB $capMB }
  catch {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    Write-Host "kill-matrix iter ${i}: FAIL (writer memory cap not applied: $($_) )"
    exit 1
  }

  # Wait until >= 5 ids are acknowledged (up to 5 s), then a beat more so the
  # process is inside the write/fsync stream, then kill.
  $t0 = Get-Date
  $acked = 0
  while (((Get-Date) - $t0).TotalSeconds -lt 5) {
    if (Test-Path -LiteralPath "$hpath.ack") {
      $acked = @(Get-Content -LiteralPath "$hpath.ack" -ErrorAction SilentlyContinue).Count
    }
    if ($acked -ge 5) { break }
    Start-Sleep -Milliseconds 25
  }
  Start-Sleep -Milliseconds (40 + $i * 25)
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
  $null = $p.WaitForExit(5000)
  Close-XvectorMemoryCap -Job $wjob

  $checkOut = "out\kill_check_$i.out"
  $checkErr = "out\kill_check_$i.err"
  $cr = Invoke-XvectorProcess -FilePath $checker `
    -Arguments ('"{0}" "{1}" "{2}"' -f "$hpath.seg", "$hpath.ckpt", "$hpath.ack") `
    -WorkingDirectory (Get-Location).Path -StdOutFile $checkOut -StdErrFile $checkErr -TimeoutSec 30
  $rc = $cr.ExitCode
  if ($rc -eq 0) {
    Write-Host "kill-matrix iter ${i}: PASS (acked=$acked)"
  } else {
    Write-Host "kill-matrix iter ${i}: FAIL (rc=$rc acked=$acked)"
    $fails = $fails + 1
  }
}

if ($fails -eq 0) {
  Write-Host "kill-matrix: ALL $Iters ITERATIONS PASS"
  exit 0
}
Write-Host "kill-matrix: $fails/$Iters ITERATIONS FAILED"
exit $fails
