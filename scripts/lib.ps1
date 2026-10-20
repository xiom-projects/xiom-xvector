# ============================================================================
# XIOM XVECTOR script helpers (dot-source) -- reliable process execution with
# output-file capture, a watchdog, a hard RAM cap, and a trustworthy exit code.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Why not Start-Process: on Windows PowerShell 5.1 `$proc.ExitCode` is
# frequently $null for redirected child processes (race between process
# object disposal and exit-code capture), which silently turns green runs
# red and vice versa. The .NET ProcessStartInfo path with async stream
# readers is deterministic and deadlock-free.
#
# Resource guard: every child is assigned to a Job Object with a hard
# process+job memory limit and KILL_ON_JOB_CLOSE (scripts/memcap.ps1). The
# default is 8 GB (XVECTOR_MEM_CAP_MB overrides); an allocation spike kills
# the child, not the host. The cap is mandatory: if it cannot be applied the
# run fails rather than running unbounded.

. "$PSScriptRoot/memcap.ps1"

function Invoke-XvectorProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = "",
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$StdOutFile,
        [Parameter(Mandatory = $true)][string]$StdErrFile,
        [int]$TimeoutSec = 120,
        [int]$MaxMemoryMB = 0,
        [switch]$NoMemoryCap
    )

    $capMB = 8192
    if ($MaxMemoryMB -gt 0) { $capMB = $MaxMemoryMB }
    elseif ($env:XVECTOR_MEM_CAP_MB) { $capMB = [int]$env:XVECTOR_MEM_CAP_MB }
    if ($NoMemoryCap) { $capMB = 0 }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    if ($Arguments) { $psi.Arguments = $Arguments }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $job = [IntPtr]::Zero
    try {
        if ($capMB -gt 0) {
            try { $job = Set-XvectorMemoryCap -Process $p -MaxMemoryMB $capMB }
            catch {
                if ($p.HasExited) {
                    # The child finished before the job assignment; nothing to cap.
                    $job = [IntPtr]::Zero
                } else {
                    try { $p.Kill() } catch { }
                    throw "memory cap (${capMB} MB) could not be applied; refusing to run unbounded: $($_)"
                }
            }
        } else {
            # No memory cap (compiler/tool): still kill the whole tree on timeout.
            try { $job = Set-XvectorJobKillOnClose -Process $p }
            catch { Write-Warning "kill-on-close job not applied: $($_)" }
        }

        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()

        $exited = $p.WaitForExit($TimeoutSec * 1000)
        if (-not $exited) {
            try { $p.Kill() } catch { }
            $p.WaitForExit(10000) | Out-Null
        }

        $outText = try { $outTask.GetAwaiter().GetResult() } catch { "" }
        $errText = try { $errTask.GetAwaiter().GetResult() } catch { "" }
        Set-Content -LiteralPath $StdOutFile -Value $outText -NoNewline
        Set-Content -LiteralPath $StdErrFile -Value $errText -NoNewline

        return [pscustomobject]@{
            ExitCode   = if ($exited) { $p.ExitCode } else { 124 }
            TimedOut   = (-not $exited)
            StdOut     = $outText
            StdErr     = $errText
            MemoryCapMB = $capMB
        }
    } finally {
        Close-XvectorMemoryCap -Job $job
        $p.Dispose()
    }
}
