#!/bin/ksh --login

# Runtime modules are loaded by the BC_PREP Slurm wrapper.

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
MPIRUN=srun

# Set the pathname of the WRF namelist
WRF_NAMELIST=${DATAHOME}/wrfprd/namelist.input

# Make sure WRF_ROOT is set and that it exists
if [ ! "${WRF_ROOT}" ]; then
  ${ECHO} "ERROR: \$WRF_ROOT is not defined"
  exit 1
fi
if [ ! -d "${WRF_ROOT}" ]; then
  ${ECHO} "ERROR: WRF_ROOT directory, '${WRF_ROOT}', does not exist"
  exit 1
fi

# Make sure that WRF_CORE is set to a valid value, and set some core dependent vars
if [ ! "${WRF_CORE}" ]; then
  ${ECHO} "ERROR: \$WRF_CORE is not defined"
  exit 1
elif [ "${WRF_CORE}" == "ARW" ]; then
  REAL=${WRF_ROOT}/real.exe
  real_prefix="met_em"
elif [ "${WRF_CORE}" == "NMM" ]; then
  REAL=${WRF_ROOT}/real_nmm.exe
  real_prefix="met_nmm"
else
  ${ECHO} "ERROR: Unsupported WRF CORE, '${WRF_CORE}'"
  exit 1
fi

# Make sure the real executable exists
if [ ! -x ${REAL} ]; then
  ${ECHO} "ERROR: real executable, '${REAL}', does not exist, or is not executable"
  exit 1
fi

# Make sure the DATAHOME is defined (it doesn't need to exist yet)
if [ ! "${DATAHOME}" ]; then
  ${ECHO} "ERROR: \$DATAHOME is not defined"
  exit 1
fi

# If $INPUT_DATAHOME is not set, then make sure DATAHOME directory exists
if [ ! "${INPUT_DATAHOME}" ]; then
  INPUT_DATAHOME=${DATAHOME}
else
  if [ ! -d "${INPUT_DATAHOME}" ]; then
    ${ECHO} "ERROR: INPUT_DATAHOME directory, '${INPUT_DATAHOME}', does not exist"
    exit 1
  fi
fi
if [ ! -d "${DATAHOME}" ]; then
  ${MKDIR} -p ${DATAHOME}
fi

# Set the input format
if [ ! "${INPUT_FORMAT}" ]; then
  INPUT_FORMAT=NETCDF
fi
if [ "${INPUT_FORMAT}" == "NETCDF" ]; then
  real_suffix=".nc"
elif [ "${INPUT_FORMAT}" == "BINARY" ]; then :
  real_suffix=""
else
  ${ECHO} "ERROR: Unsupported INPUT_FORMAT, '${INPUT_FORMAT}'"
  exit 1
fi

if [ ! "${START_TIME}" ]; then
  ${ECHO} "ERROR: \$START_TIME is not defined!"
  exit 1
fi

# Make sure the FCST_LENGTH is defined
if [ ! "${FCST_LENGTH}" ]; then
  ${ECHO} "ERROR: \$FCST_LENGTH is not defined"
  exit 1
fi
# Make sure the RUNLENGTH_DFI_FWD is defined
if [ ! "${RUNLENGTH_DFI_FWD}" ]; then
  ${ECHO} "ERROR: \$RUNLENGTH_DFI_FWD is not defined"
  exit 1
fi
# Make sure the RUNLENGTH_DFI_BCK is defined
if [ ! "${RUNLENGTH_DFI_BCK}" ]; then
  ${ECHO} "ERROR: \$RUNLENGTH_DFI_BCK is not defined"
  exit 1
fi

# Make sure the FCST_INTERVAL is defined
if [ ! "${FCST_INTERVAL}" ]; then
  ${ECHO} "ERROR: \$FCST_INTERVAL is not defined"
  exit 1
fi

# Make sure NAMELIST is defined
if [ ! "${NAMELIST}" ]; then
  NAMELIST="wrf.nl"
fi

# Make sure NUM_DOMAINS is defined
if [ ! "${NUM_DOMAINS}" ]; then
  NUM_DOMAINS=1
fi

# Make sure number of perturbed members for boundary conditions is defined
if [ ! "${NUM_PERT_MEM_BC}" ]; then
  NUM_PERT_MEM_BC=0
fi

