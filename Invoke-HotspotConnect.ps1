<#
.SYNOPSIS
Runs the hotspot connector silently for the Ctrl+0 hotkey.

.DESCRIPTION
This wrapper intentionally shows nothing on success. If the connector fails, it
shows a Windows system message box with the failure reason.
#>

[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 120,
    [int]$RetryIntervalSeconds = 5,
    [int]$ConnectWaitSeconds = 15
)

$ErrorActionPreference = "Stop"

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
$mutex = New-Object Threading.Mutex($true, "Global\FastIosHotspotConnectRun", [ref]$createdNew)

if (-not $createdNew) {
    exit 0
}

try {
    $connectorPath = Join-Path $PSScriptRoot "Connect-iPhoneHotspot.ps1"

    if (-not (Test-Path -LiteralPath $connectorPath)) {
        throw "Connector script not found: $connectorPath"
    }

    & $connectorPath `
        -TimeoutSeconds $TimeoutSeconds `
        -RetryIntervalSeconds $RetryIntervalSeconds `
        -ConnectWaitSeconds $ConnectWaitSeconds `
        -DisconnectFirst *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "Connector exited with code $LASTEXITCODE."
    }

    exit 0
}
catch {
    Show-SystemMessage -Title "Hotspot connection failed" -Message $_.Exception.Message
    exit 1
}
finally {
    if ($createdNew) {
        $mutex.ReleaseMutex()
    }

    $mutex.Dispose()
}
