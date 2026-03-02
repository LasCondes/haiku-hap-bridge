#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${HAP_BRIDGE_BIN:-$ROOT_DIR/.build/release/haiku-hap-bridge}"
CONFIG="${HAP_BRIDGE_CONFIG:-$ROOT_DIR/Config/bridge-config.json}"
LABEL="${HAP_BRIDGE_LABEL:-com.andrew.haiku-hap-bridge}"
TMP_DISC="$(mktemp "${TMPDIR:-/tmp}/haiku-discover.XXXXXX.json")"
TMP_MERGED="$(mktemp "${TMPDIR:-/tmp}/haiku-merged.XXXXXX.json")"
TS="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="$ROOT_DIR/Config/backups"
BACKUP_FILE="$BACKUP_DIR/bridge-config.$TS.json"

cleanup() {
  rm -f "$TMP_DISC" "$TMP_MERGED"
}
trap cleanup EXIT

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ ! -x "$BIN" ]]; then
  log "[recover] release binary missing: $BIN"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  log "[recover] config missing: $CONFIG"
  exit 1
fi

if ! "$BIN" --discover > "$TMP_DISC"; then
  log "[recover] discovery failed; leaving current config unchanged."
  exit 0
fi

set +e
merge_output="$(
python3 - "$CONFIG" "$TMP_DISC" "$TMP_MERGED" <<'PY'
import json
import re
import sys

config_path, discover_path, merged_path = sys.argv[1:4]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)
with open(discover_path, "r", encoding="utf-8") as f:
    discovered = json.load(f)

cfg_fans = list(config.get("fans", []))
disc_fans = list(discovered.get("fans", []))

if not cfg_fans:
    print("ERROR: current config has no fans")
    sys.exit(2)
if not disc_fans:
    print("NO_DISCOVERY")
    sys.exit(10)

def normalize(name: str) -> str:
    if not isinstance(name, str):
        return ""
    name = name.strip()
    name = re.sub(r"\s+[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$", "", name)
    return name.casefold()

name_to_indices = {}
for idx, fan in enumerate(disc_fans):
    name_to_indices.setdefault(normalize(fan.get("name", "")), []).append(idx)

used = set()
updated_fans = []
changes = []

for idx, existing in enumerate(cfg_fans):
    match_idx = None

    key = normalize(existing.get("name", ""))
    if key in name_to_indices:
        while name_to_indices[key]:
            cand_idx = name_to_indices[key].pop(0)
            if cand_idx not in used:
                match_idx = cand_idx
                break

    if match_idx is None:
        for cand_idx, cand in enumerate(disc_fans):
            if cand_idx in used:
                continue
            if cand.get("fanHost") == existing.get("fanHost"):
                match_idx = cand_idx
                break

    if match_idx is None and len(cfg_fans) == len(disc_fans) and idx < len(disc_fans) and idx not in used:
        match_idx = idx

    if match_idx is None:
        updated_fans.append(existing)
        continue

    used.add(match_idx)
    discovered_fan = disc_fans[match_idx]
    merged = dict(existing)
    new_host = discovered_fan.get("fanHost", merged.get("fanHost"))
    new_port = discovered_fan.get("fanPort", merged.get("fanPort"))

    if merged.get("fanHost") != new_host or merged.get("fanPort") != new_port:
        changes.append(
            f"{existing.get('name', '<unnamed>')}: {merged.get('fanHost')}:{merged.get('fanPort')} -> {new_host}:{new_port}"
        )
    merged["fanHost"] = new_host
    merged["fanPort"] = new_port
    updated_fans.append(merged)

config["fans"] = updated_fans

with open(merged_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")

if changes:
    print("CHANGED")
    for line in changes:
        print(line)
else:
    print("UNCHANGED")
PY
)"
merge_status=$?
set -e

if [[ $merge_status -eq 10 ]]; then
  log "[recover] discovery returned no fans; skipping update."
  exit 0
fi
if [[ $merge_status -ne 0 ]]; then
  log "[recover] merge failed."
  echo "$merge_output"
  exit 1
fi

if [[ "$merge_output" == UNCHANGED* ]]; then
  log "[recover] no IP/port changes detected."
  exit 0
fi

if [[ "$merge_output" != CHANGED* ]]; then
  log "[recover] unexpected merge output; skipping update."
  echo "$merge_output"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp "$CONFIG" "$BACKUP_FILE"
mv "$TMP_MERGED" "$CONFIG"

log "[recover] updated config with discovered fan addresses."
while IFS= read -r line; do
  [[ "$line" == "CHANGED" || -z "$line" ]] && continue
  log "[recover] $line"
done <<< "$merge_output"

launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
log "[recover] restarted $LABEL"
