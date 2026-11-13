#!/bin/bash
# ============================================================================
# WoFS v1.0 BC_PREP PERTURB application script
#
# Execute the scientific perturbation algorithm in a private directory.
# The isolated runner holds the working-product lock through COM staging.
#
# HRRR initialization and WoFS forecast cycle are independent.
# Supports both regression and operational execution modes.
# ============================================================================

set -euo pipefail

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

# Required environment.
for VAR in \
    HOMEwofs MEMBER START_TIME FCST_LEAD_TIME WOF_CYCLE_TIME \
    DATAHOME DATAHOME_GEFS HRRR_DIR NCL_SCRIPTS COMROOT \
    WOFS_PYTHON MIN_FILE_SIZE
do
    [[ -n "${!VAR:-}" ]] ||
        die "${VAR} must be defined"
done

export BC_PREP_MODE="${BC_PREP_MODE:-regression}"

export SENDCOM="${SENDCOM:-YES}"
export COM_OVERWRITE="${COM_OVERWRITE:-NO}"
export WORK_OVERWRITE="${WORK_OVERWRITE:-NO}"
export KEEP_INTERMEDIATE="${KEEP_INTERMEDIATE:-NO}"
export KEEP_FAILED_RUN="${KEEP_FAILED_RUN:-NO}"

export TZ=UTC

VALIDATOR="${HOMEwofs}/ush/validate_bc_perturb_paths.sh"
RUNNER="${HOMEwofs}/ush/run_bc_perturb_isolated.sh"

[[ -x "$VALIDATOR" ]] ||
    die "Missing path validator: $VALIDATOR"

[[ -x "$RUNNER" ]] ||
    die "Missing isolated runner: $RUNNER"

[[ -x "$WOFS_PYTHON" ]] ||
    die "Invalid WOFS_PYTHON: $WOFS_PYTHON"

# Validate configuration before dispatching the runner.
"$VALIDATOR"

# Normalize member and forecast-hour identifiers.
printf -v MEM2 '%02d' "$((10#$MEMBER))"
printf -v MEM4 '%04d' "$((10#$MEMBER))"
printf -v FHOUR '%02d' "$((10#$FCST_LEAD_TIME))"

export MEMBER="$MEM2"
export FCST_LEAD_TIME="$FHOUR"

PDY="${WOF_CYCLE_TIME:0:8}"
cyc="${WOF_CYCLE_TIME:8:2}"

FILENAME="wrfnat_pert_hrrr_mem${MEM4}_${FHOUR}.grib2"

SOURCE_FILE="${DATAHOME}/${FILENAME}"
COMOUT="${COMROOT}/wofs.${PDY}/${cyc}/INPUT/mem${MEM2}"
TARGET_FILE="${COMOUT}/${FILENAME}"

echo "============================================================"
echo "WoFS BC_PREP PERTURB"
echo "============================================================"
echo "BC_PREP_MODE     = ${BC_PREP_MODE}"
echo "START_TIME       = ${START_TIME}"
echo "FCST_LEAD_TIME   = ${FHOUR}"
echo "MEMBER           = ${MEM2}"
echo "WOF_CYCLE_TIME   = ${WOF_CYCLE_TIME}"
echo "DATAHOME         = ${DATAHOME}"
echo "DATAHOME_GEFS    = ${DATAHOME_GEFS}"
echo "COMOUT           = ${COMOUT}"
echo "WOFS_PYTHON      = ${WOFS_PYTHON}"
echo "SENDCOM          = ${SENDCOM}"
echo "WORK_OVERWRITE   = ${WORK_OVERWRITE}"
echo "COM_OVERWRITE    = ${COM_OVERWRITE}"
echo "KEEP_INTERMEDIATE = ${KEEP_INTERMEDIATE}"
echo "KEEP_FAILED_RUN   = ${KEEP_FAILED_RUN}"
echo "============================================================"

# The runner manages scientific execution, working publication,
# COM staging, interruption recovery, locking, and cleanup.
#
# A nonzero runner status must terminate the application.
"$RUNNER"

# The runner has already validated publication under its locks.
# Report completion without repeating unlocked file operations.
echo "============================================================"
echo "PERTURB completed successfully"
echo "Working output: ${SOURCE_FILE}"

if [[ "$SENDCOM" == YES ]]; then
    echo "Staged output: ${TARGET_FILE}"
else
    echo "COM publication skipped: SENDCOM=NO"
fi

echo "============================================================"
