#!/bin/bash
# ============================================================================
# exwofs_bc_prep_ungrib.sh
# WoFS v1 boundary-condition preparation UNGRIB application script
#
# Called by:
#   jobs/JWOFS_BC_PREP_UNGRIB
#
# Purpose:
#   Process the WoFS v1 GEFS boundary-condition inputs for one ensemble
#   member. Process 11 GEFS forecast hours (06-36 UTC every 3 hours) and
#   one high-resolution SST input.
#
# Example:
#   WoFS cycle:          2026100512
#   GEFS initialization: 2026100506
#   GEFS forecast hours: 06 09 12 15 18 21 24 27 30 33 36
#   Valid times:         2026100512 through 2026100618
#   SST source date:     20261004
#
# MEMBER is supplied by JWOFS_BC_PREP_UNGRIB from the Slurm array task.
#
# SST handling:
#   SST is common to all ensemble members.  Therefore only MEMBER=01
#   performs the SST UNGRIB operation.  Members 02-18 wait for the
#   SST_UNGRIB_DONE completion marker before continuing.
# ============================================================================

set -e

export EXECwofs="${EXECwofs:-${HOMEwofs}/exec}"
export UNGRIB_EXE="${UNGRIB_EXE:-${EXECwofs}/ungrib.exe}"
export WPS_NAMELIST="${FIXwofs}/WPS/namelist.wps.GFSENS"
export SST_VTABLE="${FIXwofs}/WPS/Vtable.SST"

export GEFS_WORK="${BC_DATA}/gefs"
export LOG_DIR="${BC_DATA}/logs"

# ----------------------------------------------------------------------------
# Basic checks
# ----------------------------------------------------------------------------

if [[ -z "${CDATE:-}" ]]; then
    echo "ERROR: CDATE is not defined."
    exit 1
fi

if [[ -z "${MEMBER:-}" ]]; then
    echo "ERROR: MEMBER is not defined."
    exit 1
fi

if [[ ! -x "${UNGRIB_EXE}" ]]; then
    echo "ERROR: WPS UNGRIB executable not found:"
    echo "  ${UNGRIB_EXE}"
    exit 1
fi

if [[ ! -f "${WPS_NAMELIST}" ]]; then
    echo "ERROR: WPS namelist not found:"
    echo "  ${WPS_NAMELIST}"
    exit 1
fi

if [[ ! -f "${SST_VTABLE}" ]]; then
    echo "ERROR: SST Vtable not found:"
    echo "  ${SST_VTABLE}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Determine GEFS initialization time and the 11 GEFS valid times
#
# WoFS cycle 2026100512
#   GEFS initialization = 2026100506
#
# Valid times:
#   2026100512
#   2026100515
#   2026100518
#   2026100521
#   2026100600
#   2026100603
#   2026100606
#   2026100609
#   2026100612
#   2026100615
#   2026100618
# ----------------------------------------------------------------------------

CDATE_ISO="${CDATE:0:4}-${CDATE:4:2}-${CDATE:6:2} ${CDATE:8:2}:00:00"
CDATE_EPOCH="$(date -u -d "${CDATE_ISO}" +%s)"

GEFS_INIT_EPOCH=$((CDATE_EPOCH - 21600))

GEFS_INIT="$(date -u -d "@${GEFS_INIT_EPOCH}" +%Y%m%d%H)"
GEFS_INIT_ISO="$(date -u -d "@${GEFS_INIT_EPOCH}" '+%Y-%m-%d %H:%M:%S')"

GEFS_CYCLE_LIST=()

for ((n=0; n<GEFS_CYCLES; n++)); do

    GEFS_VALID_EPOCH=$((CDATE_EPOCH + n * GEFS_INTERVAL * 3600))

    GEFS_VALID_TIME="$(
        date -u -d "@${GEFS_VALID_EPOCH}" +%Y%m%d%H
    )"

    GEFS_CYCLE_LIST+=("${GEFS_VALID_TIME}")

done

echo "============================================================"
echo "WoFS v1 BC UNGRIB"
echo "============================================================"
echo "CDATE=${CDATE}"
echo "CDATE_ISO=${CDATE_ISO}"
echo "GEFS_INIT=${GEFS_INIT}"
echo "GEFS_INIT_ISO=${GEFS_INIT_ISO}"
echo "MEMBER=${MEMBER}"
echo "GEFS_CYCLES=${GEFS_CYCLES}"
echo "GEFS_INTERVAL=${GEFS_INTERVAL}"
echo "GEFS_CYCLE_LIST=${GEFS_CYCLE_LIST[*]}"
echo "GEFS_DIR=${GEFS_DIR}"
echo "HIGHRES_SST_DIR=${HIGHRES_SST_DIR}"
echo "GEFS_WORK=${GEFS_WORK}"
echo "============================================================"

