#!/usr/bin/env python3
"""
WoFS v1.0 DOMAIN_SETUP YAML configuration loader.

Usage:
    python3 load_domain_config.py CONFIG.yaml

Prints shell-safe export statements.
Nonempty environment variables override YAML launch defaults.
"""

import math
import os
import re
import shlex
import sys
from datetime import datetime
from pathlib import Path

import yaml


def fail(message):
    sys.exit(f"ERROR: {message}")


def override(name, default):
    return os.environ.get(name) or default


def positive_int(value, name):
    if not re.fullmatch(r"[0-9]+", str(value)):
        fail(f"{name} must be a positive integer")

    number = int(value)

    if number <= 0:
        fail(f"{name} must be positive")

    return number


def coordinate(value, name, lower, upper):
    try:
        number = float(value)
    except (TypeError, ValueError):
        fail(f"Invalid {name}: {value}")

    if not math.isfinite(number):
        fail(f"{name} must be finite")

    if not lower <= number <= upper:
        fail(f"{name} must be between {lower} and {upper}")

    return number


def yes_no(value, name):
    if isinstance(value, bool):
        return "YES" if value else "NO"

    value = str(value).upper()

    if value not in ("YES", "NO"):
        fail(f"{name} must be YES or NO")

    return value


def main():

    if len(sys.argv) != 2:
        fail("Usage: load_domain_config.py CONFIG.yaml")

    with open(sys.argv[1], encoding="utf-8") as handle:
        config = yaml.safe_load(handle)

    if not isinstance(config, dict):
        fail("Configuration must be a YAML mapping")

    for section in ("workflow", "grid", "paths",
                    "files", "runtime"):
        if not isinstance(config.get(section), dict):
            fail(f"Missing or invalid section: {section}")

    workflow = config["workflow"]
    grid = config["grid"]
    paths = config["paths"]
    files = config["files"]
    runtime = config["runtime"]

    home = os.environ.get("HOMEwofs")

    if not home:
        fail("HOMEwofs must be exported")

    home = str(Path(home).resolve())

    # Domain launch parameters.
    pdy = str(override("PDY", workflow["event"]))
    cyc = str(override("cyc", workflow["start_hour"]))
    region = str(override("region", workflow["region"]))

    if not re.fullmatch(r"[0-9]{8}", pdy):
        fail("PDY must be YYYYMMDD")

    if not re.fullmatch(r"(?:[01][0-9]|2[0-3])", cyc):
        fail("cyc must be between 00 and 23")

    try:
        start_dt = datetime.strptime(pdy + cyc, "%Y%m%d%H")
    except ValueError as exc:
        fail(f"Invalid launch date: {exc}")

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*",
                        region):
        fail(f"Invalid region identifier: {region}")

    # Protect the shared IC_PREP and BC_PREP directory.
    if region.upper() == "INPUT":
        fail("INPUT is reserved for shared IC/BC products")

    center_lat = coordinate(
        override("CENTER_LAT", grid["center_lat"]),
        "CENTER_LAT", -90, 90
    )

    center_lon = coordinate(
        override("CENTER_LON", grid["center_lon"]),
        "CENTER_LON", -180, 180
    )

    if abs(center_lat) == 90:
        fail("CENTER_LAT cannot be a geographic pole")

    width_km = positive_int(
        override("WIDTH_KM", grid["width_km"]),
        "WIDTH_KM"
    )

    values = {
        "HOMEwofs": home,
        "PDY": pdy,
        "cyc": cyc,
        "CDATE": pdy + cyc,
        "event": pdy,
        "start_hr": cyc,
        "region": region,
        "CENTER_LAT": str(center_lat),
        "CENTER_LON": str(center_lon),
        "WIDTH_KM": str(width_km),
        "DOMAIN_START_TIME":
            start_dt.strftime("%Y-%m-%d_%H:%M:%S"),
    }

    # Expand only known configuration variables.
    pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")

    def expand(raw):
        result = str(raw)

        for _ in range(20):
            matches = pattern.findall(result)

            if not matches:
                if "$" in result:
                    fail(f"Unsupported placeholder: {result}")
                return result

            for name in matches:
                if name not in values:
                    fail(f"Undefined placeholder: {name}")

                result = result.replace(
                    "${" + name + "}", values[name]
                )

        fail(f"Circular or excessive expansion: {raw}")

    # Resolve root paths first.
    values["DATAROOT"] = expand(
        override("DATAROOT", paths["dataroot"])
    )

    values["COMROOT"] = expand(
        override("COMROOT", paths["comroot"])
    )

    # Derived paths are recalculated for every domain.
    path_exports = {
        "work_root": "WORK_ROOT",
        "comout": "COMOUT",
        "comout_domain": "COMOUT_DOMAIN",
        "station_dir": "STATION_DIR",
        "radar_script": "RADAR_SCRIPT",
        "log_dir": "DOMAIN_LOG_DIR",
    }

    for key, name in path_exports.items():
        values[name] = expand(paths[key])

    for name in ("DATAROOT", "COMROOT",
                 *path_exports.values()):
        if not Path(values[name]).is_absolute():
            fail(f"{name} must be an absolute path")

    # Preserve the agreed domain-specific directory structure.
    expected_work = (
        Path(values["DATAROOT"]) /
        "domain_setup" / pdy / cyc / region
    )

    expected_com = (
        Path(values["COMROOT"]) /
        f"wofs.{pdy}" / cyc
    )

    expected_paths = {
        "WORK_ROOT": expected_work,
        "COMOUT": expected_com,
        "COMOUT_DOMAIN": expected_com / region,
    }

    for name, expected in expected_paths.items():
        if Path(values[name]) != expected:
            fail(f"Unexpected {name}: {values[name]}")

    # The J-job creates a unique DATA directory under this
    # parent after acquiring the domain-level lock.
    values["DOMAIN_WORK_ROOT"] = values["WORK_ROOT"]

    # Domain-specific filenames.
    file_exports = {
        "radar_config": "RADAR_CONFIG",
        "domain_plot": "DOMAIN_PLOT",
        "runtime_config": "RUNTIME_CONFIG",
    }

    expected_files = {
        "RADAR_CONFIG": f"radars_{pdy}_{region}.sh",
        "DOMAIN_PLOT": f"WOFS_domain_{pdy}_{region}.png",
        "RUNTIME_CONFIG": f"realtime.cfg.{pdy}.{region}",
    }

    for key, name in file_exports.items():
        values[name] = expand(files[key])

        if values[name] != expected_files[name]:
            fail(f"Unexpected filename: {values[name]}")

    # Runtime configuration.
    values["SENDCOM"] = yes_no(
        override("SENDCOM", runtime["sendcom"]),
        "SENDCOM"
    )

    values["KEEPDATA"] = yes_no(
        override("KEEPDATA", runtime["keepdata"]),
        "KEEPDATA"
    )

    values["DOMAIN_MODULEFILE"] = str(
        override("DOMAIN_MODULEFILE", runtime["modulefile"])
    )

    values["DOMAIN_MPI_TASKS"] = str(positive_int(
        override("DOMAIN_MPI_TASKS", runtime["mpi_tasks"]),
        "DOMAIN_MPI_TASKS"
    ))

    values["DOMAIN_CPUS_PER_TASK"] = str(positive_int(
        override("DOMAIN_CPUS_PER_TASK",
                 runtime["cpus_per_task"]),
        "DOMAIN_CPUS_PER_TASK"
    ))

    for key, name in (
        ("partition", "DOMAIN_PARTITION"),
        ("qos", "DOMAIN_QOS"),
        ("walltime", "DOMAIN_WALLTIME"),
    ):
        values[name] = str(override(name, runtime[key]))

    # Standard NCO-style repository paths.
    for name, directory in (
        ("EXECwofs", "exec"),
        ("PARMwofs", "parm"),
        ("USHwofs", "ush"),
        ("FIXwofs", "fix"),
        ("SCRIPTwofs", "scripts"),
    ):
        values[name] = str(Path(home) / directory)

    # Print assignments only after validation is complete.
    for name, value in values.items():
        print(f"export {name}={shlex.quote(str(value))}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError,
            yaml.YAMLError) as exc:
        fail(str(exc))
