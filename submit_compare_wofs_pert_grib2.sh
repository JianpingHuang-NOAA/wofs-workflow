#!/bin/bash
set -euo pipefail

CYCLE="${1:-2026111512}"

export HOMEwofs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

REPORT_ROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/compare_pert_grb2_${CYCLE}"

mkdir -p "$REPORT_ROOT/logs"

for m in $(seq -w 1 18); do
    mkdir -p "$REPORT_ROOT/mem${m}"
done

sbatch \
    --array=1-18%18 \
    --output="${REPORT_ROOT}/logs/compare_bc_%A_%a.out" \
    --error="${REPORT_ROOT}/logs/compare_bc_%A_%a.err" \
    --chdir="$REPORT_ROOT" \
    "${HOMEwofs}/run_compare_wofs_pert_grib2_array.slurm" \
    "$CYCLE"

echo "Report root: $REPORT_ROOT"
echo "Log directory: $REPORT_ROOT/logs"

