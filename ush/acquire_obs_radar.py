#!/usr/bin/env python3
"""Acquire shared NEXRAD and MRMS inputs for prepared OBS_RADAR cases."""

import argparse
from datetime import datetime, timedelta
import gzip
from pathlib import Path
import re
import shutil
import subprocess
from tempfile import TemporaryDirectory

import yaml


AWS = ["aws", "s3", "--no-sign-request", "--region", "us-east-1"]
LEVELS = (
    "00.50", "01.00", "01.50", "02.00", "02.50", "03.00", "04.00",
    "05.00", "06.00", "07.00", "08.00", "09.00", "10.00",
)


def objects(prefix, pattern):
    listing = subprocess.check_output([*AWS, "ls", prefix], text=True)
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2].isdigit() and int(fields[2]) > 0:
            match = pattern.fullmatch(fields[3])
            if match:
                yield match[1], fields[3]


def fetch(uri, target, is_mrms):
    if target.is_file() and target.stat().st_size:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=".radar-", dir=target.parent) as directory:
        partial = Path(directory) / target.name
        subprocess.run(
            [*AWS, "cp", "--only-show-errors", uri, str(partial)], check=True
        )
        if not partial.stat().st_size:
            raise ValueError(f"Empty download: {uri}")
        if is_mrms:
            with gzip.open(partial, "rb") as stream, open("/dev/null", "wb") as sink:
                if stream.read(4) != b"GRIB":
                    raise ValueError(f"Expected gzipped GRIB: {uri}")
                shutil.copyfileobj(stream, sink)
        partial.replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="store_true", help="List and check inputs without downloading")
    parser.add_argument("cases", nargs="+", type=Path)
    args = parser.parse_args()

    cases = [yaml.safe_load(path.read_text()) for path in args.cases]
    keys = ("cdate", "start", "end", "interval_minutes", "scan_padding_minutes",
            "nexrad_root", "mrms_feed")
    settings = tuple(cases[0][key] for key in keys)
    if any(tuple(case[key] for key in keys) != settings for case in cases[1:]):
        parser.error("Cases must share the same schedule and raw archive paths")

    cdate, first, last, interval, padding, nexrad_root, mrms_feed = settings
    start, end = (datetime.strptime(value, "%Y%m%d%H%M") for value in (first, last))
    if type(interval) is not int or interval < 1 or type(padding) is not int or padding < 0:
        parser.error("Expected positive interval_minutes and nonnegative scan_padding_minutes")
    if end < start or (end - start).total_seconds() % (interval * 60):
        parser.error("Expected an aligned analysis schedule")

    lower = start - timedelta(minutes=padding)
    upper = end + timedelta(minutes=padding)
    day = start.strftime("%Y%m%d")
    if lower.date() != upper.date() or day != cdate[:8]:
        parser.error("This acquisition task requires a same-day padded scan window")

    nexrad = Path(nexrad_root)
    mrms = Path(mrms_feed.format(day))
    if not nexrad.is_absolute() or not mrms.is_absolute() or mrms_feed.count("{}") != 1:
        parser.error("Expected absolute archive paths and one {} placeholder in mrms_feed")

    stations = sorted({station for case in cases for station in case["stations"]})
    if not stations or any(not re.fullmatch(r"[A-Z][A-Z0-9]{3}", s) for s in stations):
        parser.error("Invalid or empty station list")
    cycles = [start + timedelta(minutes=offset)
              for offset in range(0, int((end - start).total_seconds() // 60) + 1, interval)]

    downloads, missing = {}, []
    for station in stations:
        prefix = f"s3://unidata-nexrad-level2/{start:%Y/%m/%d}/{station}/"
        pattern = re.compile(rf"{station}{day}_(\d{{6}})_V06")
        selected = [name for stamp, name in objects(prefix, pattern)
                    if lower.strftime("%H%M%S") <= stamp <= upper.strftime("%H%M%S")]
        if not selected:
            missing.append(f"NEXRAD {station}: no scans in the padded window")
        for name in selected:
            downloads[nexrad / day / station / name] = prefix + name, False

    window = timedelta(minutes=3)
    for level in LEVELS:
        product = f"MergedReflectivityQC_{level}"
        prefix = f"s3://noaa-mrms-pds/CONUS/{product}/{day}/"
        pattern = re.compile(rf"MRMS_{re.escape(product)}_{day}-(\d{{6}})\.grib2\.gz")
        scans = [(datetime.strptime(day + stamp, "%Y%m%d%H%M%S"), name)
                 for stamp, name in objects(prefix, pattern)]
        for cycle in cycles:
            eligible = [(stamp, name) for stamp, name in scans
                        if cycle - window <= stamp < cycle + window]
            if not eligible:
                missing.append(f"MRMS {cycle:%H:%M} UTC: missing level {level}")
                continue
            _, name = min(eligible, key=lambda item: (abs(item[0] - cycle), item))
            downloads[mrms / name] = prefix + name, True

    if missing:
        raise SystemExit("\n".join(missing))

    mrms_count = sum(is_mrms for _, is_mrms in downloads.values())
    print(f"Selected {len(downloads) - mrms_count} NEXRAD files for {len(stations)} stations",
          flush=True)
    print(f"Selected {mrms_count} MRMS files for {len(cycles)} cycles", flush=True)
    if not args.plan:
        for target, (uri, is_mrms) in sorted(downloads.items()):
            fetch(uri, target, is_mrms)
        print("PASS: all selected raw inputs are available")


if __name__ == "__main__":
    main()
