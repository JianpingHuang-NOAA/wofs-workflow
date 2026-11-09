#!/bin/bash
# ============================================================================
# exwofs_bc_prep_metgrid.sh
# WoFS v1 boundary-condition preparation METGRID application script
#
# Purpose:
#   Reproduce the legacy WoF_BC METGRID behavior for one GEFS ensemble
#   member and one WoFS forecast valid time.
#
# Legacy reference:
#   WoFS/WoF_BC/bin/metgrid.ksh
#
# Working directory:
#   ${DATAHOME}/wpsprd
#
# Inputs:
#   GEFS:
#     ${SOURCE_PATH}/GFSENS
#
#   SST:
#     ${CONSTANT_PATH}/SST
#
#   Static geogrid file:
#     ${STATIC_DIR}/geo_*.d01.nc
#
# Target UNGRIB naming:
#   extprd/GFSENS -> FILE:YYYY-MM-DD_HH:MM:SS
#
# Legacy METGRID staging:
#   GFSENS:YYYY-MM-DD_HH
#   SST
#
# Output:
#   met_em.d01.YYYY-MM-DD_HH:MM:SS.nc
# ============================================================================

set -e

# ----------------------------------------------------------------------------
# Define executable and namelist.
# ----------------------------------------------------------------------------
export EXECwofs="${EXECwofs:-${HOMEwofs}/exec}"
export METGRID_EXE="${METGRID_EXE:-${EXECwofs}/metgrid.exe}"
export WPS_NAMELIST="${NAMELIST}"

# ----------------------------------------------------------------------------
# Check required executable.
# ----------------------------------------------------------------------------
if [[ ! -x "${METGRID_EXE}" ]]; then
    echo "ERROR: METGRID executable not found or not executable:"
    echo "  ${METGRID_EXE}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Check required namelist.
# ----------------------------------------------------------------------------
if [[ ! -r "${WPS_NAMELIST}" ]]; then
    echo "ERROR: METGRID namelist not found or not readable:"
    echo "  ${WPS_NAMELIST}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Check required GEFS source directory.
# ----------------------------------------------------------------------------
if [[ ! -d "${SOURCE_PATH}" ]]; then
    echo "ERROR: GEFS source directory not found:"
    echo "  ${SOURCE_PATH}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Check required SST source directory.
# ----------------------------------------------------------------------------
if [[ ! -d "${CONSTANT_PATH}" ]]; then
    echo "ERROR: SST constant directory not found:"
    echo "  ${CONSTANT_PATH}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Check required geogrid static file.
#
# Legacy metgrid.ksh does:
#
#   rm -f geo_*.d01.nc
#   ln -s ${STATIC_DIR}/geo_*.d01.nc .
#
# The target package contains:
#
#   ${STATIC_DIR}/geo_em.d01.nc
# ----------------------------------------------------------------------------
if [[ ! -s "${STATIC_DIR}/geo_em.d01.nc" ]]; then
    echo "ERROR: Required geogrid file not found:"
    echo "  ${STATIC_DIR}/geo_em.d01.nc"
    exit 1
fi

# ----------------------------------------------------------------------------
# Define target input files.
# ----------------------------------------------------------------------------
GFSENS_INPUT="${SOURCE_PATH}/GFSENS"
SST_INPUT="${CONSTANT_PATH}/SST"

if [[ ! -e "${GFSENS_INPUT}" ]]; then
    echo "ERROR: GFSENS input not found:"
    echo "  ${GFSENS_INPUT}"
    exit 1
fi

if [[ ! -e "${SST_INPUT}" ]]; then
    echo "ERROR: SST input not found:"
    echo "  ${SST_INPUT}"
    exit 1
fi

