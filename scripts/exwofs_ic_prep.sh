#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================="
echo " WoFS IC Preparation / UPP"
echo "=============================================================="

# ----------------------------------------------------------------------
# IC preparation stage
# ----------------------------------------------------------------------
: "${IC_PREP_STAGE:?IC_PREP_STAGE must be defined}"

case "${IC_PREP_STAGE}" in

DOWNLOAD)

    echo "=============================================================="
    echo " WoFS IC Preparation -- HRRRDAS DOWNLOAD"
    echo "=============================================================="

    : "${DATA:?DATA must be defined}"
    : "${INIT_TIME:?INIT_TIME must be defined}"

    export WORK_DIR="${DATA}"

    echo "INIT_TIME = ${INIT_TIME}"
    echo "WORK_DIR  = ${WORK_DIR}"

    "${HOMEwofs}/ush/nomads_hrrrdas_download.sh"

    echo "HRRRDAS download completed successfully."

    exit 0
    ;;

POST)
    ;;

*)
    echo "ERROR: Unsupported IC_PREP_STAGE=${IC_PREP_STAGE}"
    exit 1
    ;;

esac

# ----------------------------------------------------------------------
# Required environment for POST
# ----------------------------------------------------------------------
: "${DATA:?DATA must be defined}"
: "${WRFOUT_SMALL_DIR:?WRFOUT_SMALL_DIR must be defined}"
: "${WRFINPUT_STATIC_DIR:?WRFINPUT_STATIC_DIR must be defined}"
: "${STATICWRF_DIR:?STATICWRF_DIR must be defined}"
: "${EXE_ROOT:?EXE_ROOT must be defined}"
: "${NCL_SCRIPTS:?NCL_SCRIPTS must be defined}"
: "${PARMWOfS:?PARMWOfS must be defined}"
: "${UPP_FIX_DIR:?UPP_FIX_DIR must be defined}"
: "${INIT_TIME:?INIT_TIME must be defined}"
: "${MEMBER:?MEMBER must be defined}"
: "${FCST_TIME:?FCST_TIME must be defined}"
: "${DOMAIN:?DOMAIN must be defined}"
: "${MODEL:?MODEL must be defined}"

# ----------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------
FHOUR="${FHOUR:-1}"
EXPECTED_NUM_FIELDS="${EXPECTED_NUM_FIELDS:-163}"

# Two-digit ensemble member
ensmemid=$(printf "%04d" "${MEMBER}")

echo "DATA                  = ${DATA}"
echo "WRFOUT_SMALL_DIR      = ${WRFOUT_SMALL_DIR}"
echo "WRFINPUT_STATIC_DIR   = ${WRFINPUT_STATIC_DIR}"
echo "STATICWRF_DIR         = ${STATICWRF_DIR}"
echo "EXE_ROOT              = ${EXE_ROOT}"
echo "NCL_SCRIPTS           = ${NCL_SCRIPTS}"
echo "PARMWOfS              = ${PARMWOfS}"
echo "UPP_FIX_DIR           = ${UPP_FIX_DIR}"
echo "INIT_TIME             = ${INIT_TIME}"
echo "DOMAIN                = ${DOMAIN}"
echo "MEMBER                = ${MEMBER}"
echo "FCST_TIME             = ${FCST_TIME}"
echo "FHOUR                 = ${FHOUR}"
echo "MODEL                 = ${MODEL}"
echo "EXPECTED_NUM_FIELDS   = ${EXPECTED_NUM_FIELDS}"

# ----------------------------------------------------------------------
# Select UPP executable / model core
# ----------------------------------------------------------------------
case "${MODEL}" in
    RAP)
        POST="${EXE_ROOT}/upp.x"
        CORE="RAPR"
        ;;

    "WRF-RR NMM")
#        POST="${EXE_ROOT}/ncep_post.exe"
        POST="${EXE_ROOT}/upp.x"
        CORE="NMM"
        ;;

    *)
        echo "ERROR: Unsupported MODEL=${MODEL}"
        exit 1
        ;;
esac

if [[ ! -x "${POST}" ]]; then
    echo "ERROR: UPP executable not found or not executable:"
    echo "       ${POST}"
    exit 1
fi

# ----------------------------------------------------------------------
# Working directory
# ----------------------------------------------------------------------
POST_WORK_DIR="${DATA}/postprd_mem${ensmemid}/${FCST_TIME}"

