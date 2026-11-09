#!/bin/bash
# ============================================================================
# exwofs_bc_prep_real.sh
#
# WoFS v1 boundary-condition preparation REAL application script.
#
# This script reproduces the relevant behavior of the legacy:
#
#   WoFS/WoF_BC/bin/real_arw.ksh
#
# for the BC_PREP REAL stage.
#
# Called by:
#   jobs/JWOFS_BC_PREP_REAL
#
# Required environment:
#   REAL_EXE
#   WPSPRD
#   WRFPRD
#   METGRID_FILE
#   WRF_NAMELIST
#   VALID_TIME
#   FIXwofs
#
# The J-job supplies:
#   REAL_EXE      = ${EXECwofs}/real.exe
#   WPSPRD        = .../gefs/${VALID_TIME}/mem${MEMBER}/wpsprd
#   WRFPRD       = .../gefs/${VALID_TIME}/mem${MEMBER}/wrfprd
#   METGRID_FILE  = .../wpsprd/met_em.d01.YYYY-MM-DD_HH:00:00.nc
#   WRF_NAMELIST  = ${FIXwofs}/WRF/namelist.input.memberN
#   VALID_TIME    = YYYYMMDDHH
#
# Legacy BC_PREP REAL behavior:
#   FCST_LENGTH       = 0 hours
#   FCST_INTERVAL     = 3 hours
#   RUNLENGTH_DFI_FWD = 0 minutes
#   RUNLENGTH_DFI_BCK = 0 minutes
#   real_fi_opt       = 3
#
# For the current WoFS member namelist template, the effective namelist
# changes are:
#   run_days         = 0
#   run_hours        = 0
#   start_*          = VALID_TIME
#   end_*            = VALID_TIME
#   interval_seconds = 10800
#   dfi_opt          = 3
#
# The legacy script calculates DFI forward/backward stop times and
# RUNLENGTH_DFI_* shell variables, but the member namelist template does
# not contain corresponding namelist entries. Therefore those legacy sed
# commands make no changes to this template.
# ============================================================================

set -e

echo
echo "============================================================"
echo "WoFS BC_PREP REAL"
echo "============================================================"
echo

# ---------------------------------------------------------------------------
# Required environment
# ---------------------------------------------------------------------------

: "${REAL_EXE:?ERROR: REAL_EXE is not set}"
: "${WPSPRD:?ERROR: WPSPRD is not set}"
: "${WRFPRD:?ERROR: WRFPRD is not set}"
: "${METGRID_FILE:?ERROR: METGRID_FILE is not set}"
: "${WRF_NAMELIST:?ERROR: WRF_NAMELIST is not set}"
: "${VALID_TIME:?ERROR: VALID_TIME is not set}"
: "${FIXwofs:?ERROR: FIXwofs is not set}"

# ---------------------------------------------------------------------------
# Verify required input files
# ---------------------------------------------------------------------------

if [[ ! -s "${METGRID_FILE}" ]]; then
    echo "ERROR: METGRID input file is missing or empty:"
    echo "  ${METGRID_FILE}"
    exit 1
fi

if [[ ! -s "${WRF_NAMELIST}" ]]; then
    echo "ERROR: WRF namelist is missing or empty:"
    echo "  ${WRF_NAMELIST}"
    exit 1
fi

if [[ ! -x "${REAL_EXE}" ]]; then
    echo "ERROR: real.exe is missing or not executable:"
    echo "  ${REAL_EXE}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Create and enter REAL working directory.
#
# Legacy:
#   workdir=${DATAHOME}/wrfprd
#
# Target:
#   WRFPRD=${DATAHOME}/wrfprd
# ---------------------------------------------------------------------------

mkdir -p "${WRFPRD}"
cd "${WRFPRD}"

# ---------------------------------------------------------------------------
# Clean files from a previous REAL attempt.
# ---------------------------------------------------------------------------

rm -f wrfinput_d01
rm -f wrfbdy_d01
rm -f wrflowinp_d01
rm -f namelist.input
rm -f rsl.out.*
rm -f rsl.error.*

# ---------------------------------------------------------------------------
# Stage METGRID input.
#
# Legacy real_arw.ksh:
#
#   source:
#     met_em.d01.YYYY-MM-DD_HH:MM:SS.nc
#
#   local link:
#     met_em.d01.YYYY-MM-DD_HH_MM_SS.nc
#
# Preserve that local naming convention.
# ---------------------------------------------------------------------------

METGRID_BASENAME="met_em.d01.${VALID_TIME:0:4}-${VALID_TIME:4:2}-${VALID_TIME:6:2}_${VALID_TIME:8:2}_00_00.nc"

if [[ -L "${METGRID_BASENAME}" ]]; then
    # Replace a stale or existing symbolic link.
    rm -f "${METGRID_BASENAME}"
elif [[ -e "${METGRID_BASENAME}" ]]; then
    echo "ERROR: ${METGRID_BASENAME} exists and is not a symbolic link."
    exit 1
fi

ln -s "${METGRID_FILE}" "${METGRID_BASENAME}"

