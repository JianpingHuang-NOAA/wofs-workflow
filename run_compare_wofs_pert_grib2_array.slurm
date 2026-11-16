#!/bin/bash
#SBATCH --job-name=compare_bc
#SBATCH --account=wofs
#SBATCH --partition=u1-compute
#SBATCH --qos=batch
#SBATCH --array=1-18%18
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00

set -euo pipefail

: "${HOMEwofs:?HOMEwofs must be set by the submission script}"
export HOMEwofs

CYCLE="${1:-2026111512}"
MEMBER="${SLURM_ARRAY_TASK_ID}"

MEM4="$(printf '%04d' "$MEMBER")"
MEM2="$(printf '%02d' "$MEMBER")"

REPORT_ROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/compare_pert_grb2_${CYCLE}"

source "${HOMEwofs}/versions/bc_prep.ver"

module purge
module use "${HOMEwofs}/modulefiles"
module load "$wofs_modulefile"

export REPORT_DIR="${REPORT_ROOT}/mem${MEM2}"

mkdir -p "$REPORT_DIR"

# Run from the member report directory, not the repository.
cd "$REPORT_DIR"

echo "=================================================="
echo "WoFS BC_PREP GRIB2 Comparison"
echo "Job ID:        $SLURM_JOB_ID"
echo "Array task:    $SLURM_ARRAY_TASK_ID"
echo "Compute node:  $(hostname)"
echo "Cycle:         $CYCLE"
echo "Member:        $MEM4"
echo "Forecast hours: 00-25"
echo "Report dir:    $REPORT_DIR"
echo "Started:       $(date)"
echo "=================================================="

bash "${HOMEwofs}/compare_wofs_pert_grib2.sh" \
    "$CYCLE" "$MEMBER"

