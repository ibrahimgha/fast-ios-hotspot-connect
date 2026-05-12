# Fast iOS Hotspot Connect

Windows PowerShell helper for connecting to known iPhone Personal Hotspots,
including hidden SSIDs that do not appear in the normal Wi-Fi list.

These hotspots are hardcoded in `Connect-iPhoneHotspot.ps1`:

- SSID: `Ibrahim`
- Authentication: `WPA2PSK`
- SSID: `Ibrahim 012`
- Authentication: `WPA2PSK`

## Run

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\ibrah\one-time-tasks\Connect-iPhoneHotspot.ps1 -TimeoutSeconds 0 -DisconnectFirst
```

## Add another optional hotspot

```powershell
cd C:\Users\ibrah\one-time-tasks
powershell -ExecutionPolicy Bypass -File .\Connect-iPhoneHotspot.ps1 -Setup
```

This keeps the hardcoded hotspots as priorities 1 and 2, then prompts for one
additional SSID and password.

## iOS limitation

This script can tell Windows to connect to a known hidden SSID by creating WLAN
profiles with `nonBroadcast` enabled. It cannot force iOS to wake the hotspot if
the iPhone has fully stopped advertising it over Wi-Fi.
