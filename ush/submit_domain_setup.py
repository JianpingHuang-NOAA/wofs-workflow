#!/usr/bin/env python3
"""
Submit one to three on-demand WoFS DOMAIN_SETUP jobs.
"""

import argparse
import math
import os
import re
import shlex
import subprocess
import sys

from datetime import datetime
from pathlib import Path

import yaml


def fail(message):
    raise SystemExit(f"[ERROR] {message}")


def expand(value, variables):
    result = str(value)

    for _ in range(20):
        updated = re.sub(
            r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}",
            lambda m: str(variables.get(m.group(1), m.group(0))),
            result,
        )

        if updated == result:
            break

        result = updated

    if "$" in result:
        fail(f"Unresolved path variable: {result}")

    return result


def positive_int(value, name):
    if isinstance(value, bool):
        fail(f"{name} must be a positive integer")

    if not re.fullmatch(r"[0-9]+", str(value)):
        fail(f"{name} must be a positive integer")

    number = int(value)

    if number <= 0:
        fail(f"{name} must be positive")

    return number


def coordinate(value, name, minimum, maximum):
    if isinstance(value, bool):
        fail(f"Invalid {name}: {value}")

    number = float(value)

    if not math.isfinite(number):
        fail(f"Invalid {name}: {value}")

    if not minimum <= number <= maximum:
        fail(f"{name} outside valid range: {number}")

    return number


