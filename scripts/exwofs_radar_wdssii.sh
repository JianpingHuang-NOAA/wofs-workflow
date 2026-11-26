#!/bin/bash
set -euo pipefail

# OBS_RADAR execution entry.
export pgm=wofs_radar_wdssii
printf 'JOB %s HAS BEGUN (%s)\n' "${job:-$pgm}" "${BASH_SOURCE[0]##*/}"
printf 'Job ID: %s | CDATE: %s | Domain: %s\n' \
    "${SLURM_JOB_ID:-${jobid:-interactive}}" "${CDATE:-unset}" "${domain:-unset}"
if [[ -n "${RADAR_CASE_YAML:-}" ]]; then
    printf 'Environment case YAML: %s\n' "$RADAR_CASE_YAML"
fi

source "${HOMEwofs:?}/versions/obs_radar.ver"
if [[ "${RADAR_LOAD_MODULES:-YES}" == YES ]]; then
    module use "$HOMEwofs/modulefiles"
    module load "$wofs_modulefile"
fi
source "$HOMEwofs/ush/load_wdssii.sh"
if (( $# == 1 )); then
    exec "${RADAR_CONFIG_PYTHON:-python3}" "$HOMEwofs/ush/run_obs_radar_case.py" "wdssii" "$@"
fi
exec "${RADAR_CONFIG_PYTHON:-python3}" "$HOMEwofs/ush/run_obs_radar.py" "wdssii" "$@"
