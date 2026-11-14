#!/usr/bin/env bash
# WoFS v1.0 IC_PREP - HRRRDAS UPP postprocessing
# All configurable paths and settings come from config.yaml.
set -euo pipefail

echo "======================================================"
echo " WoFS v1.0 IC_PREP - POST"
echo "======================================================"

: "${IC_PREP_STAGE:?Missing IC_PREP_STAGE}"
: "${INIT_TIME:?Missing INIT_TIME}"

if [[ "${IC_PREP_STAGE}" == "DOWNLOAD" ]]; then
    : "${DOWNLOAD_SCRIPT:?Missing DOWNLOAD_SCRIPT}"
    : "${DOWNLOAD_WORK_DIR:?Missing DOWNLOAD_WORK_DIR}"
    export WORK_DIR="${DOWNLOAD_WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    exec "${DOWNLOAD_SCRIPT}"
fi

[[ "${IC_PREP_STAGE}" == "POST" ]] || {
    echo "ERROR: Unsupported stage ${IC_PREP_STAGE}" >&2
    exit 1
}

# -------------------------------------------------------
# Required configuration exports
# -------------------------------------------------------
required_vars=(
    MEMBER DOMAIN FCST_TIME FHOUR
    WRFOUT_SMALL_DIR WRFINPUT_STATIC_DIR
    WRFOUT_SMALL WRFINPUT_STATIC
    POST_WORK_DIR INPUTDIR
    UPP_EXECUTABLE NCL_SCRIPT
    STATIC_VARS_FILE ITAG_TEMPLATE
    POST_AVBLFLDS PARAMS_GRIB2_TBL
    POSTCNTRL POSTXCONFIG
    GTG_CONFIG ETA_MICRO_LOOKUP
    IC_MPI_TASKS EXPECTED_NUM_FIELDS
    UPP_CORE UPP_IOFORM UPP_GRIB
    UPP_KPO UPP_PO VALID_TIME CRTM
)

for var in "${required_vars[@]}"; do
    [[ -n "${!var:-}" ]] || {
        echo "ERROR: Missing configuration variable ${var}" >&2
        exit 1
    }
done

MEMBER04=$(printf "%04d" "$((10#${MEMBER}))")
MEMBER02=$(printf "%02d" "$((10#${MEMBER}))")

WRFOUT="${WRFOUT_SMALL_DIR}/${WRFOUT_SMALL}"
WRFINPUT_FILE="${WRFINPUT_STATIC_DIR}/${WRFINPUT_STATIC}"
POST="${UPP_EXECUTABLE}"

echo "INIT_TIME       = ${INIT_TIME}"
echo "VALID_TIME      = ${VALID_TIME}"
echo "MEMBER          = ${MEMBER04}"
echo "WRFOUT          = ${WRFOUT}"
echo "WRFINPUT_STATIC = ${WRFINPUT_FILE}"
echo "POST_WORK_DIR   = ${POST_WORK_DIR}"
echo "UPP_EXECUTABLE  = ${POST}"
echo "IC_MPI_TASKS    = ${IC_MPI_TASKS}"

# -------------------------------------------------------
# Validate dependencies before processing
# -------------------------------------------------------
for cmd in ncks ncatted ncap2 ncl wgrib2 srun python3; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        echo "ERROR: Required command unavailable: ${cmd}" >&2
        exit 1
    }
done

for file in \
    "${WRFOUT}" \
    "${WRFINPUT_FILE}" \
    "${STATIC_VARS_FILE}" \
    "${ITAG_TEMPLATE}" \
    "${NCL_SCRIPT}" \
    "${POST_AVBLFLDS}" \
    "${PARAMS_GRIB2_TBL}" \
    "${POSTCNTRL}" \
    "${POSTXCONFIG}" \
    "${GTG_CONFIG}" \
    "${ETA_MICRO_LOOKUP}"; do

    [[ -f "${file}" ]] || {
        echo "ERROR: Missing required file: ${file}" >&2
        exit 1
    }
done

[[ -x "${POST}" ]] || {
    echo "ERROR: UPP executable unavailable: ${POST}" >&2
    exit 1
}

# -------------------------------------------------------
# Ensemble-member working directory
# -------------------------------------------------------
mkdir -p "${POST_WORK_DIR}"
cd "${POST_WORK_DIR}"

