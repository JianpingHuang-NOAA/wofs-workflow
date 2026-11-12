#!/bin/bash
#
# Install the WoFS v1.0 BC_PREP Python runtime on NOAA Ursa.
#
# Usage:
#   install_bc_prep_python.sh /absolute/path/to/new/venv
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Require an explicit installation directory.
if [[ "$#" -ne 1 || "$1" != /* || "$1" == / ]]; then
    echo "Usage: $0 /absolute/path/to/new/venv" >&2
    exit 1
fi

if [[ -e "$1" || -L "$1" ]]; then
    echo "[ERROR] Installation path already exists: $1" >&2
    exit 1
fi

VENV="$(realpath -m -- "$1")"

if [[ "$VENV" == / || -e "$VENV" || -L "$VENV" ]]; then
    echo "[ERROR] Invalid installation path: $VENV" >&2
    exit 1
fi

source "$ROOT/versions/bc_prep.ver"

# Initialize the validated BC_PREP module environment.
module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

# Prevent hidden personal Python dependencies.
export PYTHONNOUSERSITE=1

unset PYTHONPATH
unset PYTHONHOME

# Do not install packages into a personal user site.
unset PIP_USER
unset PIP_TARGET
unset PIP_PREFIX

BASE_PYTHON="$(command -v python3)"

echo "=================================================="
echo "WoFS BC_PREP Python installation"
echo "=================================================="
echo "Repository  : $ROOT"
echo "Base Python : $BASE_PYTHON"
echo "Environment : $VENV"

echo
echo "===== Loaded modules ====="

module list

echo
echo "===== Validate NOAA base Python ====="

"$BASE_PYTHON" - <<'PYTHON'
import os
import sys
import site
import importlib
import importlib.metadata
from pathlib import Path

expected = os.environ["python_patch_ver"]
actual = ".".join(map(str, sys.version_info[:3]))

if actual != expected:
    sys.exit(f"[ERROR] Python {actual}; expected {expected}")

if sys.prefix != sys.base_prefix:
    sys.exit("[ERROR] Base Python is already a virtual environment")

if site.ENABLE_USER_SITE is not False:
    sys.exit("[ERROR] Personal user-site packages are enabled")

print(f"[PASS] Python: {actual}")
print("[PASS] Personal user-site packages disabled")

base_root = Path(sys.base_prefix).resolve()

packages = [
    ("yaml", "PyYAML", "pyyaml_ver"),
    ("numpy", "numpy", "numpy_ver"),
    ("scipy", "scipy", "scipy_ver"),
    ("packaging", "packaging", "packaging_ver"),
    ("certifi", "certifi", "certifi_ver"),
]

for name, dist, key in packages:
    mod = importlib.import_module(name)

    actual = importlib.metadata.version(dist)
    expected = os.environ[key]

    if actual != expected:
        sys.exit(
            f"[ERROR] {name}: {actual}; expected {expected}"
        )

    location = Path(mod.__file__).resolve()

    if not location.is_relative_to(base_root):
        sys.exit(
            f"[ERROR] Unexpected package location: {location}"
        )

    print(f"[PASS] {name}: {actual}")
    print(f"       {location}")
PYTHON

echo
echo "===== Create WoFS virtual environment ====="

"$BASE_PYTHON" -m venv \
    --system-site-packages \
    "$VENV"

PY="$VENV/bin/python3"

[[ -x "$PY" ]]

echo
echo "===== Install pinned Python packages ====="

"$PY" -m pip --isolated install \
    --only-binary=:all: \
    --no-deps \
    --ignore-installed \
    -r "$ROOT/sorc/requirements_bc_prep.txt"

echo
echo "===== Validate installed environment ====="

bash "$ROOT/tests/check_bc_prep_python.sh" "$PY"

echo
echo "===== Locally installed packages ====="

"$PY" -m pip freeze --local

echo
echo "=================================================="
echo "[PASS] WoFS BC_PREP Python installation completed"
echo "VENV=$VENV"
echo
echo "Configure the workflow using:"
printf 'export WOFS_PYTHON=%q\n' "$PY"
echo "export PYTHONNOUSERSITE=1"
echo "unset PYTHONPATH"
echo "unset PYTHONHOME"
echo "=================================================="
