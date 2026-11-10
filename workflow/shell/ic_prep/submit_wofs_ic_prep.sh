#!/usr/bin/env bash
#
# WoFS v1.0 IC_PREP - SLURM submission script
#
# Reads:
#   parm/ic_prep/config.yaml
#
# Submits:
#   workflow/shell/ic_prep/jwofs_ic_prep_post.sh
#
# Usage:
#   ./submit_wofs_ic_prep.sh YYYYMMDDHH
#
# Example:
#   ./submit_wofs_ic_prep.sh 2026103114
#

set -euo pipefail

# -------------------------------------------------------
# Locate repository root
# -------------------------------------------------------
SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)"

export HOMEwofs="$(
    cd "${SCRIPT_DIR}/../../.." && pwd
)"

# -------------------------------------------------------
# Initialization time
# -------------------------------------------------------
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 YYYYMMDDHH" >&2
    exit 1
fi

export INIT_TIME="$1"

if [[ ! "${INIT_TIME}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: INIT_TIME must be YYYYMMDDHH" >&2
    exit 1
fi

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
export IC_PREP_CONFIG="${IC_PREP_CONFIG:-${HOMEwofs}/parm/ic_prep/config.yaml}"
export IC_PREP_STAGE="POST"

CONFIG_LOADER="${HOMEwofs}/ush/load_ic_prep_config.py"

[[ -f "${IC_PREP_CONFIG}" ]] || {
    echo "ERROR: Missing config.yaml: ${IC_PREP_CONFIG}" >&2
    exit 1
}

[[ -f "${CONFIG_LOADER}" ]] || {
    echo "ERROR: Missing YAML loader: ${CONFIG_LOADER}" >&2
    exit 1
}

# MEMBER is needed by the loader to expand member paths.
# The array task will override this value at runtime.
export MEMBER=1

# Load the WoFS IC_PREP runtime environment before selecting Python.
source "${HOMEwofs}/versions/run.ver"

module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

# Resolve Python from the configured module environment.
export IC_PREP_PYTHON="$(command -v python3)"

if [[ -z "${IC_PREP_PYTHON}" ]] ||
   ! "${IC_PREP_PYTHON}" -c \
       'import yaml, numpy, netCDF4, scipy' >/dev/null 2>&1; then
    echo "[ERROR] WoFS IC_PREP Python dependencies are unavailable" >&2
    echo "Required packages: PyYAML, NumPy, netCDF4, SciPy." >&2
    exit 1
fi

CONFIG_EXPORTS=$("${IC_PREP_PYTHON}" "${CONFIG_LOADER}" \
    "${IC_PREP_CONFIG}")

eval "${CONFIG_EXPORTS}"

# -------------------------------------------------------
# Validate SLURM configuration
# -------------------------------------------------------
: "${ENS_SIZE:?Missing ENS_SIZE}"
: "${IC_MPI_TASKS:?Missing IC_MPI_TASKS}"
: "${IC_PARTITION:?Missing IC_PARTITION}"
: "${IC_QOS:?Missing IC_QOS}"
: "${IC_WALLTIME:?Missing IC_WALLTIME}"
: "${IC_LOG_DIR:?Missing IC_LOG_DIR}"
: "${IC_MODULEFILE:?Missing IC_MODULEFILE}"

[[ "${ENS_SIZE}" =~ ^[0-9]+$ ]] || {
    echo "ERROR: ENS_SIZE must be an integer" >&2
    exit 1
}

(( ENS_SIZE > 0 )) || {
    echo "ERROR: ENS_SIZE must be positive" >&2
    exit 1
}

# -------------------------------------------------------
# Prepare log directory
# -------------------------------------------------------
mkdir -p "${IC_LOG_DIR}"

# -------------------------------------------------------
# SLURM job script
# -------------------------------------------------------
JOB_SCRIPT="${SCRIPT_DIR}/jwofs_ic_prep_post.sh"

[[ -f "${JOB_SCRIPT}" ]] || {
    echo "ERROR: Missing SLURM job script:" >&2
    echo "  ${JOB_SCRIPT}" >&2
    exit 1
}

# -------------------------------------------------------
# Display submission settings
# -------------------------------------------------------
echo "======================================================"
echo " WoFS v1.0 IC_PREP - SLURM submission"
echo "======================================================"
echo "HOMEwofs       = ${HOMEwofs}"
echo "IC_PREP_CONFIG = ${IC_PREP_CONFIG}"
echo "INIT_TIME      = ${INIT_TIME}"
echo "PDY            = ${PDY}"
echo "cyc            = ${cyc}"
echo "ENS_SIZE       = ${ENS_SIZE}"
echo "IC_MPI_TASKS   = ${IC_MPI_TASKS}"
echo "IC_PARTITION   = ${IC_PARTITION}"
echo "IC_QOS         = ${IC_QOS}"
echo "IC_WALLTIME    = ${IC_WALLTIME}"
echo "IC_MODULEFILE  = ${IC_MODULEFILE}"
echo "IC_LOG_DIR     = ${IC_LOG_DIR}"
echo "======================================================"

# -------------------------------------------------------
# Submit SLURM array
# -------------------------------------------------------
sbatch \
    --job-name=wofs_ic_post \
    --partition="${IC_PARTITION}" \
    --qos="${IC_QOS}" \
    --ntasks="${IC_MPI_TASKS}" \
    --time="${IC_WALLTIME}" \
    --array="${IC_PREP_ARRAY:-1-${ENS_SIZE}}" \
    --output="${IC_LOG_DIR}/wofs_ic_post_%A_%a.out" \
    --error="${IC_LOG_DIR}/wofs_ic_post_%A_%a.err" \
    --export="ALL,HOMEwofs=${HOMEwofs},INIT_TIME=${INIT_TIME},IC_PREP_CONFIG=${IC_PREP_CONFIG},IC_PREP_STAGE=POST" \
    "${JOB_SCRIPT}"
