#!/bin/bash
#
# Install standard Natural Earth vector datasets
# for WoFS DOMAIN_SETUP, POST and PLOT.
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

: "${WOFS_PYTHON:?WOFS_PYTHON must be defined}"

TARGET="${1:-${ROOT}/fix/cartopy}"

mkdir -p "$TARGET"

export PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME

"$WOFS_PYTHON" - "$TARGET" <<'PYTHON'
import sys
from pathlib import Path

import cartopy
from cartopy.io import shapereader

target = Path(sys.argv[1]).resolve()

cartopy.config["data_dir"] = target
cartopy.config["pre_existing_data_dir"] = target

resolutions = ["110m", "50m", "10m"]

datasets = [
    ("physical", "coastline"),
    ("physical", "land"),
    ("physical", "ocean"),
    ("physical", "lakes"),
    ("physical", "rivers_lake_centerlines"),
    ("cultural", "admin_0_boundary_lines_land"),
    ("cultural", "admin_1_states_provinces_lines"),
]

count = 0

for resolution in resolutions:

    for category, name in datasets:

        path = Path(
            shapereader.natural_earth(
                resolution=resolution,
                category=category,
                name=name,
            )
        )

        if not path.resolve().is_relative_to(target):
            raise RuntimeError(
                f"Unexpected data location: {path}"
            )

        for suffix in (".shp", ".shx", ".dbf", ".prj"):

            required = path.with_suffix(suffix)

            if not required.is_file():
                raise FileNotFoundError(required)

            if required.stat().st_size == 0:
                raise RuntimeError(
                    f"Empty file: {required}"
                )

        count += 1

        print(f"[PASS] {resolution} {category}/{name}")

print(f"[PASS] Installed {count} geographical datasets")
print(f"[PASS] Cartopy data directory: {target}")

PYTHON

echo
echo "===== Installed Cartopy data size ====="

du -sh "$TARGET"

echo
echo "===== Number of shapefiles ====="

find "$TARGET" -name "*.shp" | wc -l

