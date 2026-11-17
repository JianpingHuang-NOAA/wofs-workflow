#!/usr/bin/env python3

import argparse
import re
from pathlib import Path

import yaml


def read_domain_config(path):
    config = {}

    for line in path.read_text().splitlines():
        fields = line.strip().split(None, 2)

        if len(fields) == 3 and fields[0] == "setenv":
            config[fields[1]] = fields[2].strip("'\"")

    return config


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--homewofs", required=True)
    parser.add_argument("--domain-config", required=True)
    parser.add_argument("--wps-config", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    root = Path(args.homewofs).resolve()

    domain = read_domain_config(
        Path(args.domain_config)
    )

    with open(args.wps_config) as f:
        cfg = yaml.safe_load(f)["geogrid"]

    template = (
        root / "parm/wps/namelist.wps.template"
    ).read_text()

    if int(domain["domains"]) != 1:
        raise ValueError("Only single-domain WoFS is supported")

    table_dir = (
        root / cfg["table_dir"]
    ).resolve()

    geog_path = Path(cfg["geog_data_path"])

    if not geog_path.is_dir():
        raise FileNotFoundError(geog_path)

    if not (table_dir / "GEOGRID.TBL").is_file():
        raise FileNotFoundError(
            table_dir / "GEOGRID.TBL"
        )

    values = {
        "WRF_CORE": cfg["wrf_core"],
        "MAX_DOM": domain["domains"],
        "START_DATE": domain["sdate_bc"],
        "END_DATE": domain["edate_bc"],
        "INTERVAL_SECONDS": cfg["interval_seconds"],
        "IO_FORM_GEOGRID": cfg["io_form_geogrid"],
        "E_WE": domain["grdpts_ew"],
        "E_SN": domain["grdpts_ns"],
        "CENTER_LAT": domain["CENTER_LAT"],
        "CENTER_LON": domain["CENTER_LON"],
        "DX": cfg["dx"],
        "DY": cfg["dy"],
        "MAP_PROJ": cfg["map_proj"],
        "TRUELAT1": cfg["truelat1"],
        "TRUELAT2": cfg["truelat2"],
        "GEOG_DATA_RES": cfg["geog_data_res"],
        "GEOG_DATA_PATH": geog_path,
        "WPS_TABLE_DIR": table_dir,
    }

    for key, value in values.items():
        template = template.replace(
            f"@{key}@", str(value)
        )

    unresolved = re.findall(
        r"@[A-Z0-9_]+@", template
    )

    if unresolved:
        raise ValueError(
            f"Unresolved placeholders: {unresolved}"
        )

    Path(args.output).write_text(template)

    print(f"Domain: {domain['region']}")
    print(f"Center: {domain['CENTER_LAT']}, "
          f"{domain['CENTER_LON']}")
    print(f"Grid: {domain['grdpts_ew']} x "
          f"{domain['grdpts_ns']}")
    print(f"Created: {args.output}")


if __name__ == "__main__":
    main()
