import subprocess
import numpy as np
from pathlib import Path
import tempfile
import sys

legacy = Path(
    "/scratch4/NCEPDEV/stmp/Jianping.Huang/WoF_IC/hrrrdas/"
    "2026102814/postprd_mem0036/"
    "wrfnat_hrrre_newse_mem0036_01.grib2"
)

target = Path(
    "/scratch3/NCEPDEV/stmp/Jianping.Huang/com/wofs/v1.0/"
    "wofs.20261028/15/INPUT/mem36/"
    "wrfnat_hrrre_newse_mem0036_01.grib2"
)

def inventory(path):
    return subprocess.check_output(
        ["wgrib2", str(path), "-s"], text=True
    ).splitlines()

def decode(path, record, outfile):
    subprocess.run(
        [
            "wgrib2", str(path),
            "-d", str(record),
            "-no_header",
            "-order", "raw",
            "-bin", str(outfile)
        ],
        check=True,
        stdout=subprocess.DEVNULL
    )
    return np.fromfile(outfile, dtype=np.float32)

inv_l = inventory(legacy)
inv_t = inventory(target)

if len(inv_l) != len(inv_t):
    sys.exit("ERROR: Different GRIB2 record counts")

print("Record | MaxAbsDiff | MeanAbsDiff | DifferentPoints | Status")

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    fl = tmp / "legacy.bin"
    ft = tmp / "target.bin"

    for rec in range(1, len(inv_l) + 1):
        a = decode(legacy, rec, fl)
        b = decode(target, rec, ft)

        if a.size != b.size:
            print(f"{rec:4d} | GRID SIZE DIFFERENT")
            continue

        valid = np.isfinite(a) & np.isfinite(b)

        if not np.all(valid):
            missing_mismatch = np.count_nonzero(
                np.isfinite(a) != np.isfinite(b)
            )
        else:
            missing_mismatch = 0

        if np.any(valid):
            diff = np.abs(a[valid].astype(np.float64)
                        - b[valid].astype(np.float64))
            maxdiff = diff.max()
            meandiff = diff.mean()
            ndiff = np.count_nonzero(diff)
        else:
            maxdiff = 0.0
            meandiff = 0.0
            ndiff = 0

        status = (
            "IDENTICAL"
            if ndiff == 0 and missing_mismatch == 0
            else "DIFFERENT"
        )

        print(
            f"{rec:4d} | {maxdiff:.8g} | {meandiff:.8g} | "
            f"{ndiff} | {status}"
        )
