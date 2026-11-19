#!/bin/bash
#=======================================================================
# Inspect MRMS GRIB2 files using the WoFS Python environment.
#
# Platform: NOAA Ursa
#
# Usage:
#   ./tests/inspect_mrms_grib2.sh FILE.grib2.gz
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

[[ $# -eq 1 ]] || {
    echo "Usage: $0 FILE.grib2.gz"
    exit 1
}

INPUT="$(realpath "$1")"

[[ -s "$INPUT" ]] || {
    echo "[ERROR] Missing input: $INPUT"
    exit 1
}

source "$ROOT/versions/bc_prep.ver"

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME

PY="$ROOT/python_env/bin/python3"

"$PY" - "$INPUT" <<'PYTHON'
import sys
import gzip
import shutil
import tempfile

import numpy as np
import pygrib

filename = sys.argv[1]

print("===== MRMS GRIB2 inspection =====")
print("Input:", filename)
print("pygrib:", pygrib.__version__)

with tempfile.NamedTemporaryFile(suffix=".grib2") as tmp:

    opener = gzip.open if filename.endswith(".gz") else open

    with opener(filename, "rb") as src:
        shutil.copyfileobj(src, tmp)

    tmp.flush()

    grbs = pygrib.open(tmp.name)

    try:
        print("Number of messages:", grbs.messages)

        for grb in grbs:

            print("\n===== GRIB2 message =====")
            print(grb)

            keys = [
                "name",
                "shortName",
                "units",
                "discipline",
                "parameterCategory",
                "parameterNumber",
                "typeOfLevel",
                "level",
                "dataDate",
                "dataTime",
                "validDate",
                "gridType",
                "Ni",
                "Nj",
                "latitudeOfFirstGridPointInDegrees",
                "longitudeOfFirstGridPointInDegrees",
                "latitudeOfLastGridPointInDegrees",
                "longitudeOfLastGridPointInDegrees",
                "iDirectionIncrementInDegrees",
                "jDirectionIncrementInDegrees",
                "iScansNegatively",
                "jScansPositively",
                "jPointsAreConsecutive",
                "alternativeRowScanning",
                "bitmapPresent",
                "missingValue",
            ]

            for key in keys:
                try:
                    print(f"{key:42s}: {grb[key]}")
                except Exception:
                    print(f"{key:42s}: unavailable")

            values = np.ma.asarray(grb.values)

            lats, lons = grb.latlons()

            print("\n===== Decoded grid =====")

            print("Data shape:", values.shape)
            print("Latitude shape:", lats.shape)
            print("Longitude shape:", lons.shape)

            print("Latitude first/last:",
                  lats[0, 0], lats[-1, 0])

            print("Longitude first/last:",
                  lons[0, 0], lons[0, -1])

            print("Latitude range:",
                  np.min(lats), np.max(lats))

            print("Longitude range:",
                  np.min(lons), np.max(lons))

            print("Latitude rectilinear:",
                  np.allclose(lats, lats[:, :1],
                              rtol=0, atol=1.e-6))

            print("Longitude rectilinear:",
                  np.allclose(lons, lons[:1, :],
                              rtol=0, atol=1.e-6))

            print("Data dtype:", values.dtype)
            print("Data minimum:", values.min())
            print("Data maximum:", values.max())

            print("Masked points:",
                  np.ma.count_masked(values))

            for val in (-999, -99, -9999):
                count = np.ma.sum(values == val)
                print(f"Points equal to {val}: {count}")

    finally:
        grbs.close()

print("\n[PASS] MRMS GRIB2 decoding completed")

PYTHON