# Make sure NCL_SCRIPTS is defined
if [ ! "${NCL_SCRIPTS}" ]; then
  NCL_SCRIPTS=/misc/whome/role.wrfruc/HRRRE/bin/NCL
fi


# Initialize an array of WRF DAT files that need to be linked
set -A WRF_DAT_FILES ${STATIC_DIR}/run/LANDUSE.TBL          \
                     ${STATIC_DIR}/run/RRTM_DATA            \
                     ${STATIC_DIR}/run/RRTM_DATA_DBL        \
                     ${STATIC_DIR}/run/RRTMG_LW_DATA        \
                     ${STATIC_DIR}/run/RRTMG_LW_DATA_DBL    \
                     ${STATIC_DIR}/run/RRTMG_SW_DATA        \
                     ${STATIC_DIR}/run/RRTMG_SW_DATA_DBL    \
                     ${STATIC_DIR}/run/VEGPARM.TBL          \
                     ${STATIC_DIR}/run/GENPARM.TBL          \
                     ${STATIC_DIR}/run/SOILPARM.TBL         \
                     ${STATIC_DIR}/run/MPTABLE.TBL          \
                     ${STATIC_DIR}/run/URBPARM.TBL          \
                     ${STATIC_DIR}/run/URBPARM_UZE.TBL      \
                     ${STATIC_DIR}/run/ETAMPNEW_DATA        \
                     ${STATIC_DIR}/run/ETAMPNEW_DATA.expanded_rain        \
                     ${STATIC_DIR}/run/ETAMPNEW_DATA.expanded_rain_DBL    \
                     ${STATIC_DIR}/run/ETAMPNEW_DATA_DBL    \
                     ${STATIC_DIR}/run/co2_trans            \
                     ${STATIC_DIR}/run/ozone.formatted      \
                     ${STATIC_DIR}/run/ozone_lat.formatted  \
                     ${STATIC_DIR}/run/ozone_plev.formatted \
                     ${STATIC_DIR}/run/tr49t85              \
                     ${STATIC_DIR}/run/tr49t67              \
                     ${STATIC_DIR}/run/tr67t85              \
                     ${STATIC_DIR}/run/grib2map.tbl         \
                     ${STATIC_DIR}/run/gribmap.txt          \
                     ${STATIC_DIR}/run/aerosol.formatted      \
                     ${STATIC_DIR}/run/aerosol_lat.formatted  \
                     ${STATIC_DIR}/run/aerosol_lon.formatted  \
                     ${STATIC_DIR}/run/aerosol_plev.formatted \
                     ${STATIC_DIR}/run/bulkdens.asc_s_0_03_0_9  \
                     ${STATIC_DIR}/run/bulkradii.asc_s_0_03_0_9 \
                     ${STATIC_DIR}/run/capacity.asc           \
                     ${STATIC_DIR}/run/CCN_ACTIVATE.BIN       \
                     ${STATIC_DIR}/run/coeff_p.asc            \
                     ${STATIC_DIR}/run/coeff_q.asc            \
                     ${STATIC_DIR}/run/constants.asc          \
                     ${STATIC_DIR}/run/kernels.asc_s_0_03_0_9 \
                     ${STATIC_DIR}/run/kernels_z.asc          \
                     ${STATIC_DIR}/run/masses.asc             \
                     ${STATIC_DIR}/run/termvels.asc           \
                     ${STATIC_DIR}/run/wind-turbine-1.tbl

# Check to make sure WRF DAT files exist
for file in ${WRF_DAT_FILES[@]}; do
  if [ ! -s ${file} ]; then
    ${ECHO} "ERROR: ${file} either does not exist or is empty"
    exit 1
  fi
done

# Make sure START_TIME is defined and in the correct format
if [ `${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{10}$/'` ]; then
  START_TIME=`${ECHO} "${START_TIME}" | ${SED} 's/\([[:digit:]]\{2\}\)$/ \1/'`
else
  ${ECHO} "ERROR: start time, '${START_TIME}', is not in 'yyyymmddhh' or 'yyyymmdd hh' format"
  exit 1
fi
START_TIME=`${DATE} -d "${START_TIME} ${OFFSET} hours"`

# Calculate the forecast end time
END_TIME=`${DATE} -d "${START_TIME} ${FCST_LENGTH} hours"`

# Calculate the DFI forward end time
DFIFWD_END_TIME=`${DATE} -d "${START_TIME} ${RUNLENGTH_DFI_FWD} minutes"`

