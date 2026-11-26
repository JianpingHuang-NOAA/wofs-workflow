#!/usr/bin/env python3
"""Prepare one OBS_RADAR case in COM and run its download step."""

import argparse
from datetime import datetime
from difflib import unified_diff
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

import yaml


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--domain", required=True)
    parser.add_argument("--cdate", required=True)
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--download-dir", type=Path,
                        help="Override both raw archive paths from the template")
    parser.add_argument("--publish-root", type=Path)
    parser.add_argument("--local-inputs", action="store_true")
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Z0-9_]+", args.domain):
        parser.error("Invalid domain name")
    for value, width, fmt in (
        (args.cdate, 10, "%Y%m%d%H"),
        (args.start, 12, "%Y%m%d%H%M"),
        (args.end, 12, "%Y%m%d%H%M"),
    ):
        if not re.fullmatch(rf"[0-9]{{{width}}}", value):
            parser.error(f"Invalid timestamp: {value}")
        try:
            datetime.strptime(value, fmt)
        except ValueError as exc:
            parser.error(str(exc))
    for path in (args.run_root, args.download_dir, args.publish_root):
        if path is not None and not path.is_absolute():
            parser.error(f"Expected an absolute path: {path}")

    ush = Path(__file__).resolve().parent
    checkout = ush.parent
    template = checkout / "parm/obs_radar/config.template.yaml"
    case = yaml.safe_load(template.read_text())
    if not isinstance(case, dict):
        parser.error(f"Expected a YAML mapping in {template}")

    home = Path(case.pop("HOMEwofs", str(checkout)))
    setup = Path(case["domain_setup_root"])
    if not home.is_absolute() or not setup.is_absolute():
        parser.error("HOMEwofs and domain_setup_root must be absolute")
    for key in ("radar_python", "radar_source", "radar_app_config", "wdssii_worker"):
        case[key] = str(home / Path(case[key]))

    for key in ("domain", "stations", "radar_list", "radar_lists",
                "domain_geometry", "download_dir"):
        case.pop(key, None)
    if args.download_dir is not None:
        case["nexrad_root"] = str(args.download_dir / "NEXRAD")
        case["mrms_feed"] = str(args.download_dir / "MRMS" / "{}")

    nexrad, mrms = case.get("nexrad_root"), case.get("mrms_feed")
    if not isinstance(nexrad, str) or not Path(nexrad).is_absolute():
        parser.error("Set nexrad_root to an absolute path")
    if (not isinstance(mrms, str) or not Path(mrms).is_absolute()
            or mrms.count("{}") != 1 or re.search(r"[{}]", mrms.replace("{}", ""))):
        parser.error("Set mrms_feed to an absolute path with one literal {} placeholder")

    case.update(
        domains=[args.domain], cdate=args.cdate, start=args.start, end=args.end,
        publish_root=str(args.publish_root or setup),
        download_command=[], mrms_download=False,
    )
    destination = (setup / f"wofs.{args.cdate[:8]}" / args.cdate[8:]
                   / args.domain / "config.yaml")
    if not destination.parent.is_dir():
        parser.error(f"Missing DOMAIN_SETUP directory: {destination.parent}")

    with TemporaryDirectory(prefix=".obs-radar-config-", dir=destination.parent) as tmp:
        tmp = Path(tmp)
        case["run_root"] = str(tmp / "runs")
        shared = tmp / "shared.yaml"
        shared.write_text(yaml.safe_dump(case, sort_keys=False))
        subprocess.run(
            [sys.executable, str(ush / "prepare_obs_radar_cases.py"),
             str(tmp / "prepared"), str(shared)],
            check=True,
        )
        prepared = yaml.safe_load((tmp / "prepared/1.yaml").read_text())
        prepared["run_root"] = str(args.run_root)
        candidate = tmp / "config.yaml"
        text = yaml.safe_dump(prepared, sort_keys=False)
        candidate.write_text(text)

        try:
            os.link(candidate, destination)
        except FileExistsError:
            if destination.is_symlink() or not destination.is_file():
                parser.error(f"Expected a regular COM config: {destination}")
            existing = destination.read_text()
            if yaml.safe_load(existing) != prepared:
                sys.stderr.writelines(unified_diff(
                    existing.splitlines(keepends=True), text.splitlines(keepends=True),
                    fromfile=str(destination), tofile="generated config.yaml",
                ))
                parser.error("Existing COM config differs. Review the diff before retrying.")

    print(f"COM configuration: {destination}", flush=True)
    print(f"NEXRAD archive: {nexrad}", flush=True)
    print(f"MRMS feed: {mrms}", flush=True)
    command = [sys.executable, str(ush / "run_obs_radar_case.py"),
               "download", str(destination)]
    if args.local_inputs:
        command.append("--local-inputs")
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
