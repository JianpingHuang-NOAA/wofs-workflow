#!/bin/bash
#
# jwofs_bc_prep_meansh
#
# WoFS v1 BC MEAN task.
#
# Computes the ensemble mean WRF input for one GEFS/WoFS cycle.
#
# Required environment:
#   PDY
#   cyc
#
# Optional:
#   ENS_SIZE
#   ENSEMBLE_SIZE
#   MEAN_PROC
#   DATAROOT
#   DATAHOME_GEFS
#   HOMEwofs
#
# Example:
#
#   sbatch \
#       --export=ALL,PDY=20261005,cyc=12 \
#       workflow/shell/bc_prep/jwofs_bc_prep_meansh
#

#SBATCH --job-name=wofs_bc_mean
#SBATCH --partition=u1-compute
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --mem=20G
#SBATCH --time=00:10:00

set -x

# ----------------------------------------------------------------------
# WoFS installation
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd -P)"
export HOMEwofs="${HOMEwofs:-${REPO_ROOT}}"
export DATAROOT="${DATAROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang}"

export PARMWOfS="${PARMWOfS:-${HOMEwofs}/parm}"

# ----------------------------------------------------------------------
# Modules
# ----------------------------------------------------------------------

module use "${HOMEwofs}/modulefiles"
module load ursa_bc_prep

# ----------------------------------------------------------------------
# Cycle
# ----------------------------------------------------------------------

export PDY="${PDY:?PDY must be defined}"
export cyc="${cyc:?cyc must be defined}"

export CYCLE_TIME="${CYCLE_TIME:-${PDY}${cyc}}"

# ----------------------------------------------------------------------
# BC data locations
# ----------------------------------------------------------------------

export DATAHOME_GEFS="${DATAHOME_GEFS:-${DATAROOT}/WoF_BC/gefs}"

# ----------------------------------------------------------------------
# Ensemble
# ----------------------------------------------------------------------

export ENS_SIZE="${ENS_SIZE:-18}"
export ENSEMBLE_SIZE="${ENSEMBLE_SIZE:-${ENS_SIZE}}"

export MEAN_PROC="${MEAN_PROC:-40}"

# ----------------------------------------------------------------------
# MEAN stage
# ----------------------------------------------------------------------

export BC_PREP_STAGE=MEAN

echo
echo "=============================================================="
echo " WoFS BC MEAN"
echo "=============================================================="
echo "SLURM_JOB_ID       = ${SLURM_JOB_ID}"
echo "SLURM_NTASKS       = ${SLURM_NTASKS}"
echo "HOMEwofs           = ${HOMEwofs}"
echo "PDY                = ${PDY}"
echo "cyc                = ${cyc}"
echo "CYCLE_TIME         = ${CYCLE_TIME}"
echo "ENS_SIZE           = ${ENS_SIZE}"
echo "ENSEMBLE_SIZE      = ${ENSEMBLE_SIZE}"
echo "MEAN_PROC          = ${MEAN_PROC}"
echo "DATAHOME_GEFS      = ${DATAHOME_GEFS}"
echo "=============================================================="
echo

# ----------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------

cd "${HOMEwofs}" || exit 1

jobs/JWOFS_BC_PREP_MEAN
rc=$?

if [[ ${rc} -ne 0 ]]; then
    echo
    echo "=============================================================="
    echo " ERROR: WoFS BC MEAN FAILED"
    echo " CYCLE_TIME = ${CYCLE_TIME}"
    echo " rc         = ${rc}"
    echo "=============================================================="
    exit ${rc}
fi

echo
echo "WoFS BC MEAN completed successfully"
echo "CYCLE_TIME=${CYCLE_TIME}"
echo

exit 0
