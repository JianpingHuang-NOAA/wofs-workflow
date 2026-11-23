#!/bin/bash
#SBATCH --job-name=wofs_radar_domains
#SBATCH --partition=u1-compute
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=01:00:00

set -euo pipefail
: "${HOMEwofs:?Export HOMEwofs before submission}"
(( $# >= 2 )) || {
    echo "Usage: $0 <output-directory> <shared.yaml> [shared2.yaml ...]" >&2
    exit 2
}

if [[ "${RADAR_LOAD_MODULES:-YES}" == YES ]]; then
    source "$HOMEwofs/versions/obs_radar.ver"
    module use "$HOMEwofs/modulefiles"
    module load "$wofs_modulefile"
fi

exec "${RADAR_CONFIG_PYTHON:-python3}" "$HOMEwofs/ush/prepare_obs_radar_cases.py" "$@"
