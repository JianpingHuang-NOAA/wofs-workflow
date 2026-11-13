#!/usr/bin/env bash
# Load WoFS BC_PREP YAML configuration into the current shell.
# Usage: source "${HOMEwofs}/ush/load_bc_prep_config.sh"
#
# Existing nonempty environment variables take precedence over YAML defaults.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "ERROR: This script must be sourced, not executed." >&2
    exit 1
fi

_bc_loader_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
_bc_repo_root="$(cd -- "${_bc_loader_dir}/.." && pwd -P)" || return 1

export HOMEwofs="${HOMEwofs:-${_bc_repo_root}}"

if [[ ! -d "${HOMEwofs}/parm/bc_prep" ]]; then
    echo "ERROR: Invalid HOMEwofs: ${HOMEwofs}" >&2
    return 1
fi

BC_PREP_CONFIG="${BC_PREP_CONFIG:-${HOMEwofs}/parm/bc_prep/config.yaml}"
export BC_PREP_CONFIG

if [[ ! -r "${BC_PREP_CONFIG}" ]]; then
    echo "ERROR: Cannot read ${BC_PREP_CONFIG}" >&2
    return 1
fi

# Resolve Python after the runtime modules have been loaded.
_bc_python_requested="${WOFS_PYTHON:-python3}"

WOFS_PYTHON="$(command -v "${_bc_python_requested}" || true)"

if [[ -z "${WOFS_PYTHON}" || ! -x "${WOFS_PYTHON}" ]]; then
    echo "ERROR: Python interpreter not found: ${_bc_python_requested}" >&2
    return 1
fi

export WOFS_PYTHON

if ! "${WOFS_PYTHON}" -c 'import yaml'; then
    echo "ERROR: ${WOFS_PYTHON} cannot import PyYAML." >&2
    echo "Set WOFS_PYTHON to a Python interpreter with PyYAML." >&2
    return 1
fi

echo "[PASS] WOFS_PYTHON: ${WOFS_PYTHON}"
"${WOFS_PYTHON}" -c 'import yaml; print("PyYAML:", yaml.__version__)'

unset _bc_python_requested

# The Python program emits only assignments to a fixed set of variables.
# Values are shell-quoted before evaluation.
_bc_assignments="$(
    "${WOFS_PYTHON}" - "${BC_PREP_CONFIG}" <<'PY'
import shlex
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    cfg = yaml.safe_load(stream)

if not isinstance(cfg, dict):
    raise ValueError("BC_PREP configuration must be a mapping")


# Fixed scientific constraints for the validated WoFS v1.0 workflow.
# These settings describe the implementation, not independent runtime knobs.
fixed_constraints = {
    ("paths", "bc_subdir"): "WoF_BC",
    ("paths", "gefs_subdir"): "gefs",
    ("paths", "hrrr_subdir"): "pert_hrrr",
    ("gefs", "ensemble_size"): 18,
    ("gefs", "cycles"): 11,
    ("gefs", "interval_hours"): 3,
    ("gefs", "initialization_lag_hours"): 6,
    ("sst", "cycle"): "06",
    ("sst", "source_lag_from_gefs_init_hours"): 24,
    ("sst", "source_hour"): "00",
    ("ungrib", "members"): 18,
    ("metgrid", "namelist"): "namelist.wps.GFSENS",
    ("real", "namelist"): "real.nl.32and4levels",
    ("mean", "ensemble_size"): 18,
    ("mean", "executable"): "average_netcdf_files_parallel.x",
    ("perturb", "ncl_script"): "perturb_hrrr.ncl",
    ("perturb", "netcdf_to_grib_script"): "netcdf_to_grib.py",
    ("perturb", "search_before_hours"): 6,
    ("perturb", "search_after_hours"): 6,
}

for (section, key), expected in fixed_constraints.items():
    value = cfg[section][key]

    if type(value) is not type(expected) or value != expected:
        raise ValueError(
            f"Unsupported WoFS v1.0 setting: "
            f"{section}.{key}={value!r}; expected {expected!r}"
        )

mapping = {
    "GEFS_DIR": ("gefs", "source_dir"),
    "GEFS_CYCLES": ("gefs", "cycles"),
    "GEFS_INTERVAL": ("gefs", "interval_hours"),
    "ENS_SIZE": ("gefs", "ensemble_size"),
    "HIGHRES_SST_DIR": ("sst", "source_dir"),
    "SST_CYCLE": ("sst", "cycle"),
    "HRRR_DIR": ("hrrr", "wrfnat_dir"),
    "HRRR_WRFPRS_DIR": ("hrrr", "wrfprs_dir"),
    "METGRID_PROC": ("metgrid", "mpi_tasks"),
    "REAL_NTASKS": ("real", "mpi_tasks"),
    "MEAN_PROC": ("mean", "mpi_tasks"),
    "SOIL_FROM_WRFPRS": ("perturb", "soil_from_wrfprs"),
    "MIN_FILE_SIZE": ("perturb", "min_file_size"),
}

optional_mapping = {
    "BC_PREP_MODE": ("perturb", "execution_mode", "regression"),
    "BC_PERTURB_WORK_ROOT": ("perturb", "operational_work_root", ""),
    "BC_PERTURB_COM_ROOT": ("perturb", "operational_com_root", ""),
    "BC_PROTECTED_WORK_ROOT": ("perturb", "protected_work_root", ""),
    "BC_PROTECTED_COM_ROOT": ("perturb", "protected_com_root", ""),
}

for variable, (section, key, default) in optional_mapping.items():
    value = cfg.get(section, {}).get(key, default)
    if not isinstance(value, str):
        raise ValueError(f"Invalid {section}.{key}")
    print(f"_bc_yaml_{variable}={shlex.quote(value)}")

