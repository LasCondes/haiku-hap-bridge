# Haiku Swift HAP Bridge

Custom Swift HomeKit bridge that exposes a non-HomeKit Haiku fan to Apple Home.

## What it does
- Runs a local HomeKit Accessory Protocol bridge on macOS.
- Exposes:
  - Fan accessory (on/off + speed)
  - Light accessory (on/off + brightness)
  - Temperature sensor accessory (room temperature)
  - Humidity sensor accessory (relative humidity)
- Translates HomeKit actions into Haiku's local TCP protocol (port 31415).

## Project layout
- `Sources/HaikuHAPBridge/main.swift` — bridge app
- `Config/bridge-config.example.json` — config template
- `Package.swift` — Swift package manifest

## Requirements
- macOS 14+
- Xcode command-line tools (`swift` available)
- Fan reachable on local network

## Build
```bash
cd HaikuHAPBridge
swift build -c release
```

## Configure
```bash
cp Config/bridge-config.example.json Config/bridge-config.json
```

Edit `Config/bridge-config.json`:
- `fanHost` — fan IP (example: `192.168.4.208`)
- `fanPort` — usually `31415`
- `bridgeName` — Home app bridge name
- `fanName` / `lightName` / `temperatureName` / `humidityName` — accessory labels
- `setupCode` — HomeKit setup code (must be valid format and not one of disallowed codes)

## Run
```bash
.build/release/haiku-hap-bridge Config/bridge-config.json
```

Debug telemetry mode:
```bash
.build/release/haiku-hap-bridge Config/bridge-config.json --debug-telemetry
```

When running, it prints:
- bridge name
- setup code
- pairing QR (ASCII)

Add the bridge in Apple Home by scanning the QR.

## Pairing lifecycle
- Pairing state persists in `hap-configuration.json`.
- To force re-pairing, stop bridge and delete `hap-configuration.json`.

## Run as a macOS service (launchd)
Example `~/Library/LaunchAgents/com.andrew.haiku-hap-bridge.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.andrew.haiku-hap-bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>/ABS/PATH/HaikuHAPBridge/.build/release/haiku-hap-bridge</string>
    <string>/ABS/PATH/HaikuHAPBridge/Config/bridge-config.json</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/ABS/PATH/HaikuHAPBridge</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/haiku-hap-bridge.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/haiku-hap-bridge.err.log</string>
</dict>
</plist>
```

Load/unload:
```bash
launchctl load ~/Library/LaunchAgents/com.andrew.haiku-hap-bridge.plist
launchctl unload ~/Library/LaunchAgents/com.andrew.haiku-hap-bridge.plist
```

## Notes
- This bridge uses the fan's local binary TCP protocol and periodic polling.
- Temperature and humidity are parsed from live telemetry fields.
- If fan IP changes, update `fanHost`.
