#!/bin/bash
set -euo pipefail
source "${HOMEwofs:?}/versions/obs_radar.ver"
if [[ "${RADAR_LOAD_MODULES:-YES}" == YES ]]; then
    module use "$HOMEwofs/modulefiles"
    module load "$wofs_modulefile"
fi
exec "${RADAR_CONFIG_PYTHON:-python3}" "$HOMEwofs/ush/run_obs_radar.py" "publish" "$@"