mkdir -p "${GEFS_WORK}" "${LOG_DIR}"

# ----------------------------------------------------------------------------
# Determine SST source
#
# For GEFS initialization 2026100506:
#   SST source date = 20261004
#   SST YJ          = 26278
# ----------------------------------------------------------------------------

GEFS_INIT_EPOCH="$(date -u -d "${GEFS_INIT_ISO}" +%s)"

SST_EPOCH=$((GEFS_INIT_EPOCH - 86400))

SST_DATE="$(date -u -d "@${SST_EPOCH}" +%Y%m%d)"
SST_YJ="$(date -u -d "@${SST_EPOCH}" +%y%j)"

SST_FILE="${HIGHRES_SST_DIR}/${SST_YJ}00000000"

SST_DATE_WPS="$(
    date -u -d "${SST_DATE} 00:00:00" +%Y-%m-%d
)_00:00:00"

echo "SST_DATE=${SST_DATE}"
echo "SST_YJ=${SST_YJ}"
echo "SST_FILE=${SST_FILE}"
echo "SST_DATE_WPS=${SST_DATE_WPS}"

if [[ ! -f "${SST_FILE}" ]]; then

    echo "ERROR: SST input file not found:"
    echo "  ${SST_FILE}"

    exit 1

fi

# ----------------------------------------------------------------------------
# Common SST directories
#
# IMPORTANT:
#   These directories are shared by all 18 Slurm array tasks.
#
#   Therefore only MEMBER=01 is allowed to run SST UNGRIB.
# ----------------------------------------------------------------------------

SST_WORK="${GEFS_WORK}/${GEFS_INIT}/sst"
SST_EXTPRD="${SST_WORK}/extprd"
SST_UNGRIB_WORK="${SST_WORK}/ungrib"

SST_DONE="${SST_WORK}/SST_UNGRIB_DONE"
SST_FAILED="${SST_WORK}/SST_UNGRIB_FAILED"

mkdir -p "${SST_WORK}"

# ----------------------------------------------------------------------------
# SST UNGRIB
#
# Only MEMBER=01 performs the SST UNGRIB.
#
# This prevents the 18 Slurm array tasks from simultaneously modifying:
#
#   ${GEFS_WORK}/${GEFS_INIT}/sst/ungrib
#
# which previously caused PFILE/SST:* race conditions.
# ----------------------------------------------------------------------------

if [[ "${MEMBER}" == "01" ]]; then

    echo "============================================================"
    echo "SST UNGRIB"
    echo "============================================================"
    echo "MEMBER=${MEMBER}"
    echo "MEMBER 01 is responsible for SST UNGRIB."
    echo "SST_WORK=${SST_WORK}"
    echo "SST_UNGRIB_WORK=${SST_UNGRIB_WORK}"
    echo "============================================================"

    # Remove stale status markers from this run.
    rm -f "${SST_DONE}" "${SST_FAILED}"

    mkdir -p "${SST_EXTPRD}" "${SST_UNGRIB_WORK}"

    cd "${SST_UNGRIB_WORK}"

    rm -f FILE:* SST:* GRIBFILE.AAA Vtable

    cp "${WPS_NAMELIST}" namelist.wps

    sed -i \
        "s|^[[:space:]]*prefix[[:space:]]*=.*| prefix = 'SST',|" \
        namelist.wps

    sed -i \
        "s|^[[:space:]]*start_date[[:space:]]*=.*| start_date = '${SST_DATE_WPS}',|" \
        namelist.wps

    sed -i \
        "s|^[[:space:]]*end_date[[:space:]]*=.*| end_date = '${SST_DATE_WPS}',|" \
        namelist.wps

    sed -i \
        "s|^[[:space:]]*fg_name[[:space:]]*=.*| fg_name = 'SST',|" \
        namelist.wps

    ln -sf "${SST_FILE}" GRIBFILE.AAA
    ln -sf "${SST_VTABLE}" Vtable

    echo "------------------------------------------------------------"
    echo "Running SST UNGRIB"
    echo "SST_FILE=${SST_FILE}"
    echo "SST_DATE_WPS=${SST_DATE_WPS}"
    echo "GRIBFILE.AAA -> $(readlink GRIBFILE.AAA)"
    echo "Vtable -> $(readlink Vtable)"
    echo "------------------------------------------------------------"

    if ! "${UNGRIB_EXE}"; then

        echo "ERROR: SST UNGRIB failed."

        touch "${SST_FAILED}"

        exit 1

    fi

    if ! compgen -G "SST:*" > /dev/null; then

        echo "ERROR: SST UNGRIB produced no SST:* output."
        echo "SST_UNGRIB_WORK=${SST_UNGRIB_WORK}"

        touch "${SST_FAILED}"

        exit 1

    fi

    SST_OUTPUT="$(compgen -G "SST:*" | head -1)"

    if [[ -z "${SST_OUTPUT}" ]]; then

        echo "ERROR: Unable to identify SST UNGRIB output."

        touch "${SST_FAILED}"

        exit 1

    fi

    SST_OUTPUT_NAME="$(basename "${SST_OUTPUT}")"

    ln -sfn \
        "${SST_UNGRIB_WORK}/${SST_OUTPUT_NAME}" \
        "${SST_EXTPRD}/${SST_OUTPUT_NAME}"

    ln -sfn \
        "${SST_OUTPUT_NAME}" \
        "${SST_EXTPRD}/SST"

    echo "SST_OUTPUT=${SST_OUTPUT_NAME}"
    echo "SST_LINK=${SST_EXTPRD}/SST"

    # ------------------------------------------------------------------------
    # SST is now complete.
    #
    # Create the completion marker only after the SST output and SST link
    # have been successfully created.
    # ------------------------------------------------------------------------

    touch "${SST_DONE}"

    echo "============================================================"
    echo "SST UNGRIB COMPLETED SUCCESSFULLY"
    echo "SST_DONE=${SST_DONE}"
    echo "============================================================"

