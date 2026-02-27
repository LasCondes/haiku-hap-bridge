# Troubleshooting

## Bridge starts but no accessories appear in Home
- Confirm the bridge process is running.
- Confirm `setupCode` is valid and not a blocked default code.
- Delete `hap-configuration.json` and re-pair if needed.

## Fan unreachable / status refresh errors
- Verify `fanHost` and `fanPort` in config.
- Confirm fan is on same LAN and reachable from Mac.
- Test connectivity:
  - `nc -vz <fanHost> <fanPort>`

## Temperature/Humidity show n/a
- Run with `--debug-telemetry`.
- Confirm telemetry lines include temp/humidity values.
- If missing, fan firmware may expose different field layouts.

## Auto/Whoosh/Eco switch does nothing
- Watch debug telemetry while toggling in Home app.
- Verify mode state updates in output.
- Some fan firmware versions may gate modes by current state.

## Home app stale values
- Restart bridge process.
- Re-open Home app.
- If still stale, unpair and re-pair bridge.
