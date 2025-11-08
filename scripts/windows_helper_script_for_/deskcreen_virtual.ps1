# deskcreen_virtual.ps1
# Run this script elevated, so there is only one UAC prompt needed for managing usbmmidd_v2 driver,
# to create and destroy the virtual screens.
# Then it starts Deskreen non-elevated and blocks until it exits.
# When the Deskreen process runs with elevated privileges, then there are some
# issues with webrtc in a browser, so to avoid fixing the culprit 
# just ensure Deskreen runs non-elevated.


$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$deviceInstaller = Join-Path $scriptDir "..\deviceinstaller64.exe"
$deskreenExe = Join-Path $scriptDir "deskreen.exe"
$deskreenArgs = ""

# -------------------------------------------------------------------
# C# helper: CreateProcessWithTokenW
# -------------------------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NonElevatedProcessStarter {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize;
        public int dwXCountChars, dwYCountChars, dwFillAttribute;
        public int dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public uint dwProcessId, dwThreadId;
    }

    [DllImport("user32.dll")]  public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")]  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint acc, bool inherit, uint pid);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr proc, uint acc, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool DuplicateTokenEx(
        IntPtr existing, uint acc, IntPtr attrs, int level, int type, out IntPtr newToken);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CreateProcessWithTokenW(
        IntPtr token, uint logonFlags, string app, string cmd, uint flags,
        IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);

    const uint PROCESS_QUERY_INFORMATION = 0x0400;
    const uint TOKEN_DUPLICATE=2, TOKEN_QUERY=8, TOKEN_ASSIGN_PRIMARY=1;
    const uint TOKEN_ALL_ACCESS=0xF01FF;
    const int  SecurityImpersonation=2, TokenPrimary=1;
    const uint CREATE_NEW_CONSOLE=0x10, INFINITE=0xFFFFFFFF;

    public static int StartAndWait(string app, string cmd, string cwd, out uint pid) {
        pid=0;
        IntPtr hwnd=GetShellWindow();
        if(hwnd==IntPtr.Zero) return -1;
        uint shellPid; GetWindowThreadProcessId(hwnd, out shellPid);
        IntPtr hProc=OpenProcess(PROCESS_QUERY_INFORMATION,false,shellPid);
        if(hProc==IntPtr.Zero) return -2;
        IntPtr hTok;
        if(!OpenProcessToken(hProc,TOKEN_DUPLICATE|TOKEN_QUERY,out hTok)) { CloseHandle(hProc); return -3; }
        IntPtr hUser;
        if(!DuplicateTokenEx(hTok,TOKEN_ALL_ACCESS,IntPtr.Zero,SecurityImpersonation,TokenPrimary,out hUser)) {
            CloseHandle(hTok); CloseHandle(hProc); return -4;
        }
        STARTUPINFO si=new STARTUPINFO(); si.cb=Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        bool ok=CreateProcessWithTokenW(hUser,0,app,cmd,CREATE_NEW_CONSOLE,IntPtr.Zero,cwd,ref si,out pi);
        if(!ok){ CloseHandle(hUser); CloseHandle(hTok); CloseHandle(hProc); return -5; }
        pid=pi.dwProcessId;
        WaitForSingleObject(pi.hProcess,INFINITE);
        CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
        CloseHandle(hUser); CloseHandle(hTok); CloseHandle(hProc);
        return 0;
    }
}
"@

# -------------------------------------------------------------------
function Start-NonElevatedAndWait {
    param([string]$exePath, [string]$exeArgs = "")
    $full = (Resolve-Path $exePath).Path
    $work = Split-Path -Parent $full
    $cmd = if ($exeArgs) { "`"$full`" $exeArgs" } else { "`"$full`"" }

    $procId = [uint32]0
    $rc = [NonElevatedProcessStarter]::StartAndWait($full, $cmd, $work, [ref]$procId)
    if ($rc -ne 0) { throw "StartNonElevated failed, code $rc" }
}

# -------------------------------------------------------------------
# Main flow
# -------------------------------------------------------------------
try {
    Write-Host "Activating virtual screen..."
    & "$deviceInstaller" enableidd 1
    & "$deviceInstaller" enableidd 1
    & "$deviceInstaller" enableidd 1
    & "$deviceInstaller" enableidd 1

    Write-Host "Launching Deskreen non-elevated..."
    Start-NonElevatedAndWait $deskreenExe $deskreenArgs

    Write-Host "Deskreen exited, deactivating virtual screen..."
    & "$deviceInstaller" enableidd 0
    & "$deviceInstaller" enableidd 0
    & "$deviceInstaller" enableidd 0
    & "$deviceInstaller" enableidd 0
    Write-Host "Done."
}
catch {
    Write-Warning $_
    try { & "$deviceInstaller" enableidd 0 } catch {}
    try { & "$deviceInstaller" enableidd 0 } catch {}
    try { & "$deviceInstaller" enableidd 0 } catch {}
    try { & "$deviceInstaller" enableidd 0 } catch {}
    exit 1
}