def main():

    root = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(
        description="Submit WoFS DOMAIN_SETUP jobs"
    )

    parser.add_argument(
        "--config",
        default=str(root / "parm/domain_setup/config.yaml"),
        help="DOMAIN_SETUP YAML configuration",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate configuration without submitting jobs",
    )

    args = parser.parse_args()

    config_file = Path(args.config).resolve()

    with config_file.open() as f:
        cfg = yaml.safe_load(f)

    workflow = cfg["workflow"]
    paths = cfg["paths"]
    runtime = cfg["runtime"]
    python_cfg = cfg["python"]

    # -------------------------------------------------------
    # Cycle configuration
    # -------------------------------------------------------

    pdy = str(workflow["event"])
    cyc = str(workflow["start_hour"]).zfill(2)

    if not re.fullmatch(r"[0-9]{8}", pdy):
        fail(f"Invalid event date: {pdy}")

    if not re.fullmatch(r"[0-9]{2}", cyc):
        fail(f"Invalid cycle hour: {cyc}")

    cdate = pdy + cyc

    datetime.strptime(cdate, "%Y%m%d%H")

    # -------------------------------------------------------
    # Shared paths
    # -------------------------------------------------------

    variables = {
        "HOMEwofs": str(root),
        "PDY": pdy,
        "cyc": cyc,
        "CDATE": cdate,
    }

    dataroot = expand(paths["dataroot"], variables)

    variables["DATAROOT"] = dataroot

    comroot = expand(paths["comroot"], variables)

    variables["COMROOT"] = comroot

    log_dir = expand(paths["log_dir"], variables)

    python_env = expand(python_cfg["env"], variables)

    cartopy_dir = expand(
        python_cfg["cartopy_data_dir"],
        variables,
    )

    for name, path in (
        ("DATAROOT", dataroot),
        ("COMROOT", comroot),
        ("DOMAIN_LOG_DIR", log_dir),
        ("WOFS_PYTHON_ENV", python_env),
        ("CARTOPY_DATA_DIR", cartopy_dir),
    ):
        if not Path(path).is_absolute():
            fail(f"{name} must be an absolute path")

    python_exe = Path(python_env) / "bin/python3"

    if not os.access(python_exe, os.X_OK):
        fail(f"Python interpreter unavailable: {python_exe}")

    if not Path(cartopy_dir).is_dir():
        fail(f"Cartopy FIX directory missing: {cartopy_dir}")

    # -------------------------------------------------------
    # Runtime resources
    # -------------------------------------------------------

    ntasks = positive_int(
        runtime["mpi_tasks"], "mpi_tasks"
    )

    cpus = positive_int(
        runtime["cpus_per_task"], "cpus_per_task"
    )

    partition = str(runtime["partition"])
    qos = str(runtime["qos"])
    walltime = str(runtime["walltime"])

    if runtime["modulefile"] != "ursa_intel":
        fail("Current DOMAIN_SETUP wrapper requires ursa_intel")

    sendcom = runtime["sendcom"]

    if not isinstance(sendcom, bool):
        fail("runtime.sendcom must be true or false")

    keepdata = runtime["keepdata"]

    if not isinstance(keepdata, bool):
        fail("runtime.keepdata must be true or false")

    # -------------------------------------------------------
    # Validate all domain definitions before submission
    # -------------------------------------------------------

    domains = cfg["domains"]

    if not isinstance(domains, list):
        fail("domains must be a YAML list")

    enabled_domains = []
    seen = set()

    for domain in domains:

        region = str(domain["region"])

        if not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9_-]*", region
        ):
            fail(f"Invalid region: {region}")

        if region.upper() == "INPUT":
            fail("INPUT is reserved for shared IC/BC products")

        if region.upper() in seen:
            fail(f"Duplicate region: {region}")

        seen.add(region.upper())

        enabled = domain["enabled"]

        if not isinstance(enabled, bool):
            fail(f"{region}: enabled must be true or false")

        if not enabled:
            continue

        lat = coordinate(
            domain["center_lat"], "center_lat", -90, 90
        )

        lon = coordinate(
            domain["center_lon"], "center_lon", -180, 180
        )

        if abs(lat) == 90:
            fail(f"{region}: polar center is not supported")

        width = positive_int(
            domain["width_km"], "width_km"
        )

        enabled_domains.append({
            "region": region,
            "lat": lat,
            "lon": lon,
            "width": width,
        })

    if not 1 <= len(enabled_domains) <= 3:
        fail("Enable between one and three domains")

    # -------------------------------------------------------
    # Prepare submission environment
    # -------------------------------------------------------

    base_env = os.environ.copy()

    # Remove inherited settings that could override YAML.
    for name in (
        "WOFS_PYTHON",
        "IC_PREP_PYTHON",
        "PYTHONPATH",
        "PYTHONHOME",
        "DOMAIN_MODULEFILE",
        "DOMAIN_MPI_TASKS",
        "DOMAIN_CPUS_PER_TASK",
        "DOMAIN_PARTITION",
        "DOMAIN_QOS",
        "DOMAIN_WALLTIME",
    ):
        base_env.pop(name, None)

    base_env.update({
        "HOMEwofs": str(root),
        "WOFS_PYTHON_ENV": python_env,
        "CARTOPY_DATA_DIR": cartopy_dir,
        "PYTHONNOUSERSITE": "1",
        "DOMAIN_SETUP_CONFIG": str(config_file),
        "PDY": pdy,
        "cyc": cyc,
        "CDATE": cdate,
        "DATAROOT": dataroot,
        "COMROOT": comroot,
        "SENDCOM": "YES" if sendcom else "NO",
        "KEEPDATA": "YES" if keepdata else "NO",
    })

    wrapper = (
        root / "workflow/shell/domain_setup/"
        "jwofs_domain_setup.sh"
    )

    if not wrapper.is_file():
        fail(f"Missing Slurm wrapper: {wrapper}")

    loader = root / "ush/load_domain_config.py"

    if not loader.is_file():
        fail(f"Missing domain configuration loader: {loader}")

    submissions = []

    for domain in enabled_domains:

        region = domain["region"]

        env = base_env.copy()

        env.update({
            "region": region,
            "CENTER_LAT": str(domain["lat"]),
            "CENTER_LON": str(domain["lon"]),
            "WIDTH_KM": str(domain["width"]),
        })

        # Validate using the existing single-domain loader.
        result = subprocess.run(
            [sys.executable, str(loader), str(config_file)],
            env=env,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            fail(
                f"{region}: configuration validation failed\n"
                f"{result.stderr}\n{result.stdout}"
            )

        command = [
            "sbatch",
            "--parsable",
            "--export=ALL",
            f"--job-name=domain_setup_{region}",
            f"--partition={partition}",
            f"--qos={qos}",
            "--nodes=1",
            f"--ntasks={ntasks}",
            f"--cpus-per-task={cpus}",
            f"--time={walltime}",
            f"--output={log_dir}/domain_setup_{region}_%j.out",
            f"--error={log_dir}/domain_setup_{region}_%j.err",
            str(wrapper),
            "--worker",
        ]

        submissions.append((region, command, env))

    # -------------------------------------------------------
    # Print submission summary
    # -------------------------------------------------------

    print("===== WoFS DOMAIN_SETUP submission =====")
    print(f"Configuration   : {config_file}")
    print(f"CDATE           : {cdate}")
    print(f"Enabled domains : {len(enabled_domains)}")
    print(f"DATAROOT        : {dataroot}")
    print(f"COMROOT         : {comroot}")
    print(f"Python          : {python_exe}")
    print(f"Cartopy FIX     : {cartopy_dir}")
    print(f"Log directory   : {log_dir}")
    print(f"SENDCOM         : {'YES' if sendcom else 'NO'}")
    print(f"KEEPDATA        : {'YES' if keepdata else 'NO'}")
    print()

    print(
        f"{'Domain':10s} {'Latitude':>12s} "
        f"{'Longitude':>12s} {'Width (km)':>12s}"
    )

    for domain in enabled_domains:
        print(
            f"{domain['region']:10s} "
            f"{domain['lat']:12.5f} "
            f"{domain['lon']:12.5f} "
            f"{domain['width']:12d}"
        )

    print()

    if args.dry_run:

        for region, command, env in submissions:
            print(f"[DRY-RUN] {region}")
            print(shlex.join(command))

        print("[PASS] Configuration validation completed")
        print("[PASS] No Slurm jobs submitted")

        return

    Path(log_dir).mkdir(parents=True, exist_ok=True)

    # -------------------------------------------------------
    # Submit all enabled domains
    # -------------------------------------------------------

    submitted = []

    for region, command, env in submissions:

        result = subprocess.run(
            command,
            env=env,
            cwd=root,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print(f"[ERROR] Submission failed for {region}")
            print(result.stderr)
            print(f"Previously submitted jobs: {submitted}")
            raise SystemExit(1)

        jobid = result.stdout.strip()

        submitted.append((region, jobid))

        print(f"Submitted {region}: {jobid}", flush=True)

    print()
    print(f"[PASS] Submitted {len(submitted)} DOMAIN_SETUP jobs")


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError,
            yaml.YAMLError) as exc:
        fail(str(exc))
