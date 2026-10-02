#!/usr/bin/env bash
# Shows devices registered in the Device Farm hub and the session queue.
set -euo pipefail

HUB_URL="${HUB_URL:-http://localhost:4723}"

curl -fsS "${HUB_URL}/status" >/dev/null || { echo "Hub ${HUB_URL} unavailable" >&2; exit 1; }

curl -fsS "${HUB_URL}/device-farm/api/device" | python3 -c '
import json, sys

devices = json.load(sys.stdin)
if not devices:
    print("No devices registered.")
    sys.exit(0)

row = "{:<9} {:<10} {:<30} {:<26} {:<7} {:<8} {}"
print(row.format("PLATFORM", "TYPE", "UDID", "NAME", "VERSION", "STATUS", "HOST"))
for d in devices:
    status = "offline" if d.get("offline") else ("busy" if d.get("busy") else "free")
    version = d.get("sdk") or d.get("platformVersion") or ""
    print(row.format(d.get("platform", ""), d.get("deviceType", ""), d.get("udid", "")[:30],
                     str(d.get("name", ""))[:26], str(version), status, d.get("host", "")))
'
echo
echo "Queued sessions: $(curl -fsS "${HUB_URL}/device-farm/api/queue/length" 2>/dev/null || echo '?')"
echo "Dashboard: ${HUB_URL}/device-farm"