# Calculate the DFI backward end time
DFIBCK_END_TIME=`${DATE} -d "${START_TIME} ${RUNLENGTH_DFI_BCK} minutes ago"`

# Print run parameters
${ECHO}
${ECHO} "real.ksh started at `${DATE}`"
${ECHO}
${ECHO} "WRF_ROOT       = ${WRF_ROOT}"
${ECHO} "WRF_CORE       = ${WRF_CORE}"
${ECHO}
${ECHO} "DATAHOME  = ${DATAHOME}"
${ECHO}
${ECHO} "INPUT_DATAHOME = ${INPUT_DATAHOME}"
${ECHO} "INPUT_FORMAT   = ${INPUT_FORMAT}"
${ECHO}
${ECHO} "FCST_LENGTH    = ${FCST_LENGTH}"
${ECHO} "FCST_INTERVAL  = ${FCST_INTERVAL}"
${ECHO}
${ECHO} "START_TIME     = "`${DATE} +"%Y/%m/%d %H:%M:%S" -d "${START_TIME}"`
${ECHO} "END_TIME       = "`${DATE} +"%Y/%m/%d %H:%M:%S" -d "${END_TIME}"`
${ECHO} "DFIFWD_END_TIME= "`${DATE} +"%Y/%m/%d %H:%M:%S" -d "${DFIFWD_END_TIME}"`
${ECHO} "DFIBCK_END_TIME= "`${DATE} +"%Y/%m/%d %H:%M:%S" -d "${DFIBCK_END_TIME}"`
${ECHO} "STATIC_DIR = ${STATIC_DIR}"
${ECHO} "NAMELIST = ${NAMELIST}"
${ECHO} "NUM_DOMAINS = ${NUM_DOMAINS}"
${ECHO} "NUM_PERT_MEM_BC = ${NUM_PERT_MEM_BC}"
${ECHO} "NCL_SCRIPTS = ${NCL_SCRIPTS}"
${ECHO}

# Check to make sure the work directory (wrfprd) exists and cd into it
workdir=${DATAHOME}/wrfprd
${MKDIR} -p ${workdir}
cd ${workdir}

# Check to make sure the real input files (e.g. met_em.d01.*) are available
# and make links to them
fcst=0
while [ ${fcst} -le ${FCST_LENGTH} ]; do

  time_str=`${DATE} "+%Y-%m-%d_%H:%M:%S" -d "${START_TIME} ${fcst} hours"`
  time_str2=`${DATE} "+%Y-%m-%d_%H_%M_%S" -d "${START_TIME} ${fcst} hours"`

  DOMAIN=1
  while [[ $DOMAIN -le $NUM_DOMAINS ]];do

    if [ ! -r "${INPUT_DATAHOME}/wpsprd/${real_prefix}.d0${DOMAIN}.${time_str}${real_suffix}" ]; then
      echo "ERROR: Input file '${INPUT_DATAHOME}/wpsprd/${real_prefix}.d0${DOMAIN}.${time_str}${real_suffix}' is missing"
      exit 1
    fi
    ${RM} -f ${real_prefix}.d0${DOMAIN}.${time_str2}${real_suffix}
    ${LN} -s ${INPUT_DATAHOME}/wpsprd/${real_prefix}.d0${DOMAIN}.${time_str}${real_suffix} ${real_prefix}.d0${DOMAIN}.${time_str2}${real_suffix}

    (( DOMAIN += 1 ))
  done

  (( fcst = fcst + ${FCST_INTERVAL} ))
done

# Make links to the WRF DAT files
for file in ${WRF_DAT_FILES[@]}; do
  ${RM} -f `basename ${file}`
  ${LN} -s ${file}
done

# Get the start and end time components
start_year=`${DATE} +%Y -d "${START_TIME}"`
start_month=`${DATE} +%m -d "${START_TIME}"`
start_day=`${DATE} +%d -d "${START_TIME}"`
start_hour=`${DATE} +%H -d "${START_TIME}"`
start_minute=`${DATE} +%M -d "${START_TIME}"`
start_second=`${DATE} +%S -d "${START_TIME}"`
end_year=`${DATE} +%Y -d "${END_TIME}"`
end_month=`${DATE} +%m -d "${END_TIME}"`
end_day=`${DATE} +%d -d "${END_TIME}"`
end_hour=`${DATE} +%H -d "${END_TIME}"`
end_minute=`${DATE} +%M -d "${END_TIME}"`
end_second=`${DATE} +%S -d "${END_TIME}"`
start_YYYYMMDDHHMM=`${DATE} +%Y%m%d%H%M -d "${START_TIME}"`