mkdir -p "${POST_WORK_DIR}"
cd "${POST_WORK_DIR}"

echo "POST_WORK_DIR         = ${POST_WORK_DIR}"

# ----------------------------------------------------------------------
# Original WoFS filename convention
#
# Example:
# hrrrdas_small_d02_202608061400f01_mem0001
# ----------------------------------------------------------------------
WRFOUT="${WRFOUT_SMALL_DIR}/hrrrdas_small_d0${DOMAIN}_${INIT_TIME}00f${FCST_TIME}_mem${ensmemid}"

# Original WoFS static WRF input:
#
# Example:
# hrrr_2026080614f001
# ----------------------------------------------------------------------
WRFINPUT_STATIC="${WRFINPUT_STATIC_DIR}/hrrr_${INIT_TIME}f001"

echo "WRFOUT                = ${WRFOUT}"
echo "WRFINPUT_STATIC       = ${WRFINPUT_STATIC}"

# ----------------------------------------------------------------------
# Check input files
# ----------------------------------------------------------------------
if [[ ! -f "${WRFOUT}" ]]; then
    echo "ERROR: Missing WRF forecast output:"
    echo "       ${WRFOUT}"
    exit 1
fi

if [[ ! -f "${WRFINPUT_STATIC}" ]]; then
    echo "ERROR: Missing WRF static input:"
    echo "       ${WRFINPUT_STATIC}"
    exit 1
fi

# ----------------------------------------------------------------------
# Prepare wrfout1.nc
#
# Original WoFS unipost_ens.wof.ksh:
#
#   cp hrrrdas_small_... ./wrfout1.nc
#
# Then copy selected static fields from:
#
#   hrrr_${INIT_TIME}f001
#
# into wrfout1.nc using ncks.
# ----------------------------------------------------------------------
echo "Preparing wrfout1.nc"

rm -f wrfout1.nc wrfout.nc

cp -p "${WRFOUT}" ./wrfout1.nc

# ----------------------------------------------------------------------
# Link static WRF input
# ----------------------------------------------------------------------
ln -sf "${WRFINPUT_STATIC}" ./wrfinput_static

if [[ ! -f ./wrfinput_static ]]; then
    echo "ERROR: Failed to link wrfinput_static"
    exit 1
fi

# ----------------------------------------------------------------------
# Add static fields from wrfinput_static to wrfout1.nc
#
# This list is taken from the original WoFS
# unipost_ens.wof.ksh.
# ----------------------------------------------------------------------
STATIC_VARS="\
HGT,PB,ZS,DZS,ZNT,LU_INDEX,VAR_SSO,MU0,QNWFA2D,QNWFA,QNIFA,TOPOSTDV,\
TOPOSLPX,TOPOSLPY,UST,SH2O,SR,MAVAIL,SFROFF,UDROFF,SHDMIN,SHDMAX,\
SNOALB,SLOPECAT,SOILHGT,LANDUSEF,SOILCTOP,SOILCBOT,SOILCAT,VEGCAT,\
LAI,ACSNOW,ACSNOM,ACGRAUP,ACRUNOFF,ACFRAIN,CANWAT,EMISS,ALBSOL,\
SNOWH,SNOWC,SNOWNC,RHOSNF,FNDSNOWH,FNDSOILW,FNDALBSI,FNDSNOWSI,\
FNDICEDEPTH,LAKE_DEPTH,VAR,CON,VARSS,CONSS,MAPFAC_U,MAPFAC_V,\
XLAT_U,XLONG_U,XLAT_V,XLONG_V,ALBBCKSOL,ALBBCK,TMN,LANDMASK,LAKEMASK,\
REFDM10C_MAX,IWP,LWP"

echo "Adding static WRF fields with ncks"

ncks -A \
    -v "${STATIC_VARS}" \
    ./wrfinput_static \
    ./wrfout1.nc

# ----------------------------------------------------------------------
# Update grid/domain attributes.
#
# These values are from the original WoFS unipost_ens.wof.ksh.
# ----------------------------------------------------------------------
echo "Updating WRF grid attributes"

ncatted -O -h \
    -a WEST-EAST_GRID_DIMENSION,global,m,l,1800 \
    wrfout1.nc

