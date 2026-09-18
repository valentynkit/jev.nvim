#!/bin/sh
# One-time recording against a real endpoint. Costs money: about 150 judgments for the
# corpus plus 8 for the failure-mode probes. Everything after this replays for free.
#
#   JEV_UPSTREAM=http://127.0.0.1:4322 ./tools/record.sh
#
# JEV_UPSTREAM defaults to the local gateway shim. Point it at https://api.typesafe.ai
# with TYPESAFE_API_KEY set to record against the direct API instead.
set -e
cd "$(dirname "$0")/.."

: "${JEV_UPSTREAM:=http://127.0.0.1:4322}"
: "${JEV_PROXY_PORT:=4373}"
export JEV_UPSTREAM JEV_PROXY_PORT

JEV_UPSTREAM="$JEV_UPSTREAM" node tools/proxy.js &
PROXY=$!
trap 'kill $PROXY 2>/dev/null' EXIT INT TERM

i=0
while [ $i -lt 60 ]; do
  curl -sf "http://127.0.0.1:$JEV_PROXY_PORT/_stats" >/dev/null && break
  i=$((i + 1))
  sleep 0.1
done

# One request at a time, patient retries, and the proxy skips every sha256 already on
# disk, so rerunning after a rate-limit wall only pays for what is still missing.
export JEV_BASE_URL="http://127.0.0.1:$JEV_PROXY_PORT"
export JEV_CONCURRENCY=1
export JEV_ATTEMPTS=6
export JEV_TIMEOUT_MS=120000
echo "recording through $JEV_BASE_URL -> $JEV_UPSTREAM"
nvim --headless -u tests/minimal.lua -l scripts/measure.lua --write-baseline
nvim --headless -u tests/minimal.lua -l scripts/failure_modes.lua
curl -s "http://127.0.0.1:$JEV_PROXY_PORT/_stats"
echo
