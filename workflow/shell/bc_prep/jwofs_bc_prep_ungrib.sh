#!/usr/bin/env bash
#SBATCH -J wofs_bc_ungrib
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH -n 1
#SBATCH -t 00:10:00
#SBATCH --mem-per-cpu=6G
#SBATCH --array=1-18
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC/logs/wofs_bc_ungrib_%A_%a.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC/logs/wofs_bc_ungrib_%A_%a.err

# ============================================================================
# WoFS v1.0 BC_PREP UNGRIB Slurm wrapper
#
# One array task processes one GEFS member.
# Each member processes 11 GEFS valid times.
#
# Scientific processing is performed by:
#   scripts/exwofs_bc_prep_ungrib.sh
# ============================================================================

set -euo pipefail

# ============================================================================
# Repository location
# ============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd -P)"

export HOMEwofs="${HOMEwofs:-${REPO_ROOT}}"

# ============================================================================
# Runtime configuration
# ============================================================================

export DATAROOT="${DATAROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang}"
export DATA="${DATA:-${DATAROOT}}"

# WOFS_PYTHON must provide PyYAML.
# Set this externally in the submission environment.
export WOFS_PYTHON="${WOFS_PYTHON:-python3}"

# ============================================================================
# Load BC_PREP configuration
# ============================================================================

source "${HOMEwofs}/ush/load_bc_prep_config.sh"

# ============================================================================
# BC_PREP runtime environment
# Follow the feature/ic-prep modulefiles/versions convention.
# ============================================================================

source "${HOMEwofs}/versions/bc_prep.ver"

module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

module list

# ============================================================================
# WoFS cycle
# ============================================================================

export model="${model:-wofs}"
export cyc="${cyc:-12}"

# Preserve CDATE supplied by the submission environment.
if [[ -z "${CDATE:-}" ]]; then
    export PDY="${PDY:-$(date -u +%Y%m%d)}"
    export CDATE="${PDY}${cyc}"
fi

# ============================================================================
# GEFS ensemble member
# ============================================================================

if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "ERROR: SLURM_ARRAY_TASK_ID is not defined."
    exit 1
fi

MEMBER_NUM=$((10#${SLURM_ARRAY_TASK_ID}))

if (( MEMBER_NUM < 1 || MEMBER_NUM > ENS_SIZE )); then
    echo "ERROR: Invalid GEFS member ${MEMBER_NUM}"
    exit 1
fi

export MEMBER
MEMBER="$(printf '%02d' "${MEMBER_NUM}")"

# ============================================================================
# Configuration summary
# ============================================================================

echo
echo "============================================================"
echo "WoFS BC_PREP UNGRIB"
echo "============================================================"
echo "HOMEwofs            = ${HOMEwofs}"
echo "BC_PREP_CONFIG      = ${BC_PREP_CONFIG}"
echo "DATAROOT            = ${DATAROOT}"
echo "BC_DATA             = ${BC_DATA}"
echo "CDATE               = ${CDATE}"
echo "MEMBER              = ${MEMBER}"
echo "GEFS_CYCLES         = ${GEFS_CYCLES}"
echo "GEFS_INTERVAL       = ${GEFS_INTERVAL}"
echo "SST_CYCLE           = ${SST_CYCLE}"
echo "SLURM_ARRAY_JOB_ID  = ${SLURM_ARRAY_JOB_ID:-}"
echo "SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID}"
echo "============================================================"

module list

# ============================================================================
# Execute J-job
# ============================================================================

"${HOMEwofs}/jobs/JWOFS_BC_PREP_UNGRIB"

echo "UNGRIB wrapper completed successfully."
date -u
