#!/usr/bin/env python3
"""Regression tests for the WoFS BC_PREP configuration loader."""

import copy
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "parm/bc_prep/config.yaml"
LOADER = ROOT / "ush/load_bc_prep_config.sh"

ORIGINAL = yaml.safe_load(CONFIG.read_text())

WORK = Path(tempfile.mkdtemp(prefix="wofs_config_regression."))
DATAROOT = str(WORK / "data")

ENV = {
    "PATH": os.environ["PATH"],
    "HOME": os.environ["HOME"],
    "HOMEwofs": str(ROOT),
    "DATAROOT": DATAROOT,
    "WOFS_PYTHON": sys.executable,
    "PYTHONNOUSERSITE": "1",
}

PASSED = 0
FAILED = 0


def report(name, ok, output=""):
    global PASSED, FAILED

    if ok:
        PASSED += 1
        print(f"[PASS] {name}")
    else:
        FAILED += 1
        print(f"[FAIL] {name}")
        print(output)


def run(name, cfg=None, overrides=None, checks=None, error=None):
    env = dict(ENV)

    if cfg is not None:
        path = WORK / f"{name}.yaml"
        content = cfg if isinstance(cfg, str) else yaml.safe_dump(cfg)
        path.write_text(content)
        env["BC_PREP_CONFIG"] = str(path)

    env.update(overrides or {})

    command = 'set -euo pipefail; source "$HOMEwofs/ush/load_bc_prep_config.sh"'

    if checks:
        for key, value in checks.items():
            command += f'; [[ "${{{key}}}" == {shlex.quote(value)} ]]'

    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", command],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    (WORK / f"{name}.log").write_text(result.stdout)

    if error is not None:
        ok = result.returncode != 0 and error in result.stdout
    else:
        ok = result.returncode == 0

    report(name, ok, result.stdout)


def modified(section, key, value):
    cfg = copy.deepcopy(ORIGINAL)
    cfg[section][key] = value
    return cfg


def test_defaults():
    defaults = {
        "ENS_SIZE": "18",
        "ENSEMBLE_SIZE": "18",
        "GEFS_CYCLES": "11",
        "GEFS_INTERVAL": "3",
        "SST_CYCLE": "06",
        "METGRID_PROC": "40",
        "REAL_NTASKS": "160",
        "MEAN_PROC": "40",
        "SOIL_FROM_WRFPRS": "0",
        "MIN_FILE_SIZE": "1000000000",
        "BC_PREP_MODE": "regression",
        "SENDCOM": "YES",
        "COM_OVERWRITE": "NO",
        "BC_DATA": f"{DATAROOT}/WoF_BC",
        "DATAHOME_GEFS": f"{DATAROOT}/WoF_BC/gefs",
        "DATAHOME_HRRR": f"{DATAROOT}/WoF_BC/pert_hrrr",
    }

    for key, value in defaults.items():
        run(f"default_{key}", checks={key: value})


def test_overrides():
    overrides = {
        "METGRID_PROC": "20",
        "REAL_NTASKS": "80",
        "MEAN_PROC": "20",
        "SOIL_FROM_WRFPRS": "1",
        "MIN_FILE_SIZE": "900000000",
        "BC_PREP_MODE": "operational",
        "SENDCOM": "NO",
        "COM_OVERWRITE": "YES",
        "BC_DATA": f"{DATAROOT}/custom_bc",
        "DATAHOME_GEFS": f"{DATAROOT}/custom_gefs",
        "DATAHOME_HRRR": f"{DATAROOT}/custom_hrrr",
    }

    for key, value in overrides.items():
        run(
            f"override_{key}",
            overrides=overrides,
            checks={key: value},
        )


