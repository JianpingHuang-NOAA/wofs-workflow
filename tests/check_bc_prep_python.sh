#!/bin/bash
#
# Compatibility entry point for the shared WoFS Python validator.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

exec bash "$ROOT/tests/check_wofs_python.sh" "$@"