# for DFI
dfi_fwdstop_year=`${DATE} +%Y -d "${DFIFWD_END_TIME}"`
dfi_fwdstop_month=`${DATE} +%m -d "${DFIFWD_END_TIME}"`
dfi_fwdstop_day=`${DATE} +%d -d "${DFIFWD_END_TIME}"`
dfi_fwdstop_hour=`${DATE} +%H -d "${DFIFWD_END_TIME}"`
dfi_fwdstop_minute=`${DATE} +%M -d "${DFIFWD_END_TIME}"`
dfi_fwdstop_second=`${DATE} +%S -d "${DFIFWD_END_TIME}"`
dfi_bckstop_year=`${DATE} +%Y -d "${DFIBCK_END_TIME}"`
dfi_bckstop_month=`${DATE} +%m -d "${DFIBCK_END_TIME}"`
dfi_bckstop_day=`${DATE} +%d -d "${DFIBCK_END_TIME}"`
dfi_bckstop_hour=`${DATE} +%H -d "${DFIBCK_END_TIME}"`
dfi_bckstop_minute=`${DATE} +%M -d "${DFIBCK_END_TIME}"`
dfi_bckstop_second=`${DATE} +%S -d "${DFIBCK_END_TIME}"`
real_fi_opt=3


# Compute number of days and hours for the run
(( run_days = 0 ))
(( run_hours = 0 ))

# Create patterns for updating the wrf namelist
run=[Rr][Uu][Nn]
equal=[[:blank:]]*=[[:blank:]]*
start=[Ss][Tt][Aa][Rr][Tt]
end=[Ee][Nn][Dd]
year=[Yy][Ee][Aa][Rr]
month=[Mm][Oo][Nn][Tt][Hh]
day=[Dd][Aa][Yy]
hour=[Hh][Oo][Uu][Rr]
minute=[Mm][Ii][Nn][Uu][Tt][Ee]
second=[Ss][Ee][Cc][Oo][Nn][Dd]
interval=[Ii][Nn][Tt][Ee][Rr][Vv][Aa][Ll]
#for DFI
dfi=[Dd][Ff][Ii]
opt=[Oo][Pp][Tt]
fwdstop=[Ff][Ww][Dd][Ss][Tt][Oo][Pp]
bckstop=[Bb][Cc][Kk][Ss][Tt][Oo][Pp]
runlength=[Rr][Uu][Nn][Ll][Ee][Nn][Gg][Tt][Hh]
fwd=[Ff][Ww][Dd]
bck=[Bb][Cc][Kk]

# Copy the wrf namelist to the workdir as namelist.input
#${CP} ${STATIC_DIR}/wrf.nl ${WRF_NAMELIST}
${CP} ${STATIC_DIR}/${NAMELIST} ${WRF_NAMELIST}

# Update the run_days in wrf namelist.input
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${run}_${day}[Ss]\)${equal}[[:digit:]]\{1,\}/\1 = ${run_days}/" \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update the run_hours in wrf namelist
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${run}_${hour}[Ss]\)${equal}[[:digit:]]\{1,\}/\1 = ${run_hours}/" \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update the start time in wrf namelist
#${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${start}_${year}\)${equal}[[:digit:]]\{4\}/\1 = ${start_year}, ${start_year}/" \
#   | ${SED} "s/\(${start}_${month}\)${equal}[[:digit:]]\{2\}/\1 = ${start_month}, ${start_month}/"                  \
#   | ${SED} "s/\(${start}_${day}\)${equal}[[:digit:]]\{2\}/\1 = ${start_day}, ${start_day}/"                        \
#   | ${SED} "s/\(${start}_${hour}\)${equal}[[:digit:]]\{2\}/\1 = ${start_hour}, ${start_hour}/"                     \
#   | ${SED} "s/\(${start}_${minute}\)${equal}[[:digit:]]\{2\}/\1 = ${start_minute}, ${start_minute}/"               \
#   | ${SED} "s/\(${start}_${second}\)${equal}[[:digit:]]\{2\}/\1 = ${start_second}, ${start_second}/"               \
#   > ${WRF_NAMELIST}.new
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${start}_${year}\)${equal}[[:digit:]]\{4\}/\1 = ${start_year}/" \
   | ${SED} "s/\(${start}_${month}\)${equal}[[:digit:]]\{2\}/\1 = ${start_month}/"                   \
   | ${SED} "s/\(${start}_${day}\)${equal}[[:digit:]]\{2\}/\1 = ${start_day}/"                       \
   | ${SED} "s/\(${start}_${hour}\)${equal}[[:digit:]]\{2\}/\1 = ${start_hour}/"                     \
   | ${SED} "s/\(${start}_${minute}\)${equal}[[:digit:]]\{2\}/\1 = ${start_minute}/"                 \
   | ${SED} "s/\(${start}_${second}\)${equal}[[:digit:]]\{2\}/\1 = ${start_second}/"                 \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update end time in namelist
