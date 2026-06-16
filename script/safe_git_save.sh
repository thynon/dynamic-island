#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 \"Commit message\" <file> [file ...]" >&2
  exit 2
fi

message="$1"
shift

echo "Current status:"
git status --short --branch

echo
echo "Staging only selected files:"
for path in "$@"; do
  echo "  $path"
  git add -- "$path"
done

echo
echo "Staged diff:"
git diff --cached --stat

if git diff --cached --quiet; then
  echo "No staged changes to commit."
  exit 0
fi

git commit -m "$message"
git status --short --branch
