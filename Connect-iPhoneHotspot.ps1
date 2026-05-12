<#
.SYNOPSIS
Creates hidden Wi-Fi profiles for iPhone hotspots and repeatedly tries to connect.

.DESCRIPTION
This script helps Windows connect to known iPhone Personal Hotspots even when the
SSID is not visible in the normal Wi-Fi list. It creates WLAN profiles with
nonBroadcast enabled, stores the hotspot passwords encrypted for the current
Windows user, and then tries each configured hotspot until one connects.

Important limitation: if iOS has fully stopped advertising the Personal Hotspot
radio, Windows cannot force the iPhone to wake it over Wi-Fi. This script can
connect to hidden/known networks and retry aggressively, but the iPhone still
has to make the hotspot available at the radio level.

.EXAMPLE
.\Connect-iPhoneHotspot.ps1 -Setup

Uses the hardcoded hotspots, prompts for one more optional SSID and password,
saves that extra password encrypted, installs the WLAN profiles, and starts
connecting.

.EXAMPLE
.\Connect-iPhoneHotspot.ps1 -TimeoutSeconds 0 -DisconnectFirst

Keeps trying forever and disconnects from the current Wi-Fi before each attempt.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Setup,
    [int]$HotspotCount = 1,
    [string]$InterfaceName,
    [int]$TimeoutSeconds = 300,
    [int]$RetryIntervalSeconds = 10,
    [int]$ConnectWaitSeconds = 20,
    [switch]$DisconnectFirst,
    [switch]$InstallOnly,
    [switch]$Once,
    [switch]$NoInternetCheck
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "hotspots.secure.json"
}

$BuiltInHotspots = @(
    [pscustomobject]@{
        Ssid = "Ibrahim"
        ProfileName = "Fast iOS Hotspot Connect - Ibrahim"
        Password = "aaaaaaaa"
        Authentication = "WPA2PSK"
        Priority = 1
    },
    [pscustomobject]@{
        Ssid = "Ibrahim 012"
        ProfileName = "Fast iOS Hotspot Connect - Ibrahim 012"
        Password = "aaaaaaaa"
        Authentication = "WPA2PSK"
        Priority = 2
    }
)

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][securestring]$SecureString)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-XmlText {
    param([Parameter(Mandatory)][string]$Text)
    [Security.SecurityElement]::Escape($Text)
}

function Save-HotspotConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Count,
        [int]$PriorityOffset = 0
    )

    $items = @()

    for ($index = 1; $index -le $Count; $index++) {
        do {
            $ssid = Read-Host "Additional SSID #$index"
        } while ([string]::IsNullOrWhiteSpace($ssid))

        $password = Read-Host "Password for '$ssid'" -AsSecureString
        $auth = Read-Host "Authentication for '$ssid' [WPA2PSK]"

        if ([string]::IsNullOrWhiteSpace($auth)) {
            $auth = "WPA2PSK"
        }

        $items += [pscustomobject]@{
            Ssid = $ssid
            PasswordSecret = ($password | ConvertFrom-SecureString)
            Authentication = $auth
            Priority = $PriorityOffset + $index
        }
    }

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($items.Count -eq 0) {
        "[]" | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    else {
        $items | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
    }

    Write-Host "Saved encrypted hotspot config to $Path"
}

function Read-HotspotConfig {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path. Run this script with -Setup first."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $data = $raw | ConvertFrom-Json

    if ($null -eq $data) {
        throw "Config file is empty: $Path"
    }

    if ($data -isnot [array]) {
        $data = @($data)
    }

    $hotspots = foreach ($entry in $data) {
        if ([string]::IsNullOrWhiteSpace($entry.Ssid)) {
            throw "A hotspot entry in $Path is missing Ssid."
        }

        if ([string]::IsNullOrWhiteSpace($entry.PasswordSecret)) {
            throw "The hotspot '$($entry.Ssid)' is missing PasswordSecret."
        }

        $securePassword = $entry.PasswordSecret | ConvertTo-SecureString
        $priority = if ($null -ne $entry.Priority) { [int]$entry.Priority } else { 999 }
        $authentication = if ([string]::IsNullOrWhiteSpace($entry.Authentication)) { "WPA2PSK" } else { [string]$entry.Authentication }

        [pscustomobject]@{
            Ssid = [string]$entry.Ssid
            ProfileName = if ([string]::IsNullOrWhiteSpace($entry.ProfileName)) { "Fast iOS Hotspot Connect - $($entry.Ssid)" } else { [string]$entry.ProfileName }
            Password = ConvertTo-PlainText -SecureString $securePassword
            Authentication = $authentication
            Priority = $priority
        }
    }

    $hotspots | Sort-Object Priority, Ssid
}

