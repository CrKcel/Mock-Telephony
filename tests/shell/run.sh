#!/usr/bin/env bash
# Runs all shell behavioral test suites.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failures=0
for suite in "$DIR"/test-*.sh; do
  echo "== $(basename "$suite") =="
  if ! bash "$suite"; then
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "shell test suites failed: $failures" >&2
  exit 1
fi
echo "all shell test suites passed"
