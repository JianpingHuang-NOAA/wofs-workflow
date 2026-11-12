#!/bin/ksh

# Runtime modules are initialized by the BC_PREP wrapper.
: "${WOFS_PYTHON:?ERROR: WOFS_PYTHON must be defined}"

PY="${WOFS_PYTHON}"

echo "Python interpreter: ${PY}"

if ! "${PY}" -c 'import numpy, netCDF4, pygrib'; then
    echo "ERROR: Required Python packages are unavailable" >&2
    exit 1
fi

echo "wgrib2 path:"
which wgrib2

# Set up paths to shell commands
LS=/bin/ls
LN=/bin/ln
RM=/bin/rm
MKDIR=/bin/mkdir
CP=/bin/cp
MV=/bin/mv
ECHO=/bin/echo
CAT=/bin/cat
GREP=/bin/grep
CUT=`which cut`
AWK="/bin/gawk --posix"
SED=/bin/sed
DATE=/bin/date
BC=/usr/bin/bc


# Make sure HRRR_DIR is set
if [ ! "${HRRR_DIR}" ]; then
  ${ECHO} "ERROR:  HRRR_DIR is not defined"
  exit 1
fi

# Make sure DATAHOME is set
if [ ! "${DATAHOME}" ]; then
  ${ECHO} "ERROR:  DATAHOME is not defined"
  exit 1
fi

# Make sure DATAHOME_GEFS is set
if [ ! "${DATAHOME_GEFS}" ]; then
  ${ECHO} "ERROR:  DATAHOME_GEFS is not defined"
  exit 1
fi

# Make sure NCL_SCRIPTS is set
if [ ! "${NCL_SCRIPTS}" ]; then
  ${ECHO} "ERROR:  NCL_SCRIPTS is not defined"
  exit 1
fi

# Make sure MEMBER is set
if [ ! "${MEMBER}" ]; then
  ${ECHO} "ERROR:  MEMBER is not defined"
  exit 1
fi

# Make sure FCST_LEAD_TIME is set
if [ ! "${FCST_LEAD_TIME}" ]; then
  ${ECHO} "ERROR:  FCST_LEAD_TIME is not defined"
  exit 1
fi

# Make sure SOIL_FROM_WRFPRS is set
if [ ! "${SOIL_FROM_WRFPRS}" ]; then
  SOIL_FROM_WRFPRS=0
fi

# Make sure MIN_FILE_SIZE is set
if [ ! ${MIN_FILE_SIZE} ]; then
  ${ECHO} "setting value of MIN_FILE_SIZE"
  MIN_FILE_SIZE=0
fi
${ECHO} "MIN_FILE_SIZE = ${MIN_FILE_SIZE}"

# Make sure START_TIME is defined and in the correct format
if [ `${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{10}$/'` ]; then
  START_TIME=`${ECHO} "${START_TIME}" | ${SED} 's/\([[:digit:]]\{2\}\)$/ \1/'`
else
  ${ECHO} "ERROR: start time, '${START_TIME}', is not in 'yyyymmddhh' or 'yyyymmdd hh' format"
  exit 1
fi
START_TIME=`${DATE} -d "${START_TIME}"`

# Calculate the forecast valid time
END_TIME=`${DATE} -d "${START_TIME} ${FCST_LEAD_TIME} hours"`

ensmemid=`printf %4.4i $MEMBER`

# Print run parameters
${ECHO}
${ECHO} "perturb_hrrr.ksh started at `${DATE}`"
${ECHO}
${ECHO} "MEMBER            = ${MEMBER}"
${ECHO} "ensmemid          = ${ensmemid}"
${ECHO} "FCST_LEAD_TIME    = ${FCST_LEAD_TIME}"
${ECHO} "HRRR_DIR          = ${HRRR_DIR}"
if [ "${HRRR_WRFPRS_DIR}" ]; then
  ${ECHO} "HRRR_WRFPRS_DIR   = ${HRRR_WRFPRS_DIR}"
fi
${ECHO} "SOIL_FROM_WRFPRS  = ${SOIL_FROM_WRFPRS}"
${ECHO} "DATAHOME          = ${DATAHOME}"
${ECHO} "DATAHOME_GEFS     = ${DATAHOME_GEFS}"
${ECHO} "NCL_SCRIPTS       = ${NCL_SCRIPTS}"
${ECHO} "START_TIME        = "`${DATE} +"%Y/%m/%d %H:%M:%S" -d "${START_TIME}"`
${ECHO} "END_TIME          = "`${DATE} +"%Y/%m/%d %H:%M:%S" -d "${END_TIME}"`
${ECHO}


# Create the work directory if it doesn't already exist.
if [ ! -d "${DATAHOME}" ]; then
  ${MKDIR} -p ${DATAHOME}