function Get-WlanInterfaceName {
    $output = & netsh wlan show interfaces 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list Wi-Fi interfaces. netsh said:`n$($output -join [Environment]::NewLine)"
    }

    $match = $output | Select-String -Pattern '^\s*Name\s*:\s*(.+)$' | Select-Object -First 1
    if ($null -eq $match) {
        throw "No Wi-Fi interface was found. Make sure Wi-Fi is enabled."
    }

    $match.Matches[0].Groups[1].Value.Trim()
}

function Get-WlanStatus {
    param([Parameter(Mandatory)][string]$Name)

    $output = & netsh wlan show interfaces 2>&1
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{
            InterfaceName = $Name
            State = "unknown"
            Ssid = $null
        }
    }

    $active = $false
    $state = $null
    $ssid = $null

    foreach ($line in $output) {
        if ($line -match '^\s*Name\s*:\s*(.+)$') {
            $active = ($Matches[1].Trim() -eq $Name)
            continue
        }

        if (-not $active) {
            continue
        }

        if ($line -match '^\s*State\s*:\s*(.+)$') {
            $state = $Matches[1].Trim()
            continue
        }

        if ($line -match '^\s*SSID\s*:\s*(.+)$' -and $line -notmatch '^\s*BSSID\s*:') {
            $ssid = $Matches[1].Trim()
            continue
        }
    }

    [pscustomobject]@{
        InterfaceName = $Name
        State = $state
        Ssid = $ssid
    }
}

function New-WlanProfileXml {
    param(
        [Parameter(Mandatory)][string]$Ssid,
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Authentication
    )

    if ($Password.Length -lt 8 -or $Password.Length -gt 63) {
        throw "The password for '$Ssid' must be 8 to 63 characters for a WPA/WPA2/WPA3 personal hotspot."
    }

    $ssidXml = ConvertTo-XmlText -Text $Ssid
    $profileNameXml = ConvertTo-XmlText -Text $ProfileName
    $passwordXml = ConvertTo-XmlText -Text $Password
    $authXml = ConvertTo-XmlText -Text $Authentication

@"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$profileNameXml</name>
    <SSIDConfig>
        <SSID>
            <name>$ssidXml</name>
        </SSID>
        <nonBroadcast>true</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$authXml</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$passwordXml</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
}

function Get-HotspotProfileName {
    param([Parameter(Mandatory)]$Hotspot)

    if (-not [string]::IsNullOrWhiteSpace($Hotspot.ProfileName)) {
        return [string]$Hotspot.ProfileName
    }

    "Fast iOS Hotspot Connect - $($Hotspot.Ssid)"
}

function Install-WlanProfile {
    param(
        [Parameter(Mandatory)]$Hotspot,
        [Parameter(Mandatory)][string]$Name
    )

    $profileName = Get-HotspotProfileName -Hotspot $Hotspot
    $xml = New-WlanProfileXml -Ssid $Hotspot.Ssid -ProfileName $profileName -Password $Hotspot.Password -Authentication $Hotspot.Authentication
    $tempProfile = Join-Path ([IO.Path]::GetTempPath()) ("wlan-profile-{0}.xml" -f ([guid]::NewGuid()))

    try {
        $xml | Set-Content -LiteralPath $tempProfile -Encoding UTF8
        & netsh wlan delete profile "name=$profileName" "interface=$Name" | Out-Null
        $addOutput = & netsh wlan add profile "filename=$tempProfile" "interface=$Name" user=current 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Could not add WLAN profile '$profileName' for '$($Hotspot.Ssid)'. netsh said:`n$($addOutput -join [Environment]::NewLine)"
        }

        & netsh wlan set profileparameter "name=$profileName" "connectionmode=auto" "nonBroadcast=yes" | Out-Null
        & netsh wlan set profileorder "name=$profileName" "interface=$Name" "priority=$($Hotspot.Priority)" | Out-Null
        Write-Host "Installed hidden-network Wi-Fi profile '$profileName' for '$($Hotspot.Ssid)'"
    }
    finally {
        if (Test-Path -LiteralPath $tempProfile) {
            Remove-Item -LiteralPath $tempProfile -Force
        }
    }
}

