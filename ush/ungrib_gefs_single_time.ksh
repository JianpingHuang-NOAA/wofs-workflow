#!/bin/ksh --login


# Make sure we are using GMT time zone for time computations
export TZ="GMT"

ulimit -s 512000

# Make sure we give other group members write access to the files we create
umask 2

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

# Set up some constants
export WPSNAMELIST=${STATIC_DIR}/namelist.wps
export UNGRIB=${WPS_ROOT}/ungrib.exe

# Print run parameters
${ECHO}
${ECHO} "ungrib_gefs.ksh started at `${DATE}`"
${ECHO}
${ECHO} "MEMBER         = ${MEMBER}"
${ECHO} "WPS_ROOT       = ${WPS_ROOT}"
${ECHO} "DATAHOME       = ${DATAHOME}"
${ECHO} "SOURCE         = ${SOURCE}"
${ECHO} "SOURCE_PATH    = ${SOURCE_PATH}"
${ECHO} "START_TIME     = ${START_TIME}"
${ECHO} "FCST_LEAD_TIME = ${FCST_LEAD_TIME}"
${ECHO}

# Check to make sure that WPS_ROOT exists
if [ ! -d ${WPS_ROOT} ]; then
  ${ECHO} "ERROR: ${WPS_ROOT} does not exist"
  exit 1
fi

# Check to make sure the ungrib executable exists
if [ ! -x ${UNGRIB} ]; then
  ${ECHO} "ERROR: ${UNGRIB} does not exist, or is not executable"
  exit 1
fi

# Check to make sure the ensemble member has been specified
if [ ! "${MEMBER}" ]; then
  ${ECHO} "ERROR: MEMBER has not been specified"
  exit 1
fi

# Check to make sure the source has been specified
if [ ! "${SOURCE}" ]; then
  ${ECHO} "ERROR: The data source (e.g. ETA, AVN, RUC, etc.) has not been specified"
  exit 1
fi

# Check to make sure the source path has been specified
if [ ! "${SOURCE_PATH}" ]; then
  ${ECHO} "ERROR: The data source path has not been specified"
  exit 1
fi

# Check to make sure the namelist exists
if [ ! -r ${WPSNAMELIST} ]; then
  ${ECHO} "ERROR: ${WPSNAMELIST} does not exist, or is not readable"
  exit 1
fi

# Check to make sure START_TIME was specified
if [ ! "${START_TIME}" ]; then
  ${ECHO} "ERROR: \$START_TIME is not set!"
  exit 1
fi

# Check to make sure FCST_LEAD_TIME was specified
if [ ! "${FCST_LEAD_TIME}" ]; then
  ${ECHO} "ERROR: \$FCST_LENGTH is not set!"
  exit 1
fi


# Check to make sure the Vtable for the source exists
if [ ! -r ${STATIC_DIR}/Vtable.${SOURCE} ]; then
  ${ECHO} "ERROR: ${STATIC_DIR}/Vtable.${SOURCE} does not exist or is not readable"
  exit 1
fi

# Make sure the START_TIME is in the correct format
if [ `${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{10}$/'` ]; then
  START_TIME=`${ECHO} "${START_TIME}" | ${SED} 's/\([[:digit:]]\{2\}\)$/ \1/'`
elif [ ! "`${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{8}[[:blank:]]{1}[[:digit:]]{2}$/'`" ]; then
  ${ECHO} "ERROR: start time, '${START_TIME}', is not in 'yyyymmddhh' or 'yyyymmdd hh' format"
  exit 1
fi

# Calculate time and date strings
END_TIME=`${DATE} -d "${START_TIME} ${FCST_LEAD_TIME} hours"`
end_yyyymmdd_hhmmss=`${DATE} +%Y-%m-%d_%H:%M:%S -d "${END_TIME}"`
echo $START_TIME
echo $FCST_LEAD_TIME
echo $END_TIME
echo $end_yyyymmdd_hhmmss
(( fcst_interval_sec = ${FCST_LEAD_TIME} * 3600 ))



# Set up the work directory and cd into it
workdir=${DATAHOME}/ungribprd/${SOURCE}.`${DATE} +%s.%N`
${RM} -rf ${workdir}
${MKDIR} -p ${workdir}
cd ${workdir}

# Link the Vtable into the work directory
${RM} -f Vtable
${LN} -s ${STATIC_DIR}/Vtable.${SOURCE} Vtable

# Copy the namelist into the work directory
${CP} ${WPSNAMELIST} .
WPSNAMELIST=${workdir}/`basename ${WPSNAMELIST}`

