#!/bin/bash
#SBATCH -J wofs_ic_post
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH --nodes=1
#SBATCH --ntasks=160
#SBATCH --time=00:10:00
#SBATCH --array=1-36%36
#SBATCH -o wofs_ic_post_%A_%a.out
#SBATCH -e wofs_ic_post_%A_%a.err

set -euo pipefail

# ------------------------------------------------------------
# WoFS workflow root
# ------------------------------------------------------------
: "${HOMEwofs:?HOMEwofs must be set to the WoFS repository root}"
export HOMEwofs

export IC_PREP_CONFIG="${IC_PREP_CONFIG:-${HOMEwofs}/parm/ic_prep/config.yaml}"
export IC_PREP_STAGE=POST

# ------------------------------------------------------------
# SLURM ensemble member
# ------------------------------------------------------------
: "${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required}"

export MEMBER="${SLURM_ARRAY_TASK_ID}"

# Load NCO-style runtime version definitions
source "${HOMEwofs}/versions/run.ver"

# Load the configured Ursa module environment
module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

# ------------------------------------------------------------
# Python interpreter for YAML loader
# ------------------------------------------------------------
# Resolve Python from the loaded WoFS runtime environment.
# Do not depend on a developer-specific Conda installation.
export IC_PREP_PYTHON="${IC_PREP_PYTHON:-$(command -v python3 || true)}"

if [[ -z "${IC_PREP_PYTHON}" ]] ||
   ! "${IC_PREP_PYTHON}" -c \
       'import yaml, numpy, netCDF4, scipy' >/dev/null 2>&1; then
    echo "[ERROR] WoFS IC_PREP Python dependencies are unavailable" >&2
    exit 1
fi

# ------------------------------------------------------------
# Execute J-job
# ------------------------------------------------------------
exec /bin/bash "${HOMEwofs}/jobs/JWOFS_IC_PREP"
