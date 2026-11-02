#!/bin/bash
#SBATCH -J wofs_ic_download
#SBATCH -p u1-service
#SBATCH -n 1
#SBATCH --mem=12G
#SBATCH -t 00:45:00
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_download_%j.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_download_%j.err

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
export HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"

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

# Load additional modules here if required by download script.
# Example:
# module load python

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
echo "JOB_SCRIPT     : ${JOB_SCRIPT}"
echo "SLURM_JOB_ID   : ${SLURM_JOB_ID:-N/A}"
echo "=========================================="

# ------------------------------------------------------------
# 5. Execute download job
# ------------------------------------------------------------
exec /bin/bash "${JOB_SCRIPT}"