rm -f wrfout1.nc wrfout.nc
rm -f fort.*

# -------------------------------------------------------
# Prepare WRF input
# -------------------------------------------------------
echo "Preparing wrfout1.nc"

cp -p "${WRFOUT}" wrfout1.nc
ln -sfn "${WRFINPUT_FILE}" wrfinput_static

# Static field names are maintained in parm/ic_prep/.
STATIC_VARS=$(tr -d '\r\n[:space:]' < "${STATIC_VARS_FILE}")

[[ -n "${STATIC_VARS}" ]] || {
    echo "ERROR: Empty static variable list" >&2
    exit 1
}

ncks -A -v "${STATIC_VARS}" \
    wrfinput_static wrfout1.nc

# -------------------------------------------------------
# Apply grid attributes from config.yaml
# -------------------------------------------------------
echo "Updating WRF grid attributes"

grid_attributes=(
    WEST-EAST_GRID_DIMENSION
    WEST-EAST_PATCH_END_UNSTAG
    WEST-EAST_PATCH_END_STAG
    SOUTH-NORTH_GRID_DIMENSION
    SOUTH-NORTH_PATCH_END_UNSTAG
    SOUTH-NORTH_PATCH_END_STAG
    MOAD_CEN_LAT
    CEN_LAT
    CEN_LON
)

for attr in "${grid_attributes[@]}"; do
    env_name="GRID_${attr//-/_}"
    value="${!env_name:-}"

    [[ -n "${value}" ]] || {
        echo "ERROR: Missing grid attribute ${env_name}" >&2
        exit 1
    }

    case "${attr}" in
        MOAD_CEN_LAT|CEN_LAT|CEN_LON)
            type=f
            ;;
        *)
            type=l
            ;;
    esac

    ncatted -O -h \
        -a "${attr},global,m,${type},${value}" \
        wrfout1.nc
done

# -------------------------------------------------------
# Compute hydrostatic pressure and surface pressure
# -------------------------------------------------------
echo "Computing P_HYD"

ncap2 -s 'P_HYD=(P+PB)' \
    wrfout1.nc wrfout.nc

[[ -s wrfout.nc ]] || {
    echo "ERROR: wrfout.nc was not created" >&2
    exit 1
}

echo "Computing PSFC"
ncl "${NCL_SCRIPT}"

# -------------------------------------------------------
# Link UPP parameter and fix files
# -------------------------------------------------------
ln -sfn "${POST_AVBLFLDS}" post_avblflds.xml
ln -sfn "${PARAMS_GRIB2_TBL}" params_grib2_tbl_new
ln -sfn "${POSTCNTRL}" postcntrl.xml
ln -sfn "${POSTXCONFIG}" postxconfig-NT.txt
ln -sfn "${GTG_CONFIG}" gtg.config
ln -sfn "${ETA_MICRO_LOOKUP}" eta_micro_lookup.dat

# -------------------------------------------------------
# Generate UPP itag from parm/ic_prep/itag.template
# -------------------------------------------------------
echo "Generating UPP itag"

: "${HOMEwofs:?Missing HOMEwofs}"

ITAG_RENDERER="${HOMEwofs}/ush/render_ic_prep_itag.py"

[[ -f "${ITAG_RENDERER}" ]] || {
    echo "ERROR: Missing itag renderer: ${ITAG_RENDERER}" >&2
    exit 1
}

"${IC_PREP_PYTHON:-python3}" "${ITAG_RENDERER}" \
    "${ITAG_TEMPLATE}" itag

[[ -s itag ]] || {
    echo "ERROR: Failed to generate itag" >&2
    exit 1
}

cat itag

# -------------------------------------------------------
# Execute UPP
# -------------------------------------------------------
echo "Running UPP with ${IC_MPI_TASKS} MPI tasks"

bash "${HOMEwofs}/ush/run_upp.sh" \
    "${POST}" "${IC_MPI_TASKS}" itag

# -------------------------------------------------------
# Postprocess GRIB2 products
# -------------------------------------------------------
WGRIB2=$(command -v wgrib2)

POSTFILE="WRFTWO.GrbF${FCST_TIME}"
WRFPRS="WRFPRS.GrbF${FCST_TIME}"
WRFNAT="WRFNAT.GrbF${FCST_TIME}"

