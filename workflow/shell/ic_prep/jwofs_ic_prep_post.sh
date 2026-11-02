#!/bin/bash
#SBATCH -J wofs_ic_post
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH --nodes=1
#SBATCH --ntasks=160
#SBATCH --time=00:10:00
#SBATCH --array=1-36%36
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_post_%A_%a.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_post_%A_%a.err

set -euo pipefail

# ------------------------------------------------------------
# WoFS workflow root
# ------------------------------------------------------------
export HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"

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
export IC_PREP_PYTHON="${IC_PREP_PYTHON:-/scratch3/NAGAPE/wof/ywang/conda/wofs_post/bin/python}"

# ------------------------------------------------------------
# Execute J-job
# ------------------------------------------------------------
exec /bin/bash "${HOMEwofs}/jobs/JWOFS_IC_PREP"
