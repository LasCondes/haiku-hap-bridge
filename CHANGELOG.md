# Changelog

## 2025-02-28 — Protocol rewrite and HomeKit fix

### Fixed
- **"No Response" in Apple Home**: Patched HAP library `pv=1.0` to `pv=1.1` in mDNS TXT record. Modern HomeKit (iOS 16.2+) requires protocol version 1.1 for software-authenticated accessories.
- **Fan communication**: Rewrote `requestFrames()` to use the correct protobuf query path (`F2.F3` = `[0x12, 0x02, 0x1a, 0x00]`). The old code wrapped queries in the commit path, which fans silently ignored.
- **Speed reading**: Use F45 (speed_percent, 0-100) instead of F46 (speed_level, 0-7) for accurate speed reporting.
- **Model detection**: Avoid recursing into F16 firmware sub-messages, which caused firmware version strings to be misidentified as the model name.
- **Int overflow crash (exit code 133)**: Use `Int(truncatingIfNeeded:)` for UInt64 varints that exceed Int.max (e.g., location offset fields).
- **stdout buffering**: Added `setbuf(stdout, nil)` so log output appears immediately when redirected to a file.
- **Main loop**: Replaced `DispatchSemaphore.wait()` with `dispatchMain()` so the main dispatch queue stays active for NetService/mDNS callbacks and signal handling.

### Added
- **Dynamic device info**: Queries each fan at startup for real model name and firmware version, used in HomeKit accessory info.
- **Deterministic bridge identifier**: Derived from the Mac's hardware UUID via `ioreg`, so the bridge identity is stable across restarts and re-builds.
- **Manufacturer/model/firmware in Apple Home**: Accessories show "Big Ass Fans", actual model name, and firmware version in Home app details.

### Changed
- **Removed humidity accessories**: Haiku H/I Series fans report F87=100000 (sentinel for no sensor). Humidity accessories were removed from the bridge.
- **Socket timeouts**: Increased receive timeout from 200ms to 500ms and read deadline from 1.2s to 2.0s for more reliable fan communication.
- **Light commands**: Simplified to use F68 (light_mode) and F69 (light_brightness) directly, removed F82 target selection.

## Initial
- Added direct Haiku TCP transport (replacing HTTP placeholder).
- Added HomeKit temperature sensor from telemetry.
- Added HomeKit humidity sensor from telemetry.
- Added debug telemetry mode (`--debug-telemetry`).
- Added Auto/Whoosh/Eco mode control via HomeKit switch accessories.
- Added best-effort make/model/software/firmware extraction from telemetry.
- Added `--print-device-info` one-shot mode.
- Added `--discover` auto-discovery mode for multi-fan config.
- Expanded README and added troubleshooting guide.
