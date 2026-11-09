#!/bin/bash
# ============================================================================
# jwofs_bc_prep_metgrid.sh
# WoFS v1 BC_PREP METGRID workflow shell wrapper
#
# Purpose:
#   Submit/run the WoFS v1 METGRID J-job for one GEFS member and one
#   forecast valid time.
#
# Required environment:
#   CDATE      WoFS workflow cycle, e.g. 2026100512
#   VALID_TIME GEFS forecast valid time, e.g. 2026100512
#
# Legacy mapping for CDATE=2026100512:
#   GEFS_INIT = 2026100506
#   VALID_TIME = 2026100512 ... 2026100618
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

export HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"

source "${HOMEwofs}/ush/load_bc_prep_config.sh"
source "${HOMEwofs}/versions/bc_prep.ver"

module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

export model=wofs
export cyc="12"

export MEMBER=$(printf "%02d" "${SLURM_ARRAY_TASK_ID}")

if [[ -z "${CDATE:-}" ]]; then
    echo "ERROR: CDATE must be exported before submitting the METGRID job."
    echo "Example: export CDATE=2026100512"
    exit 1
fi

if [[ -z "${VALID_TIME:-}" ]]; then
    echo "ERROR: VALID_TIME must be exported before submitting the METGRID job."
    echo "Example: export VALID_TIME=2026100512"
    exit 1
fi

module list

"${HOMEwofs}/jobs/JWOFS_BC_PREP_METGRID"