# ----------------------------------------------------------------------------
# Convert VALID_TIME from YYYYMMDDHH to WPS date formats.
#
# Example:
#
#   VALID_TIME       = 2026100518
#   VALID_TIME_WPS   = 2026-10-05_18:00:00
#   VALID_TIME_STAGE = 2026-10-05_18
# ----------------------------------------------------------------------------
VALID_TIME_WPS="${VALID_TIME:0:4}-${VALID_TIME:4:2}-${VALID_TIME:6:2}_${VALID_TIME:8:2}:00:00"
VALID_TIME_STAGE="${VALID_TIME:0:4}-${VALID_TIME:4:2}-${VALID_TIME:6:2}_${VALID_TIME:8:2}"

# ----------------------------------------------------------------------------
# Print run parameters.
# ----------------------------------------------------------------------------
echo
echo "============================================================"
echo "WoFS v1 BC METGRID application"
echo "============================================================"
echo "VALID_TIME       = ${VALID_TIME}"
echo "VALID_TIME_WPS   = ${VALID_TIME_WPS}"
echo "VALID_TIME_STAGE = ${VALID_TIME_STAGE}"
echo "DATAHOME         = ${DATAHOME}"
echo "SOURCE_PATH      = ${SOURCE_PATH}"
echo "CONSTANT_PATH    = ${CONSTANT_PATH}"
echo "STATIC_DIR       = ${STATIC_DIR}"
echo "WPS_ROOT         = ${WPS_ROOT}"
echo "NAMELIST         = ${NAMELIST}"
echo "METGRID_PROC     = ${METGRID_PROC}"
echo "METGRID_EXE      = ${METGRID_EXE}"
echo "============================================================"
echo

# ----------------------------------------------------------------------------
# Create and enter the legacy METGRID working directory.
# ----------------------------------------------------------------------------
WPSPRD="${DATAHOME}/wpsprd"

mkdir -p "${WPSPRD}"
cd "${WPSPRD}"

# ----------------------------------------------------------------------------
# Remove pre-existing files.
#
# This follows the legacy metgrid.ksh behavior.
# ----------------------------------------------------------------------------
rm -f geo_*.d01.nc
rm -f GFSENS:*
rm -f SST
rm -f met_em.d01.*
rm -f metgrid.log.*
rm -f namelist.wps

# ----------------------------------------------------------------------------
# Stage the legacy geogrid static file.
#
# Legacy:
#
#   rm -f geo_*.d01.nc
#   ln -s ${STATIC_DIR}/geo_*.d01.nc .
# ----------------------------------------------------------------------------
ln -s "${STATIC_DIR}"/geo_*.d01.nc .

# ----------------------------------------------------------------------------
# Verify that the geogrid file was staged.
# ----------------------------------------------------------------------------
if [[ ! -e "geo_em.d01.nc" ]]; then
    echo "ERROR: Failed to stage geo_em.d01.nc:"
    echo "  ${STATIC_DIR}/geo_em.d01.nc"
    exit 1
fi

# ----------------------------------------------------------------------------
# Stage GEFS input using the exact legacy METGRID filename.
#
# Target UNGRIB:
#
#   extprd/GFSENS
#       -> FILE:YYYY-MM-DD_HH:MM:SS
#
# Legacy METGRID expects:
#
#   GFSENS:YYYY-MM-DD_HH
# ----------------------------------------------------------------------------
GFSENS_STAGE="GFSENS:${VALID_TIME_STAGE}"

ln -s "${GFSENS_INPUT}" "${GFSENS_STAGE}"

# ----------------------------------------------------------------------------
# Stage SST using the exact legacy filename:
#
#   SST
# ----------------------------------------------------------------------------
ln -s "${SST_INPUT}" SST

# ----------------------------------------------------------------------------
# Copy the static METGRID namelist into the working directory.
# ----------------------------------------------------------------------------
cp "${WPS_NAMELIST}" namelist.wps

