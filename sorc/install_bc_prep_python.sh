#!/bin/bash
#
# Compatibility entry point for the shared WoFS Python installer.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

exec bash "$ROOT/sorc/install_wofs_python.sh" "$@"
