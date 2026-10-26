# ============================================================================
# XIOM XVECTOR resource guard -- hard process-memory caps (Windows).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Why: the app/probe must never take the whole PC down. Every lane-run child
# is placed in a Job Object with PROCESS + JOB memory limits and
# KILL_ON_JOB_CLOSE, so an allocation spike kills the child (non-zero exit)
# instead of the host. Defaults: 8 GB for apps/probes, 16 GB for compiler
# builds (override with XVECTOR_MEM_CAP_MB or -MaxMemoryMB).
#
# The job handle must stay alive for the child's lifetime; callers close it
# after WaitForExit (which also kills any descendant still in the job).

if (-not ("XvMemCap" -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class XvMemCap
{
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll")]
    public static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr info, uint infoLen);

    [DllImport("kernel32.dll")]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

    public static IntPtr Apply(IntPtr hProcess, long limitBytes, bool limitMemory)
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) { return IntPtr.Zero; }

        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        uint flags = 0x2000; // KILL_ON_JOB_CLOSE
        if (limitMemory)
        {
            flags |= 0x100 | 0x200; // PROCESS | JOB memory
            info.ProcessMemoryLimit = (UIntPtr)limitBytes;
            info.JobMemoryLimit = (UIntPtr)limitBytes;
        }
        info.BasicLimitInformation.LimitFlags = flags;

        int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr buf = Marshal.AllocHGlobal(len);
        try
        {
            Marshal.StructureToPtr(info, buf, false);
            if (!SetInformationJobObject(job, 9, buf, (uint)len)) { CloseHandle(job); return IntPtr.Zero; }
        }
        finally
        {
            Marshal.FreeHGlobal(buf);
        }
        if (!AssignProcessToJobObject(job, hProcess)) { CloseHandle(job); return IntPtr.Zero; }
        return job;
    }
}
"@
}

function Set-XvectorMemoryCap {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [int]$MaxMemoryMB = 0
    )
    if ($MaxMemoryMB -le 0) { return [IntPtr]::Zero }
    if ($Process.HasExited) { return [IntPtr]::Zero }
    $job = [XvMemCap]::Apply($Process.Handle, [int64]$MaxMemoryMB * 1MB, $true)
    if ($job -eq [IntPtr]::Zero) {
        throw "memory cap could not be applied (job object create/set/assign failed)"
    }
    return $job
}

# Compiler/tool helpers: kill the whole tree on close, but no memory limit.
# The v0.64.8 compiler hung under a PROCESS/JOB memory-limit job (XVC-C-21,
# verified fixed on v0.65.1); this keeps timeout cleanup while leaving
# routine compiler memory governed by the watchdog.
function Set-XvectorJobKillOnClose {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    if ($Process.HasExited) { return [IntPtr]::Zero }
    $job = [XvMemCap]::Apply($Process.Handle, 0, $false)
    if ($job -eq [IntPtr]::Zero) {
        throw "kill-on-close job could not be applied"
    }
    return $job
}

function Close-XvectorMemoryCap {
    param([IntPtr]$Job)
    if ($Job -ne [IntPtr]::Zero) {
        [XvMemCap]::CloseHandle($Job) | Out-Null
    }
}