#${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${end}_${year}\)${equal}[[:digit:]]\{4\}/\1 = ${end_year}, ${end_year}/" \
#   | ${SED} "s/\(${end}_${month}\)${equal}[[:digit:]]\{2\}/\1 = ${end_month}, ${end_month}/"                  \
#   | ${SED} "s/\(${end}_${day}\)${equal}[[:digit:]]\{2\}/\1 = ${end_day}, ${end_day}/"                        \
#   | ${SED} "s/\(${end}_${hour}\)${equal}[[:digit:]]\{2\}/\1 = ${end_hour}, ${end_hour}/"                     \
#   | ${SED} "s/\(${end}_${minute}\)${equal}[[:digit:]]\{2\}/\1 = ${end_minute}, ${end_minute}/"               \
#   | ${SED} "s/\(${end}_${second}\)${equal}[[:digit:]]\{2\}/\1 = ${end_second}, ${end_second}/"               \
#   > ${WRF_NAMELIST}.new
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${end}_${year}\)${equal}[[:digit:]]\{4\}/\1 = ${end_year}/" \
   | ${SED} "s/\(${end}_${month}\)${equal}[[:digit:]]\{2\}/\1 = ${end_month}/"                   \
   | ${SED} "s/\(${end}_${day}\)${equal}[[:digit:]]\{2\}/\1 = ${end_day}/"                       \
   | ${SED} "s/\(${end}_${hour}\)${equal}[[:digit:]]\{2\}/\1 = ${end_hour}/"                     \
   | ${SED} "s/\(${end}_${minute}\)${equal}[[:digit:]]\{2\}/\1 = ${end_minute}/"                 \
   | ${SED} "s/\(${end}_${second}\)${equal}[[:digit:]]\{2\}/\1 = ${end_second}/"                 \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update DFI forward end time in namelist
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${dfi}_${fwdstop}_${year}\)${equal}[[:digit:]]\{4\}/\1 = ${dfi_fwdstop_year}/" \
   | ${SED} "s/\(${dfi}_${fwdstop}_${month}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_fwdstop_month}/"     \
   | ${SED} "s/\(${dfi}_${fwdstop}_${day}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_fwdstop_day}/"         \
   | ${SED} "s/\(${dfi}_${fwdstop}_${hour}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_fwdstop_hour}/"       \
   | ${SED} "s/\(${dfi}_${fwdstop}_${minute}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_fwdstop_minute}/"   \
   | ${SED} "s/\(${dfi}_${fwdstop}_${second}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_fwdstop_second}/"   \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update DFI backward end time in namelist
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${dfi}_${bckstop}_${year}\)${equal}[[:digit:]]\{4\}/\1 = ${dfi_bckstop_year}/" \
   | ${SED} "s/\(${dfi}_${bckstop}_${month}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_bckstop_month}/"     \
   | ${SED} "s/\(${dfi}_${bckstop}_${day}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_bckstop_day}/"         \
   | ${SED} "s/\(${dfi}_${bckstop}_${hour}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_bckstop_hour}/"       \
   | ${SED} "s/\(${dfi}_${bckstop}_${minute}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_bckstop_minute}/"   \
   | ${SED} "s/\(${dfi}_${bckstop}_${second}\)${equal}[[:digit:]]\{2\}/\1 = ${dfi_bckstop_second}/"   \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update runlenfth_dfi_fwd  in namelist
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${runlength}_${dfi}_${fwd}\)${equal}[[:digit:]]\{1,\}/\1 = ${RUNLENGTH_DFI_FWD}/" \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update runlenfth_dfi_bck  in namelist
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${runlength}_${dfi}_${bck}\)${equal}[[:digit:]]\{1,\}/\1 = ${RUNLENGTH_DFI_BCK}/" \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Update dfi_opt  in namelist
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${dfi}_${opt}\)${equal}[[:digit:]]\{1,\}/\1 = ${real_fi_opt}/" \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}


