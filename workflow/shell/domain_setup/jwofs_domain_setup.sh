#!/bin/bash
#SBATCH --job-name=wofs_domain_setup
#SBATCH --partition=u1-compute
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00

#
# WoFS v1.0 DOMAIN_SETUP Slurm wrapper
#
# Controller:
#   sbatch jwofs_domain_setup.sh
#
# Worker:
#   Automatically submitted with --worker
#

set -euo pipefail

# Determine execution mode.
if [[ "${1:-}" == "--worker" ]]; then

    export DOMAIN_SETUP_MODE=worker
    shift

    : "${HOMEwofs:?HOMEwofs must be defined}"

else

    export DOMAIN_SETUP_MODE=controller

    SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$PWD}"

    if [[ -f "${SUBMIT_DIR}/versions/run.ver" ]]; then

        HOMEwofs="$(cd "${SUBMIT_DIR}" && pwd -P)"

    elif [[ -f "${SUBMIT_DIR}/../../../versions/run.ver" ]]; then

        HOMEwofs="$(cd "${SUBMIT_DIR}/../../.." && pwd -P)"

    else

        echo "[ERROR] Cannot determine HOMEwofs" >&2
        exit 1

    fi

    export HOMEwofs

    unset WOFS_PYTHON IC_PREP_PYTHON
    unset PYTHONPATH PYTHONHOME

    export PYTHONNOUSERSITE=1

fi

cd "${HOMEwofs}"

export DOMAIN_SETUP_CONFIG="${DOMAIN_SETUP_CONFIG:-${HOMEwofs}/parm/domain_setup/config.yaml}"

if [[ ! -r "${DOMAIN_SETUP_CONFIG}" ]]; then
    echo "[ERROR] Missing configuration: ${DOMAIN_SETUP_CONFIG}" >&2
    exit 1
fi

# Load component runtime versions.
source "${HOMEwofs}/versions/domain_setup.ver"

# Initialize Ursa modules.
module purge
module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

# Initialize the appropriate Python runtime.
if [[ "${DOMAIN_SETUP_MODE}" == worker ]]; then

    source "${HOMEwofs}/ush/load_wofs_python.sh"

else

    module load python/3.11

fi

echo "======================================================"
echo " WoFS v1.0 DOMAIN_SETUP"
echo " MODE     = ${DOMAIN_SETUP_MODE}"
echo " HOMEwofs = ${HOMEwofs}"
echo " CONFIG   = ${DOMAIN_SETUP_CONFIG}"
echo " JOBID    = ${SLURM_JOB_ID:-interactive}"
echo "======================================================"

# Execute the NCO-style J-job in both modes.
exec /bin/bash "${HOMEwofs}/jobs/JWOFS_DOMAIN_SETUP" "$@"