for variable, (section, key) in mapping.items():
    value = cfg[section][key]
    if value is None or isinstance(value, (dict, list, bool)):
        raise ValueError(f"Invalid {section}.{key}")
    print(f"_bc_yaml_{variable}={shlex.quote(str(value))}")
PY
)" || {
    echo "ERROR: Failed to parse ${BC_PREP_CONFIG}" >&2
    return 1
}

eval "${_bc_assignments}"

# Apply YAML values only where the environment has no nonempty value.
for _bc_name in \
    GEFS_DIR GEFS_CYCLES GEFS_INTERVAL ENS_SIZE \
    HIGHRES_SST_DIR SST_CYCLE HRRR_DIR HRRR_WRFPRS_DIR \
    METGRID_PROC REAL_NTASKS MEAN_PROC \
    SOIL_FROM_WRFPRS MIN_FILE_SIZE \
    BC_PREP_MODE BC_PERTURB_WORK_ROOT BC_PERTURB_COM_ROOT \
    BC_PROTECTED_WORK_ROOT BC_PROTECTED_COM_ROOT
do
    _bc_yaml_name="_bc_yaml_${_bc_name}"
    if [[ -z "${!_bc_name:-}" ]]; then
        printf -v "${_bc_name}" '%s' "${!_bc_yaml_name}"
    fi
    export "${_bc_name}"
    unset "${_bc_yaml_name}"
done

case "${BC_PREP_MODE}" in
    regression|operational) ;;
    *)
        echo "ERROR: Invalid BC_PREP_MODE=${BC_PREP_MODE}" >&2
        return 1
        ;;
esac

export ENSEMBLE_SIZE="${ENSEMBLE_SIZE:-${ENS_SIZE}}"

# Validate effective runtime settings after environment overrides.
# WoFS v1.0 uses a fixed 18-member GEFS boundary ensemble.
if [[ "${ENS_SIZE}" != "18" ||
      "${ENSEMBLE_SIZE}" != "18" ]]; then
    echo "ERROR: WoFS v1.0 requires 18 BC_PREP members." >&2
    echo "ENS_SIZE=${ENS_SIZE}" >&2
    echo "ENSEMBLE_SIZE=${ENSEMBLE_SIZE}" >&2
    return 1
fi

# Preserve the validated GEFS forecast schedule.
if [[ "${GEFS_CYCLES}" != "11" ||
      "${GEFS_INTERVAL}" != "3" ]]; then
    echo "ERROR: Unsupported WoFS v1.0 GEFS schedule." >&2
    echo "GEFS_CYCLES=${GEFS_CYCLES}; expected 11" >&2
    echo "GEFS_INTERVAL=${GEFS_INTERVAL}; expected 3" >&2
    return 1
fi

# SST_CYCLE is a legacy setting, not the SST source-file hour.
if [[ "${SST_CYCLE}" != "06" ]]; then
    echo "ERROR: SST_CYCLE must be 06 for WoFS v1.0." >&2
    return 1
fi

# Computational resources remain configurable.
for _bc_name in METGRID_PROC REAL_NTASKS MEAN_PROC MIN_FILE_SIZE
do
    if [[ ! "${!_bc_name}" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: ${_bc_name} must be a positive integer." >&2
        echo "${_bc_name}=${!_bc_name}" >&2
        return 1
    fi
done

case "${SOIL_FROM_WRFPRS}" in
    0|1) ;;
    *)
        echo "ERROR: SOIL_FROM_WRFPRS must be 0 or 1." >&2
        return 1
        ;;
esac

echo "[PASS] WoFS v1.0 BC_PREP scientific constraints"
echo "[PASS] BC_PREP runtime resource configuration"


# Runtime paths. Do not insert user-specific machine paths here.
export DATAROOT="${DATAROOT:-${DATA:-}}"

if [[ -z "${DATAROOT}" ]]; then
    echo "ERROR: Set DATAROOT or DATA before loading BC_PREP." >&2
    return 1
fi

export BC_DATA="${BC_DATA:-${DATAROOT}/WoF_BC}"
export DATAHOME_GEFS="${DATAHOME_GEFS:-${BC_DATA}/gefs}"
export DATAHOME_HRRR="${DATAHOME_HRRR:-${BC_DATA}/pert_hrrr}"

# Standard WoFS COM publication settings.
# PERTURB requires an explicitly configured COMROOT.
export SENDCOM="${SENDCOM:-YES}"
export COM_OVERWRITE="${COM_OVERWRITE:-NO}"

for _bc_name in SENDCOM COM_OVERWRITE
do
    case "${!_bc_name}" in
        YES|NO) ;;
        *)
            echo "ERROR: ${_bc_name} must be YES or NO." >&2
            return 1
            ;;
    esac
done


export EXECwofs="${EXECwofs:-${HOMEwofs}/exec}"
export PARMwofs="${PARMwofs:-${HOMEwofs}/parm}"
export USHwofs="${USHwofs:-${HOMEwofs}/ush}"
export FIXwofs="${FIXwofs:-${HOMEwofs}/fix}"
export SORCwofs="${SORCwofs:-${HOMEwofs}/sorc}"

# Compatibility names used by legacy MEAN scripts.
export EXECSWOfS="${EXECSWOfS:-${EXECwofs}}"
export USHWOfS="${USHWOfS:-${USHwofs}}"
export FIXWOfS="${FIXWOfS:-${FIXwofs}}"
export PARMWOfS="${PARMWOfS:-${PARMwofs}}"

export NCL_SCRIPTS="${NCL_SCRIPTS:-${HOMEwofs}/util}"

unset _bc_assignments _bc_name _bc_yaml_name
unset _bc_loader_dir _bc_repo_root

echo "BC_PREP configuration loaded: ${BC_PREP_CONFIG}"
