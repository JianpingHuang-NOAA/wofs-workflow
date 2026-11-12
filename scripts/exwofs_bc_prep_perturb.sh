#!/bin/bash
# ============================================================================
# WoFS v1.0 BC_PREP PERTURB application script
#
# Runs the legacy scientific perturbation utility and stages GRIB2 output.
# HRRR initialization and WoFS forecast cycle are independent.
# ============================================================================

set -euo pipefail

# Required environment
for VAR in \
    HOMEwofs MEMBER START_TIME FCST_LEAD_TIME WOF_CYCLE_TIME \
    DATAHOME DATAHOME_GEFS HRRR_DIR NCL_SCRIPTS COMROOT
do
    if [[ -z "${!VAR:-}" ]]; then
        echo "ERROR: ${VAR} must be defined"
        exit 1
    fi
done

[[ "${START_TIME}" =~ ^[0-9]{10}$ ]] || exit 1
[[ "${WOF_CYCLE_TIME}" =~ ^[0-9]{10}$ ]] || exit 1
[[ "${MEMBER}" =~ ^[0-9]{1,2}$ ]] || exit 1
[[ "${FCST_LEAD_TIME}" =~ ^[0-9]{1,2}$ ]] || exit 1

MEMBER_NUM=$((10#${MEMBER}))
FHOUR_NUM=$((10#${FCST_LEAD_TIME}))

(( MEMBER_NUM >= 1 && MEMBER_NUM <= 18 )) || exit 1
(( FHOUR_NUM >= 0 && FHOUR_NUM <= 25 )) || exit 1

MEM2=$(printf "%02d" "${MEMBER_NUM}")
MEM4=$(printf "%04d" "${MEMBER_NUM}")
FHOUR=$(printf "%02d" "${FHOUR_NUM}")

PDY="${WOF_CYCLE_TIME:0:8}"
cyc="${WOF_CYCLE_TIME:8:2}"

SOURCE_FILE="${DATAHOME}/wrfnat_pert_hrrr_mem${MEM4}_${FHOUR}.grib2"
COMOUT="${COMROOT}/wofs.${PDY}/${cyc}/INPUT/mem${MEM2}"

# ---------------------------------------------------------------------------
# Safety checks: prohibit historical output locations
# ---------------------------------------------------------------------------

HISTORICAL_PERTURB_ROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC/pert_hrrr"
HISTORICAL_COMROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/com/wofs/v1.0"

# Resolve paths, including symlinks and relative components.
DATAHOME_RESOLVED=$(realpath -m "${DATAHOME}")
COMROOT_RESOLVED=$(realpath -m "${COMROOT}")
HIST_PERTURB_RESOLVED=$(realpath -m "${HISTORICAL_PERTURB_ROOT}")
HIST_COM_RESOLVED=$(realpath -m "${HISTORICAL_COMROOT}")

case "${DATAHOME_RESOLVED}/" in
    "${HIST_PERTURB_RESOLVED}/"*)
        echo "ERROR: DATAHOME points into historical PERTURB outputs"
        exit 1
        ;;
esac

case "${COMROOT_RESOLVED}/" in
    "${HIST_COM_RESOLVED}/"*)
        echo "ERROR: COMROOT points into historical COM outputs"
        exit 1
        ;;
esac

# Restrict this test to the isolated test tree.
: "${TEST_ROOT:?ERROR: TEST_ROOT must be defined}"

TEST_ROOT_RESOLVED=$(realpath -m "${TEST_ROOT}")

case "${DATAHOME_RESOLVED}/" in
    "${TEST_ROOT_RESOLVED}/"*) ;;
    *)
        echo "ERROR: DATAHOME must be inside TEST_ROOT"
        exit 1
        ;;
esac

case "${COMROOT_RESOLVED}/" in
    "${TEST_ROOT_RESOLVED}/"*) ;;
    *)
        echo "ERROR: COMROOT must be inside TEST_ROOT"
        exit 1
        ;;
esac

UTILITY="${HOMEwofs}/ush/perturb_hrrr.ksh"
STAGER="${HOMEwofs}/ush/stage_bc_perturb.sh"

[[ -x "${UTILITY}" ]] || {
    echo "ERROR: Missing or non-executable utility: ${UTILITY}"
    exit 1
}

[[ -x "${STAGER}" ]] || {
    echo "ERROR: Missing or non-executable staging utility: ${STAGER}"
    exit 1
}

export SENDCOM="${SENDCOM:-YES}"
export COM_OVERWRITE="${COM_OVERWRITE:-NO}"

[[ "${SENDCOM}" == YES || "${SENDCOM}" == NO ]] || {
    echo "ERROR: Invalid SENDCOM"
    exit 1
}

[[ "${COM_OVERWRITE}" == YES || "${COM_OVERWRITE}" == NO ]] || {
    echo "ERROR: Invalid COM_OVERWRITE"
    exit 1
}

echo "============================================================"
echo "WoFS BC_PREP PERTURB"
echo "============================================================"
echo "START_TIME       = ${START_TIME}"
echo "FCST_LEAD_TIME   = ${FHOUR}"
echo "MEMBER           = ${MEM2}"
echo "WOF_CYCLE_TIME   = ${WOF_CYCLE_TIME}"
echo "DATAHOME         = ${DATAHOME_RESOLVED}"
echo "DATAHOME_GEFS    = ${DATAHOME_GEFS}"
echo "COMOUT           = ${COMOUT}"
echo "============================================================"

# Run the original scientific perturbation algorithm.
"${UTILITY}"

# Verify generated output.
if [[ ! -s "${SOURCE_FILE}" ]]; then
    echo "ERROR: Missing PERTURB output: ${SOURCE_FILE}"
    exit 1
fi

ls -lh "${SOURCE_FILE}"

# Publish through the shared BC_PREP staging utility.
echo "SENDCOM          = ${SENDCOM}"
echo "COM_OVERWRITE    = ${COM_OVERWRITE}"

"${STAGER}"

echo "============================================================"
echo "PERTURB completed successfully"

if [[ "${SENDCOM}" == YES ]]; then
    echo "Staged output: ${COMOUT}/$(basename "${SOURCE_FILE}")"
else
    echo "COM publication skipped: SENDCOM=NO"
    echo "Working output: ${SOURCE_FILE}"
fi

echo "============================================================"