# ---------------------------------------------------------------------------
# Stage WRF static/data files required by real.exe.
#
# This reproduces the legacy WoF_BC/bin/real_arw.ksh behavior:
#
#   WRF_DAT_FILES = ${STATIC_DIR}/run/*
#
# Target equivalent:
#
#   ${FIXwofs}/WRF/run
# ---------------------------------------------------------------------------

WRF_STATIC_DIR="${FIXwofs}/WRF/run"

WRF_DAT_FILES=(
    LANDUSE.TBL
    RRTM_DATA
    RRTM_DATA_DBL
    RRTMG_LW_DATA
    RRTMG_LW_DATA_DBL
    RRTMG_SW_DATA
    RRTMG_SW_DATA_DBL
    VEGPARM.TBL
    GENPARM.TBL
    SOILPARM.TBL
    MPTABLE.TBL
    URBPARM.TBL
    URBPARM_UZE.TBL
    ETAMPNEW_DATA
    ETAMPNEW_DATA.expanded_rain
    ETAMPNEW_DATA.expanded_rain_DBL
    ETAMPNEW_DATA_DBL
    co2_trans
    ozone.formatted
    ozone_lat.formatted
    ozone_plev.formatted
    tr49t85
    tr49t67
    tr67t85
    grib2map.tbl
    gribmap.txt
    aerosol.formatted
    aerosol_lat.formatted
    aerosol_lon.formatted
    aerosol_plev.formatted
    bulkdens.asc_s_0_03_0_9
    coeff_p.asc
    coeff_q.asc
    constants.asc
    kernels.asc_s_0_03_0_9
    kernels_z.asc
    masses.asc
    termvels.asc
    wind-turbine-1.tbl
)

for file in "${WRF_DAT_FILES[@]}"; do

    if [[ ! -s "${WRF_STATIC_DIR}/${file}" ]]; then
        echo "ERROR: Required WRF static/data file is missing or empty:"
        echo "  ${WRF_STATIC_DIR}/${file}"
        exit 1
    fi

    rm -f "${file}"
    ln -s "${WRF_STATIC_DIR}/${file}" "${file}"

done

# ---------------------------------------------------------------------------
# Stage legacy BC-PREP REAL namelist.
#
# Legacy WoF_BC/bin/real_arw.ksh is invoked with:
#
#   NAMELIST=real.nl.32and4levels
#
# and copies:
#
#   ${STATIC_DIR}/real.nl.32and4levels
#
# to:
#
#   ${DATAHOME}/wrfprd/namelist.input
#
# Preserve that exact legacy BC-PREP REAL behavior.
# ---------------------------------------------------------------------------

REAL_NAMELIST="${FIXwofs}/WRF/real.nl.32and4levels"

if [[ ! -s "${REAL_NAMELIST}" ]]; then
    echo "ERROR: Legacy BC-PREP REAL namelist is missing or empty:"
    echo "  ${REAL_NAMELIST}"
    exit 1
fi

cp "${REAL_NAMELIST}" namelist.input

# ---------------------------------------------------------------------------
# Convert VALID_TIME to WRF namelist timestamp.
#
# Example:
#
#   VALID_TIME=2026100512
#
# becomes:
#
#   2026-10-05_12:00:00
# ---------------------------------------------------------------------------

VALID_TIME_WPS="${VALID_TIME:0:4}-${VALID_TIME:4:2}-${VALID_TIME:6:2}_${VALID_TIME:8:2}:00:00"

# ---------------------------------------------------------------------------
# Legacy REAL namelist settings.
#
# These reproduce the effective namelist changes made by
# WoF_BC/bin/real_arw.ksh for the BC_PREP REAL task.
#
#   FCST_LENGTH       = 0 hours  -> run_days/run_hours = 0
#   FCST_INTERVAL     = 3 hours  -> interval_seconds = 10800
#
# Match the effective legacy-generated namelist for this comparison:
#   dfi_opt = 3
#   moist_adv_dfi_opt = 3, 1, 1.
# ---------------------------------------------------------------------------

sed -i \
    -e "s#^[[:space:]]*run_days[[:space:]]*=.*# run_days = 0,#" \
    -e "s#^[[:space:]]*run_hours[[:space:]]*=.*# run_hours = 0,#" \
    -e "s#^[[:space:]]*interval_seconds[[:space:]]*=.*# interval_seconds = 10800,#" \
    -e "s#^[[:space:]]*dfi_opt[[:space:]]*=.*# dfi_opt = 3,#" \
    -e "s#^[[:space:]]*moist_adv_dfi_opt[[:space:]]*=.*# moist_adv_dfi_opt = 3, 1, 1,#" \
    namelist.input

# ---------------------------------------------------------------------------
# Set REAL start/end time to VALID_TIME.
#
# Legacy real_arw.ksh calculates:
#
#   START_TIME
#   END_TIME = START_TIME + FCST_LENGTH
#
# Since FCST_LENGTH = 0 for BC_PREP REAL:
#
#   END_TIME = START_TIME
# ---------------------------------------------------------------------------

