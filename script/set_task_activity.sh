#!/usr/bin/env bash
set -euo pipefail

STATE="${1:-}"
STATE_FILE="${HOME}/Library/Application Support/Island/task-activity-state.txt"

case "$STATE" in
  idle|thinking|running|compacting|warning|error)
    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$STATE" >"$STATE_FILE"
    echo "Island task activity: $STATE"
    ;;
  *)
    echo "usage: $0 idle|thinking|running|compacting|warning|error" >&2
    exit 2
    ;;
esac
