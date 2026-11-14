#!/bin/bash
#SBATCH -J wofs_ic_download
#SBATCH -p u1-service
#SBATCH -n 1
#SBATCH --mem=12G
#SBATCH -t 00:45:00
#SBATCH -o wofs_ic_download_%j.out
#SBATCH -e wofs_ic_download_%j.err

set -euo pipefail

# ============================================================
# WoFS IC_PREP - HRRRDAS Download SLURM Wrapper
#
# Responsibilities:
#   1. Define HOMEwofs
#   2. Locate IC_PREP configuration
#   3. Initialize required modules
#   4. Execute jobs/JWOFS_IC_DOWNLOAD
# ============================================================

# ------------------------------------------------------------
# 1. Define workflow root
# ------------------------------------------------------------
: "${HOMEwofs:?HOMEwofs must be set to the WoFS repository root}"

export HOMEwofs

# Locate the IC_PREP configuration.
export IC_PREP_CONFIG="${IC_PREP_CONFIG:-${HOMEwofs}/parm/ic_prep/config.yaml}"

if [[ ! -r "${IC_PREP_CONFIG}" ]]; then
    echo "[ERROR] Configuration file not found: ${IC_PREP_CONFIG}" >&2
    exit 1
fi

# ------------------------------------------------------------
# 2. Initialize environment modules
# ------------------------------------------------------------
if ! type module >/dev/null 2>&1; then
    if [[ -f /etc/profile.d/modules.sh ]]; then
        source /etc/profile.d/modules.sh
    elif [[ -f /usr/share/lmod/lmod/init/bash ]]; then
        source /usr/share/lmod/lmod/init/bash
    fi
fi

# Load centralized runtime version definitions.
VERSION_FILE="${HOMEwofs}/versions/run.ver"

if [[ ! -r "${VERSION_FILE}" ]]; then
    echo "[ERROR] Runtime version file not found: ${VERSION_FILE}" >&2
    exit 1
fi

source "${VERSION_FILE}"

# ------------------------------------------------------------
# Initialize Python for the YAML configuration loader.
# ------------------------------------------------------------
if [[ -z "${WOFS_PYTHON:-}" ]]; then

    if ! type module >/dev/null 2>&1; then
        echo "[ERROR] Environment modules unavailable" >&2
        exit 1
    fi

    : "${python_ver:?python_ver must be defined in run.ver}"

    module load "python/${python_ver}"

    export WOFS_PYTHON="$(command -v python3 || true)"

fi

if [[ -z "${WOFS_PYTHON:-}" ]]; then
    echo "[ERROR] Python interpreter unavailable" >&2
    exit 1
fi

if ! "${WOFS_PYTHON}" -c 'import yaml'; then
    echo "[ERROR] PyYAML unavailable in ${WOFS_PYTHON}" >&2
    exit 1
fi

echo "[PASS] DOWNLOAD Python environment validated"
echo "WOFS_PYTHON: ${WOFS_PYTHON}"

"${WOFS_PYTHON}" -c 'import yaml; print("PyYAML:", yaml.__version__)'


# ------------------------------------------------------------
# 3. Locate download job
# ------------------------------------------------------------
JOB_SCRIPT="${HOMEwofs}/jobs/JWOFS_IC_DOWNLOAD"

if [[ ! -f "${JOB_SCRIPT}" ]]; then
    echo "[ERROR] Job script not found: ${JOB_SCRIPT}" >&2
    exit 1
fi

# 4. Print environment summary
# ------------------------------------------------------------
echo "=========================================="
echo "WoFS IC_PREP - HRRRDAS Download"
echo "=========================================="
echo "HOMEwofs       : ${HOMEwofs}"
echo "IC_PREP_CONFIG : ${IC_PREP_CONFIG}"
echo "wofs_ver       : ${wofs_ver:-undefined}"
echo "JOB_SCRIPT     : ${JOB_SCRIPT}"
echo "SLURM_JOB_ID   : ${SLURM_JOB_ID:-N/A}"
echo "=========================================="

# ------------------------------------------------------------
# 5. Execute download job
# ------------------------------------------------------------
exec /bin/bash "${JOB_SCRIPT}"
