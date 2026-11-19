#!/bin/bash
#=======================================================================
# Install additional WoFS radar Python dependencies on NOAA Ursa.
#
# Usage:
#   ./sorc/install_radar_python.sh
#
# Preserve the validated core WoFS Python package versions.
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

source "$ROOT/versions/bc_prep.ver"

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME
unset PIP_USER PIP_TARGET PIP_PREFIX

PY="$ROOT/python_env/bin/python3"

if [[ ! -x "$PY" ]]; then
    bash "$ROOT/sorc/install_wofs_python.sh"
fi

echo "===== Validate core WoFS Python environment ====="

bash "$ROOT/tests/check_wofs_python.sh" "$PY"

BUILD_DIR="$(mktemp -d "$ROOT/staging/radar_python.XXXXXXXX")"

CONSTRAINTS="$BUILD_DIR/constraints.txt"

echo "===== Preserve core package versions ====="

"$PY" - <<'PYTHON' > "$CONSTRAINTS"
from importlib.metadata import version

packages = [
    "numpy",
    "scipy",
    "PyYAML",
    "packaging",
    "certifi",
    "matplotlib",
    "pandas",
    "pygrib",
    "pyproj",
    "netCDF4",
    "cftime",
    "cartopy",
    "shapely",
    "pyshp",
]

for name in packages:
    print(f"{name}=={version(name)}")
PYTHON

cat "$CONSTRAINTS"

echo "===== Resolve radar dependencies ====="

"$PY" -m pip --isolated install \
    --dry-run \
    --only-binary=:all: \
    --constraint "$CONSTRAINTS" \
    --requirement "$ROOT/sorc/requirements_radar.txt" \
    --report "$BUILD_DIR/install_plan.json" \
    2>&1 | tee "$BUILD_DIR/install_plan.log"

echo "===== Install radar dependencies ====="

"$PY" -m pip --isolated install \
    --only-binary=:all: \
    --constraint "$CONSTRAINTS" \
    --requirement "$ROOT/sorc/requirements_radar.txt" \
    2>&1 | tee "$BUILD_DIR/install.log"

echo "===== Validate core WoFS Python environment ====="

bash "$ROOT/tests/check_wofs_python.sh" "$PY"

echo "===== Validate radar Python imports ====="

"$PY" - <<'PYTHON'
import importlib
import sys

packages = [
    "numpy",
    "scipy",
    "netCDF4",
    "matplotlib",
    "cartopy",
    "pyproj",
    "pandas",
    "xarray",
    "dask",
    "pyart",
    "metpy",
    "mpl_toolkits.basemap",
    "pygeodesy",
    "boto3",
    "s3fs",
    "bs4",
    "future",
    "pint",
    "mesonbuild",
]

failed = []

for name in packages:
    try:
        mod = importlib.import_module(name)
        ver = getattr(mod, "__version__", "available")
        print(f"[PASS] {name:25s} {ver}")
    except Exception as exc:
        print(f"[FAIL] {name:25s} {exc}")
        failed.append(name)

if failed:
    sys.exit(f"Failed imports: {failed}")

print("[PASS] Radar Python dependencies")
PYTHON

"$PY" -m pip freeze --local > "$BUILD_DIR/packages.txt"

echo "============================================"
echo "[PASS] Radar Python installation completed"
echo "Python: $PY"
echo "Report: $BUILD_DIR"
echo "============================================"
