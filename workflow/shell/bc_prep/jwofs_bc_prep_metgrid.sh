#!/bin/bash
# ============================================================================
# jwofs_bc_prep_metgrid.sh
# WoFS v1.0 BC_PREP METGRID workflow shell wrapper
#
# Purpose:
#   Run the WoFS METGRID J-job for one GEFS member and one
#   forecast valid time.
#
# Required environment:
#   HOMEwofs   WoFS workflow repository
#   CDATE      WoFS workflow cycle, e.g. 2026111212
#   VALID_TIME GEFS forecast valid time, e.g. 2026111212
#   DATAROOT   Runtime data directory
#
# Legacy mapping for CDATE=2026111212:
#   GEFS_INIT = 2026111206
#   VALID_TIME = 2026111212 ... 2026111318
#   FCST_HOUR = 6 ... 36
# ============================================================================

#SBATCH -J wofs_bc_metgrid
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH -n 40
#SBATCH -t 00:10:00
#SBATCH --mem=32G
#SBATCH --array=1-18
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC/logs/wofs_bc_metgrid_%A_%a.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC/logs/wofs_bc_metgrid_%A_%a.err

set -euo pipefail

# ============================================================================
# Repository location
# ============================================================================

: "${HOMEwofs:?ERROR: HOMEwofs must be exported before submission}"

export HOMEwofs

if [[ ! -f "${HOMEwofs}/versions/run.ver" ]]; then
    echo "ERROR: Invalid HOMEwofs: ${HOMEwofs}" >&2
    exit 1
fi

# ============================================================================
# Runtime environment
# Load modules before parsing YAML configuration.
# ============================================================================

source "${HOMEwofs}/versions/run.ver"
source "${HOMEwofs}/versions/bc_prep.ver"

module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

# Preserve an explicitly supplied Python interpreter.
export WOFS_PYTHON="${WOFS_PYTHON:-$(command -v python3 || true)}"

echo "WOFS_PYTHON = ${WOFS_PYTHON}"

# ============================================================================
# Load BC_PREP configuration
# ============================================================================

source "${HOMEwofs}/ush/load_bc_prep_config.sh"

# ============================================================================
# WoFS cycle and forecast valid time
# ============================================================================

export model="${model:-wofs}"

if [[ ! "${CDATE:-}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: CDATE must be YYYYMMDDHH." >&2
    exit 1
fi

if [[ ! "${VALID_TIME:-}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: VALID_TIME must be YYYYMMDDHH." >&2
    exit 1
fi

export PDY="${CDATE:0:8}"
export cyc="${CDATE:8:2}"

# ============================================================================
# GEFS ensemble member
# ============================================================================

if [[ ! "${SLURM_ARRAY_TASK_ID:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid SLURM_ARRAY_TASK_ID." >&2
    exit 1
fi

MEMBER_NUM=$((10#${SLURM_ARRAY_TASK_ID}))

if (( MEMBER_NUM < 1 || MEMBER_NUM > ENS_SIZE )); then
    echo "ERROR: Invalid GEFS member: ${MEMBER_NUM}" >&2
    exit 1
fi

export MEMBER
MEMBER="$(printf '%02d' "${MEMBER_NUM}")"

# ============================================================================
# Configuration summary
# ============================================================================

echo
echo "============================================================"
echo "WoFS BC_PREP METGRID"
echo "============================================================"
echo "HOMEwofs            = ${HOMEwofs}"
echo "BC_PREP_CONFIG      = ${BC_PREP_CONFIG}"
echo "WOFS_PYTHON         = ${WOFS_PYTHON}"
echo "DATAROOT            = ${DATAROOT}"
echo "BC_DATA             = ${BC_DATA}"
echo "PDY                 = ${PDY}"
echo "cyc                 = ${cyc}"
echo "CDATE               = ${CDATE}"
echo "VALID_TIME          = ${VALID_TIME}"
echo "MEMBER              = ${MEMBER}"
echo "ENS_SIZE            = ${ENS_SIZE}"
echo "METGRID_PROC        = ${METGRID_PROC}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS:-}"
echo "SLURM_ARRAY_JOB_ID  = ${SLURM_ARRAY_JOB_ID:-}"
echo "SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID}"
echo "============================================================"

module list

# ============================================================================
# Execute J-job
# ============================================================================

"${HOMEwofs}/jobs/JWOFS_BC_PREP_METGRID"

echo "METGRID wrapper completed successfully."
date -u

