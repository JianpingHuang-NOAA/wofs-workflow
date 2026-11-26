#!/usr/bin/env python3
"""Run a grouped OBS_RADAR stage in job-local DATA and publish its COM handoff."""

import filecmp
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

import yaml


def publish_tree(source, destination):
    """Copy and verify a tree before exposing it under its final COM name."""
    if not source.is_dir():
        raise FileNotFoundError(source)
    if os.path.lexists(destination):
        raise FileExistsError(f"COM output already exists: {destination}")

    with TemporaryDirectory(prefix=".radar-copy-", dir=destination.parent) as temp:
        candidate = Path(temp) / destination.name
        shutil.copytree(source, candidate)
        files = [path for path in source.rglob("*") if path.is_file()]
        if not files:
            raise ValueError(f"No files to publish from {source}")
        for path in files:
            if not filecmp.cmp(path, candidate / path.relative_to(source), shallow=False):
                raise ValueError(f"COM copy verification failed for {path}")
        subprocess.run(["mv", "-nT", "--", str(candidate), str(destination)], check=True)
        if candidate.exists():
            raise FileExistsError(f"COM destination appeared during publication: {destination}")

    print(f"Published and verified {destination}", flush=True)


def main():
    stage, executable, config, *options = sys.argv[1:]
    source = Path(config).resolve(strict=True)
    executable = Path(executable).resolve(strict=True)
    case = yaml.safe_load(source.read_text())
    domain, cdate = case["domain"], case["cdate"]
    if not re.fullmatch(r"[A-Z0-9_]+", domain) or not re.fullmatch(r"[0-9]{10}", cdate):
        raise ValueError("Expected a valid domain and quoted YYYYMMDDHH cdate")

    dataroot = Path(os.environ["DATAROOT"])
    publish_root = Path(case["publish_root"])
    if not dataroot.is_absolute() or not publish_root.is_absolute():
        raise ValueError("DATAROOT and publish_root must be absolute paths")
    keep = os.environ.get("KEEP_DATA", "NO")
    if keep not in {"YES", "NO"}:
        raise ValueError("KEEP_DATA must be YES or NO")

    jobname = f"JWOFS_RADAR_{stage.upper()}"
    jobid = os.environ.get("SLURM_JOB_ID") or os.environ.get("jobid") or str(os.getpid())
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", jobid):
        raise ValueError(f"Invalid job ID: {jobid}")

    com_domain = publish_root / f"wofs.{cdate[:8]}" / cdate[8:] / domain
    if not com_domain.is_dir():
        raise FileNotFoundError(com_domain)
    destination = com_domain / "OBS_RADAR"
    destination.mkdir(exist_ok=True)
    dcom = Path(os.environ.get(
        "RADAR_DCOM_ROOT",
        "/scratch4/NCEPDEV/fv3-cam/Jianping.Huang/dcom",
    ))
    if not dcom.is_absolute():
        raise ValueError("RADAR_DCOM_ROOT must be an absolute path")
    raw = dcom / "obs_radar" / cdate / domain / "raw"
    if stage == "download":
        raw.parent.mkdir(parents=True, exist_ok=True)
    print(f"Raw radar handoff: {raw}", flush=True)
    wdssii = destination / "wdssii"

    dataroot.mkdir(parents=True, exist_ok=True)
    data = dataroot / f"{jobname}.{jobid}"
    data.mkdir()
    print(f"DATA={data}\nCOMOUT={destination}\nKEEP_DATA={keep}", flush=True)

    try:
        local = data / "config.yaml"
        case.update(run_root=str(data), config_path=str(local))

        # Copy the science INI into DATA. Link geometry in its expected layout.
        app = Path(case["radar_app_config"]).resolve(strict=True)
        local_app = data / app.name
        shutil.copy2(app, local_app)
        case["radar_app_config"] = str(local_app)

        geometry = Path(case["domain_geometry"]).resolve(strict=True)
        geometry_dir = data / "geometry"
        geometry_dir.mkdir()
        local_geometry = geometry_dir / geometry.name
        shutil.copy2(geometry, local_geometry)
        (geometry_dir / "WPS").symlink_to(geometry.parent / "WPS", target_is_directory=True)
        case["domain_geometry"] = str(local_geometry)

        if stage == "download":
            local_raw = data / "raw"
            for name in ("NEXRAD", "MRMS"):
                (local_raw / name).mkdir(parents=True)
            case.update(nexrad_root=str(local_raw / "NEXRAD"),
                        mrms_feed=str(local_raw / "MRMS" / "{}"))
            if options:
                raise ValueError("COM download mode expects acquisition into fresh DATA")
            if os.path.lexists(raw):
                raise FileExistsError(f"COM raw inputs already exist: {raw}")
        else:
            for name in ("NEXRAD", "MRMS"):
                target = raw / name
                if not target.is_dir():
                    raise FileNotFoundError(f"Missing download handoff: {target}")
                (data / name).symlink_to(target, target_is_directory=True)
            case.update(nexrad_root=str(data / "NEXRAD"),
                        mrms_feed=str(data / "MRMS" / "{}"))

        if stage == "wdssii" and os.path.lexists(wdssii):
            raise FileExistsError(f"COM WDSS-II handoff already exists: {wdssii}")
        if stage == "processing":
            if not wdssii.is_dir():
                raise FileNotFoundError(f"Missing WDSS-II handoff: {wdssii}")
            (data / "CLOUD_OBS").symlink_to(wdssii, target_is_directory=True)
            staging = data / "publish"
            staged_domain = staging / f"wofs.{cdate[:8]}" / cdate[8:] / domain
            staged_domain.mkdir(parents=True)
            case["publish_root"] = str(staging)

        local.write_text(yaml.safe_dump(case, sort_keys=False))
        logs = Path(os.environ.get("LOG_DIR") or data / "logs")
        if not logs.is_absolute():
            raise ValueError("LOG_DIR must be absolute")
        logs.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, DATA=str(data), TMPDIR=str(data), LOG_DIR=str(logs),
                   RADAR_CASE_YAML=str(local))
        subprocess.run([str(executable), str(local), *options], cwd=data, env=env, check=True)

        if stage == "download":
            publish_tree(local_raw, raw)
        elif stage == "wdssii":
            publish_tree(data / "CLOUD_OBS", wdssii)
        else:
            cycles = sorted((staged_domain / "OBS_RADAR").iterdir())
            for cycle in cycles:
                if os.path.lexists(destination / cycle.name):
                    raise FileExistsError(f"COM cycle already exists: {destination / cycle.name}")
            for cycle in cycles:
                publish_tree(cycle, destination / cycle.name)
    except BaseException:
        print(f"Failed job scratch retained at {data}", file=sys.stderr, flush=True)
        raise

    if keep == "YES":
        print(f"Kept DATA for debugging: {data}", flush=True)
    else:
        shutil.rmtree(data)
        print(f"Removed DATA after publication: {data}", flush=True)


if __name__ == "__main__":
    main()