ncatted -O -h \
    -a WEST-EAST_PATCH_END_UNSTAG,global,m,l,1799 \
    wrfout1.nc

ncatted -O -h \
    -a WEST-EAST_PATCH_END_STAG,global,m,l,1800 \
    wrfout1.nc

ncatted -O -h \
    -a SOUTH-NORTH_GRID_DIMENSION,global,m,l,1060 \
    wrfout1.nc

ncatted -O -h \
    -a SOUTH-NORTH_PATCH_END_UNSTAG,global,m,l,1059 \
    wrfout1.nc

ncatted -O -h \
    -a SOUTH-NORTH_PATCH_END_STAG,global,m,l,1060 \
    wrfout1.nc

ncatted -O -h \
    -a MOAD_CEN_LAT,global,m,f,38.5 \
    wrfout1.nc

ncatted -O -h \
    -a CEN_LAT,global,m,f,38.5 \
    wrfout1.nc

ncatted -O -h \
    -a CEN_LON,global,m,f,-97.5 \
    wrfout1.nc

# ----------------------------------------------------------------------
# Compute hydrostatic pressure.
#
# Original WoFS:
#     ncap2 -s 'P_HYD=(P+PB)' wrfout1.nc wrfout.nc
# ----------------------------------------------------------------------
echo "Computing P_HYD"

ncap2 -s 'P_HYD=(P+PB)' \
    wrfout1.nc \
    wrfout.nc

if [[ ! -f wrfout.nc ]]; then
    echo "ERROR: ncap2 did not create wrfout.nc"
    exit 1
fi

# ----------------------------------------------------------------------
# Compute surface pressure.
#
# Original WoFS workflow:
#   compute_wrf_pressure.ncl adds PSFC to wrfout.nc
# ----------------------------------------------------------------------
echo "Computing PSFC"

ncl "${HOMEwofs}/util/compute_wrf_pressure.ncl"

if [[ $? -ne 0 ]]; then
    echo "ERROR: compute_wrf_pressure.ncl failed"
    exit 1
fi

# ----------------------------------------------------------------------
# Prepare UPP configuration
# ----------------------------------------------------------------------
UPP_PARM_FILES=(
    "${PARMWOfS}/post_avblflds.xml"
    "${PARMWOfS}/params_grib2_tbl_new"
    "${PARMWOfS}/postcntrl.xml"
    "${PARMWOfS}/postxconfig-NT.txt"
)

UPP_FIX_FILES=(
    "${UPP_FIX_DIR}/gtg.config.raphrrr"
)

echo "Checking WoFS UPP configuration"

for file in "${UPP_PARM_FILES[@]}" "${UPP_FIX_FILES[@]}"; do
    if [[ ! -f "${file}" ]]; then
        echo "ERROR: Missing UPP configuration file:"
        echo "       ${file}"
        exit 1
    fi
done

