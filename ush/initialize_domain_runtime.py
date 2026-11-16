#!/usr/bin/env python3
"""
Initialize WoFS domain-specific runtime directories.

This operation is non-destructive and safe to rerun.
"""

import os
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path


def fail(message):
    sys.exit(f"[ERROR] {message}")


def required_env(name):
    value = os.environ.get(name)
    if not value:
        fail(f"Missing environment variable: {name}")
    return value


def read_config(path):
    values = {}

    if not path.is_file():
        fail(f"Missing runtime configuration: {path}")

    for line in path.read_text().splitlines():

        fields = line.strip().split(maxsplit=2)

        if len(fields) == 3 and fields[0] == "setenv":

            name, value = fields[1:]

            if name in values:
                fail(f"Duplicate variable: {name}")

            if not re.fullmatch(
                r"[A-Za-z0-9_./:+-]+", value
            ):
                fail(f"Invalid configuration value: {name}")

            values[name] = value

    return values


def main():

    work = Path(required_env("WORK_ROOT")).resolve()

    config = work / required_env("RUNTIME_CONFIG")

    cfg = read_config(config)

    def get(name):
        if name not in cfg:
            fail(f"Missing runtime setting: {name}")
        return cfg[name]

    # Ensure the configuration belongs to this launch.
    for name in (
        "PDY", "cyc", "CDATE", "region",
        "WORK_ROOT", "COMOUT_DOMAIN",
        "DOMAIN_LOG_DIR",
    ):
        if get(name) != required_env(name):
            fail(f"Runtime configuration mismatch: {name}")

    rundir = Path(get("RUNDIR")).resolve()

    if rundir != work:
        fail("RUNDIR does not match WORK_ROOT")

    # All domain runtime directories must remain
    # within the current domain's working directory.
    directory_names = (
        "WRF_RUN",
        "GSI_RUN",
        "FCST_DIR",
        "ENKFDIR",
        "RESULTSDIR",
        "SEMA4",
        "INPUTDIR",
        "OBSDIR",
        "RADAR_OBS_DIR",
        "SAT_OBS_DIR",
    )

    directories = {}

    for name in directory_names:

        path = Path(get(name)).resolve()

        if path == rundir or not path.is_relative_to(rundir):
            fail(f"Unsafe domain directory: {name}={path}")

        directories[name] = path

    # Validate centralized log directory.
    log_root = Path(
        required_env("DOMAIN_LOG_DIR")
    ).resolve()

    log_dir = Path(
        get("DOMAIN_RUN_LOG_DIR")
    ).resolve()

    expected_log_dir = (
        log_root
        / get("PDY")
        / get("cyc")
        / get("region")
    )

    if log_dir != expected_log_dir:
        fail(f"Unexpected domain log directory: {log_dir}")

    # Generate DA cycling timestamps.
    start = datetime.strptime(
        get("DA_START_CDATE"), "%Y%m%d%H%M"
    )

    end = datetime.strptime(
        get("DA_END_CDATE"), "%Y%m%d%H%M"
    )

    interval = int(get("cycleinterval"))

    if interval <= 0:
        fail("Invalid cycling interval")

    if end < start:
        fail("Invalid DA cycling period")

    step = timedelta(minutes=interval)

    if (end - start) % step != timedelta(0):
        fail("DA cycling endpoint is not aligned")

    cycles = []

    current = start

    while current <= end:

        timestamp = current.strftime("%Y%m%d%H%M")

        path = rundir / timestamp

        if path.resolve() != path:
            fail(f"Unexpected cycle directory symlink: {path}")

        cycles.append(path)

        current += step

    expected_count = int(get("DA_NUM_CYCLES"))

    if len(cycles) != expected_count:
        fail(
            f"Cycle count mismatch: "
            f"{len(cycles)} != {expected_count}"
        )

    # Check for conflicting files before creating directories.
    all_dirs = list(directories.values()) + cycles + [log_dir]

    for path in all_dirs:
        if path.exists() and not path.is_dir():
            fail(f"Path exists but is not a directory: {path}")

    # Non-destructive directory initialization.
    print("===== Initialize domain runtime directories =====")

    for name, path in directories.items():

        path.mkdir(parents=True, exist_ok=True)

        print(f"[PASS] {name}: {path}")

    log_dir.mkdir(parents=True, exist_ok=True)

    print(f"[PASS] DOMAIN_RUN_LOG_DIR: {log_dir}")

    for path in cycles:
        path.mkdir(parents=True, exist_ok=True)

    print()
    print("===== DA cycling directories =====")
    print(f"First cycle : {cycles[0].name}")
    print(f"Last cycle  : {cycles[-1].name}")
    print(f"Interval    : {interval} minutes")
    print(f"Total cycles: {len(cycles)}")

    print()
    print("[PASS] All runtime directories initialized")
    print("[PASS] Existing files preserved")
    print("===== Phase D.1 SUCCESS =====")


if __name__ == "__main__":
    main()
