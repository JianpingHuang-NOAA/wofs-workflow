#!/bin/bash --login
#SBATCH --job-name=wofs_ungrib
#SBATCH --partition=u1-compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=10G
#SBATCH --time=00:30:00

set -euo pipefail

: "${HOMEwofs:?HOMEwofs is required}"

source "$HOMEwofs/versions/build.ver"
source "$HOMEwofs/versions/wps.ver"

module purge
module use "$HOMEwofs/modulefiles"
module load "$wps_modulefile"

export WOFS_PYTHON_ENV="$HOMEwofs/python_env"
export WOFS_PYTHON="$WOFS_PYTHON_ENV/bin/python3"

unset IC_PREP_PYTHON PYTHONPATH PYTHONHOME

export PYTHONNOUSERSITE=1

module list

"$HOMEwofs/jobs/JWOFS_WPS_UNGRIB"