# ----------------------------------------------------------------------------
# Update the METGRID namelist.
#
# Legacy metgrid.ksh updates:
#   start_date
#   end_date
#   interval_seconds
#   fg_name
#   constants_name
#
# For this task:
#   FCST_LENGTH   = 0
#   FCST_INTERVAL = 3
#
# Therefore start and end time are identical.
# ----------------------------------------------------------------------------
sed -i \
    -e "s#^[[:space:]]*start_date[[:space:]]*=.*# start_date = '${VALID_TIME_WPS}',#" \
    -e "s#^[[:space:]]*end_date[[:space:]]*=.*# end_date = '${VALID_TIME_WPS}',#" \
    -e "s#^[[:space:]]*interval_seconds[[:space:]]*=.*# interval_seconds = 10800,#" \
    -e "s#^[[:space:]]*fg_name[[:space:]]*=.*# fg_name = 'GFSENS',#" \
    -e "s#^[[:space:]]*constants_name[[:space:]]*=.*# constants_name = 'SST',#" \
    namelist.wps

# ----------------------------------------------------------------------------
# Print staged input information.
# ----------------------------------------------------------------------------
echo
echo "============================================================"
echo "METGRID working directory:"
echo "  ${WPSPRD}"
echo "============================================================"

echo "METGRID input files:"
ls -lh \
    "${GFSENS_STAGE}" \
    SST \
    geo_*.d01.nc

echo
echo "METGRID input link details:"
ls -l \
    "${GFSENS_STAGE}" \
    SST \
    geo_*.d01.nc

echo
echo "METGRID namelist:"
echo "------------------------------------------------------------"
cat namelist.wps
echo "============================================================"
echo

# ----------------------------------------------------------------------------
# Stage the WPS METGRID interpolation table.
# The executable expects metgrid/METGRID.TBL.
if [[ ! -s "${STATIC_DIR}/METGRID.TBL" ]]; then
    echo "ERROR: METGRID.TBL is missing:"
    echo "  ${STATIC_DIR}/METGRID.TBL"
    exit 1
fi

mkdir -p metgrid
ln -sfn "${STATIC_DIR}/METGRID.TBL" metgrid/METGRID.TBL

if [[ ! -s metgrid/METGRID.TBL ]]; then
    echo "ERROR: Failed to stage METGRID.TBL"
    exit 1
fi

echo "METGRID.TBL = $(readlink -f metgrid/METGRID.TBL)"

# Run METGRID.
#
# Legacy:
#
#   MPIRUN=srun
#   ${MPIRUN} ${METGRID}
#
# The target uses METGRID_PROC from the J-job/Slurm allocation.
# ----------------------------------------------------------------------------
echo "Running metgrid.exe..."
echo "Command: srun -n ${METGRID_PROC} ${METGRID_EXE}"
echo

srun -n "${METGRID_PROC}" "${METGRID_EXE}"

METGRID_STATUS=$?

if [[ ${METGRID_STATUS} -ne 0 ]]; then
    echo
    echo "ERROR: metgrid.exe exited with status ${METGRID_STATUS}"
    exit ${METGRID_STATUS}
fi

# ----------------------------------------------------------------------------
# Check expected METGRID output.
#
# Legacy WPS ARW output:
#
#   met_em.d01.YYYY-MM-DD_HH:MM:SS.nc
# ----------------------------------------------------------------------------
METGRID_OUTPUT="met_em.d01.${VALID_TIME_WPS}.nc"

if [[ ! -s "${METGRID_OUTPUT}" ]]; then
    echo
    echo "ERROR: METGRID failed to create expected output:"
    echo "  ${WPSPRD}/${METGRID_OUTPUT}"
    echo
    echo "Available METGRID output files:"
    ls -lh met_em* 2>/dev/null || true
    exit 1
fi

# ----------------------------------------------------------------------------
# Successful completion.
# ----------------------------------------------------------------------------
echo
echo "============================================================"
echo "METGRID completed successfully."
echo "============================================================"
echo "Output:"
ls -lh "${METGRID_OUTPUT}"
echo "============================================================"
echo

exit 0
