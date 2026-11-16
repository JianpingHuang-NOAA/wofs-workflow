#!/usr/bin/env python3
"""
Generate the domain-specific WoFS runtime configuration.

Requires the environment initialized by load_domain_config.sh.
"""

import os
import re
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

import yaml


def fail(message):
    sys.exit(f"ERROR: {message}")


def required(name):
    value = os.environ.get(name)
    if not value:
        fail(f"Missing environment variable: {name}")
    return value


def main():

    config_file = Path(required("DOMAIN_SETUP_CONFIG"))

    with config_file.open(encoding="utf-8") as stream:
        cfg = yaml.safe_load(stream)

    values = {}

    # Import validated launch settings from Phase B.
    for name in (
        "HOMEwofs", "DATAROOT", "PDY", "cyc",
        "CDATE", "event", "start_hr", "region",
        "CENTER_LAT", "CENTER_LON", "WIDTH_KM",
        "COMROOT", "COMOUT",
        "COMOUT_DOMAIN", "DOMAIN_LOG_DIR",
        "RADAR_CONFIG", "DOMAIN_PLOT",
        "RUNTIME_CONFIG",
    ):
        values[name] = required(name)

    start = datetime.strptime(
        values["CDATE"], "%Y%m%d%H"
    )

    next_day = start + timedelta(days=1)

    def wrf_time(dt):
        return dt.strftime("%Y-%m-%d_%H:%M:%S")

    # WPS IC and BC processing windows.
    wps = cfg["wps"]

    bc_start = start + timedelta(
        hours=wps["bc_start_offset_hours"]
    )

    bc_end = bc_start + timedelta(
        hours=wps["bc_duration_hours"]
    )

    ic_start = start + timedelta(
        hours=wps["ic_start_offset_hours"]
    )

    ic_end = ic_start + timedelta(
        hours=wps["ic_duration_hours"]
    )

    values.update({
        "sdate_bc": wrf_time(bc_start),
        "edate_bc": wrf_time(bc_end),
        "sdate_ic": wrf_time(ic_start),
        "edate_ic": wrf_time(ic_end),
        "runyr": start.strftime("%Y"),
        "runmon": start.strftime("%m"),
        "runday": start.strftime("%d"),
        "nxtyr": next_day.strftime("%Y"),
        "nxtmon": next_day.strftime("%m"),
        "nxtday": next_day.strftime("%d"),
        "runDay": start.strftime("%Y%m%d"),
        "nxtDay": next_day.strftime("%Y%m%d"),
        "cycle_start": start.strftime("%H"),
        "geog_data_resouter":
            str(wps["geog_data_resouter"]),
    })

    # DA cycling schedule.
    cycling = cfg["cycling"]

    interval = int(cycling["cycleinterval"])

    if interval <= 0 or 60 % interval != 0:
        fail("Invalid cycling interval")

    cycle_end = (
        start + timedelta(
            days=int(cycling["end_day_offset"])
        )
    ).replace(
        hour=int(cycling["end_hour"]),
        minute=int(cycling["end_minute"]),
        second=0,
    )

    if cycle_end < start:
        fail("Cycling endpoint precedes start time")

    duration = int(
        (cycle_end - start).total_seconds() / 60
    )

    if duration % interval != 0:
        fail("Cycling endpoint is not aligned")

    values.update({
        "cycleinterval": str(interval),
        "DA_START_TIME": wrf_time(start),
        "DA_END_TIME": wrf_time(cycle_end),
        "DA_START_CDATE":
            start.strftime("%Y%m%d%H%M"),
        "DA_END_CDATE":
            cycle_end.strftime("%Y%m%d%H%M"),
        "DA_NUM_CYCLES":
            str(duration // interval + 1),
    })

    # Preserve legacy scientific variable names.
    for section in (
        "ensemble",
        "wrf",
        "resources",
        "observations",
        "additive_noise",
        "gsi_enkf",
    ):
        for name, value in cfg[section].items():

            if name in values:
                fail(f"Duplicate variable: {name}")

            if isinstance(value, (dict, list, bool)):
                fail(f"Invalid scalar: {name}")

            values[name] = str(value)

    # Validate essential scientific relationships.
    if values["ENS_SIZE"] != values["NANALS"]:
        fail("ENS_SIZE and NANALS must agree")

    if values["domains"] != "1":
        fail("Each WoFS launch requires one WRF domain")

    if int(values["grdpts_ew"]) - 1 != int(values["NLONS"]):
        fail("Inconsistent east-west dimensions")

    if int(values["grdpts_ns"]) - 1 != int(values["NLATS"]):
        fail("Inconsistent north-south dimensions")

    # Resolve persistent domain-specific COM directories.
    pattern = re.compile(
        r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"
    )

    def expand(raw):

        def replace(match):
            name = match.group(1)
            if name not in values:
                fail(f"Undefined placeholder: {name}")
            return values[name]

        result = pattern.sub(replace, str(raw))

        if "$" in result:
            fail(f"Unresolved placeholder: {result}")

        return result

    for name, value in cfg["domain_directories"].items():

        if name in values:
            fail(f"Duplicate directory variable: {name}")

        values[name] = expand(value)

    # Standard repository resource directories.
    home = Path(values["HOMEwofs"])

    values.update({
        "EXECwofs": str(home / "exec"),
        "FIXwofs": str(home / "fix"),
        "PARMwofs": str(home / "parm"),
        "USHwofs": str(home / "ush"),
        "SCRIPTwofs": str(home / "scripts"),
    })

    # Legacy log names, isolated by domain.
    log_names = {
        "logWPSBCs": "WPSBCs.log",
        "logWPSICs": "WPSICs.log",
        "logWPSIND": "WPSIND.log",
        "logREALBCs": "BCs.log",
        "logREALICs": "ICs.log",
        "logIcbcIND": "ICBCIND.log",
        "logConv": "ConvMAIN.log",
    }

    for name, filename in log_names.items():
        values[name] = str(
            Path(values["DOMAIN_RUN_LOG_DIR"]) / filename
        )

    # Generate C-shell-compatible configuration.
    lines = [
        "#!/bin/csh",
        "# WoFS v1.0 domain runtime configuration",
        f"# CDATE: {values['CDATE']}",
        f"# Region: {values['region']}",
        "# Generated automatically. Do not edit.",
        "",
    ]

    for name, value in values.items():

        if not re.fullmatch(
            r"[A-Za-z_][A-Za-z0-9_]*", name
        ):
            fail(f"Invalid variable name: {name}")

        # Restrict values to safe C-shell scalar characters.
        if not re.fullmatch(
            r"[A-Za-z0-9_./:+-]+", str(value)
        ):
            fail(f"Unsafe C-shell value: {name}={value}")

        lines.append(f"setenv {name} {value}")

    # Resource paths will be resolved in Phase D.
    lines.extend([
        "",
        "# GSI fix filenames: resource root pending.",
    ])

    for name, filename in cfg["gsi_fix_files"].items():
        lines.append(f"# {name}: {filename}")

    # Write into temporary DATA without exporting DATA
    # or WORK_ROOT into the persistent domain configuration.
    work = Path(required("DATA"))

    if not work.is_dir():
        fail(f"Temporary DATA directory missing: {work}")

    output = work / values["RUNTIME_CONFIG"]

    temporary = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=work,
            prefix=f".{output.name}.",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)
            stream.write("\n".join(lines) + "\n")

        temporary.chmod(0o664)
        os.replace(temporary, output)

    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

    print(f"[PASS] Runtime configuration: {output}")
    print(f"WPS BC : {values['sdate_bc']} -> {values['edate_bc']}")
    print(f"WPS IC : {values['sdate_ic']} -> {values['edate_ic']}")
    print(f"DA     : {values['DA_START_TIME']} -> {values['DA_END_TIME']}")
    print(f"Cycles : {values['DA_NUM_CYCLES']}")
    print(f"Exports: {len(values)}")


if __name__ == "__main__":
    main()
