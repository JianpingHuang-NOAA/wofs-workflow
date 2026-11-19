#!/usr/bin/env python3
"""Run one NCO radar stage and persist its handoff in the case directory."""

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shlex
import subprocess

import yaml


def absolute(value):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError(f"Expected an absolute path: {path}")
    return path


def run(config, stage):
    cdate, domain = config["cdate"], config["domain"]
    datetime.strptime(cdate, "%Y%m%d%H")
    start, end = (datetime.strptime(config[key], "%Y%m%d%H%M")
                  for key in ("start", "end"))
    interval = config["interval_minutes"]
    if type(interval) is not int or interval < 1 or end < start:
        raise ValueError("Invalid analysis schedule")
    if (end - start).total_seconds() % (interval * 60):
        raise ValueError("END must land on the analysis interval")
    stations = config["stations"]
    if (not isinstance(stations, list) or not stations or
            any(not re.fullmatch(r"[A-Z][A-Z0-9]{3}", site) for site in stations) or
            len(set(stations)) != len(stations)):
        raise ValueError("Expected unique four-character radar station IDs")

    root = absolute(config["run_root"])
    nexrad = absolute(config["nexrad_root"])
    root.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CDATE=cdate, DOMAIN=domain, NEXRAD_ROOT=str(nexrad),
               RADAR_RUN_ROOT=str(root), RADAR_STATIONS=" ".join(stations),
               RADAR_START=config["start"], RADAR_END=config["end"])
    receipt = root / "wdssii.json"

    if stage == "download":
        if config["download_command"]:
            subprocess.run(config["download_command"], env=env, check=True)
        validate_archive(nexrad, cdate[:8], stations)
    elif stage == "wdssii":
        validate_archive(nexrad, cdate[:8], stations)
        if receipt.exists():
            raise FileExistsError(receipt)
        result = subprocess.run(config["wdssii_command"], env=env, stdout=subprocess.PIPE,
                                text=True, check=True)
        data = json.loads(result.stdout)
        validate_receipt(data)
        with receipt.open("x") as stream:
            json.dump(data, stream)
            stream.write("\n")
    else:
        job, cloud = read_receipt(receipt)
        for day in {start.strftime("%Y%m%d"), end.strftime("%Y%m%d")}:
            if not (cloud / day / "Radar").is_dir():
                raise ValueError(f"Missing staged radar directory for {day} after job {job}")
        obs_root = root / "processing"
        settings = dict(START=config["start"], END=config["end"],
                        INTERVAL_MINUTES=interval, STATIONS=" ".join(stations),
                        CLOUD_ROOT=str(cloud), RUN_ROOT=str(obs_root))
        base = absolute(config["obs_base_config"]).read_text()
        case = root / "obs.conf"
        with case.open("x") as stream:
            stream.write(base + "\n")
            for key, value in settings.items():
                stream.write(f"{key}={shlex.quote(str(value))}\n")
        subprocess.run(["bash", absolute(config["obs_launcher"]), case], env=env, check=True)


def validate_archive(nexrad, day, stations):
    for site in stations:
        path = nexrad / day / site
        if not any(scan.is_file() and scan.stat().st_size
                   for scan in path.glob("*V06")):
            raise ValueError(f"No Level II scans in {path}")


def read_receipt(path):
    return validate_receipt(json.loads(path.read_text()))


def validate_receipt(data):
    job = str(data["stage_job_id"])
    if not re.fullmatch(r"[1-9][0-9]*", job):
        raise ValueError("Invalid WDSS-II stage job ID")
    cloud = absolute(data["cloud_root"])
    print(f"WDSS-II staging job {job}, CLOUD_ROOT={cloud}", flush=True)
    return job, cloud


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("download", "wdssii", "processing"))
    parser.add_argument("config", type=Path)
    args = parser.parse_args()
    with args.config.open() as stream:
        run(yaml.safe_load(stream), args.stage)