# Create a poor man's namelist hash
#
# Strip off comments, section names, slashes, and remove white space.
# Then loop over each line to create an array of names, an array of
# values, and variables that contain the index of the names in the
# array of names.  Each variable that contains an index of a namelist
# name is named $_NAME_ where 'NAME' is one of the names in the namelist
# The $_NAME_ vars are always capitalized even if the names in the namelist
# are not.
i=-1
for name in `${SED} 's/[[:blank:]]//g' ${WPSNAMELIST} | ${AWK} '/^[^#&\/]/' | ${SED} 's/[[:cntrl:]]//g'`
do
  # If there's an = in the line
  if [ `${ECHO} ${name} | ${AWK} /=/` ]; then
    (( i=i+1 ))
    left=`${ECHO} ${name} | ${CUT} -d"=" -f 1 | ${AWK} '{print toupper($0)}'`
    right=`${ECHO} ${name} | ${CUT} -d"=" -f 2`
#    var[${i}]=${left}
    val[${i}]=${right}
    (( _${left}_=${i} ))
  else
    val[${i}]=${val[${i}]}${name}
  fi
done

# Create patterns for updating the namelist
equal=[[:blank:]]*=[[:blank:]]*
start=[Ss][Tt][Aa][Rr][Tt]
end=[Ee][Nn][Dd]
date=[Dd][Aa][Tt][Ee]
interval=[Ii][Nn][Tt][Ee][Rr][Vv][Aa][Ll]
seconds=[Ss][Ee][Cc][Oo][Nn][Dd][Ss]
prefix=[Pp][Rr][Ee][Ff][Ii][Xx]
yyyymmdd_hhmmss='[[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}'

# Update the start and end date in namelist
${CAT} ${WPSNAMELIST} | ${SED} "s/\(${start}_${date}\)${equal}'${yyyymmdd_hhmmss}'/\1 = '${end_yyyymmdd_hhmmss}'/" \
                      | ${SED} "s/\(${end}_${date}\)${equal}'${yyyymmdd_hhmmss}'/\1 = '${end_yyyymmdd_hhmmss}'/"     \
                      > ${WPSNAMELIST}.new
${MV} ${WPSNAMELIST}.new ${WPSNAMELIST}

# Update interval in namelist
${CAT} ${WPSNAMELIST} | ${SED} "s/\(${interval}_${seconds}\)${equal}[[:digit:]]\{1,\}/\1 = ${fcst_interval_sec}/" \
                      > ${WPSNAMELIST}.new
${MV} ${WPSNAMELIST}.new ${WPSNAMELIST}

# Update the prefix in the namelist
${CAT} ${WPSNAMELIST} | ${SED} "s/\(${prefix}\)${equal}'[[:alnum:]]\{1,\}'/\1 = '${SOURCE}'/" \
                      > ${WPSNAMELIST}.new
${MV} ${WPSNAMELIST}.new ${WPSNAMELIST}


# Get time components to use for matching with grib file
start_year=`${DATE} +%Y -d "${START_TIME}"`
start_yr=`${DATE} +%y -d "${START_TIME}"`
start_month=`${DATE} +%m -d "${START_TIME}"`
start_day=`${DATE} +%d -d "${START_TIME}"`
start_jday=`${DATE} +%j -d "${START_TIME}"`
start_hour=`${DATE} +%H -d "${START_TIME}"`

fcst_hour=`printf %6.6i $FCST_LEAD_TIME`

if [ $MEMBER -eq 00 ]; then
  PATH1=${SOURCE_PATH}/gec${MEMBER}
  PATH2=${SOURCE_PATH}/pgrb2b/gec${MEMBER}
else
  PATH1=${SOURCE_PATH}/gep${MEMBER}
  PATH2=${SOURCE_PATH}/pgrb2b/gep${MEMBER}
fi

cd ${workdir}

grib_file=${PATH2}/${start_yr}${start_jday}${start_hour}${fcst_hour}

${ECHO} "grib_file = ${grib_file}"

if [ ! -r ${grib_file} ]; then

  ${ECHO} "ERROR: ${grib_file} does not exist, or is not readable"
  exit 1

else

  ${LN} -s ${grib_file} ${workdir}/GRIBFILE.AAA

  # Run ungrib
  ${UNGRIB}
  error=$?
  if [ ${error} -ne 0 ]; then
    ${ECHO} "ERROR: ${UNGRIB} exited with status: ${error}"
    exit ${error}
  fi

  filename=${workdir}/${SOURCE}:`${DATE} +%Y-%m-%d_%H -d "${START_TIME} ${FCST_LEAD_TIME} hours"`
  if [ ! -s ${filename} ]; then
    echo "ERROR: ${filename} is missing"
    exit 1
  fi

  # Move the output files to the extprd directory
  ${MKDIR} -p ${DATAHOME}/extprd
  for file in `${LS} -1 ${workdir} | ${GREP} ^${SOURCE}:`; do
    ${MV} ${file} ${DATAHOME}/extprd
  done

fi

${ECHO} "ungrib.ksh terminated at `${DATE}`"

exit 0
