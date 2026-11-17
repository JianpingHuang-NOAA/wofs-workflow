#!/usr/bin/env python3

"""Validate WoFS METGRID output before publication."""

import argparse
from pathlib import Path

from netCDF4 import Dataset


def validate_file(path, atmospheric_levels, soil_levels):

    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty file: {path}")

    required_dimensions = {
        "num_metgrid_levels": atmospheric_levels,
        "num_soilt_levels": soil_levels,
        "num_soilm_levels": soil_levels,
    }

    with Dataset(path) as nc:

        for name, expected in required_dimensions.items():

            if name not in nc.dimensions:
                raise ValueError(
                    f"{path}: missing dimension {name}"
                )

            actual = len(nc.dimensions[name])

            if actual != expected:
                raise ValueError(
                    f"{path}: {name}={actual}, "
                    f"expected={expected}"
                )

        attr = "NUM_METGRID_SOIL_LEVELS"

        if attr not in nc.ncattrs():
            raise ValueError(
                f"{path}: missing attribute {attr}"
            )

        actual = int(nc.getncattr(attr))

        if actual != soil_levels:
            raise ValueError(
                f"{path}: {attr}={actual}, "
                f"expected={soil_levels}"
            )

        for name in ("SOILT", "SOILM"):

            if name not in nc.variables:
                raise ValueError(
                    f"{path}: missing variable {name}"
                )


def main():

    parser = argparse.ArgumentParser(
        description=__doc__
    )

    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--atmospheric-levels",
        type=int,
        required=True,
    )

    parser.add_argument(
        "--soil-levels",
        type=int,
        required=True,
    )

    args = parser.parse_args()

    files = [
        Path(line.strip())
        for line in args.manifest.read_text().splitlines()
        if line.strip()
    ]

    if not files:
        raise ValueError("Empty METGRID file manifest")

    for path in files:

        validate_file(
            path,
            args.atmospheric_levels,
            args.soil_levels,
        )

    print(
        f"[PASS] Validated {len(files)} METGRID files"
    )

    print(
        f"[PASS] Atmospheric levels: "
        f"{args.atmospheric_levels}"
    )

    print(
        f"[PASS] Soil temperature and moisture levels: "
        f"{args.soil_levels}"
    )


if __name__ == "__main__":
    main()
