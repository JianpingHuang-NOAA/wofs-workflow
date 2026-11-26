#!/usr/bin/env python3
"""Run one OBS_RADAR stage for an entire prepared domain."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
import os
from pathlib import Path
import re
import subprocess
import sys

import yaml


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("download", "wdssii", "processing"))
    parser.add_argument("case", nargs="?", type=Path)
    parser.add_argument("--local-inputs", action="store_true",
                        help="Check prepositioned files and skip S3 acquisition")
    args = parser.parse_args()

    if args.local_inputs and args.stage != "download":
        parser.error("--local-inputs applies to download only")

    if args.case is None:
        from tempfile import mkdtemp

        if args.stage != "download":
            parser.error("A case YAML is required for this step")
        configured = os.environ.get("RADAR_CASE_YAML", "")
        if not configured or not Path(configured).is_absolute():
            parser.error("Export RADAR_CASE_YAML as an absolute COM config path")

        args.case = Path(configured)
        # Service nodes perform acquisition. Compute nodes check local inputs.
        if (os.environ.get("SLURM_JOB_ID")
                and os.environ.get("SLURM_JOB_PARTITION") != "u1-service"):
            args.local_inputs = True

        if not os.path.lexists(args.case):
            ush = Path(__file__).resolve().parent
            template = yaml.safe_load(
                (ush.parent / "parm/obs_radar/config.template.yaml").read_text()
            )
            cdate, start, end = (template.get(key) for key in ("cdate", "start", "end"))
            if not isinstance(cdate, str) or not re.fullmatch(r"[0-9]{10}", cdate):
                parser.error("Set a quoted YYYYMMDDHH cdate in config.template.yaml")
            if any(not isinstance(value, str) or not re.fullmatch(r"[0-9]{12}", value)
                   for value in (start, end)):
                parser.error("Set quoted YYYYMMDDHHMM start and end in config.template.yaml")

            domain = args.case.parent.name
            cycle_dir = (Path(template["domain_setup_root"]) / f"wofs.{cdate[:8]}"
                         / cdate[8:])
            if (not re.fullmatch(r"[A-Z0-9_]+", domain)
                    or args.case != cycle_dir / domain / "config.yaml"):
                parser.error(f"Expected RADAR_CASE_YAML under {cycle_dir}/<DOMAIN>/config.yaml")

            nexrad = Path(template["nexrad_root"])
            if not nexrad.is_absolute():
                parser.error("Set an absolute nexrad_root in config.template.yaml")
            run_base = nexrad.parent / "RADAR_RUNS"
            run_base.mkdir(parents=True, exist_ok=True)
            work = Path(mkdtemp(prefix=f"{cdate}-{domain}.", dir=run_base))

            command = [sys.executable, str(ush / "prepare_obs_radar_download.py"),
                       "--domain", domain, "--cdate", cdate,
                       "--start", start, "--end", end, "--run-root", str(work / "run")]
            if args.local_inputs:
                command.append("--local-inputs")
            subprocess.run(command, check=True)
            return

    case_path = args.case.resolve(strict=True)
    case = yaml.safe_load(case_path.read_text())
    domain = case["domain"]
    stations = case["stations"]
    if not isinstance(domain, str) or not re.fullmatch(r"[A-Z0-9_]+", domain):
        parser.error("Expected a valid domain in the prepared case")
    if (not isinstance(stations, list) or not stations
            or any(not isinstance(site, str) or not re.fullmatch(r"[A-Z][A-Z0-9]{3}", site)
                   for site in stations)
            or len(stations) != len(set(stations))):
        parser.error("Expected a nonempty list of unique radar IDs")

    ush = Path(__file__).resolve().parent

    def run(script, *operands):
        subprocess.run([sys.executable, str(ush / script), *map(str, operands)], check=True)

    def task(stage, *operands):
        print(f"{domain}: {stage} {' '.join(operands)}", flush=True)
        run("run_obs_radar.py", stage, case_path, *operands)

    if args.stage == "download":
        if case.get("download_command") or case.get("mrms_download"):
            parser.error("Use download_command: [] and disable mrms_download in the case YAML")
        if not args.local_inputs:
            run("acquire_obs_radar.py", case_path)
        task("download")
        return

    if args.stage == "wdssii":
        allocated = int(os.environ.get("SLURM_CPUS_PER_TASK", "1"))
        if allocated < 1:
            parser.error("SLURM_CPUS_PER_TASK must be positive")
        workers = min(allocated, len(stations))
        print(f"{domain}: converting {len(stations)} stations with {workers} workers",
              flush=True)
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(task, "wdssii", station): station for station in stations}
            failed = []
            for future in as_completed(futures):
                station = futures[future]
                try:
                    future.result()
                except subprocess.CalledProcessError as exc:
                    failed.append(station)
                    print(f"{domain}: {station} conversion failed with status {exc.returncode}",
                          file=sys.stderr, flush=True)
            if failed:
                raise SystemExit(f"{domain}: WDSS-II failed for {', '.join(sorted(failed))}")
        task("stage")
        return

    if not case.get("publish_root"):
        parser.error("Set publish_root in the prepared case YAML")
    publish_root = Path(case["publish_root"])
    cdate = case["cdate"]
    if (not isinstance(cdate, str) or not re.fullmatch(r"[0-9]{10}", cdate)
            or not publish_root.is_absolute()):
        parser.error("Expected quoted YYYYMMDDHH cdate and an absolute publish_root")
    datetime.strptime(cdate, "%Y%m%d%H")
    dest = publish_root / f"wofs.{cdate[:8]}" / cdate[8:] / domain / "OBS_RADAR"
    if not dest.parent.is_dir() or os.path.lexists(dest):
        parser.error(f"Expected a fresh publication destination with an existing parent: {dest}")

    start, end = (datetime.strptime(case[key], "%Y%m%d%H%M") for key in ("start", "end"))
    interval = case["interval_minutes"]
    if (type(interval) is not int or interval < 1 or end < start
            or (end - start).total_seconds() % (60 * interval)):
        parser.error("Expected an aligned analysis schedule")

    step = timedelta(minutes=interval)
    stamps = [
        (start + i * step).strftime("%Y%m%d%H%M")
        for i in range((end - start) // step + 1)
    ]
    try:
        allocated = int(os.environ.get("SLURM_CPUS_PER_TASK", "1"))
    except ValueError:
        parser.error("SLURM_CPUS_PER_TASK must be a positive integer")
    if allocated < 1:
        parser.error("SLURM_CPUS_PER_TASK must be a positive integer")
    workers = min(3, allocated, len(stamps))

    def process_cycle(stamp):
        print(f"{domain}: starting cycle {stamp}", flush=True)
        for station in stations:
            task("processing", stamp, station)
        task("merge", stamp)
        print(f"{domain}: completed cycle {stamp}", flush=True)

    print(f"{domain}: processing {len(stamps)} cycles with {workers} workers",
          flush=True)
    failed = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(process_cycle, stamp): stamp for stamp in stamps}
        for future in as_completed(futures):
            stamp = futures[future]
            try:
                future.result()
            except subprocess.CalledProcessError as exc:
                failed.append(stamp)
                print(f"{domain}: cycle {stamp} failed with status {exc.returncode}",
                      file=sys.stderr, flush=True)
    if failed:
        raise SystemExit(f"{domain}: processing failed for {', '.join(sorted(failed))}")

    task("publish")

    source_root = Path(case["run_root"]) / "processing" / "obs"
    cycle = start
    while cycle <= end:
        stamp = cycle.strftime("%Y%m%d%H%M")
        hhmm = stamp[8:]
        for name in (f"{hhmm}-vrobs.nc", f"{hhmm}-dbzobs.nc", "cycle_complete.json"):
            source = source_root / stamp / name
            published = dest / stamp / name
            subprocess.run(["cmp", "--", str(source), str(published)], check=True)
        print(f"PASS: {domain} {hhmm} UTC published byte-for-byte", flush=True)
        cycle += timedelta(minutes=interval)


if __name__ == "__main__":
    main()
