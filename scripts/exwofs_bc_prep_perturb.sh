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

[[ -f "${UTILITY}" ]] || {
    echo "ERROR: Missing utility: ${UTILITY}"
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

# Stage into isolated COM using a verified temporary file.
mkdir -p "${COMOUT}"

STAGED_FILE="${COMOUT}/$(basename "${SOURCE_FILE}")"
TEMP_FILE=$(mktemp "${STAGED_FILE}.tmp.XXXXXXXX")

cleanup_staging() {
    if [[ -n "${TEMP_FILE:-}" ]]; then
        rm -f -- "${TEMP_FILE}"
    fi
}
trap cleanup_staging EXIT

cp -- "${SOURCE_FILE}" "${TEMP_FILE}"

# Verify the entire file before publishing.
if ! cmp -- "${SOURCE_FILE}" "${TEMP_FILE}"; then
    echo "ERROR: Staged copy differs from the working GRIB2"
    exit 1
fi

# Preserve source file permissions before publishing.
chmod --reference="${SOURCE_FILE}" "${TEMP_FILE}"

mv -f -- "${TEMP_FILE}" "${STAGED_FILE}"
TEMP_FILE=""

[[ -s "${STAGED_FILE}" ]] || {
    echo "ERROR: Staged PERTURB output is missing or empty"
    exit 1
}

echo "============================================================"
echo "PERTURB completed successfully"
echo "Staged output: ${STAGED_FILE}"
echo "============================================================"
