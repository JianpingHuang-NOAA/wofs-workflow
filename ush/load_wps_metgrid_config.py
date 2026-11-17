#!/usr/bin/env python3

import argparse
import re
from datetime import datetime, timedelta
from pathlib import Path

import yaml

from load_wps_ungrib_config import read_domain_config


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

    metgrid = config["metgrid"]
    ungrib = config["ungrib"]

    stage_cfg = ungrib[args.stage.lower()]

    if not 1 <= args.member <= int(stage_cfg["ens_size"]):
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

    start_date = domain[stage_cfg["start_key"]]
    end_date = domain[stage_cfg["end_key"]]

    date_format = "%Y-%m-%d_%H:%M:%S"

    start = datetime.strptime(start_date, date_format)
    end = datetime.strptime(end_date, date_format)

    interval = int(ungrib["interval_seconds"])

    if interval != 3600 or end < start:
        raise ValueError("Invalid METGRID time window")

    if (end - start).total_seconds() % interval:
        raise ValueError("Time window is not interval-aligned")

    # Locate completed GEOGRID output.
    geogrid_dir = domain_dir / "WPS/GEOGRID"

    if not (geogrid_dir / "GEOGRID_SUCCESS").is_file():
        raise RuntimeError("GEOGRID_SUCCESS is missing")

    geo_file = geogrid_dir / "geo_em.d01.nc"

    if not geo_file.is_file() or geo_file.stat().st_size == 0:
        raise FileNotFoundError(geo_file)

    Path("geo_em.d01.nc").symlink_to(geo_file.resolve())

    # Locate completed shared UNGRIB output.
    ungrib_dir = (
        comout / "WPS/UNGRIB" /
        args.stage / f"mem{mem2}"
    )

    if not (ungrib_dir / "UNGRIB_SUCCESS").is_file():
        raise RuntimeError(
            f"UNGRIB_SUCCESS is missing: {ungrib_dir}"
        )

    prefix = ungrib["prefix"]

    expected_input = []
    expected_output = []

    valid = start

    while valid <= end:

        input_name = f"{prefix}:{valid:%Y-%m-%d_%H}"

        output_name = (
            f"met_em.d01.{valid:%Y-%m-%d_%H:%M:%S}.nc"
        )

        source = ungrib_dir / input_name

        if not source.is_file() or source.stat().st_size == 0:
            raise FileNotFoundError(source)

        Path(input_name).symlink_to(source.resolve())

        expected_input.append(input_name)
        expected_output.append(output_name)

        valid += timedelta(seconds=interval)

    # Ensure the shared UNGRIB time window is consistent.
    ungrib_expected = (
        ungrib_dir / "expected_files.txt"
    ).read_text().splitlines()

    if expected_input != ungrib_expected:
        raise ValueError("UNGRIB/METGRID time-window mismatch")

    # Reuse GEOGRID namelist to preserve domain geometry.
    namelist = (
        geogrid_dir / "namelist.wps"
    ).read_text()

    def replace_setting(text, key, value):

        pattern = rf"(?im)^\s*{re.escape(key)}\s*=.*$"

        text, count = re.subn(
            pattern,
            lambda match: f" {key} = {value},",
            text,
        )

        if count != 1:
            raise ValueError(
                f"Expected one namelist setting: {key}; "
                f"found {count}"
            )

        return text

    namelist = replace_setting(
        namelist, "start_date", f"'{start_date}'"
    )

    namelist = replace_setting(
        namelist, "end_date", f"'{end_date}'"
    )

    namelist = replace_setting(
        namelist, "interval_seconds", interval
    )

    table_dir = (
        root / metgrid["table_dir"]
    ).resolve()

    table = table_dir / "METGRID.TBL"

    if not table.is_file():
        raise FileNotFoundError(table)

    # Replace the existing metgrid namelist section.
    metgrid_section = f"""&metgrid
 fg_name = '{prefix}',
 io_form_metgrid = {metgrid['io_form_metgrid']},
 opt_metgrid_tbl_path = '{table_dir}/',
/
"""

    namelist, count = re.subn(
        r"(?ims)^[ \t]*&metgrid\b.*?^[ \t]*/[ \t]*$",
        lambda match: metgrid_section,
        namelist,
    )

    if count != 1:
        raise ValueError(
            f"Expected one &metgrid section, found {count}"
        )

    Path("namelist.wps").write_text(namelist)

    Path("expected_files.txt").write_text(
        "\n".join(expected_output) + "\n"
    )

    print(f"Region         : {args.region}")
    print(f"Stage          : {args.stage}")
    print(f"Member         : {mem2}")
    print(f"Start date     : {start_date}")
    print(f"End date       : {end_date}")
    print(f"GEOGRID input  : {geo_file}")
    print(f"UNGRIB input   : {ungrib_dir}")
    print(f"METGRID table  : {table}")
    print(f"Expected files : {len(expected_output)}")


if __name__ == "__main__":
    main()
