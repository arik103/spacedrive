#!/usr/bin/env bash
# Add a Spacedrive library location via RPC (browser dev stack on :8080).
# Usage: ./scripts/aitkis-add-location.sh <absolute-path> [display-name]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATH_ARG="${1:?Usage: $0 <absolute-path> [display-name]}"
NAME="${2:-$(basename "$PATH_ARG")}"

if ! curl -sf --max-time 2 http://localhost:8080/health >/dev/null; then
	echo "✗ sd-server not running — start with: ./scripts/aitkis-dev-browser.sh start" >&2
	exit 1
fi

LIB=$(curl -sf -X POST http://localhost:8080/rpc \
	-H 'Content-Type: application/json' \
	-d '{"Query":{"method":"query:libraries.list","library_id":null,"payload":{"include_stats":false}}}' \
	| python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('JsonOk') or d.get('json'); print(r[0]['id'])")

DEVICE=$(curl -sf -X POST http://localhost:8080/rpc \
	-H 'Content-Type: application/json' \
	-d "{\"Query\":{\"method\":\"query:devices.list\",\"library_id\":\"$LIB\",\"payload\":{\"include_offline\":true,\"include_details\":false}}}" \
	| python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('JsonOk') or d.get('json'); print(r[0]['slug'])")

PAYLOAD=$(python3 -c "import json; print(json.dumps({
  'path': {'Physical': {'device_slug': '$DEVICE', 'path': '$PATH_ARG'}},
  'name': '$NAME',
  'mode': 'Shallow',
  'job_policies': None,
}))")

RESP=$(curl -sf -X POST http://localhost:8080/rpc \
	-H 'Content-Type: application/json' \
	-d "{\"Action\":{\"method\":\"action:locations.add.input\",\"library_id\":\"$LIB\",\"payload\":$PAYLOAD}}")

if echo "$RESP" | grep -q '"JsonOk"'; then
	echo "✓ Added location: $NAME → $PATH_ARG"
	echo "$RESP" | python3 -m json.tool
else
	echo "✗ Failed to add location" >&2
	echo "$RESP" | python3 -m json.tool >&2
	if echo "$RESP" | grep -q 'Path not accessible'; then
		echo >&2
		echo "macOS blocked read access. Grant Full Disk Access to Cursor (or Terminal)," >&2
		echo "restart the dev stack, then re-run this script." >&2
		open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
	fi
	exit 1
fi
