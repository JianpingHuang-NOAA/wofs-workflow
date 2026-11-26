#!/usr/bin/env python3
"""Execute one scheduled OBS_RADAR task."""

import argparse
from configparser import ConfigParser
from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from tempfile import TemporaryDirectory, mkdtemp

import yaml

from load_wps_ungrib_config import read_domain_config


def absolute(value):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError(f"Expected an absolute path: {path}")
    return path


def geometry_settings(path, cdate, domain):
    geometry = absolute(path)
    values = read_domain_config(geometry)
    if values.get("CDATE") != cdate or values.get("region") != domain:
        raise ValueError(f"DOMAIN_SETUP case or region mismatch: {geometry}")
    lat = float(values["CENTER_LAT"])
    lon = float(values["CENTER_LON"])
    if not (-90 < lat < 90 and -180 <= lon <= 180):
        raise ValueError(f"Invalid domain center in {geometry}: {lat}, {lon}")
    geo = geometry.parent / "WPS" / "GEOGRID" / "geo_em.d01.nc"
    if not geo.is_file() or not geo.stat().st_size:
        raise FileNotFoundError(f"Missing or empty GEOGRID input: {geo}")
    return dict(GEO=geo, LAT=lat, LON=lon)


def publish(config, root, cdate, domain, start, end, interval):
    destination = (absolute(config["publish_root"]) / f"wofs.{cdate[:8]}"
                   / cdate[8:] / domain / "OBS_RADAR")
    source = root / "processing" / "obs"
    if not destination.parent.is_dir():
        raise FileNotFoundError(destination.parent)
    if os.path.lexists(destination):
        raise FileExistsError(destination)

    with TemporaryDirectory(prefix=".obs-radar-", dir=destination.parent) as work:
        staged = Path(work) / "OBS_RADAR"
        staged.mkdir(mode=0o755)
        current = start
        while current <= end:
            cycle = current.strftime("%Y%m%d%H%M")
            target = staged / cycle
            target.mkdir()
            for name in ("cycle_complete.json", f"{cycle[-4:]}-dbzobs.nc", f"{cycle[-4:]}-vrobs.nc"):
                path = source / cycle / name
                if not path.is_file() or not path.stat().st_size:
                    raise ValueError(f"Missing or empty observation product: {path}")
                shutil.copy2(path, target / name)
            current += timedelta(minutes=interval)

        subprocess.run(["mv", "-nT", "--", str(staged), str(destination)], check=True)
        if staged.exists():
            raise FileExistsError(destination)
    print(f"Published radar products to {destination}", flush=True)


FIELDS = ("Velocity", "ReflectivityQC")


def require_file(path):
    if not path.is_file() or not path.stat().st_size:
        raise FileNotFoundError(f"Missing or empty input: {path}")
    return path


def dates(start, end):
    day = start.date()
    while day <= end.date():
        yield day.strftime("%Y%m%d")
        day += timedelta(days=1)


def scan_files(archive, station, lower, upper):
    pattern = re.compile(rf"{station}(\d{{8}}_\d{{6}})_V06")
    for day in dates(lower, upper):
        for path in sorted((archive / day / station).glob("*V06")):
            match = pattern.fullmatch(path.name)
            if match and lower <= datetime.strptime(match[1], "%Y%m%d_%H%M%S") <= upper:
                yield require_file(path)


def require_mrms(config, day):
    feed = absolute(config["mrms_feed"].format(day))
    if not any(path.is_file() and path.stat().st_size for path in feed.glob("*.grib2.gz")):
        raise FileNotFoundError(f"No archived MRMS GRIB2 files under {feed}")
    return feed


def station_wdssii(config, root, station, day, scans):
    # The installed legacy worker takes an event date and an input tree of stations.
    worker = require_file(absolute(config["wdssii_worker"]))
    output = root / "WDSSII"
    output.mkdir(exist_ok=True)
    with TemporaryDirectory(prefix=f".{station}-", dir=output) as tmp:
        work = Path(tmp)
        source = work / "input" / station
        source.mkdir(parents=True)
        for scan in scans:
            shutil.copy2(scan, source / scan.name)
        (work / "output").mkdir()
        log_root = root / "logs" / "wdssii"
        log_root.mkdir(parents=True, exist_ok=True)
        worker_dir = Path(mkdtemp(prefix=f"{day}-{station}-", dir=log_root))
        print(f"{station}: WDSS-II worker logs in {worker_dir}", flush=True)
        subprocess.run(
            [config["radar_python"], "-u", str(worker), day, str(source.parent),
             str(work / "output"), str(work / "output"), station[0]],
            cwd=worker_dir, check=True,
        )
        result = work / "output" / station
        for field in FIELDS:
            if not any(path.is_file() and path.stat().st_size
                       for path in (result / field).rglob("*.netcdf")):
                raise ValueError(f"{station}: WDSS-II produced no {field}")
        result.rename(output / station)


