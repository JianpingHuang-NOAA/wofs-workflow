#!/bin/bash
#SBATCH -q batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:30:00
#SBATCH -o wofs_obs_radar_download.out
#SBATCH -e wofs_obs_radar_download.err
#SBATCH --job-name=wofs_radar_download
#SBATCH --partition=u1-service
#SBATCH --mem=2G

set -euo pipefail
# Resolve HOMEwofs from the submission directory.
if [[ -z "${HOMEwofs:-}" ]]; then
    submit_dir="${SLURM_SUBMIT_DIR:-$PWD}"
    if [[ ! -x "$submit_dir/jobs/JWOFS_RADAR_DOWNLOAD" ]]; then
        printf 'ERROR: Submit from the WoFS repository root or export HOMEwofs.\n' >&2
        exit 1
    fi
    export HOMEwofs="$submit_dir"
fi
: "${HOMEwofs:?Export HOMEwofs before submission}"

# Initialize the OBS_RADAR runtime.
source "$HOMEwofs/versions/obs_radar.ver"

if [[ "${RADAR_LOAD_MODULES:-YES}" == YES ]]; then
    module purge
    module use "$HOMEwofs/modulefiles"
    module load "$wofs_modulefile"
    module list
fi

export WOFS_PYTHON_ENV="$HOMEwofs/python_env"
export WOFS_PYTHON="$WOFS_PYTHON_ENV/bin/python3"
export RADAR_CONFIG_PYTHON="${RADAR_CONFIG_PYTHON:-$WOFS_PYTHON}"

unset PYTHONPATH PYTHONHOME
export PYTHONNOUSERSITE=1

if [[ ! -x "$RADAR_CONFIG_PYTHON" ]]; then
    printf '[ERROR] Radar Python is not executable: %s\n' "$RADAR_CONFIG_PYTHON" >&2
    exit 1
fi

if [[ -n "${SLURM_JOB_ID:-}" && "${SLURM_NTASKS:-0}" != 1 ]]; then
    printf '[ERROR] OBS_RADAR requires one Slurm task. Allocated: %s\n' \
        "${SLURM_NTASKS:-0}" >&2
    exit 1
fi

# The execution script inherits this runtime from the wrapper.
export RADAR_LOAD_MODULES=NO

exec "$HOMEwofs/jobs/JWOFS_RADAR_DOWNLOAD" "$@"
