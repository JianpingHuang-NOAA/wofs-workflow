#!/bin/bash --login
#SBATCH --job-name=wofs_real
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1

set -euo pipefail

: "${HOMEwofs:?HOMEwofs is required}"
: "${REAL_MPI_TASKS:?REAL_MPI_TASKS is required}"

source "$HOMEwofs/versions/build.ver"
source "$HOMEwofs/versions/wps.ver"

module purge

module use "$HOMEwofs/modulefiles"

module load ursa_wrf

export WOFS_PYTHON_ENV="$HOMEwofs/python_env"

export WOFS_PYTHON="$WOFS_PYTHON_ENV/bin/python3"

unset IC_PREP_PYTHON PYTHONPATH PYTHONHOME

export PYTHONNOUSERSITE=1

module list

if [[ "${SLURM_NTASKS:-0}" != "$REAL_MPI_TASKS" ]]; then

    echo "[ERROR] MPI task allocation mismatch"

    exit 1

fi

"$HOMEwofs/jobs/JWOFS_WPS_REAL"
