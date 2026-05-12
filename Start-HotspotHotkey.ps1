<#
.SYNOPSIS
Registers Ctrl+0 as a global hotkey for the hotspot connector.

.DESCRIPTION
This script stays running in the background. Pressing Ctrl+0 launches
Invoke-HotspotConnect.ps1 in a hidden PowerShell process. Success is silent;
failure is reported by the runner with a Windows system message box.
#>

[CmdletBinding()]
param(
    [string]$RunnerPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RunnerPath)) {
    $RunnerPath = Join-Path $PSScriptRoot "Invoke-HotspotConnect.ps1"
}

function Show-SystemMessage {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        & msg.exe * "$Title`n$Message" 2>$null | Out-Null
    }
}

$createdNew = $false
$mutex = New-Object Threading.Mutex($true, "Global\FastIosHotspotConnectHotkey", [ref]$createdNew)

if (-not $createdNew) {
    exit 0
}

$registered = $false
$window = $null

try {
    if (-not (Test-Path -LiteralPath $RunnerPath)) {
        throw "Hotkey runner not found: $RunnerPath"
    }

    Add-Type -AssemblyName System.Windows.Forms

    $source = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class HotspotHotkeyWindow : NativeWindow, IDisposable
{
    public const int WmHotkey = 0x0312;
    public event EventHandler HotkeyPressed;

    public HotspotHotkeyWindow()
    {
        CreateHandle(new CreateParams());
    }

    public IntPtr WindowHandle
    {
        get { return Handle; }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && HotkeyPressed != null)
        {
            HotkeyPressed(this, EventArgs.Empty);
        }

        base.WndProc(ref m);
    }

    public void Dispose()
    {
        DestroyHandle();
    }
}

public static class HotspotHotkeyNative
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@

    Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms

    $script:PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $script:RunnerPath = (Resolve-Path -LiteralPath $RunnerPath).Path

    $window = New-Object HotspotHotkeyWindow
    $hotkeyId = 0x4930
    $modControl = 0x0002
    $modNoRepeat = 0x4000
    $vk0 = 0x30

    $registered = [HotspotHotkeyNative]::RegisterHotKey(
        $window.WindowHandle,
        $hotkeyId,
        ($modControl -bor $modNoRepeat),
        $vk0
    )

    if (-not $registered) {
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Could not register Ctrl+0. Another app may already own it. Win32 error: $lastError"
    }

    $window.add_HotkeyPressed({
        Start-Process `
            -FilePath $script:PowerShellExe `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-WindowStyle",
                "Hidden",
                "-File",
                $script:RunnerPath
            ) `
            -WindowStyle Hidden
    })

    [System.Windows.Forms.Application]::Run()
}
catch {
    Show-SystemMessage -Title "Hotspot hotkey failed" -Message $_.Exception.Message
    exit 1
}
finally {
    if ($registered -and $null -ne $window) {
        [HotspotHotkeyNative]::UnregisterHotKey($window.WindowHandle, 0x4930) | Out-Null
    }

    if ($null -ne $window) {
        $window.Dispose()
    }

    if ($createdNew) {
        $mutex.ReleaseMutex()
    }

    $mutex.Dispose()
}
