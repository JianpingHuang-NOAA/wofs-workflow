#!/usr/bin/env python3

import argparse
import os
import string
from datetime import datetime, timedelta
from pathlib import Path

import yaml


def read_domain_config(path):
    cfg = {}

    for line in path.read_text().splitlines():
        fields = line.strip().split(None, 2)

        if len(fields) == 3 and fields[0] == "setenv":
            cfg[fields[1]] = fields[2].strip("'\"")

    return cfg


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--homewofs", required=True)
    parser.add_argument("--comout", required=True)
    parser.add_argument("--cdate", required=True)
    parser.add_argument("--regions", nargs="+", required=True)
    parser.add_argument("--stage", choices=["BC", "IC"],
                        required=True)
    parser.add_argument("--member", type=int, required=True)
    parser.add_argument("--wps-config", required=True)

    args = parser.parse_args()

    root = Path(args.homewofs).resolve()
    comout = Path(args.comout).resolve()

    with open(args.wps_config) as f:
        cfg = yaml.safe_load(f)["ungrib"]

    stage_cfg = cfg[args.stage.lower()]

    member = args.member

    if not 1 <= member <= int(stage_cfg["ens_size"]):
        raise ValueError(f"Invalid member: {member}")

    mem2 = f"{member:02d}"
    mem4 = f"{member:04d}"

    # Confirm identical time windows across selected domains.
    windows = []

    for region in args.regions:

        path = (
            comout / region /
            f"realtime.cfg.{args.cdate[:8]}.{region}"
        )

        domain = read_domain_config(path)

        if domain["CDATE"] != args.cdate:
            raise ValueError(f"CDATE mismatch: {path}")

        if domain["region"] != region:
            raise ValueError(f"Region mismatch: {path}")

        windows.append((
            domain[stage_cfg["start_key"]],
            domain[stage_cfg["end_key"]],
        ))

    if len(set(windows)) != 1:
        raise ValueError(
            f"Different {args.stage} time windows: {windows}"
        )

    start_date, end_date = windows[0]

    date_format = "%Y-%m-%d_%H:%M:%S"

    start = datetime.strptime(start_date, date_format)
    end = datetime.strptime(end_date, date_format)

    interval = int(cfg["interval_seconds"])

    if interval <= 0 or end < start:
        raise ValueError("Invalid UNGRIB time window")

    if (end - start).total_seconds() % interval:
        raise ValueError("Time window is not interval-aligned")

    # Generate namelist.wps.
    template = (
        root / "parm/wps/namelist.ungrib.template"
    ).read_text()

    values = {
        "START_DATE": start_date,
        "END_DATE": end_date,
        "INTERVAL_SECONDS": interval,
        "OUT_FORMAT": cfg["out_format"],
        "PREFIX": cfg["prefix"],
    }

    for key, value in values.items():
        template = template.replace(
            f"@{key}@", str(value)
        )

    Path("namelist.wps").write_text(template)

    # Link stage-specific Vtable.
    vtable = (
        root / cfg["table_dir"] / stage_cfg["vtable"]
    ).resolve()

    if not vtable.is_file():
        raise FileNotFoundError(vtable)

    Path("Vtable").symlink_to(vtable)

    # Locate shared IC_PREP or BC_PREP inputs.
    input_dir = comout / "INPUT" / f"mem{mem2}"

    pattern = stage_cfg["input_pattern"].format(
        mem2=mem2,
        mem4=mem4,
    )

    files = sorted(input_dir.glob(pattern))

    if not files:
        raise FileNotFoundError(
            f"No input files: {input_dir}/{pattern}"
        )

    if args.stage == "IC" and len(files) != 1:
        raise ValueError(
            f"Expected one IC file, found {len(files)}"
        )

    # Reproduce WPS link_grib.csh naming.
    alphabet = string.ascii_uppercase

    manifest = []

    for index, path in enumerate(files):

        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Invalid GRIB2 input: {path}")

        if index >= 26**3:
            raise ValueError("Too many GRIB2 files")

        suffix = (
            alphabet[index // 676]
            + alphabet[(index // 26) % 26]
            + alphabet[index % 26]
        )

        name = f"GRIBFILE.{suffix}"

        Path(name).symlink_to(path.resolve())

        manifest.append(f"{name}\t{path.resolve()}")

    Path("input_manifest.tsv").write_text(
        "\n".join(manifest) + "\n"
    )

    # Expected intermediate output files.
    expected = []

    valid = start

    while valid <= end:

        expected.append(
            f"{cfg['prefix']}:{valid:%Y-%m-%d_%H}"
        )

        valid += timedelta(seconds=interval)

    Path("expected_files.txt").write_text(
        "\n".join(expected) + "\n"
    )

    print(f"Stage          : {args.stage}")
    print(f"Member         : {mem2}")
    print(f"Regions        : {args.regions}")
    print(f"Start date     : {start_date}")
    print(f"End date       : {end_date}")
    print(f"GRIB2 inputs   : {len(files)}")
    print(f"Expected output: {len(expected)}")


if __name__ == "__main__":
    main()