def test_invalid_environment():
    tests = [
        ("ENS_SIZE", "36", "requires 18 BC_PREP members"),
        ("ENS_SIZE", "0", "requires 18 BC_PREP members"),
        ("ENSEMBLE_SIZE", "17", "requires 18 BC_PREP members"),
        ("GEFS_CYCLES", "10", "Unsupported WoFS v1.0 GEFS schedule"),
        ("GEFS_INTERVAL", "6", "Unsupported WoFS v1.0 GEFS schedule"),
        ("SST_CYCLE", "00", "SST_CYCLE must be 06"),
        ("METGRID_PROC", "0", "METGRID_PROC must be a positive integer"),
        ("METGRID_PROC", "abc", "METGRID_PROC must be a positive integer"),
        ("REAL_NTASKS", "-1", "REAL_NTASKS must be a positive integer"),
        ("REAL_NTASKS", "1.5", "REAL_NTASKS must be a positive integer"),
        ("MEAN_PROC", "0", "MEAN_PROC must be a positive integer"),
        ("MEAN_PROC", "abc", "MEAN_PROC must be a positive integer"),
        ("MIN_FILE_SIZE", "0", "MIN_FILE_SIZE must be a positive integer"),
        ("MIN_FILE_SIZE", "-100", "MIN_FILE_SIZE must be a positive integer"),
        ("SOIL_FROM_WRFPRS", "2", "SOIL_FROM_WRFPRS must be 0 or 1"),
        ("SOIL_FROM_WRFPRS", "YES", "SOIL_FROM_WRFPRS must be 0 or 1"),
        ("BC_PREP_MODE", "invalid", "Invalid BC_PREP_MODE"),
        ("SENDCOM", "MAYBE", "SENDCOM must be YES or NO"),
        ("COM_OVERWRITE", "TRUE", "COM_OVERWRITE must be YES or NO"),
        ("COM_OVERWRITE", "1", "COM_OVERWRITE must be YES or NO"),
    ]

    for index, (key, value, error) in enumerate(tests, 1):
        run(
            f"invalid_env_{index:02d}_{key}",
            overrides={key: value},
            error=error,
        )


def test_fixed_yaml():
    tests = [
        ("paths", "bc_subdir", "Other_BC"),
        ("paths", "gefs_subdir", "other_gefs"),
        ("paths", "hrrr_subdir", "other_hrrr"),
        ("gefs", "ensemble_size", 36),
        ("gefs", "cycles", 10),
        ("gefs", "interval_hours", 6),
        ("gefs", "initialization_lag_hours", 12),
        ("sst", "cycle", "12"),
        ("sst", "source_lag_from_gefs_init_hours", 12),
        ("sst", "source_hour", "06"),
        ("ungrib", "members", 36),
        ("metgrid", "namelist", "namelist.wps.other"),
        ("real", "namelist", "other.nl"),
        ("mean", "ensemble_size", 36),
        ("mean", "executable", "other.exe"),
        ("perturb", "ncl_script", "other.ncl"),
        ("perturb", "netcdf_to_grib_script", "other.py"),
        ("perturb", "search_before_hours", 12),
        ("perturb", "search_after_hours", 12),
    ]

    for section, key, value in tests:
        run(
            f"invalid_yaml_{section}_{key}",
            cfg=modified(section, key, value),
            error=f"Unsupported WoFS v1.0 setting: {section}.{key}=",
        )


def test_yaml_robustness():
    cfg = copy.deepcopy(ORIGINAL)
    del cfg["gefs"]["initialization_lag_hours"]

    run("missing_required_key", cfg, error="Failed to parse")
    run("malformed_yaml", "gefs: [", error="Failed to parse")
    run("invalid_root", [], error="configuration must be a mapping")

    run("string_ensemble",
        modified("gefs", "ensemble_size", "18"),
        error="Unsupported WoFS v1.0 setting")

    run("float_interval",
        modified("gefs", "interval_hours", 3.0),
        error="Unsupported WoFS v1.0 setting")

    run("integer_sst_hour",
        modified("sst", "source_hour", 0),
        error="Unsupported WoFS v1.0 setting")

    run("boolean_mpi",
        modified("real", "mpi_tasks", True),
        error="Invalid real.mpi_tasks")

    run("invalid_optional_type",
        modified("perturb", "execution_mode", 123),
        error="Invalid perturb.execution_mode")

    run("fixed_yaml_cannot_be_masked",
        modified("gefs", "ensemble_size", 36),
        overrides={"ENS_SIZE": "18", "ENSEMBLE_SIZE": "18"},
        error="Unsupported WoFS v1.0 setting")

    cfg = modified("real", "mpi_tasks", 80)

    run("valid_yaml_override", cfg,
        checks={"REAL_NTASKS": "80"})

    run("environment_precedence", cfg,
        overrides={"REAL_NTASKS": "160"},
        checks={"REAL_NTASKS": "160"})

    run("empty_environment_fallback", cfg,
        overrides={"REAL_NTASKS": ""},
        checks={"REAL_NTASKS": "80"})


def main():
    print(f"Repository: {ROOT}")
    print(f"Python: {sys.executable}")
    print(f"PyYAML: {yaml.__version__}")
    print(f"Test directory: {WORK}")

    test_defaults()
    test_overrides()
    test_invalid_environment()
    test_fixed_yaml()
    test_yaml_robustness()

    print("\n===== BC_PREP configuration regression summary =====")
    print(f"PASS = {PASSED}")
    print(f"FAIL = {FAILED}")
    print(f"Logs = {WORK}")

    if PASSED != 78 or FAILED != 0:
        return 1

    print("[PASS] All 78 BC_PREP configuration tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