fi
cd ${DATAHOME}


# Check for existence of HRRR forecast file (grib format)
YYJJJHH=`${DATE} +%y%j%H -d "${START_TIME}"`
FF=`printf %2.2i $FCST_LEAD_TIME`
FFFFFF=`printf %6.6i $FCST_LEAD_TIME`
hrrr_file=${HRRR_DIR}/${YYJJJHH}${FFFFFF}

# HRRR source files on Ursa have no .grib2 extension.
# Provide an extension-bearing symlink for NCL in the working directory.
hrrr_ncl_file=${DATAHOME}/hrrr_input_${FF}.grib2

if [ ! -s "${hrrr_file}" ]; then
  echo "ERROR: Missing HRRR input: ${hrrr_file}"
  exit 1
fi

if [ -e "${hrrr_ncl_file}" ] || [ -L "${hrrr_ncl_file}" ]; then
  echo "ERROR: NCL input path already exists: ${hrrr_ncl_file}"
  exit 1
fi

ln -s "${hrrr_file}" "${hrrr_ncl_file}"

if [ -r "${hrrr_file}" ]; then
  target_file=wrfnat_pert_hrrr_mem${ensmemid}_${FF}.grib2
  if [ -r "${target_file}" ]; then
    ${ECHO} "removing existing ${target_file}"
    ${RM} ${target_file}
  fi
else
  ${ECHO} "ERROR: ${hrrr_file} not found"
  exit 1
fi

# Check for existence of HRRR wrfprs (if needed for soil fields)
if [ ${SOIL_FROM_WRFPRS} -eq 1 ]; then
  if [ ! "${HRRR_WRFPRS_DIR}" ]; then
    ${ECHO} "ERROR:  HRRR_WRFPRS_DIR is not defined"
    exit 1
  else
    hrrr_wrfprs_file=${HRRR_WRFPRS_DIR}/${YYJJJHH}${FFFFFF}
    if [ ! -r "${hrrr_wrfprs_file}" ]; then
      ${ECHO} "ERROR: ${hrrr_wrfprs_file} not found"
      exit 1
    fi
  fi
fi

# Remove old files from any previous failed calls to this script.
if [ -r "perturbed_hrrr_fields_${FF}.nc" ]; then
  ${RM} perturbed_hrrr_fields_${FF}.nc
fi
if [ -r "pert_${FF}_time1.nc" ]; then
  ${RM} pert_${FF}_time1.nc
fi
if [ -r "pert_${FF}_time2.nc" ]; then
    ${RM} pert_${FF}_time2.nc
fi

# Find the GEFS member at the closest time at or before the HRRR forecast time.
t1=0
found_gefs=0
while [ ${t1} -ge -6 ]; do
  YYYYMMDDHH=`${DATE} +%Y%m%d%H -d "${END_TIME} ${t1} hours"`
  gefs_member_time1=${DATAHOME_GEFS}/${YYYYMMDDHH}/mem${MEMBER}/wrfprd/wrfinput_d01
  gefs_mean_time1=${DATAHOME_GEFS}/${YYYYMMDDHH}/mean/wrfinput_d01
  if [ -r "${gefs_member_time1}" ]; then
    if [ -r "${gefs_mean_time1}" ]; then
      found_gefs=1
      break
    fi
  fi
  (( t1 -= 1 ))
done

if [ ${found_gefs} -eq 0 ]; then
  ${ECHO} "ERROR: no match found for gefs_member_time1 and gefs_mean_time1"
  exit 1
fi

${ECHO} "gefs_member_time1 = ${gefs_member_time1}"
${ECHO} "gefs_mean_time1 = ${gefs_mean_time1}"
${ECHO} "t1 = ${t1}"

# Find the GEFS member at the closest time at or after the HRRR forecast time.
t2=0
found_gefs=0
while [ ${t2} -le 6 ]; do
  YYYYMMDDHH=`${DATE} +%Y%m%d%H -d "${END_TIME} ${t2} hours"`
  gefs_member_time2=${DATAHOME_GEFS}/${YYYYMMDDHH}/mem${MEMBER}/wrfprd/wrfinput_d01
  gefs_mean_time2=${DATAHOME_GEFS}/${YYYYMMDDHH}/mean/wrfinput_d01
  if [ -r "${DATAHOME_GEFS}/${YYYYMMDDHH}/mem${MEMBER}/wrfprd/wrfinput_d01" ]; then
    if [ -r "${DATAHOME_GEFS}/${YYYYMMDDHH}/mean/wrfinput_d01" ]; then
      found_gefs=1
      break
    fi
  fi
  (( t2 += 1 ))
done

