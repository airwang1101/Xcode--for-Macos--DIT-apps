#!/usr/bin/env bash
set -euo pipefail

DIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DIT_SCRIPT_DIR/release.py" "$@"
