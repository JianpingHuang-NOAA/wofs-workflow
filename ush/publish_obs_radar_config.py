#!/usr/bin/env python3
"""Publish the OBS_RADAR case for one completed DOMAIN_SETUP region."""

import argparse
from datetime import datetime, timedelta
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

import yaml


def timestamp(value, width, fmt):
    if not isinstance(value, str) or not re.fullmatch(rf"[0-9]{{{width}}}", value):
        raise ValueError(f"Expected a quoted {width}-digit UTC timestamp, got {value!r}")
    return datetime.strptime(value, fmt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    parser.add_argument("com_domain", type=Path)
    parser.add_argument("cdate")
    parser.add_argument("region")
    args = parser.parse_args()

    initial = timestamp(args.cdate, 10, "%Y%m%d%H")
    if not re.fullmatch(r"[A-Z0-9_]+", args.region):
        parser.error("Invalid DOMAIN_SETUP region")
    suffix = (f"wofs.{args.cdate[:8]}", args.cdate[8:], args.region)
    if not args.com_domain.is_absolute() or args.com_domain.parts[-3:] != suffix:
        parser.error(f"Unexpected COM domain directory: {args.com_domain}")
    com_root = args.com_domain.parents[2]
    destination = args.com_domain / "config.yaml"

    settings = yaml.safe_load(args.template.read_text())
    if not isinstance(settings, dict):
        parser.error("Expected a template mapping")
    template_cycle = timestamp(settings["cdate"], 10, "%Y%m%d%H")
    start = initial + (timestamp(settings["start"], 12, "%Y%m%d%H%M") - template_cycle)
    end = initial + (timestamp(settings["end"], 12, "%Y%m%d%H%M") - template_cycle)
    interval = settings["interval_minutes"]
    padding = settings.get("scan_padding_minutes", 0)
    if (type(interval) is not int or interval < 1 or end < start
            or (end - start).total_seconds() % (interval * 60)
            or type(padding) is not int or padding < 0):
        parser.error("Invalid analysis schedule or scan padding")
    margin = timedelta(minutes=padding)
    if (start - margin).date() != initial.date() or (end + margin).date() != initial.date():
        parser.error("Expected the padded radar scan window to stay within CDATE's UTC day")

    checkout = Path(__file__).resolve().parent.parent
    home = Path(settings.pop("HOMEwofs", str(checkout)))
    if not home.is_absolute():
        parser.error("HOMEwofs in the template must be absolute")
    for key in ("radar_python", "radar_source", "radar_app_config", "wdssii_worker"):
        settings[key] = str(home / Path(settings[key]))

    nexrad = Path(settings["nexrad_root"])
    mrms = settings["mrms_feed"]
    if (not nexrad.is_absolute() or not Path(mrms).is_absolute()
            or mrms.count("{}") != 1 or re.search(r"[{}]", mrms.replace("{}", ""))):
        parser.error("Expected absolute archive paths and one {} date placeholder in mrms_feed")
    run_base = Path(settings.pop("run_root_base", str(nexrad.parent / "RADAR_RUNS")))
    if not run_base.is_absolute():
        parser.error("run_root_base must be absolute")
    run_root = run_base / args.cdate / args.region
    for key in ("domain", "stations", "radar_list", "radar_lists", "domain_geometry",
                "obs_base_configs"):
        settings.pop(key, None)
    settings.update(
        domains=[args.region], cdate=args.cdate,
        start=start.strftime("%Y%m%d%H%M"), end=end.strftime("%Y%m%d%H%M"),
        domain_setup_root=str(com_root), publish_root=str(com_root),
    )

    with TemporaryDirectory(prefix=".obs-radar-config-", dir=args.com_domain) as temp:
        temp = Path(temp)
        # The case generator requires an unused run root during preparation.
        settings["run_root"] = str(temp / "runs")
        shared = temp / "shared.yaml"
        shared.write_text(yaml.safe_dump(settings, sort_keys=False))
        subprocess.run(
            [sys.executable, str(checkout / "ush/prepare_obs_radar_cases.py"),
             str(temp / "prepared"), str(shared)],
            check=True,
        )
        case = yaml.safe_load((temp / "prepared/1.yaml").read_text())
        case["run_root"] = str(run_root)
        case["config_path"] = str(destination)
        candidate = temp / "config.yaml"
        candidate.write_text(yaml.safe_dump(case, sort_keys=False))
        try:
            os.link(candidate, destination)
        except FileExistsError:
            if destination.is_symlink() or not destination.is_file():
                parser.error(f"Expected a regular COM configuration: {destination}")
            existing = yaml.safe_load(destination.read_text())
            if existing == case:
                print(f"[PASS] Existing OBS_RADAR configuration matches: {destination}")
            elif isinstance(existing, dict) and "config_path" not in existing and (
                    existing | {"config_path": str(destination)} == case):
                # DOMAIN_SETUP holds the COM publication lock during this update.
                candidate.chmod(destination.stat().st_mode & 0o777)
                candidate.replace(destination)
                print(f"[PASS] Added config_path to {destination}")
            else:
                parser.error(f"Existing OBS_RADAR configuration differs: {destination}")
        else:
            print(f"[PASS] Published {destination}")


if __name__ == "__main__":
    main()
