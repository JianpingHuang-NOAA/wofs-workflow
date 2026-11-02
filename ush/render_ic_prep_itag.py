#!/usr/bin/env python3
"""
WoFS v1.0 IC_PREP - UPP itag template renderer.

Usage:
    python3 render_ic_prep_itag.py ITAG_TEMPLATE OUTPUT_ITAG

Example:
    python3 render_ic_prep_itag.py \
        parm/ic_prep/itag.template itag

The template is populated using environment variables
exported by load_ic_prep_config.py.

This script requires only the Python standard library.
"""

import os
import re
import sys
from pathlib import Path


REQUIRED_VARIABLES = (
    "UPP_IOFORM",
    "UPP_GRIB",
    "VALID_TIME",
    "UPP_CORE",
    "UPP_KPO",
    "UPP_PO",
)

PLACEHOLDER = re.compile(
    r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"
)


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        fail(
            "Usage: render_ic_prep_itag.py "
            "ITAG_TEMPLATE OUTPUT_ITAG"
        )

    template_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not template_path.is_file():
        fail(f"Missing itag template: {template_path}")

    for name in REQUIRED_VARIABLES:
        if not os.environ.get(name):
            fail(f"Required environment variable is missing: {name}")

    try:
        kpo = int(os.environ["UPP_KPO"])
    except ValueError:
        fail("UPP_KPO must be an integer")

    if kpo <= 0:
        fail("UPP_KPO must be positive")

    pressure_levels = [
        value.strip()
        for value in os.environ["UPP_PO"].split(",")
        if value.strip()
    ]

    if len(pressure_levels) != kpo:
        fail(
            f"Pressure-level mismatch: "
            f"UPP_KPO={kpo}, "
            f"UPP_PO contains {len(pressure_levels)} levels"
        )

    try:
        for value in pressure_levels:
            float(value)
    except ValueError:
        fail("UPP_PO contains a nonnumeric pressure level")

    template = template_path.read_text(encoding="utf-8")

    def replace(match):
        name = match.group(1)

        if name not in os.environ:
            fail(f"Undefined itag placeholder: {name}")

        return os.environ[name]

    normalized_po = ",".join(pressure_levels)

    def replace(match):
        name = match.group(1)

        if name == "UPP_PO":
            return normalized_po

        if name not in os.environ:
             fail(f"Undefined itag placeholder: {name}")

        return os.environ[name]

    rendered = PLACEHOLDER.sub(replace, template)

    if PLACEHOLDER.search(rendered):
        fail("Unresolved placeholders remain in rendered itag")

    if "&MODEL_INPUTS" not in rendered.upper():
        fail("itag is missing &MODEL_INPUTS")

    if "&NAMPGB" not in rendered.upper():
        fail("itag is missing &NAMPGB")

    if output_path.parent != Path("."):
        output_path.parent.mkdir(parents=True, exist_ok=True)

    # Write through a temporary file to avoid partial output.
    temporary_path = output_path.with_name(
        output_path.name + f".tmp.{os.getpid()}"
    )

    try:
        temporary_path.write_text(rendered, encoding="utf-8")
        temporary_path.replace(output_path)
    finally:
        temporary_path.unlink(missing_ok=True)

    print(f"Generated UPP itag: {output_path}")
    print(f"Valid time: {os.environ['VALID_TIME']}")
    print(f"Model core: {os.environ['UPP_CORE']}")
    print(f"Pressure levels: {kpo}")


if __name__ == "__main__":
    main()
