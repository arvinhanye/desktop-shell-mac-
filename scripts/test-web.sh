#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' '需要 Node.js（brew install node）' >&2
  exit 1
fi
exec node --test "Tests/web/**/*.test.mjs"
