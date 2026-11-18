#!/usr/bin/env python3

import argparse
import re
from datetime import datetime, timedelta
from pathlib import Path

import yaml
from netCDF4 import Dataset

from read_domain_runtime_config import read_domain_config


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--homewofs", required=True)
    parser.add_argument("--comout", required=True)
    parser.add_argument("--cdate", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--stage", choices=["BC", "IC"],
                        required=True)
    parser.add_argument("--member", type=int, required=True)
    parser.add_argument("--wps-config", required=True)

    args = parser.parse_args()

    root = Path(args.homewofs).resolve()
    comout = Path(args.comout).resolve()

    with open(args.wps_config) as f:
        config = yaml.safe_load(f)

    real = config["real"]
    ungrib = config["ungrib"]

    stage = args.stage.lower()

    stage_cfg = ungrib[stage]
    real_cfg = real[stage]

    ens_size = int(stage_cfg["ens_size"])

    if not 1 <= args.member <= ens_size:
        raise ValueError(f"Invalid member: {args.member}")

    mem2 = f"{args.member:02d}"

    domain_dir = comout / args.region

    domain_config = (
        domain_dir /
        f"realtime.cfg.{args.cdate[:8]}.{args.region}"
    )

    domain = read_domain_config(domain_config)

    if domain["CDATE"] != args.cdate:
        raise ValueError("Domain CDATE mismatch")

    if domain["region"] != args.region:
        raise ValueError("Domain region mismatch")

    if int(domain["domains"]) != 1:
        raise ValueError("Only one WRF domain is supported")

    date_format = "%Y-%m-%d_%H:%M:%S"

    start = datetime.strptime(
        domain[stage_cfg["start_key"]], date_format
    )

    end = datetime.strptime(
        domain[stage_cfg["end_key"]], date_format
    )

    interval = int(ungrib["interval_seconds"])

    if interval <= 0 or end < start:
        raise ValueError("Invalid REAL time window")

    if (end - start).total_seconds() % interval:
        raise ValueError("Time window is not interval-aligned")

    if args.stage == "IC" and start != end:
        raise ValueError("REAL_IC requires a single valid time")

    # --------------------------------------------------
    # Member-specific WRF namelist template
    # --------------------------------------------------

    template = (
        root / real["template_dir"] /
        f"namelist.input.member{args.member}"
    )

    if not template.is_file():
        raise FileNotFoundError(template)

    namelist = template.read_text()

    def replace_setting(text, key, value):

        pattern = (
            rf"(?im)^[ \t]*{re.escape(key)}[ \t]*=.*$"
        )

        text, count = re.subn(
            pattern,
            lambda match: f" {key:<36} = {value},",
            text,
        )

        if count != 1:
            raise ValueError(
                f"Expected one namelist setting: "
                f"{key}; found {count}"
            )

        return text

    # --------------------------------------------------
    # Runtime settings following legacy REAL scripts
    # --------------------------------------------------

    settings = {}

    for prefix, date in (
        ("start", start),
        ("end", end),
    ):

        for field in (
            "year", "month", "day",
            "hour", "minute", "second"
        ):

            value = getattr(date, field)

            settings[f"{prefix}_{field}"] = (
                f"{value}, {value}"
            )

    settings.update({
        "interval_seconds": interval,
        "time_step": int(domain["ts"]),
        "time_step_fract_num": 0,
        "time_step_fract_den": 1,
        "max_dom": 1,
        "e_we": f"{domain['grdpts_ew']}, 1",
        "e_sn": f"{domain['grdpts_ns']}, 1",
        "i_parent_start": "1, 1",
        "j_parent_start": "1, 1",
        "parent_grid_ratio": "1, 5",
        "parent_time_step_ratio": "1, 5",
        "numtiles": 1,
        "nproc_x": -1,
        "nproc_y": -1,
        "num_land_cat": 21,
    })

    if args.stage == "BC":

        settings["p_top_requested"] = (
            real_cfg["p_top_requested"]
        )

    for key, value in settings.items():

        namelist = replace_setting(
            namelist, key, value
        )

    # --------------------------------------------------
    # Link domain-specific METGRID input files
    # --------------------------------------------------

    metgrid_dir = (
        domain_dir / "WPS" /
        args.stage / f"mem{mem2}"
    )

    if not (metgrid_dir / "METGRID_SUCCESS").is_file():
        raise RuntimeError(
            f"Missing METGRID_SUCCESS: {metgrid_dir}"
        )

    expected = []

    valid = start

    while valid <= end:

        name = (
            f"met_em.d01.{valid:%Y-%m-%d_%H:%M:%S}.nc"
        )

        source = metgrid_dir / name

        if not source.is_file() or source.stat().st_size == 0:
            raise FileNotFoundError(source)

        Path(name).symlink_to(source.resolve())

        expected.append(name)

        valid += timedelta(seconds=interval)

    # --------------------------------------------------
    # Check METGRID vertical dimensions against namelist
    # --------------------------------------------------

    def get_namelist_integer(key):

        match = re.search(
            rf"(?im)^[ \t]*{re.escape(key)}[ \t]*=[ \t]*(\d+)",
            namelist,
        )

        if match is None:
            raise ValueError(
                f"Missing namelist setting: {key}"
            )

        return int(match.group(1))

    requested_atm = get_namelist_integer(
        "num_metgrid_levels"
    )

    requested_soil = get_namelist_integer(
        "num_metgrid_soil_levels"
    )

    # Validate every required METGRID file for BC and IC.
    for metfile in expected:

        with Dataset(metfile) as nc:

            required_dims = {
                "num_metgrid_levels": requested_atm,
                "num_soilt_levels": requested_soil,
                "num_soilm_levels": requested_soil,
            }

            for key, requested in required_dims.items():

                if key not in nc.dimensions:
                    raise ValueError(
                        f"{metfile}: missing dimension {key}"
                    )

                actual = len(nc.dimensions[key])

                if actual != requested:
                    raise ValueError(
                        f"{metfile}: {key}: "
                        f"METGRID={actual}, "
                        f"namelist={requested}"
                    )

            key = "NUM_METGRID_SOIL_LEVELS"

            if key not in nc.ncattrs():
                raise ValueError(
                    f"{metfile}: missing attribute {key}"
                )

            actual = int(nc.getncattr(key))

            if actual != requested_soil:
                raise ValueError(
                    f"{metfile}: {key}: "
                    f"METGRID={actual}, "
                    f"namelist={requested_soil}"
                )

    print(f"[PASS] num_metgrid_levels = {requested_atm}")
    print(f"[PASS] num_soilt_levels = {requested_soil}")
    print(f"[PASS] num_soilm_levels = {requested_soil}")
    print(f"[PASS] NUM_METGRID_SOIL_LEVELS = {requested_soil}")
    print(f"[PASS] Validated {len(expected)} METGRID files")

    # --------------------------------------------------
    # Link WRF static files
    # --------------------------------------------------

    static_dir = (
        root / real["static_dir"]
    ).resolve()

    if not static_dir.is_dir():
        raise FileNotFoundError(static_dir)

    required_static = [
        "ETAMPNEW_DATA",
        "GENPARM.TBL",
        "LANDUSE.TBL",
        "RRTMG_LW_DATA",
        "RRTMG_SW_DATA",
        "RRTM_DATA",
        "SOILPARM.TBL",
        "VEGPARM.TBL",
        "gribmap.txt",
        "tr49t67",
        "tr49t85",
        "tr67t85",
    ]

    for name in required_static:

        source = static_dir / name

        if not source.is_file():
            raise FileNotFoundError(source)

    count = 0

    for source in sorted(static_dir.iterdir()):

        if source.is_file():

            if source.name.startswith("README"):
                continue

            Path(source.name).symlink_to(
                source.resolve()
            )

            count += 1

    # --------------------------------------------------
    # Write runtime configuration
    # --------------------------------------------------

    Path("namelist.input").write_text(namelist)

    Path("input_manifest.txt").write_text(
        "\n".join(expected) + "\n"
    )

    print(f"Region         : {args.region}")
    print(f"Stage          : {args.stage}")
    print(f"Member         : {mem2}")
    print(f"Start date     : {start}")
    print(f"End date       : {end}")
    print(f"Template       : {template}")
    print(f"METGRID files  : {len(expected)}")
    print(f"Static files   : {count}")


if __name__ == "__main__":
    main()
