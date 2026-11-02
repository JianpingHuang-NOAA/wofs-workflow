#!/usr/bin/env python3
"""
WoFS v1.0 IC_PREP YAML configuration loader.

Usage:
    python3 load_ic_prep_config.py /path/to/config.yaml

Prints shell-safe export statements for evaluation by
JWOFS_IC_PREP or the SLURM submission helper.

Requires PyYAML.
"""

import os
import re
import shlex
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("ERROR: PyYAML is required to load IC_PREP config.yaml")


def fail(message):
    sys.exit(f"ERROR: {message}")


def as_bool(value):
    if isinstance(value, bool):
        return value
    return str(value).lower() in ("true", "yes", "1", "on")


def load_config(filename):
    with open(filename, encoding="utf-8") as handle:
        config = yaml.safe_load(handle)
    if not isinstance(config, dict):
        fail("config.yaml must contain a YAML mapping")
    return config


def main():
    if len(sys.argv) != 2:
        fail("Usage: load_ic_prep_config.py CONFIG.yaml")

    config = load_config(sys.argv[1])

    workflow = config.get("workflow", {})
    paths = config.get("paths", {})
    files = config.get("files", {})
    runtime = config.get("runtime", {})
    upp = config.get("upp", {})
    grid = config.get("grid_attributes", {})

    home = os.environ.get("HOMEwofs")