else

    # ------------------------------------------------------------------------
    # Members 02-18 wait for MEMBER=01 to finish SST UNGRIB.
    # ------------------------------------------------------------------------

    echo "============================================================"
    echo "WAITING FOR SST UNGRIB"
    echo "============================================================"
    echo "MEMBER=${MEMBER}"
    echo "SST_DONE=${SST_DONE}"
    echo "SST_FAILED=${SST_FAILED}"
    echo "============================================================"

    SST_WAIT_SECONDS=0
    SST_WAIT_MAX=600

    while [[ ! -f "${SST_DONE}" && ! -f "${SST_FAILED}" ]]; do

        if (( SST_WAIT_SECONDS >= SST_WAIT_MAX )); then

            echo "ERROR: Timed out waiting for SST UNGRIB."
            echo "SST_DONE=${SST_DONE}"
            echo "SST_FAILED=${SST_FAILED}"

            exit 1

        fi

        sleep 5

        SST_WAIT_SECONDS=$((SST_WAIT_SECONDS + 5))

    done

    if [[ -f "${SST_FAILED}" ]]; then

        echo "ERROR: SST UNGRIB failed in MEMBER=01."
        echo "SST_FAILED=${SST_FAILED}"

        exit 1

    fi

    if [[ ! -f "${SST_DONE}" ]]; then

        echo "ERROR: SST completion marker not found."

        exit 1

    fi

    if [[ ! -L "${SST_EXTPRD}/SST" ]]; then

        echo "ERROR: SST link does not exist:"
        echo "  ${SST_EXTPRD}/SST"

        exit 1

    fi

    echo "SST UNGRIB completed successfully by MEMBER=01."
    echo "SST_LINK=${SST_EXTPRD}/SST"
    echo "Waited ${SST_WAIT_SECONDS} seconds."

fi

# ----------------------------------------------------------------------------
# GEFS ensemble member processing
#
# Each Slurm array task processes one GEFS ensemble member.
#
# For each member, process:
#
#   2026100512
#   2026100515
#   2026100518
#   2026100521
#   2026100600
#   2026100603
#   2026100606
#   2026100609
#   2026100612
#   2026100615
#   2026100618
#
# GEFS input forecast hour starts at 06 and increases by 3 hours.
# ----------------------------------------------------------------------------

GEFS_INIT_YJH="$(date -u -d "${GEFS_INIT_ISO}" +%y%j%H)"

GEFS_MEMBER_DIR="${GEFS_DIR}/pgrb2b/gep${MEMBER}"

#MEMBER_WORK="${GEFS_WORK}/${GEFS_INIT}/mem${MEMBER}"
#mkdir -p "${MEMBER_WORK}"

FCST_HOUR=6

