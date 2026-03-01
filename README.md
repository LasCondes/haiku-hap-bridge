# Haiku Swift HAP Bridge

Custom Swift HomeKit bridge for Big Ass Fans (BAF) Haiku H/I Series ceiling fans. Exposes fan, light, temperature, and mode controls to Apple Home via the HomeKit Accessory Protocol.

## What it does
- Runs a local HAP bridge on macOS, appearing as a native HomeKit bridge.
- Communicates with Haiku fans using their local protobuf-over-TCP protocol (port 31415, SLIP framing).
- Exposes per-fan accessories:
  - **Fan** (on/off + speed 0-7 mapped to 0-100%)
  - **Light** (on/off + brightness 0-100%)
  - **Temperature sensor** (built-in sensor, hundredths °C)
  - **Mode switches** (Auto / Whoosh / Eco)
- Queries each fan at startup for real model name and firmware version, displayed in Apple Home accessory details.
- Generates a deterministic bridge identifier from the Mac's hardware UUID so the bridge identity is stable across restarts.

## Project layout
- `Sources/HaikuHAPBridge/main.swift` — bridge app
- `Config/bridge-config.example.json` — config template
- `Package.swift` — Swift package manifest
- `docs/TROUBLESHOOTING.md` — troubleshooting guide

## Requirements
- macOS 14+
- Xcode command-line tools (`swift` available)
- Haiku fan(s) reachable on local network (protobuf firmware, not legacy SenseME text protocol)

## Build
```bash
swift build -c release
```

## Configure
```bash
cp Config/bridge-config.example.json Config/bridge-config.json
```

Edit `Config/bridge-config.json`:
- `bridgeName` — Home app bridge name
- `setupCode` — HomeKit setup code (must be valid format and not one of disallowed codes)
- `fans` — array of fan entries
  - `name` — base accessory label
  - `fanHost` — fan IP (example: `192.168.4.208`)
  - `fanPort` — usually `31415`
  - optional: `lightName`, `temperatureName`

Or use auto-discovery to generate a config:
```bash
.build/release/haiku-hap-bridge --discover
```

## Run
```bash
.build/release/haiku-hap-bridge Config/bridge-config.json
```

Debug telemetry mode (prints fan state every 8 seconds):
```bash
.build/release/haiku-hap-bridge Config/bridge-config.json --debug-telemetry
```

One-shot device info mode (prints make/model/software/firmware/temperature for each configured fan and exits):
```bash
.build/release/haiku-hap-bridge Config/bridge-config.json --print-device-info
```

When running, the bridge prints its name, setup code, and a pairing QR code. Add the bridge in Apple Home by scanning the QR or entering the setup code manually.

## Pairing lifecycle
- Pairing state persists in `hap-configuration.json` (auto-generated on first run).
- The bridge identifier is derived from the Mac's hardware UUID for consistency across restarts.
- To force re-pairing, stop the bridge, delete `hap-configuration.json`, and remove the bridge from Apple Home.

## Protocol details

The bridge speaks the BAF protobuf protocol, not the older SenseME text protocol. Key details:

- **Transport**: TCP port 31415 with SLIP framing (0xC0 delimiters)
- **Query**: `Root { root2(F2) { query(F3) {} } }` = `[0x12, 0x02, 0x1a, 0x00]`
- **Command**: `Root { root2(F2) { commit(F2) { properties(F3) { field=val } } } }` = prefix `[0x12, 0x07, 0x12, 0x05, 0x1a, 0x03]` + 3-byte field payload
- **Key fields**: F43 fan_mode, F45 speed_percent, F46 speed_level, F58 whoosh, F65 eco, F68 light_mode, F69 light_brightness, F86 temperature, F87 humidity

Reference implementations: [aiobafi6](https://github.com/jfroy/aiobafi6) (Python), [homebridge-i6-bigAssFans](https://github.com/oogje/homebridge-i6-bigAssFans) (TypeScript)

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
    <string>/ABS/PATH/haiku-hap-bridge/.build/release/haiku-hap-bridge</string>
    <string>/ABS/PATH/haiku-hap-bridge/Config/bridge-config.json</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/ABS/PATH/haiku-hap-bridge</string>
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
- Humidity sensors were removed — Haiku H/I Series fans report a sentinel value (100000) indicating no humidity sensor hardware.
- The Bouke/HAP library ships with `pv=1.0` in its mDNS TXT record. This bridge patches it to `pv=1.1` for compatibility with modern HomeKit (iOS 16.2+). Without this fix, Apple Home shows "No Response" after pairing.
- Temperature and humidity are parsed from live protobuf telemetry fields.
- If fan IP changes, update `fanHost` in the config.