def stage_outputs(root, stations, days):
    target = root / "CLOUD_OBS"
    with TemporaryDirectory(prefix=".stage-", dir=root) as tmp:
        staged = Path(tmp) / "CLOUD_OBS"
        staged.mkdir()
        for station in stations:
            for field in FIELDS:
                source = root / "WDSSII" / station / field
                for day in days:
                    files = sorted(p for p in source.rglob(f"{day}*.netcdf")
                                   if p.is_file() and p.stat().st_size)
                    if not files:
                        raise ValueError(f"No staged {field} for {station} on {day}")
                    for path in files:
                        dest = staged / day / "Radar" / station / field / path.relative_to(source)
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(path, dest)
        staged.rename(target)


def application_config(config, root, work, cycle, mrms=False):
    app = ConfigParser(interpolation=None)
    app.optionxform = str
    app.read(require_file(absolute(config["radar_app_config"])))
    if mrms:
        app["MRMS"].update(
            feed=config["mrms_feed"], obs_seq=str(work), plot="",
            refl_var_name="MergedReflectivityQC",
        )
    else:
        app["RASS"].update(
            input=str(root / "CLOUD_OBS" / "{}" / "Radar"),
            input_refl="ReflectivityQC", input_vel="Velocity",
            reflectivity_var="ReflectivityQC", output=str(work),
            onlyVR="True", write="True", write_dart="False", plot="",
        )
    target = work / "app.cfg"
    with target.open("w") as stream:
        app.write(stream)
    return target


def radar_tool(config, tool, *args):
    source = absolute(config["radar_source"])
    script = Path(__file__).resolve().with_name("run_obs_radar_science.py")
    command = [config["radar_python"], "-I"]
    if tool == "reflectivity":
        # Isolated Python does not add the working directory to sys.path.
        bootstrap = """
import runpy
import sys
from pathlib import Path

source, script, *args = sys.argv[1:]
source = Path(source).resolve()
sys.path.insert(0, str(source))

from wofs_radar.refl import prep_mrms

writer = Path(prep_mrms.__file__).resolve()
expected = (source / "wofs_radar/refl/prep_mrms.py").resolve()
if writer != expected:
    raise SystemExit(f"Unexpected MRMS writer: {writer}, expected {expected}")
print(f"MRMS writer: {writer}", flush=True)
sys.argv = [script, *args]
runpy.run_path(script, run_name="__main__")
"""
        command.extend(["-c", bootstrap, str(source)])
    command.extend([str(script), tool, *map(str, args)])
    subprocess.run(command, cwd=source, check=True)


def process_station(config, root, cycle, station, geometry):
    station_root = root / "processing" / "stations" / cycle
    station_root.mkdir(parents=True, exist_ok=True)
    day, hhmm = cycle[:8], cycle[8:]
    for field in FIELDS:
        if not (root / "CLOUD_OBS" / day / "Radar" / station / field).is_dir():
            raise FileNotFoundError(f"Missing staged {field} for {station} on {day}")
    with TemporaryDirectory(prefix=f".{station}-", dir=station_root) as tmp:
        work = Path(tmp)
        app = application_config(config, root, work, cycle)
        radar_tool(config, "velocity", cycle, station, geometry["LON"], geometry["LAT"],
                   app, geometry["GEO"])
        name = f"obs_seq_{station}_VR_{day}_{hhmm}.nc"
        product = station_root / name
        skip = product.with_suffix(".skip.json")
        if (work / "no_eligible_scans").is_file():
            marker = work / skip.name
            marker.write_text(json.dumps({"cycle": cycle, "station": station,
                                          "reason": "no_eligible_scans"}) + "\n")
            product.unlink(missing_ok=True)
            marker.replace(skip)
        else:
            require_file(work / day / name).replace(product)
            skip.unlink(missing_ok=True)