# Update interval in namelist
(( fcst_interval_sec = ${FCST_INTERVAL} * 3600 ))
${CAT} ${WRF_NAMELIST} | ${SED} "s/\(${interval}${second}[Ss]\)${equal}[[:digit:]]\{1,\}/\1 = ${fcst_interval_sec}/" \
   > ${WRF_NAMELIST}.new
${MV} ${WRF_NAMELIST}.new ${WRF_NAMELIST}

# Move existing rsl files to a subdir if there are any
${ECHO} "Checking for pre-existing rsl files"
if [ -f "rsl.out.0000" ]; then
  rsldir=rsl.`${LS} -l --time-style=+%Y%m%d%H%M%S rsl.out.0000 | ${CUT} -d" " -f 7`
  ${MKDIR} ${rsldir}
  ${ECHO} "Moving pre-existing rsl files to ${rsldir}"
  ${MV} rsl.out.* ${rsldir}
  ${MV} rsl.error.* ${rsldir}
else
  ${ECHO} "No pre-existing rsl files were found"
fi

# Get the current time
now=`${DATE} +%Y%m%d%H%M%S`

# Run real
${MPIRUN} ${REAL}
error=$?
if [ ${error} -ne 0 ]; then
  ${ECHO} "ERROR: ${REAL} exited with status: ${error}"
  exit ${error}
else

  # Check to see if the output is there

  DOMAIN=1
  while [[ $DOMAIN -le $NUM_DOMAINS ]];do

    if [ ! -s "wrfinput_d0${DOMAIN}" ]; then
      ${ECHO} "${REAL} failed to complete"
      ${ECHO} "wrfinput_d0${DOMAIN} not found"
      exit 1
    fi

    (( DOMAIN += 1 ))
  done

  if [ ! -s "wrfbdy_d01" ]; then
    ${ECHO} "warning:  no wrfbdy_d01 found"
  fi

  ${ECHO} "real_arw.ksh completed successfully at `${DATE}`"
fi


# Create perturbed boundary conditions
if [ ${NUM_PERT_MEM_BC} -ne 0 ]; then

  ${ECHO} "perturbing members"

  ensmem=1
  while [[ $ensmem -le $NUM_PERT_MEM_BC ]];do
    ensmemid=`printf %4.4i $ensmem`
    cp wrfbdy_d01 wrfbdy_d01_mem${ensmemid} &
    (( ensmem += 1 ))
  done

  wait

  if [ -s "pert_bc_multi_time.ncl" ]; then
    ${RM} pert_bc_multi_time.ncl
  fi
  cp ${NCL_SCRIPTS}/pert_bc_multi_time.ncl .

  ensmem=1
  while [[ $ensmem -le $NUM_PERT_MEM_BC ]];do
    ensmemid=`printf %4.4i $ensmem`
    if [ -s "run_ncl_${ensmemid}" ]; then
      ${RM} run_ncl_${ensmemid}
    fi
    cat << EOF > run_ncl_${ensmemid}
ncl 'ENSMEMID="${ensmemid}"' 'WORKDIR="${workdir}"' pert_bc_multi_time.ncl
EOF
    chmod +x run_ncl_${ensmemid}
    ./run_ncl_${ensmemid} > pert_bc_${ensmemid}.out &

    sleep 1

    (( ensmem += 1 ))
  done

  wait

  ${ECHO} "finished perturbing members at `${DATE}`"

fi


# clean up unneeded files
dir=${DATAHOME}/extprd
${ECHO} "removing ${dir}"
${RM} -rf ${dir}

dir=${DATAHOME}/ungribprd
${ECHO} "removing ${dir}"
${RM} -rf ${dir}

#dir=${DATAHOME}/wpsprd
#${ECHO} "removing ${dir}"
#${RM} -rf ${dir}


# Save a copy of the RSL files
rsldir=rsl.real.${now}
${MKDIR} ${rsldir}
mv rsl.out.* ${rsldir}
mv rsl.error.* ${rsldir}

${ECHO} "" > real_finished

exit 0