function Test-InternetConnection {
    try {
        Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
    }
    catch {
        $false
    }
}

function Connect-Hotspot {
    param(
        [Parameter(Mandatory)]$Hotspot,
        [Parameter(Mandatory)][string]$Name
    )

    Write-Host "Trying '$($Hotspot.Ssid)'..."

    $profileName = Get-HotspotProfileName -Hotspot $Hotspot

    & netsh wlan show networks mode=bssid "interface=$Name" | Out-Null

    if ($DisconnectFirst) {
        & netsh wlan disconnect "interface=$Name" | Out-Null
        Start-Sleep -Seconds 2
    }

    $connectOutput = & netsh wlan connect "name=$profileName" "ssid=$($Hotspot.Ssid)" "interface=$Name" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Windows did not start a connection attempt for '$($Hotspot.Ssid)' using profile '$profileName': $($connectOutput -join ' ')"
        return $false
    }

    $waitUntil = (Get-Date).AddSeconds($ConnectWaitSeconds)

    do {
        Start-Sleep -Seconds 2
        $status = Get-WlanStatus -Name $Name

        if ($status.State -match 'connected' -and $status.Ssid -eq $Hotspot.Ssid) {
            if ($NoInternetCheck -or (Test-InternetConnection)) {
                Write-Host "Connected to '$($Hotspot.Ssid)' on interface '$Name'."
                return $true
            }

            Write-Host "Connected to '$($Hotspot.Ssid)', but internet check failed. Keeping the connection."
            return $true
        }
    } while ((Get-Date) -lt $waitUntil)

    Write-Host "No connection to '$($Hotspot.Ssid)' yet."
    $false
}

if ($Setup) {
    Save-HotspotConfig -Path $ConfigPath -Count $HotspotCount -PriorityOffset $BuiltInHotspots.Count
}

$configuredHotspots = @()
if (Test-Path -LiteralPath $ConfigPath) {
    $configuredHotspots = @(Read-HotspotConfig -Path $ConfigPath)
}
else {
    Write-Host "No extra hotspot config found. Using the hardcoded hotspots only."
}

$builtInSsids = @{}
foreach ($hotspot in $BuiltInHotspots) {
    $builtInSsids[$hotspot.Ssid] = $true
}

$hotspots = @(
    $BuiltInHotspots
    $configuredHotspots | Where-Object { -not $builtInSsids.ContainsKey($_.Ssid) }
) | Sort-Object Priority, Ssid

if ($hotspots.Count -eq 0) {
    throw "No hotspots are configured in $ConfigPath"
}

if ([string]::IsNullOrWhiteSpace($InterfaceName)) {
    $InterfaceName = Get-WlanInterfaceName
}

Write-Host "Using Wi-Fi interface '$InterfaceName'"

foreach ($hotspot in $hotspots) {
    Install-WlanProfile -Hotspot $hotspot -Name $InterfaceName
}

if ($InstallOnly) {
    Write-Host "Profiles installed. Exiting because -InstallOnly was provided."
    exit 0
}

$stopAt = if ($TimeoutSeconds -gt 0) { (Get-Date).AddSeconds($TimeoutSeconds) } else { [DateTime]::MaxValue }

do {
    foreach ($hotspot in $hotspots) {
        if (Connect-Hotspot -Hotspot $hotspot -Name $InterfaceName) {
            exit 0
        }
    }

    if ($Once) {
        break
    }

    if ((Get-Date) -lt $stopAt) {
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
} while ((Get-Date) -lt $stopAt)

throw "Could not connect to any configured hotspot before the timeout."
