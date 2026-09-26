#!/usr/bin/env bash
# Synthetic fixture by default; guided captures require explicit --evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 0 ] && { [ "$#" -ne 2 ] || [ "$1" != --evidence ]; }; then
  echo 'Usage: test-model-recovery.sh [--evidence DIR]' >&2
  exit 2
fi
python3 "$ROOT/test/verify-recovery-evidence.py" "$@"