for GEFS_VALID_TIME in "${GEFS_CYCLE_LIST[@]}"; do

    GEFS_VALID_TIME_ISO="${GEFS_VALID_TIME:0:4}-${GEFS_VALID_TIME:4:2}-${GEFS_VALID_TIME:6:2} ${GEFS_VALID_TIME:8:2}:00:00"

    GEFS_VALID_TIME_WPS="$(
        date -u -d "${GEFS_VALID_TIME_ISO}" +%Y-%m-%d_%H:%M:%S
    )"

    # ------------------------------------------------------------------------
    # GEFS GRIB2 filename
    #
    # The public GEFS directory has historically contained both filename
    # forms, so check both formats.
    # ------------------------------------------------------------------------

    GEFS_FILE_5="${GEFS_MEMBER_DIR}/${GEFS_INIT_YJH}00000${FCST_HOUR}"
    GEFS_FILE_4="${GEFS_MEMBER_DIR}/${GEFS_INIT_YJH}0000${FCST_HOUR}"

    if [[ -f "${GEFS_FILE_5}" ]]; then

        GEFS_INPUT="${GEFS_FILE_5}"

    elif [[ -f "${GEFS_FILE_4}" ]]; then

        GEFS_INPUT="${GEFS_FILE_4}"

    else

        echo "ERROR: GEFS input file not found."
        echo "  Tried:"
        echo "    ${GEFS_FILE_5}"
        echo "    ${GEFS_FILE_4}"

        exit 1

    fi

    # ------------------------------------------------------------------------
    # Work directories for this member and valid time
    # ------------------------------------------------------------------------

    VALID_WORK="${GEFS_WORK}/${GEFS_VALID_TIME}/mem${MEMBER}"

    VALID_EXTPRD="${VALID_WORK}/extprd"

    UNGRIB_WORK="${VALID_WORK}/ungrib"

    mkdir -p "${VALID_EXTPRD}" "${UNGRIB_WORK}"

    cd "${UNGRIB_WORK}"

    # Clean only this member's private UNGRIB directory.
    rm -f FILE:* GFSENS:* GRIBFILE.AAA Vtable

    cp "${WPS_NAMELIST}" namelist.wps

    sed -i \
        "s|^[[:space:]]*prefix[[:space:]]*=.*| prefix = 'FILE',|" \
        namelist.wps

    sed -i \
        "s|^[[:space:]]*start_date[[:space:]]*=.*| start_date = '${GEFS_VALID_TIME_WPS}',|" \
        namelist.wps

    sed -i \
        "s|^[[:space:]]*end_date[[:space:]]*=.*| end_date = '${GEFS_VALID_TIME_WPS}',|" \
        namelist.wps

    sed -i \
        "s|^[[:space:]]*fg_name[[:space:]]*=.*| fg_name = 'GFSENS',|" \
        namelist.wps

    ln -sf "${GEFS_INPUT}" GRIBFILE.AAA

    ln -sf "${WPS_NAMELIST%/*}/Vtable.GFSENS" Vtable

    echo "------------------------------------------------------------"
    echo "Running GEFS UNGRIB"
    echo "GEFS_INIT=${GEFS_INIT}"
    echo "MEMBER=${MEMBER}"
    echo "FCST_HOUR=${FCST_HOUR}"
    echo "GEFS_VALID_TIME=${GEFS_VALID_TIME}"
    echo "GEFS_VALID_TIME_WPS=${GEFS_VALID_TIME_WPS}"
    echo "GEFS_INPUT=${GEFS_INPUT}"
    echo "GRIBFILE.AAA -> $(readlink GRIBFILE.AAA)"
    echo "Vtable -> $(readlink Vtable)"
    echo "------------------------------------------------------------"

    "${UNGRIB_EXE}"

    if ! compgen -G "FILE:*" > /dev/null; then

        echo "ERROR: GEFS UNGRIB produced no FILE:* output."
        echo "UNGRIB_WORK=${UNGRIB_WORK}"

        exit 1

    fi

    # ------------------------------------------------------------------------
    # Link the UNGRIB output into the common external-prd directory.
    # ------------------------------------------------------------------------

    for FILE_OUTPUT in FILE:*; do

        FILE_OUTPUT_NAME="$(basename "${FILE_OUTPUT}")"

        ln -sfn \
            "${UNGRIB_WORK}/${FILE_OUTPUT_NAME}" \
            "${VALID_EXTPRD}/${FILE_OUTPUT_NAME}"

    done

    # Preserve the legacy-style GFSENS link expected by METGRID.
    FIRST_FILE_OUTPUT="$(compgen -G "FILE:*" | head -1)"

    if [[ -n "${FIRST_FILE_OUTPUT}" ]]; then

        FIRST_FILE_NAME="$(basename "${FIRST_FILE_OUTPUT}")"

        ln -sfn \
            "${FIRST_FILE_NAME}" \
            "${VALID_EXTPRD}/GFSENS"

    fi

    echo "GEFS UNGRIB output:"
    ls -lh "${VALID_EXTPRD}"

    # Next GEFS forecast hour.
    FCST_HOUR=$((FCST_HOUR + GEFS_INTERVAL))

done

echo "============================================================"
echo "WoFS v1 BC UNGRIB COMPLETED"
echo "============================================================"
echo "CDATE=${CDATE}"
echo "GEFS_INIT=${GEFS_INIT}"
echo "MEMBER=${MEMBER}"
echo "Processed GEFS valid times:"
printf '  %s\n' "${GEFS_CYCLE_LIST[@]}"
echo "============================================================"

exit 0