if [ ${found_gefs} -eq 0 ]; then
  ${ECHO} "ERROR: no valid time found for gefs_time_2"
  exit 1
fi

${ECHO} "gefs_member_time2 = ${gefs_member_time2}"
${ECHO} "gefs_mean_time2 = ${gefs_mean_time2}"
${ECHO} "t2 = ${t2}"


# Produce NetCDF files with the GEFS perturbations at the two times.
ncdiff -v U,V,T,QVAPOR,PH ${gefs_member_time1} ${gefs_mean_time1} pert_${FF}_time1.nc
ncdiff -v U,V,T,QVAPOR,PH ${gefs_member_time2} ${gefs_mean_time2} pert_${FF}_time2.nc

# Produce a NetCDF file that contains the time-interpolated GEFS perturbations
# added to the HRRR forecast fields.
if [ -s "run_ncl_${FF}" ]; then
  ${RM} run_ncl_${FF}
fi
cat << EOF > run_ncl_${FF}
ncl 'HRRR_FCST="${hrrr_ncl_file}"' 'GEFSPERTTIME1="pert_${FF}_time1.nc"' 'GEFSPERTTIME2="pert_${FF}_time2.nc"' 'T1="${t1}"' 'T2="${t2}"' 'PERT_HRRR="perturbed_hrrr_fields_${FF}.nc"' ${NCL_SCRIPTS}/perturb_hrrr.ncl
EOF
chmod +x run_ncl_${FF}
./run_ncl_${FF} > pert_hrrr_${FF}.out

success=`grep completion pert_hrrr_${FF}.out | wc -l`
${ECHO} "success=${success}"
if [ ${success} -ne 1 ]; then
  ${ECHO} "ERROR: NCL script did not run to completion"
  exit 1
fi

# Replace the HRRR forecast fields in the grib file with the perturbed fields from the NetCDF file.

unperturbed_forecast=unperturbed_hrrr_forecast_${FF}.grib2

# Produce template files for the 5 perturbed 3-D variables
wgrib2 ${hrrr_file} -match ":TMP:" -match "hybrid level" -set_grib_type simple -grib_out TMP_template_${FF}.grib2
wgrib2 ${hrrr_file} -match ":UGRD:" -match "hybrid level" -set_grib_type simple -grib_out UGRD_template_${FF}.grib2
wgrib2 ${hrrr_file} -match ":VGRD:" -match "hybrid level" -set_grib_type simple -grib_out VGRD_template_${FF}.grib2
wgrib2 ${hrrr_file} -match ":SPFH:" -match "hybrid level" -set_grib_type simple -grib_out SPFH_template_${FF}.grib2
wgrib2 ${hrrr_file} -match ":HGT:" -match "hybrid level" -set_grib_type simple -grib_out HGT_template_${FF}.grib2

# Save fields at other levels
wgrib2 ${hrrr_file} -match ":TMP:" -not "hybrid level" -grib TMP_other_${FF}.grib2
wgrib2 ${hrrr_file} -match ":UGRD:" -not "hybrid level" -grib UGRD_other_${FF}.grib2
wgrib2 ${hrrr_file} -match ":VGRD:" -not "hybrid level" -grib VGRD_other_${FF}.grib2
wgrib2 ${hrrr_file} -match ":SPFH:" -not "hybrid level" -grib SPFH_other_${FF}.grib2
wgrib2 ${hrrr_file} -match ":HGT:" -not "hybrid level" -grib HGT_other_${FF}.grib2

# Remove unperturbed fields that will be replaced with perturbed fields
wgrib2 ${hrrr_file} -not_if "TMP" -not_if "SPFH" -not_if "UGRD" -not_if "VGRD" -not_if "HGT" -grib ${unperturbed_forecast}


