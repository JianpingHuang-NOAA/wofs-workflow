#!/bin/bash
#
# exwofs_bc_prep_mean.sh
#
# WoFS v1 Boundary Condition MEAN workflow.
#
# Computes the ensemble mean WRF input for one GEFS/WoFS cycle.
#
# Called by:
#   jobs/JWOFS_BC_PREP_MEAN
#
# Legacy equivalent:
#   compute_mean.ksh
#

set -euo pipefail

echo
echo "=============================================================="
echo " WoFS BC PREPARATION -- MEAN"
echo "=============================================================="

# ----------------------------------------------------------------------
# Required environment
# ----------------------------------------------------------------------

: "${HOMEwofs:?HOMEwofs must be defined}"
: "${DATAHOME_GEFS:?DATAHOME_GEFS must be defined}"
: "${CYCLE_TIME:?CYCLE_TIME must be defined}"

# ----------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------

export ENS_SIZE="${ENS_SIZE:-18}"
export ENSEMBLE_SIZE="${ENSEMBLE_SIZE:-${ENS_SIZE}}"

export MEAN_PROC="${MEAN_PROC:-40}"

export EXECSWOfS="${EXECSWOfS:-${HOMEwofs}/exec}"
export USHWOfS="${USHWOfS:-${HOMEwofs}/ush}"

export EXEC_ROOT="${EXEC_ROOT:-${EXECSWOfS}}"

# IMPORTANT:
# The legacy MEAN WORK_ROOT is the GEFS cycle directory.
#
#   WORK_ROOT = DATAHOME_GEFS/<CYCLE_TIME>
#
# NOT:
#
#   DATAHOME_GEFS/<CYCLE_TIME>/<lead time>
#
export WORK_ROOT="${WORK_ROOT:-${DATAHOME_GEFS}/${CYCLE_TIME}}"

# ----------------------------------------------------------------------
# Diagnostics
# ----------------------------------------------------------------------

echo "HOMEwofs       = ${HOMEwofs}"
echo "CYCLE_TIME     = ${CYCLE_TIME}"
echo "ENS_SIZE       = ${ENS_SIZE}"
echo "ENSEMBLE_SIZE  = ${ENSEMBLE_SIZE}"
echo "MEAN_PROC      = ${MEAN_PROC}"
echo "EXEC_ROOT      = ${EXEC_ROOT}"
echo "WORK_ROOT      = ${WORK_ROOT}"
echo

# ----------------------------------------------------------------------
# Required directories
# ----------------------------------------------------------------------

if [[ ! -d "${WORK_ROOT}" ]]; then
    echo "ERROR: WORK_ROOT does not exist:"
    echo "       ${WORK_ROOT}"
    exit 1
fi

if [[ ! -d "${WORK_ROOT}/mem01/wrfprd" ]]; then
    echo "ERROR: First ensemble member directory does not exist:"
    echo "       ${WORK_ROOT}/mem01/wrfprd"
    exit 1
fi

# ----------------------------------------------------------------------
# MEAN executable
# ----------------------------------------------------------------------

AVERAGE_EXE="${EXEC_ROOT}/average_netcdf_files_parallel.x"

if [[ ! -x "${AVERAGE_EXE}" ]]; then
    echo "ERROR: MEAN executable does not exist or is not executable:"
    echo "       ${AVERAGE_EXE}"
    exit 1
fi

# ----------------------------------------------------------------------
# Run legacy MEAN workflow
# ----------------------------------------------------------------------

echo "Running compute_mean.ksh"
echo

export EXEC_ROOT
export WORK_ROOT
export ENSEMBLE_SIZE
export MEAN_PROC

"${USHWOfS}/compute_mean.ksh"
rc=$?

if [[ ${rc} -ne 0 ]]; then
    echo
    echo "ERROR: compute_mean.ksh failed with rc=${rc}"
    exit ${rc}
fi

# ----------------------------------------------------------------------
# Validate expected output
# ----------------------------------------------------------------------

MEAN_DIR="${WORK_ROOT}/mean"
MEAN_FILE="${MEAN_DIR}/wrfinput_d01"

if [[ ! -s "${MEAN_FILE}" ]]; then
    echo
    echo "ERROR: MEAN output does not exist or is empty:"
    echo "       ${MEAN_FILE}"
    exit 1
fi

echo
echo "=============================================================="
echo " WoFS BC MEAN completed successfully"
echo "=============================================================="
echo "CYCLE_TIME = ${CYCLE_TIME}"
echo "MEAN_DIR   = ${MEAN_DIR}"
echo "MEAN_FILE  = ${MEAN_FILE}"
echo "=============================================================="
echo

exit 0
