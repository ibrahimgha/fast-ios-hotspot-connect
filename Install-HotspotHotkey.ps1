<#
.SYNOPSIS
Installs the Ctrl+0 hotspot hotkey for the current Windows user.

.DESCRIPTION
Creates a Startup-folder shortcut that launches Start-HotspotHotkey.ps1 hidden
at login, then starts the listener immediately unless -NoStart is provided.
#>

[CmdletBinding()]
param(
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

$listenerPath = Join-Path $PSScriptRoot "Start-HotspotHotkey.ps1"
$powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Fast iOS Hotspot Connect Hotkey.lnk"

if (-not (Test-Path -LiteralPath $listenerPath)) {
    throw "Hotkey listener not found: $listenerPath"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShellExe
$shortcut.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $listenerPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = "Registers Ctrl+0 to run Fast iOS Hotspot Connect."
$shortcut.Save()

if (-not $NoStart) {
    Start-Process `
        -FilePath $powerShellExe `
        -ArgumentList @(
            "-NoProfile",
            "-STA",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-File",
            $listenerPath
        ) `
        -WindowStyle Hidden
}

Write-Host "Installed Ctrl+0 hotspot hotkey startup shortcut: $shortcutPath"
