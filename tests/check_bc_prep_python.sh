#!/bin/bash
#
# Validate the WoFS v1.0 BC_PREP Python runtime.
#
# Usage:
#   check_bc_prep_python.sh /path/to/venv/bin/python3
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "$ROOT/versions/bc_prep.ver"

PY="${1:-${WOFS_PYTHON:-}}"

if [[ -z "$PY" || ! -x "$PY" ]]; then
    echo "[ERROR] Specify a valid Python interpreter" >&2
    exit 1
fi

export PYTHONNOUSERSITE=1

unset PYTHONPATH
unset PYTHONHOME

echo "===== WoFS BC_PREP Python validation ====="

"$PY" - "$ROOT/sorc/requirements_bc_prep.txt" <<'PYTHON'
import os
import sys
import site
import importlib
import importlib.metadata
from pathlib import Path

failed = []

def check(label, actual, expected):
    if str(actual) == str(expected):
        print(f"[PASS] {label}: {actual}")
    else:
        print(f"[FAIL] {label}: {actual}; expected {expected}")
        failed.append(label)

def check_condition(label, condition):
    if condition:
        print(f"[PASS] {label}")
    else:
        print(f"[FAIL] {label}")
        failed.append(label)

check(
    "Python",
    ".".join(map(str, sys.version_info[:3])),
    os.environ["python_patch_ver"],
)

check_condition(
    "Virtual environment active",
    sys.prefix != sys.base_prefix,
)

check_condition(
    "Personal user-site packages disabled",
    site.ENABLE_USER_SITE is False,
)

print("Interpreter:", sys.executable)
print("Virtual environment:", sys.prefix)
print("Base Python:", sys.base_prefix)

venv_root = Path(sys.prefix).resolve()
base_root = Path(sys.base_prefix).resolve()

packages = [
    ("yaml", "PyYAML", "pyyaml_ver", False),
    ("numpy", "numpy", "numpy_ver", False),
    ("scipy", "scipy", "scipy_ver", False),
    ("packaging", "packaging", "packaging_ver", False),
    ("certifi", "certifi", "certifi_ver", False),
    ("netCDF4", "netCDF4", "netcdf4_python_ver", True),
    ("cftime", "cftime", "cftime_ver", True),
    ("pyproj", "pyproj", "pyproj_ver", True),
    ("pygrib", "pygrib", "pygrib_ver", True),
]

print()
print("===== Python package validation =====")

for name, dist, version_var, local_required in packages:
    try:
        mod = importlib.import_module(name)

        check(
            name,
            importlib.metadata.version(dist),
            os.environ[version_var],
        )

        location = Path(mod.__file__).resolve()

        print("       Location:", location)

        expected_root = (
            venv_root if local_required else base_root
        )

        check_condition(
            f"{name} installation location",
            location.is_relative_to(expected_root),
        )

    except Exception as exc:
        print(f"[FAIL] {name}: {exc}")
        failed.append(name)

print()
print("===== Requirements consistency =====")

requirements_file = Path(sys.argv[1])

actual_requirements = {
    line.strip()
    for line in requirements_file.read_text().splitlines()
    if line.strip() and not line.strip().startswith("#")
}

expected_requirements = {
    f"{dist}=={os.environ[version_var]}"
    for name, dist, version_var, local_required in packages
    if local_required
}

check_condition(
    "Requirements match BC_PREP version metadata",
    actual_requirements == expected_requirements,
)

if actual_requirements != expected_requirements:
    print("Actual:", sorted(actual_requirements))
    print("Expected:", sorted(expected_requirements))

print()
print("===== Native library validation =====")

try:
    import pygrib
    import pyproj
    import netCDF4

    check(
        "ecCodes",
        pygrib.eccodes_version,
        os.environ["eccodes_ver"],
    )

    check(
        "PROJ",
        pyproj.proj_version_str,
        os.environ["python_proj_ver"],
    )

    check(
        "Python NetCDF",
        netCDF4.__netcdf4libversion__,
        os.environ["python_netcdf_ver"],
    )

    check(
        "Python HDF5",
        netCDF4.__hdf5libversion__,
        os.environ["python_hdf5_ver"],
    )

    definitions = pygrib.get_definitions_path()

    print("ecCodes definitions:", definitions)

    check_condition(
        "ecCodes definitions available",
        bool(definitions)
        and Path(definitions).is_dir(),
    )

    check_condition(
        "ecCodes definitions inside WoFS venv",
        bool(definitions)
        and Path(definitions).resolve().is_relative_to(venv_root),
    )

except Exception as exc:
    print("[FAIL] Native library validation:", exc)
    failed.append("native libraries")

if failed:
    print()
    print("Failed checks:", ", ".join(failed))
    sys.exit(1)

print()
print("[PASS] All Python runtime checks passed")
PYTHON

echo
echo "===== Python dependency consistency ====="

"$PY" -m pip check

echo
echo "[PASS] BC_PREP Python environment validated"
