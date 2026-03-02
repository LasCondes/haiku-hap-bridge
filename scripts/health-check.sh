#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${HAP_BRIDGE_LABEL:-com.andrew.haiku-hap-bridge}"
BIN="${HAP_BRIDGE_BIN:-$ROOT_DIR/.build/release/haiku-hap-bridge}"
CONFIG="${1:-${HAP_BRIDGE_CONFIG:-$ROOT_DIR/Config/bridge-config.json}}"
OUT_LOG="${HAP_BRIDGE_OUT_LOG:-/tmp/haiku-hap-bridge.out.log}"
ERR_LOG="${HAP_BRIDGE_ERR_LOG:-/tmp/haiku-hap-bridge.err.log}"
LAUNCH_DOMAIN="gui/$(id -u)"

EXIT_CODE=0

ok() {
  echo "[OK] $*"
}

warn() {
  echo "[WARN] $*"
}

fail() {
  echo "[FAIL] $*"
  EXIT_CODE=1
}

echo "Haiku HAP Bridge health check"
echo "Label:  $LABEL"
echo "Binary: $BIN"
echo "Config: $CONFIG"
echo ""

if [[ -x "$BIN" ]]; then
  ok "Release binary exists and is executable."
else
  fail "Release binary missing or not executable: $BIN"
fi

if [[ -f "$CONFIG" ]]; then
  ok "Config file exists."
else
  fail "Config file not found: $CONFIG"
fi

if service_info="$(launchctl print "$LAUNCH_DOMAIN/$LABEL" 2>/dev/null)"; then
  if echo "$service_info" | grep -q "state = running"; then
    ok "LaunchAgent is running."
  else
    fail "LaunchAgent is loaded but not running."
  fi
else
  fail "LaunchAgent not found in launchd domain ($LAUNCH_DOMAIN)."
fi

if [[ -f "$OUT_LOG" ]]; then
  ok "stdout log present: $OUT_LOG"
else
  warn "stdout log not found: $OUT_LOG"
fi

if [[ -f "$ERR_LOG" ]]; then
  if tail -n 50 "$ERR_LOG" | grep -q "Status refresh error"; then
    warn "Recent status refresh errors found in stderr log."
  else
    ok "No recent status refresh errors in stderr log."
  fi
else
  warn "stderr log not found: $ERR_LOG"
fi

if [[ -x "$BIN" && -f "$CONFIG" ]]; then
  probe_output="$("$BIN" "$CONFIG" --print-device-info 2>&1 || true)"
  expected_fans="$(grep -c '"fanHost"' "$CONFIG" || true)"
  observed_fans="$(echo "$probe_output" | grep -c '^\[' || true)"

  if [[ "$observed_fans" -gt 0 ]]; then
    ok "Device info probe returned $observed_fans fan block(s)."
  else
    fail "Device info probe returned no fan data."
  fi

  if [[ "$expected_fans" -gt 0 && "$observed_fans" -lt "$expected_fans" ]]; then
    fail "Probe saw fewer fans than config ($observed_fans/$expected_fans)."
  fi

  if echo "$probe_output" | grep -q "make=n/a"; then
    warn "Probe returned partial metadata (make/model/firmware unavailable for some fans)."
  fi
fi

echo ""
if [[ "$EXIT_CODE" -eq 0 ]]; then
  ok "Health check passed."
else
  fail "Health check failed."
fi

exit "$EXIT_CODE"