# Use python (pygrib) to insert the perturbed values (netcdf) into the grib arrays
for VAR in TMP UGRD VGRD SPFH HGT
do
  NCFILE="perturbed_hrrr_fields_${FF}.nc"
  NCVAR="${VAR}_P0_L105_GLC0"
  TEMPLATE="${VAR}_template_${FF}.grib2"
  OUTPUT="${VAR}_${FF}.grib2"

  echo "Converting ${VAR} from NetCDF to GRIB2"

  if [ ! -s "${NCFILE}" ]; then
    echo "ERROR: Missing NetCDF input: ${NCFILE}" >&2
    exit 1
  fi

  if [ ! -s "${TEMPLATE}" ]; then
    echo "ERROR: Missing GRIB2 template: ${TEMPLATE}" >&2
    exit 1
  fi

  # Prevent stale output from masking a failed conversion.
  rm -f -- "${OUTPUT}" || exit 1

  if ! "${PY}" "${NCL_SCRIPTS}/netcdf_to_grib.py" \
      "${NCFILE}" "${NCVAR}" "${TEMPLATE}" "${OUTPUT}"
  then
    echo "ERROR: Python GRIB2 conversion failed for ${VAR}" >&2
    exit 1
  fi

  if [ ! -s "${OUTPUT}" ]; then
    echo "ERROR: Missing GRIB2 output: ${OUTPUT}" >&2
    exit 1
  fi

  TEMPLATE_INV=$(wgrib2 "${TEMPLATE}" -s) || exit 1
  OUTPUT_INV=$(wgrib2 "${OUTPUT}" -s) || exit 1

  TEMPLATE_COUNT=$(printf '%s\n' "${TEMPLATE_INV}" | grep -c .)
  OUTPUT_COUNT=$(printf '%s\n' "${OUTPUT_INV}" | grep -c .)

  if [ "${TEMPLATE_COUNT}" -le 0 ] || \
     [ "${TEMPLATE_COUNT}" -ne "${OUTPUT_COUNT}" ]; then
    echo "ERROR: GRIB2 record count mismatch for ${VAR}" >&2
    echo "Template=${TEMPLATE_COUNT}, Output=${OUTPUT_COUNT}" >&2
    exit 1
  fi

  echo "[PASS] ${VAR}: ${OUTPUT_COUNT} GRIB2 records"
done

if [ ${SOIL_FROM_WRFPRS} -eq 1 ]; then
  wgrib2 ${unperturbed_forecast} -not_if "SOILW" -grib unperturbed_no_soilw_${FF}.grib2
  wgrib2 ${hrrr_wrfprs_file} -match ":TSOIL:" -grib TSOIL_${FF}.grib2
  wgrib2 ${hrrr_wrfprs_file} -match ":SOILW:" -grib SOILW_${FF}.grib2
  ${CAT} unperturbed_no_soilw_${FF}.grib2 TSOIL_${FF}.grib2 SOILW_${FF}.grib2 TMP_${FF}.grib2 UGRD_${FF}.grib2 VGRD_${FF}.grib2 SPFH_${FF}.grib2 HGT_${FF}.grib2 TMP_other_${FF}.grib2 UGRD_other_${FF}.grib2 VGRD_other_${FF}.grib2 SPFH_other_${FF}.grib2 HGT_other_${FF}.grib2 > ${target_file}
  ${RM} TSOIL_${FF}.grib2
  ${RM} SOILW_${FF}.grib2
  ${RM} unperturbed_no_soilw_${FF}.grib2
else
  ${CAT} ${unperturbed_forecast} TMP_${FF}.grib2 UGRD_${FF}.grib2 VGRD_${FF}.grib2 SPFH_${FF}.grib2 HGT_${FF}.grib2 TMP_other_${FF}.grib2 UGRD_other_${FF}.grib2 VGRD_other_${FF}.grib2 SPFH_other_${FF}.grib2 HGT_other_${FF}.grib2 > ${target_file}
fi

# Check file size (to catch intermittent Jet problem)
file_size=$(wc -c ${target_file} | awk '{print $1}')
${ECHO} "size of wrfnat file = ${file_size}"
if [ ${file_size} -lt ${MIN_FILE_SIZE} ]; then
  ${ECHO} "file too small ... exiting"
  exit 1
fi

# Clean up
${RM} pert_${FF}_time1.nc
${RM} pert_${FF}_time2.nc
if [ "${KEEP_INTERMEDIATE:-NO}" != "YES" ]; then
  ${RM} perturbed_hrrr_fields_${FF}.nc
fi

${RM} ${unperturbed_forecast}

${RM} TMP_${FF}.grib2
${RM} UGRD_${FF}.grib2
${RM} VGRD_${FF}.grib2
${RM} SPFH_${FF}.grib2
${RM} HGT_${FF}.grib2

${RM} TMP_other_${FF}.grib2
${RM} UGRD_other_${FF}.grib2
${RM} VGRD_other_${FF}.grib2
${RM} SPFH_other_${FF}.grib2
${RM} HGT_other_${FF}.grib2

if [ "${KEEP_INTERMEDIATE:-NO}" != "YES" ]; then
  ${RM} TMP_template_${FF}.grib2
  ${RM} UGRD_template_${FF}.grib2
  ${RM} VGRD_template_${FF}.grib2
  ${RM} SPFH_template_${FF}.grib2
  ${RM} HGT_template_${FF}.grib2
else
  echo "KEEP_INTERMEDIATE=YES"
  echo "Retaining perturbed NetCDF and GRIB2 templates"
fi

${RM} run_ncl_${FF}

${ECHO} "finished perturbing HRRR forecast at `${DATE}`"

exit 0