# ----------------------------------------------------------------------
# UPP itag
#
# The UPP executable consumes itag from stdin.
# ----------------------------------------------------------------------
# Forecast-valid time for UPP: INIT_TIME + FCST_TIME
#jp VALID_EPOCH=$(date -u -d "${INIT_TIME:0:8} ${INIT_TIME:8:2}:00:00" +%s)
#VALID_EPOCH=$((VALID_EPOCH + FCST_TIME * 3600))
#VALID_TIME=$(date -u -d "@${VALID_EPOCH}" +"%Y-%m-%d_%H:00:00")
VALID_EPOCH=$(date -u -d "${INIT_TIME:0:8} ${INIT_TIME:8:2}:00:00" +%s)
FCST_HOURS=$((10#${FCST_TIME}))
VALID_EPOCH=$((VALID_EPOCH + FCST_HOURS * 3600))
VALID_TIME=$(date -u -d "@${VALID_EPOCH}" +"%Y-%m-%d_%H:00:00")

cat > itag << EOF
&MODEL_INPUTS
 fileName='wrfout.nc',
 IOFORM='netcdf',
 grib='grib2',
 DateStr='${VALID_TIME}',
 MODELNAME='RAPR',
 SUBMODELNAME='',
 fileNameFlux='wrfout.nc',
 fileNameFlat='postxconfig-NT.txt'
/
&NAMPGB
 KPO=47,PO=1013.2,1000.,975.,950.,925.,900.,875.,850.,825.,800.,775.,750.,725.,700.,675.,650.,625.,600.,575.,550.,525.,500.,475.,450.,425.,400.,375.,350.,325.,300.,275.,250.,225.,200.,175.,150.,125.,100.,75.,70.,50.,30.,20.,10.,7.,5.,2.,
/
EOF

echo "=============================================================="
echo "UPP itag:"
cat itag
echo "=============================================================="

# ----------------------------------------------------------------------
# Link WoFS-specific UPP configuration
# ----------------------------------------------------------------------
ln -sf "${PARMWOfS}/post_avblflds.xml" \
    post_avblflds.xml

ln -sf "${PARMWOfS}/params_grib2_tbl_new" \
    params_grib2_tbl_new

ln -sf "${PARMWOfS}/postcntrl.xml" \
    postcntrl.xml

ln -sf "${PARMWOfS}/postxconfig-NT.txt" \
    postxconfig-NT.txt

ln -sf "${UPP_FIX_DIR}/gtg.config.raphrrr" \
    gtg.config

# ----------------------------------------------------------------------
# UPP WRF static microphysics lookup
# ----------------------------------------------------------------------
ETAMPNEW_DATA="${STATICWRF_DIR}/run/ETAMPNEW_DATA"

if [[ ! -f "${ETAMPNEW_DATA}" ]]; then
    echo "ERROR: Missing ETAMPNEW_DATA:"
    echo "       ${ETAMPNEW_DATA}"
    exit 1
fi

ln -sf "${ETAMPNEW_DATA}" eta_micro_lookup.dat


# ----------------------------------------------------------------------
# UPP CRTM coefficient files
#
# CRTM is controlled by the CRTM enable flag. The actual coefficient
# directory is specified by CRTM_FIX.
# ----------------------------------------------------------------------
if [[ "${CRTM}" == "1" ]]; then

    CRTM_FIX="${CRTM_FIX:-/contrib/spack-stack/spack-stack-1.9.1/envs/ue-oneapi-2024.2.1/install/oneapi/2024.2.1/crtm-fix-2.4.0.1_emc-t5jym6r/fix}"

    if [[ ! -d "${CRTM_FIX}" ]]; then
        echo "ERROR: CRTM fix directory not found:"
        echo "       ${CRTM_FIX}"
        exit 1
    fi

    shopt -s nullglob
    CRTM_BIN_FILES=( "${CRTM_FIX}"/*bin )
    shopt -u nullglob

    if (( ${#CRTM_BIN_FILES[@]} == 0 )); then
        echo "ERROR: No CRTM coefficient files found:"
        echo "       ${CRTM_FIX}"
        exit 1
    fi

    echo "Staging ${#CRTM_BIN_FILES[@]} CRTM coefficient files"
    echo "CRTM_FIX = ${CRTM_FIX}"

    for file in "${CRTM_BIN_FILES[@]}"; do
        ln -sf "${file}" "./$(basename "${file}")"
    done

else
    echo "CRTM disabled: CRTM=${CRTM}"
fi


# ----------------------------------------------------------------------
# Verify links
# ----------------------------------------------------------------------
echo "UPP configuration in ${POST_WORK_DIR}:"

ls -lh \
    post_avblflds.xml \
    params_grib2_tbl_new \
    postcntrl.xml \
    postxconfig-NT.txt \
    gtg.config \
    eta_micro_lookup.dat

# ----------------------------------------------------------------------
# Run UPP
# ----------------------------------------------------------------------
echo "=============================================================="
echo "Running UPP"
echo "POST = ${POST}"
echo "=============================================================="

srun -n 160 -p u1-compute -q debug \
    --exclusive -t 00:25:00 "${POST}" < itag
#srun -N 1 -n 128 -p u1-compute -q debug --exclusive -t 00:25:00  "${POST}" < itag
#srun -N 1 -n 160 "${POST}" < itag
# ----------------------------------------------------------------------
# Post-UPP GRIB2 processing
#
# UPP creates WRFNAT/WRFPRS/WRFTWO.  The legacy workflow moves WRFTWO
# to orig.grib2 and uses wgrib2 to remove duplicate APCP/WEASD fields,
# then creates the final WoFS GRIB2 products.
# ----------------------------------------------------------------------

POSTFILE="${POST_WORK_DIR}/WRFTWO.GrbF${FCST_TIME}"
ORIG_GRIB2="${POST_WORK_DIR}/orig.grib2"
TEMP_GRIB2="${POST_WORK_DIR}/temp.grib2"
OTHERFIELDS_GRIB2="${POST_WORK_DIR}/otherfields.grib2"
WEASD_GRIB2="${POST_WORK_DIR}/weasd.grib2"
APCP_GRIB2="${POST_WORK_DIR}/apcp.grib2"
FIELDS_LIST="${POST_WORK_DIR}/fields.list"

WGRIB2="${WGRIB2:-$(command -v wgrib2)}"

if [[ -z "${WGRIB2}" || ! -x "${WGRIB2}" ]]; then
    echo "ERROR: wgrib2 executable not found"
    exit 1
fi

if [[ ! -s "${POSTFILE}" ]]; then
    echo "ERROR: UPP did not create ${POSTFILE}"
    exit 1
fi

rm -f \
    "${FIELDS_LIST}" \
    "${ORIG_GRIB2}" \
    "${TEMP_GRIB2}" \
    "${OTHERFIELDS_GRIB2}" \
    "${WEASD_GRIB2}" \
    "${APCP_GRIB2}"

echo "=============================================================="
echo "Post-UPP GRIB2 processing"
echo "=============================================================="

# Legacy behavior: WRFTWO becomes orig.grib2.
mv "${POSTFILE}" "${ORIG_GRIB2}"

# Detect WRFTWO files that are too small.
"${WGRIB2}" "${ORIG_GRIB2}" > "${FIELDS_LIST}"
field_count=$(wc -l < "${FIELDS_LIST}")
echo "number of fields = ${field_count}"

if [[ "${field_count}" -lt "${EXPECTED_NUM_FIELDS}" ]]; then
    echo "ERROR: not enough fields (${field_count} < ${EXPECTED_NUM_FIELDS})"
    exit 1
fi

# Determine accumulation interval exactly as in the legacy workflow.
if [[ "${FHOUR}" -eq 24 ]]; then
    ACCUM_INTERVAL="0-1 day"
elif [[ "${FHOUR}" -eq 48 ]]; then
    ACCUM_INTERVAL="0-2 day"
else
    ACCUM_INTERVAL="0-${FHOUR} hour"
fi

echo "Accumulation interval = ${ACCUM_INTERVAL}"

# Remove duplicate WEASD.
"${WGRIB2}" "${ORIG_GRIB2}" \
    -not_if "WEASD:surface:${ACCUM_INTERVAL} acc fcst" \
    -grib "${TEMP_GRIB2}"

# Remove duplicate APCP.
"${WGRIB2}" "${TEMP_GRIB2}" \
    -not_if "APCP:surface:${ACCUM_INTERVAL} acc fcst" \
    -grib "${OTHERFIELDS_GRIB2}"

rm -f "${TEMP_GRIB2}"

# Extract desired WEASD field.
"${WGRIB2}" "${ORIG_GRIB2}" \
    -match "WEASD:surface:${ACCUM_INTERVAL} acc fcst" \
    -end -grib "${WEASD_GRIB2}"

# Extract desired APCP field.
"${WGRIB2}" "${ORIG_GRIB2}" \
    -match "APCP:surface:${ACCUM_INTERVAL} acc fcst" \
    -end -grib "${APCP_GRIB2}"

# Rebuild WRFTWO with duplicate fields removed.
cat "${OTHERFIELDS_GRIB2}" "${WEASD_GRIB2}" "${APCP_GRIB2}" > "${POSTFILE}"

rm -f "${OTHERFIELDS_GRIB2}" "${WEASD_GRIB2}" "${APCP_GRIB2}"

# ----------------------------------------------------------------------
# Append entire WRFTWO to WRFPRS.
# ----------------------------------------------------------------------

WRFPRS="${POST_WORK_DIR}/WRFPRS.GrbF${FCST_TIME}"
WRFNAT="${POST_WORK_DIR}/WRFNAT.GrbF${FCST_TIME}"

WRFPRS_FINAL="${POST_WORK_DIR}/wrfprs_mem${ensmemid}_${FCST_TIME}.grib2"
WRFNAT_FINAL="${POST_WORK_DIR}/wrfnat_mem${ensmemid}_${FCST_TIME}.grib2"
WRFTWO_FINAL="${POST_WORK_DIR}/wrftwo_mem${ensmemid}_${FCST_TIME}.grib2"
WRFNAT_HRRRE="${POST_WORK_DIR}/wrfnat_hrrre_newse_mem${ensmemid}_${FCST_TIME}.grib2"

if [[ ! -s "${WRFPRS}" ]]; then
    echo "ERROR: ${WRFPRS} is missing"
    exit 1
fi

if [[ ! -s "${WRFNAT}" ]]; then
    echo "ERROR: ${WRFNAT} is missing"
    exit 1
fi

cat "${WRFPRS}" "${POSTFILE}" > "${WRFPRS_FINAL}.new"
mv "${WRFPRS_FINAL}.new" "${WRFPRS_FINAL}"

# ----------------------------------------------------------------------
# Append entire WRFTWO to WRFNAT.
# ----------------------------------------------------------------------

cat "${WRFNAT}" "${POSTFILE}" > "${WRFNAT_FINAL}.new"
mv "${WRFNAT_FINAL}.new" "${WRFNAT_FINAL}"

# ----------------------------------------------------------------------
# Save WRFTWO.
# ----------------------------------------------------------------------

mv "${POSTFILE}" "${WRFTWO_FINAL}"

# ----------------------------------------------------------------------
# Provide full HRRRE domain for creating WoFS initial conditions.
# ----------------------------------------------------------------------

mv "${WRFNAT_FINAL}" "${WRFNAT_HRRRE}"

echo "Post-UPP GRIB2 processing completed:"
ls -lh \
    "${WRFPRS_FINAL}" \
    "${WRFTWO_FINAL}" \
    "${WRFNAT_HRRRE}"

# ----------------------------------------------------------------------
# Final output checks.
# ----------------------------------------------------------------------

if [[ ! -s "${WRFPRS_FINAL}" ]]; then
    echo "ERROR: wrfprs_mem${ensmemid}_${FCST_TIME}.grib2 is missing"
    exit 1
fi

if [[ ! -s "${WRFTWO_FINAL}" ]]; then
    echo "ERROR: wrftwo_mem${ensmemid}_${FCST_TIME}.grib2 is missing"
    exit 1
fi

if [[ ! -s "${WRFNAT_HRRRE}" ]]; then
    echo "ERROR: wrfnat_hrrre_newse_mem${ensmemid}_${FCST_TIME}.grib2 is missing"
    exit 1
fi

# Copy the final WRFNAT GRIB2 IC file to COMOUT/INPUT for WPS.
COMOUT_INPUT="${COMOUT}/INPUT"
mkdir -p "${COMOUT_INPUT}"

MEMBER_DIR=$(printf "mem%02d" "${MEMBER}")
COMOUT_MEMBER="${COMOUT_INPUT}/${MEMBER_DIR}"

mkdir -p "${COMOUT_MEMBER}"

if [[ ! -d "${COMOUT_MEMBER}" ]]; then
    echo "ERROR: failed to create member output directory:"
    echo "       ${COMOUT_MEMBER}"
    exit 1
fi

WRFNAT_COMOUT="${COMOUT_MEMBER}/wrfnat_hrrre_newse_mem${ensmemid}_${FCST_TIME}.grib2"

echo "Copying final IC GRIB2:"
echo "  SOURCE: ${WRFNAT_HRRRE}"
echo "  DEST:   ${WRFNAT_COMOUT}"

cp -f "${WRFNAT_HRRRE}" "${WRFNAT_COMOUT}"

if [[ ! -s "${WRFNAT_COMOUT}" ]]; then
    echo "ERROR: failed to copy ${WRFNAT_HRRRE}"
    echo "       to ${WRFNAT_COMOUT}"
    exit 1
fi

echo "IC GRIB2 copied successfully:"
echo "  MEMBER: ${MEMBER}"
echo "  DIR:    ${COMOUT_MEMBER}"
echo "  FILE:   ${WRFNAT_COMOUT}"

echo "=============================================================="
echo "WoFS IC preparation completed successfully"
echo "MEMBER     = ${MEMBER}"
echo "INIT_TIME  = ${INIT_TIME}"
echo "DOMAIN     = ${DOMAIN}"
echo "FCST_TIME  = ${FCST_TIME}"
echo "OUTPUT     = ${POST_WORK_DIR}"
echo "=============================================================="

exit 0