for file in "${POSTFILE}" "${WRFPRS}" "${WRFNAT}"; do
    [[ -s "${file}" ]] || {
        echo "ERROR: UPP output missing: ${file}" >&2
        exit 1
    }
done

rm -f orig.grib2 temp.grib2 otherfields.grib2
rm -f weasd.grib2 apcp.grib2 fields.list

mv "${POSTFILE}" orig.grib2

"${WGRIB2}" orig.grib2 > fields.list
field_count=$(wc -l < fields.list)

echo "WRFTWO field count: ${field_count}"

if (( field_count < EXPECTED_NUM_FIELDS )); then
    echo "ERROR: Too few GRIB2 fields" >&2
    exit 1
fi

# Preserve the original accumulation interval convention.
if (( FHOUR == 24 )); then
    ACCUM_INTERVAL="0-1 day"
elif (( FHOUR == 48 )); then
    ACCUM_INTERVAL="0-2 day"
else
    ACCUM_INTERVAL="0-${FHOUR} hour"
fi

# Remove duplicate accumulation fields.
"${WGRIB2}" orig.grib2 \
    -not_if "WEASD:surface:${ACCUM_INTERVAL} acc fcst" \
    -grib temp.grib2

"${WGRIB2}" temp.grib2 \
    -not_if "APCP:surface:${ACCUM_INTERVAL} acc fcst" \
    -grib otherfields.grib2

# Extract the desired accumulated fields.
"${WGRIB2}" orig.grib2 \
    -match "WEASD:surface:${ACCUM_INTERVAL} acc fcst" \
    -end -grib weasd.grib2

"${WGRIB2}" orig.grib2 \
    -match "APCP:surface:${ACCUM_INTERVAL} acc fcst" \
    -end -grib apcp.grib2

cat otherfields.grib2 weasd.grib2 apcp.grib2 \
    > "${POSTFILE}"

rm -f temp.grib2 otherfields.grib2
rm -f weasd.grib2 apcp.grib2

# -------------------------------------------------------
# Construct final GRIB2 products
# -------------------------------------------------------
WRFPRS_FINAL="wrfprs_mem${MEMBER04}_${FCST_TIME}.grib2"
WRFTWO_FINAL="wrftwo_mem${MEMBER04}_${FCST_TIME}.grib2"
WRFNAT_FINAL="wrfnat_hrrre_newse_mem${MEMBER04}_${FCST_TIME}.grib2"

cat "${WRFPRS}" "${POSTFILE}" > "${WRFPRS_FINAL}.new"
mv "${WRFPRS_FINAL}.new" "${WRFPRS_FINAL}"

cat "${WRFNAT}" "${POSTFILE}" > "${WRFNAT_FINAL}.new"
mv "${WRFNAT_FINAL}.new" "${WRFNAT_FINAL}"

mv "${POSTFILE}" "${WRFTWO_FINAL}"

# -------------------------------------------------------
# Validate final GRIB2 products
# -------------------------------------------------------
for file in \
    "${WRFPRS_FINAL}" \
    "${WRFTWO_FINAL}" \
    "${WRFNAT_FINAL}"; do

    [[ -s "${file}" ]] || {
        echo "ERROR: Missing final output: ${file}" >&2
        exit 1
    }
done

# -------------------------------------------------------
# Copy WRFNAT to COMOUT/INPUT for WPS
# -------------------------------------------------------
COMOUT_MEMBER="${INPUTDIR}/mem${MEMBER02}"
mkdir -p "${COMOUT_MEMBER}"

OUTPUT_FILE="${COMOUT_MEMBER}/${WRFNAT_FINAL}"

cp -f "${WRFNAT_FINAL}" "${OUTPUT_FILE}"

[[ -s "${OUTPUT_FILE}" ]] || {
    echo "ERROR: Failed to copy WRFNAT to ${OUTPUT_FILE}" >&2
    exit 1
}

echo "======================================================"
echo " WoFS IC_PREP completed successfully"
echo " INIT_TIME = ${INIT_TIME}"
echo " MEMBER    = ${MEMBER04}"
echo " OUTPUT    = ${OUTPUT_FILE}"
echo "======================================================"