def merge_cycle(config, root, cycle, stations, geometry):
    day, hhmm = cycle[:8], cycle[8:]
    output = root / "processing" / "obs"
    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=f".{cycle}-", dir=output) as tmp:
        work = Path(tmp)
        vr = work / "vr"
        mrms = work / "mrms"
        target = work / cycle
        for path in (vr, mrms, target):
            path.mkdir()
        station_root = root / "processing" / "stations" / cycle
        names, included, skipped = [], [], {}
        for station in stations:
            path = station_root / f"obs_seq_{station}_VR_{day}_{hhmm}.nc"
            marker = path.with_suffix(".skip.json")
            if path.exists() or not marker.is_file():
                shutil.copy2(require_file(path), vr / path.name)
                names.append(path.name)
                included.append(station)
            else:
                record = json.loads(marker.read_text())
                if record != {"cycle": cycle, "station": station,
                              "reason": "no_eligible_scans"}:
                    raise ValueError(f"Invalid station skip record: {marker}")
                skipped[station] = record["reason"]
        if not included:
            raise ValueError(f"No usable station velocity files for {cycle}")
        radar_tool(config, "combine", f"_VR_{day}_{hhmm}.nc", vr)
        products = [path for path in vr.rglob("*.nc") if path.name not in names]
        if len(products) != 1:
            raise ValueError(f"Expected one combined VR output for {cycle}, found {products}")
        app = application_config(config, root, mrms, cycle, mrms=True)
        radar_tool(config, "reflectivity", cycle, geometry["LON"], geometry["LAT"],
                   app, geometry["GEO"], require_mrms(config, day))
        dbz = require_file(mrms / day / f"obs_seq_RF_{day}_{hhmm}.nc")
        vr_name, dbz_name = f"{hhmm}-vrobs.nc", f"{hhmm}-dbzobs.nc"
        require_file(products[0]).rename(target / vr_name)
        dbz.rename(target / dbz_name)
        manifest = {"cycle": cycle, "stations": included, "skipped_stations": skipped,
                    "vrobs": vr_name, "dbzobs": dbz_name}
        (target / "cycle_complete.json").write_text(json.dumps(manifest) + "\n")
        target.rename(output / cycle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("download", "wdssii", "stage", "processing", "merge", "publish"))
    parser.add_argument("config", type=Path)
    parser.add_argument("task", nargs="*")
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    stage, task = args.stage, args.task
    cdate, domain = config["cdate"], config["domain"]
    datetime.strptime(cdate, "%Y%m%d%H")
    if not re.fullmatch(r"[A-Z0-9_]+", domain):
        parser.error("Invalid radar domain")
    start, end = (datetime.strptime(config[key], "%Y%m%d%H%M") for key in ("start", "end"))
    interval, padding = config["interval_minutes"], config.get("scan_padding_minutes", 0)
    if (type(interval) is not int or interval < 1 or end < start
            or (end - start).total_seconds() % (60 * interval)):
        parser.error("Invalid observation schedule")
    if type(padding) is not int or padding < 0:
        parser.error("Invalid scan padding")
    lower, upper = start - timedelta(minutes=padding), end + timedelta(minutes=padding)
    stations = config["stations"]
    if (not isinstance(stations, list) or not stations
            or any(not isinstance(site, str) or not re.fullmatch(r"[A-Z][A-Z0-9]{3}", site)
                   for site in stations) or len(set(stations)) != len(stations)):
        parser.error("Expected unique four-character station identifiers")
    expected_args = {"wdssii": 1, "processing": 2, "merge": 1}.get(stage, 0)
    if len(task) != expected_args:
        parser.error(f"{stage} requires {expected_args} task argument(s)")
    if stage in {"wdssii", "processing"} and task[-1] not in stations:
        parser.error(f"Station is outside the configured domain: {task[-1]}")
    if stage in {"processing", "merge"}:
        analysis = datetime.strptime(task[0], "%Y%m%d%H%M")
        if (analysis.strftime("%Y%m%d%H%M") != task[0] or not start <= analysis <= end
                or (analysis - start).total_seconds() % (60 * interval)):
            parser.error(f"Observation time is outside the configured schedule: {task[0]}")

    root = absolute(config["run_root"])
    root.mkdir(parents=True, exist_ok=True)
    if stage in {"download", "wdssii"}:
        if lower.date() != upper.date() or lower.strftime("%Y%m%d") != cdate[:8]:
            parser.error("WDSS-II input currently requires a same-day padded scan window")
        archive = absolute(config["nexrad_root"])
        if stage == "download":
            if config.get("download_command"):
                env = dict(os.environ, CDATE=cdate, DOMAIN=domain, NEXRAD_ROOT=str(archive),
                           RADAR_RUN_ROOT=str(root), RADAR_STATIONS=" ".join(stations),
                           RADAR_START=config["start"], RADAR_END=config["end"],
                           MRMS_FEED=config["mrms_feed"])
                subprocess.run(config["download_command"], env=env, check=True)
            for station in stations:
                if not list(scan_files(archive, station, lower, upper)):
                    raise ValueError(f"No archived NEXRAD scans in the window for {station}")
            for day in dates(start, end):
                require_mrms(config, day)
        else:
            station = task[0]
            scans = list(scan_files(archive, station, lower, upper))
            if not scans:
                raise ValueError(f"No archived NEXRAD scans in the window for {station}")
            station_wdssii(config, root, station, cdate[:8], scans)
    elif stage == "stage":
        stage_outputs(root, stations, list(dates(start, end)))
    elif stage == "publish":
        publish(config, root, cdate, domain, start, end, interval)
    else:
        geometry = geometry_settings(config["domain_geometry"], cdate, domain)
        if stage == "processing":
            process_station(config, root, *task, geometry)
        else:
            merge_cycle(config, root, task[0], stations, geometry)


if __name__ == "__main__":
    main()
