# iPhone Hotspot Connector

This folder contains `Connect-iPhoneHotspot.ps1`, a Windows PowerShell script
that installs hidden Wi-Fi profiles for your iPhone hotspots and repeatedly
tries to connect to them.

These hotspots are hardcoded:

- SSID: `Ibrahim`
- Authentication: `WPA2PSK`
- SSID: `Ibrahim 012`
- Authentication: `WPA2PSK`

## First-time setup

The script can run immediately with the hardcoded hotspots. To add or replace
one extra hotspot, run this from PowerShell:

```powershell
cd C:\Users\ibrah\one-time-tasks
powershell -ExecutionPolicy Bypass -File .\Connect-iPhoneHotspot.ps1 -Setup
```

It will keep using the hardcoded `Ibrahim` and `Ibrahim 012` hotspots first,
then ask for one additional SSID and password. The additional password is saved
in `hotspots.secure.json` using Windows user-level encryption, so that extra
password is not stored as plain text.

## Normal use

Try for five minutes:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\ibrah\one-time-tasks\Connect-iPhoneHotspot.ps1
```

Keep trying forever:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\ibrah\one-time-tasks\Connect-iPhoneHotspot.ps1 -TimeoutSeconds 0
```

More aggressive mode, useful when Windows keeps clinging to another Wi-Fi
network:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\ibrah\one-time-tasks\Connect-iPhoneHotspot.ps1 -TimeoutSeconds 0 -DisconnectFirst
```

## Ctrl+0 hotkey

Install and start the background listener:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\ibrah\one-time-tasks\Install-HotspotHotkey.ps1
```

Press `Ctrl+0` to run the connector. Success is silent. Failure shows a Windows
system message box with the reason.

## What this can and cannot do

This script can tell Windows to connect to a known hidden SSID by creating WLAN
profiles with `nonBroadcast` enabled. That is the Windows equivalent of
"connect even if this network is not broadcasting."

It cannot force iOS to wake the hotspot if the iPhone has fully stopped
advertising it over Wi-Fi. In that case, the reliable options are:

- briefly open the iPhone Personal Hotspot settings page,
- use USB tethering,
- use Bluetooth tethering,
- keep both devices in the same Apple ecosystem and use Apple's Instant Hotspot
  features where supported.

If connection attempts fail with authentication or security errors, turn on
Personal Hotspot's "Maximize Compatibility" option on the iPhone and rerun
setup with the default `WPA2PSK` authentication.
