# Troubleshooting

## "No Response" in Apple Home

This is most commonly caused by the HAP protocol version mismatch. The Bouke/HAP library advertises `pv=1.0` by default, but modern HomeKit (iOS 16.2+) requires `pv=1.1` for software-authenticated accessories.

**Symptoms**: Bridge pairs successfully, but all accessories show "No Response". The HomeKit controller connects (pair-verify completes, GET /accessories returns 200) but never sends PUT/GET /characteristics requests.

**Fix**: This bridge patches `pv=1.0` to `pv=1.1` in `.build/checkouts/HAP/Sources/HAP/Server/Device.swift`. If you rebuild from a clean checkout, verify the patch is applied.

**Verify with mDNS**:
```bash
dns-sd -Z _hap._tcp local.
```
The TXT record should show `pv=1.1`, not `pv=1.0`.

Other causes:
- Multiple bridge processes running (check `pgrep -fl haiku-hap-bridge`).
- Stale `hap-configuration.json` — stop bridge, delete the file, remove bridge from Home, and re-pair.

## Bridge starts but no accessories appear in Home
- Confirm the bridge process is running.
- Confirm `setupCode` is valid and not a blocked default code.
- Delete `hap-configuration.json` and re-pair if needed.

## Fan unreachable / status refresh errors
- Verify `fanHost` and `fanPort` in config.
- Confirm fan is on same LAN and reachable from Mac.
- Test connectivity: `nc -vz <fanHost> <fanPort>`
- These fans speak protobuf, not the older SenseME text protocol. If your fan uses the text protocol, this bridge won't work.

## Temperature shows n/a
- Run with `--debug-telemetry`.
- Confirm telemetry lines include `temp=` values.
- If missing, fan firmware may expose different field layouts.

## Humidity shows n/a
- This is expected. Haiku H/I Series fans report F87=100000, a sentinel value meaning "no humidity sensor". The bridge no longer exposes humidity accessories.

## Auto/Whoosh/Eco switch does nothing
- Watch debug telemetry while toggling in Home app.
- Verify mode state updates in output.
- Some fan firmware versions may gate modes by current state.

## Home app shows stale values
- Restart bridge process.
- Re-open Home app.
- If still stale, remove and re-add the bridge from Home.

## Model/firmware shows "unknown" in Home
- The bridge queries each fan at startup for device info. Check the startup log for lines like `[Fan Name] model=... firmware=...`.
- If the query fails (fan unreachable at startup), defaults are used.
- After updating, you may need to remove and re-add the bridge for Apple Home to refresh cached accessory metadata.
