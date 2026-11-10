#!/bin/ksh --login


# Make sure we are using GMT time zone for time computations
export TZ="GMT"

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
CUT=/bin/cut
AWK="/bin/gawk --posix"
SED=/bin/sed
DATE=/bin/date
BC=/usr/bin/bc


# DATAHOME_GEFS=/mnt/lfs5/BMC/wrfruc/WoF_BC/gefs
# DATAHOME_HRRR=/mnt/lfs5/BMC/wrfruc/WoF_BC/pert_hrrr
# START_TIME=2022030300
# DAYS_AGO=2


# Make sure DATAHOME directories are defined
if [ ! ${DATAHOME_GEFS} ]; then
  ${ECHO} "exiting because ${DATAHOME_GEFS} is not defined"
  exit 1
fi
if [ ! ${DATAHOME_HRRR} ]; then
  ${ECHO} "exiting because ${DATAHOME_HRRR} is not defined"
  exit 1
fi
if [ ! ${LOG_DIR} ]; then
  ${ECHO} "exiting because ${LOG_DIR} is not defined"
  exit 1
fi

# Print run parameters
${ECHO}
${ECHO} "delete_hrrr_gefs.ksh started at `${DATE}`"
${ECHO}
${ECHO} "DATAHOME_GEFS = ${DATAHOME_GEFS}"
${ECHO} "DATAHOME_HRRR = ${DATAHOME_HRRR}"
${ECHO} "LOG_DIR = ${LOG_DIR}"
${ECHO} "START_TIME = ${START_TIME}"
${ECHO} "DAYS_AGO = ${DAYS_AGO}"


# Convert START_TIME from 'YYYYMMDDHH' format to Unix date format, e.g. "Fri May  6 19:50:23 GMT 2005"
if [ `${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{10}$/'` ]; then
  START_TIME=`${ECHO} "${START_TIME}" | ${SED} 's/\([[:digit:]]\{2\}\)$/ \1/'`
else
  ${ECHO} "ERROR: start time, '${START_TIME}', is not in 'yyyymmddhh' or 'yyyymmdd hh' format"
  exit 1
fi
START_TIME=`${DATE} -d "${START_TIME}"`
PURGE_TIME=`${DATE} +"%Y%m%d%H" -d "${START_TIME}  ${DAYS_AGO} days ago"`
PURGE_YYYYMMDD=`${DATE} +"%Y%m%d" -d "${START_TIME}  ${DAYS_AGO} days ago"`
${ECHO} "PURGE_TIME = ${PURGE_TIME}"
${ECHO} "PURGE_YYYYMMDD = ${PURGE_YYYYMMDD}"

cd ${DATAHOME_GEFS}
${RM} -rf ${PURGE_YYYYMMDD}??

HRRR_DIR=${DATAHOME_HRRR}/${PURGE_YYYYMMDD}12
${ECHO} "HRRR_DIR = ${HRRR_DIR}"

if [ -d ${HRRR_DIR} ]; then
  cd ${HRRR_DIR}
  ${RM} -rf postprd_mem????
fi

echo "removing log files in ${LOG_DIR}"
cd ${LOG_DIR}
\rm comp*${PURGE_YYYYMMDD}*log*
\rm met*${PURGE_YYYYMMDD}*log*
\rm pert*${PURGE_YYYYMMDD}*log*
\rm real*${PURGE_YYYYMMDD}*log*
\rm ungrib*${PURGE_YYYYMMDD}*log*

${ECHO}
${ECHO} "delete_hrrr_gefs.ksh finished at `${DATE}`"

exit 0
