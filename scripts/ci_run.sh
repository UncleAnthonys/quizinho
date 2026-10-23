#!/usr/bin/env bash
# Runs a command; if it fails, re-publishes the tail of its output as a GitHub
# annotation (readable via the API even where raw logs aren't), then fails.
#   bash scripts/ci_run.sh "Analyze" flutter analyze --no-fatal-infos
set -uo pipefail
label="$1"; shift
out="$(mktemp)"
"$@" 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  # keep only the useful lines (errors/warnings + context), max ~150 lines
  body="$(grep -E "error|Error|warning|•|\.dart:[0-9]+|Exception|Expected|FAILED|failed" "$out" | head -150)"
  [ -z "$body" ] && body="$(tail -80 "$out")"
  body="${body//'%'/'%25'}"; body="${body//$'\r'/'%0D'}"; body="${body//$'\n'/'%0A'}"
  echo "::error title=$label failed::$body"
fi
exit "$status"