sed -i \
    -e "s#^[[:space:]]*start_year[[:space:]]*=.*# start_year = ${VALID_TIME:0:4},#" \
    -e "s#^[[:space:]]*start_month[[:space:]]*=.*# start_month = ${VALID_TIME:4:2},#" \
    -e "s#^[[:space:]]*start_day[[:space:]]*=.*# start_day = ${VALID_TIME:6:2},#" \
    -e "s#^[[:space:]]*start_hour[[:space:]]*=.*# start_hour = ${VALID_TIME:8:2},#" \
    -e "s#^[[:space:]]*start_minute[[:space:]]*=.*# start_minute = 00,#" \
    -e "s#^[[:space:]]*start_second[[:space:]]*=.*# start_second = 00,#" \
    -e "s#^[[:space:]]*end_year[[:space:]]*=.*# end_year = ${VALID_TIME:0:4},#" \
    -e "s#^[[:space:]]*end_month[[:space:]]*=.*# end_month = ${VALID_TIME:4:2},#" \
    -e "s#^[[:space:]]*end_day[[:space:]]*=.*# end_day = ${VALID_TIME:6:2},#" \
    -e "s#^[[:space:]]*end_hour[[:space:]]*=.*# end_hour = ${VALID_TIME:8:2},#" \
    -e "s#^[[:space:]]*end_minute[[:space:]]*=.*# end_minute = 00,#" \
    -e "s#^[[:space:]]*end_second[[:space:]]*=.*# end_second = 00,#" \
    namelist.input

# ---------------------------------------------------------------------------
# Display staged input and namelist.
# ---------------------------------------------------------------------------

echo
echo "REAL working directory:"
pwd

echo
echo "METGRID input:"
ls -lh "${METGRID_BASENAME}"

echo
echo "Namelist:"
cat namelist.input

echo
echo "REAL executable:"
ls -lh "${REAL_EXE}"
readlink -f "${REAL_EXE}" || true

echo
echo "Environment:"
echo "  VALID_TIME    = ${VALID_TIME}"
echo "  WPSPRD        = ${WPSPRD}"
echo "  WRFPRD       = ${WRFPRD}"
echo "  METGRID_FILE  = ${METGRID_FILE}"
echo "  WRF_NAMELIST  = ${WRF_NAMELIST}"
echo "  REAL_EXE      = ${REAL_EXE}"

# ---------------------------------------------------------------------------
# Run real.exe.
#
# Legacy:
#
#   MPIRUN=srun
#   ${MPIRUN} ${REAL}
#
# Default target REAL task size:
#
#   160 MPI ranks
#
# IMPORTANT:
# Because this script uses "set -e", do NOT write:
#
#   srun ...
#   REAL_STATUS=$?
#
# If srun fails, set -e exits before REAL_STATUS can be assigned.
# Use an if/else construct so the failure can be diagnosed below.
# ---------------------------------------------------------------------------

REAL_NTASKS="${SLURM_NTASKS:-160}"

echo
echo "============================================================"
echo "Running real.exe"
echo "============================================================"
echo
echo "Command:"
echo "  srun -n ${REAL_NTASKS} ${REAL_EXE}"
echo

if srun -n "${REAL_NTASKS}" "${REAL_EXE}"; then
    REAL_STATUS=0
else
    REAL_STATUS=$?
fi

if [[ ${REAL_STATUS} -ne 0 ]]; then

    echo
    echo "ERROR: real.exe failed with status ${REAL_STATUS}"
    echo

    echo "REAL working directory:"
    pwd

    echo
    echo "Directory contents:"
    ls -lah

    echo
    echo "RSL output files:"
    ls -lh rsl.out.* rsl.error.* 2>/dev/null || true

    echo
    echo "Last 100 lines of rsl.error.0000:"
    if [[ -s rsl.error.0000 ]]; then
        tail -100 rsl.error.0000
    else
        echo "rsl.error.0000 does not exist or is empty."
    fi

    echo
    echo "Last 100 lines of rsl.out.0000:"
    if [[ -s rsl.out.0000 ]]; then
        tail -100 rsl.out.0000
    else
        echo "rsl.out.0000 does not exist or is empty."
    fi

    exit "${REAL_STATUS}"

fi

# ---------------------------------------------------------------------------
# Verify REAL output.
#
# wrfinput_d01 is required.
#
# The legacy REAL workflow can produce wrfbdy_d01 depending on the
# namelist/domain configuration. Report its presence but do not fabricate
# or pre-stage it.
# ---------------------------------------------------------------------------

if [[ ! -s wrfinput_d01 ]]; then
    echo
    echo "ERROR: real.exe completed but wrfinput_d01 was not created:"
    echo "  ${WRFPRD}/wrfinput_d01"
    exit 1
fi

echo
echo "OK: wrfinput_d01 created:"
ls -lh wrfinput_d01

if [[ ! -s wrfbdy_d01 ]]; then
    echo
    echo "WARNING: wrfbdy_d01 was not created:"
    echo "  ${WRFPRD}/wrfbdy_d01"
else
    echo
    echo "OK: wrfbdy_d01 created:"
    ls -lh wrfbdy_d01
fi

echo
echo "============================================================"
echo "REAL completed successfully"
echo "============================================================"
echo