# Read INIT_TIME from YAML by default.
# An explicitly exported INIT_TIME may override the YAML setting.
    yaml_init_time = str(workflow.get("INIT_TIME", "")).strip()
    init_time = os.environ.get("INIT_TIME") or yaml_init_time
    init_time = str(init_time).strip()

    if not home:
        fail("HOMEwofs must be exported")

    if not re.fullmatch(r"\d{10}", init_time):
        fail(
            "INIT_TIME must have format YYYYMMDDHH; "
            f"received {init_time!r}"
        )

    member = int(
        os.environ.get(
            "MEMBER",
            os.environ.get("SLURM_ARRAY_TASK_ID", "1"),
        )
    )
    ens_size = int(workflow.get("ens_size", 36))

    if not 1 <= member <= ens_size:
        fail(f"MEMBER must be between 1 and {ens_size}")

    forecast_hour = int(workflow.get("forecast_hour", 1))
    if forecast_hour < 0:
        fail("forecast_hour cannot be negative")

    try:
        init_dt = datetime.strptime(init_time, "%Y%m%d%H")
    except ValueError as exc:
        fail(f"Invalid INIT_TIME: {exc}")

    valid_dt = init_dt + timedelta(hours=forecast_hour)

    pdy = valid_dt.strftime("%Y%m%d")
    cyc = valid_dt.strftime("%H")
    fcst_time = f"{forecast_hour:02d}"

    values = {
        "HOMEwofs": home,
        "INIT_TIME": init_time,
        "MEMBER": str(member),
        "MEMBER04": f"{member:04d}",
        "MEMBER02": f"{member:02d}",
        "PDY": pdy,
        "cyc": cyc,
        "FCST_TIME": fcst_time,
        "FHOUR": str(forecast_hour),
        "VALID_TIME": valid_dt.strftime("%Y-%m-%d_%H:%M:%S"),
        "ENS_SIZE": str(ens_size),
        "DOMAIN": str(workflow.get("domain", 2)),
        "MODEL": str(workflow.get("model", "RAP")),
        "IC_PREP_STAGE": os.environ.get(
            "IC_PREP_STAGE", str(workflow.get("stage", "POST"))
        ),
        "EXPECTED_NUM_FIELDS": str(
            workflow.get("expected_num_fields", 163)
        ),
        "CRTM": "1" if as_bool(
            workflow.get("crtm_enabled", True)
        ) else "0",
    }

    # Expand paths using only known configuration variables.
    # Undefined placeholders are errors, not silently ignored.
    pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")

    def expand(raw):
        result = str(raw)
        for _ in range(20):
            matches = pattern.findall(result)
            if not matches:
                return result
            for name in matches:
                if name not in values:
                    fail(f"Undefined configuration placeholder: {name}")
                result = result.replace("${" + name + "}", values[name])
        fail(f"Circular or excessive expansion: {raw}")

    path_exports = {
        "dataroot": "DATAROOT",
        "legacy_root": "LEGACY_ROOT",
        "input_root": "INPUT_ROOT",
        "wrfout_small_dir": "WRFOUT_SMALL_DIR",
        "wrfinput_static_dir": "WRFINPUT_STATIC_DIR",
        "work_root": "WORK_ROOT",
        "download_work_dir": "DOWNLOAD_WORK_DIR",
        "download_script": "DOWNLOAD_SCRIPT",
        "static_vars_file": "STATIC_VARS_FILE",
        "post_work_dir": "POST_WORK_DIR",
        "comroot": "COMROOT",
        "comout": "COMOUT",
        "input_output_dir": "INPUTDIR",
        "upp_executable": "UPP_EXECUTABLE",
        "upp_fix_dir": "UPP_FIX_DIR",
        "static_wrf_dir": "STATICWRF_DIR",
        "crtm_fix_dir": "CRTM_FIX_DIR",
        "ncl_script": "NCL_SCRIPT",
        "itag_template": "ITAG_TEMPLATE",
        "post_avblflds": "POST_AVBLFLDS",
        "params_grib2_tbl": "PARAMS_GRIB2_TBL",
        "postcntrl": "POSTCNTRL",
        "postxconfig": "POSTXCONFIG",
        "gtg_config": "GTG_CONFIG",
        "eta_micro_lookup": "ETA_MICRO_LOOKUP",
    }

    # Resolve paths in YAML insertion order.
    for key, export_name in path_exports.items():
        if key in paths:
            values[export_name] = expand(paths[key])

    file_exports = {
        "wrfout_small": "WRFOUT_SMALL",
        "wrfinput_static": "WRFINPUT_STATIC",
        "final_wrfnat": "FINAL_WRFNAT",
        "final_wrfprs": "FINAL_WRFPRS",
        "final_wrftwo": "FINAL_WRFTWO",
    }

    for key, export_name in file_exports.items():
        if key in files:
            values[export_name] = expand(files[key])

    # Preserve names used by existing NCO-style scripts.
    if "WORK_ROOT" in values:
        values["DATA"] = values["WORK_ROOT"]

    if "INPUT_ROOT" in values:
        values["DATAHOME"] = values["INPUT_ROOT"]

    if "UPP_FIX_DIR" in values:
        values["UPP_FIX_DIR"] = values["UPP_FIX_DIR"]

    if "LEGACY_ROOT" in values:
        values["EXE_ROOT"] = str(
            Path(values["UPP_EXECUTABLE"]).parent
        )

    values["PARMWOfS"] = str(Path(home) / "parm")
    values["SCRIPTWOfS"] = str(Path(home) / "scripts")
    values["NCL_SCRIPTS"] = str(Path(home) / "util")

    # SLURM settings
    values["IC_MPI_TASKS"] = str(runtime.get("mpi_tasks", 160))
    values["IC_PARTITION"] = str(
        runtime.get("partition", "u1-compute")
    )
    values["IC_QOS"] = str(runtime.get("qos", "debug"))
    values["IC_WALLTIME"] = str(
        runtime.get("walltime", "00:30:00")
    )
    values["IC_MODULEFILE"] = str(
        runtime.get("modulefile", "ursa_intel")
    )

    if "log_dir" in runtime:
        values["IC_LOG_DIR"] = expand(runtime["log_dir"])

    # UPP configuration
    values["UPP_CORE"] = str(upp.get("core", "RAPR"))
    values["UPP_IOFORM"] = str(upp.get("ioform", "netcdf"))
    values["UPP_GRIB"] = str(upp.get("grib", "grib2"))

    pressure_levels = upp.get("pressure_levels_hpa", [])

    if not pressure_levels:
        fail("upp.pressure_levels_hpa cannot be empty")

    values["UPP_KPO"] = str(len(pressure_levels))

    def format_pressure(value):
        number = float(value)
        if number.is_integer():
            return f"{number:.1f}"
        return f"{number:g}"

    values["UPP_PO"] = ",".join(
        format_pressure(level) for level in pressure_levels
    ) + ","

    # Grid attributes used by ncatted.
    for name, value in grid.items():
        env_name = "GRID_" + name.replace("-", "_")
        values[env_name] = str(value)

    # Print safely quoted shell assignments.
    for name, value in values.items():
        print(f"export {name}={shlex.quote(str(value))}")


if __name__ == "__main__":
    main()
