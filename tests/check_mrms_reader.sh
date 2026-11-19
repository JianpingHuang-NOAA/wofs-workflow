#!/bin/bash
#=======================================================================
# Validate the replacement MRMS GRIB2 reader.
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

source versions/bc_prep.ver

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME

PY="$ROOT/python_env/bin/python3"

SAMPLE="$(cat staging/mrms_sample/sample_path.txt)"

"$PY" - "$SAMPLE" <<'PYTHON'
import sys
import gzip
import tempfile

import numpy as np
import pygrib

from wofs_radar.refl.prep_mrms import load_mrms_NCEP
from wofs_radar.refl.grib2_reader import REFLECTIVITY_NAME

filename = sys.argv[1]

print("===== Validate MRMS replacement reader =====")
print("Input:", filename)

with load_mrms_NCEP(filename) as ds:

    print(ds)

    values = ds[REFLECTIVITY_NAME].values

    assert values.shape == (3500, 7000)

    assert np.all(np.diff(ds.lat_0.values) < 0)
    assert np.all(np.diff(ds.lon_0.values) > 0)

    assert np.isclose(ds.lat_0.values[0], 54.995)
    assert np.isclose(ds.lat_0.values[-1], 20.005)

    assert np.isclose(ds.lon_0.values[0], 230.005)
    assert np.isclose(ds.lon_0.values[-1], 299.995)

    assert np.array_equal(
        ds["MergedReflectivityQC"].values,
        values,
    )

    print("[PASS] Dataset dimensions and coordinates")
    print("[PASS] Legacy reflectivity variable names")

    # Compare with directly decoded GRIB2 values.

    with tempfile.NamedTemporaryFile(suffix=".grib2") as tmp:

        with gzip.open(filename, "rb") as src:
            tmp.write(src.read())

        tmp.flush()

        grbs = pygrib.open(tmp.name)

        try:
            original = np.asarray(grbs.message(1).values)

            assert np.array_equal(values, original)

        finally:
            grbs.close()

    print("[PASS] All reflectivity values identical")

    print("Minimum:", values.min())
    print("Maximum:", values.max())

    n_missing = np.count_nonzero(values == -99)
    n_nocover = np.count_nonzero(values == -999)

    print("Missing-data points:", n_missing)
    print("No-coverage points:", n_nocover)

    assert n_missing == 1619607
    assert n_nocover == 22723367

    print("[PASS] Original missing-data codes preserved")

    # Confirm compatibility with legacy domain subsetting.

    subset = ds.variables[REFLECTIVITY_NAME][
        1000:1300:3,
        3000:3300:3,
    ]

    assert subset.shape == (100, 100)

    print("[PASS] Legacy 2-D subsetting")

print("\n[PASS] MRMS replacement reader validation completed")

PYTHON
