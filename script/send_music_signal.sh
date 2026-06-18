#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ISLAND_DEBUG_MUSIC_SIGNAL_FILE:-}" ]]; then
  echo "Set ISLAND_DEBUG_MUSIC_SIGNAL_FILE to the debug signal JSON path." >&2
  exit 2
fi

command="${1:-playing}"
progress="${2:-0}"
title="${3:-Debug Track}"
artist="${4:-Signal Preview}"
tmp_file="$(mktemp "${ISLAND_DEBUG_MUSIC_SIGNAL_FILE}.XXXXXX")"

case "$command" in
  idle)
    cat >"$tmp_file" <<JSON
{"isPlaying":false,"title":"","artist":"","direction":null,"progress":0}
JSON
    ;;
  playing)
    cat >"$tmp_file" <<JSON
{"isPlaying":true,"title":"$title","artist":"$artist","direction":null,"progress":0}
JSON
    ;;
  next|previous)
    cat >"$tmp_file" <<JSON
{"isPlaying":true,"title":"$title","artist":"$artist","direction":"$command","progress":$progress}
JSON
    ;;
  clear)
    cat >"$tmp_file" <<JSON
{"isPlaying":true,"title":"$title","artist":"$artist","direction":null,"progress":0}
JSON
    ;;
  *)
    echo "Usage: $0 idle|playing|next <progress>|previous <progress>|clear [title] [artist]" >&2
    rm -f "$tmp_file"
    exit 2
    ;;
esac

mv "$tmp_file" "$ISLAND_DEBUG_MUSIC_SIGNAL_FILE"
