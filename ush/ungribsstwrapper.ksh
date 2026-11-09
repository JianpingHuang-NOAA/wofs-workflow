#!/bin/ksh --login

module load wgrib2

echo "wgrib2 executable:"
which wgrib2

# Make sure we are using GMT time zone for time computations
export TZ="GMT"

ulimit -s 512000

LS=/bin/ls
LN=/bin/ln
RM=/bin/rm
AWK="/bin/gawk --posix"
SED=/bin/sed
ECHO=/bin/echo
CUT=`which cut`
DATE=/bin/date

# Make sure SST_FILE is defined
if [ ! "${SST_FILE}" ]; then
  ${ECHO} "ERROR: \$SST_FILE was not specified"
  exit 1
fi

# Make sure SCRIPTS is defined
if [ ! "${SCRIPTS}" ]; then
  ${ECHO} "ERROR: \$SCRIPTS was not specified"
  exit 1
fi

${ECHO} "      SST_FILE = ${SST_FILE}"

# Calculate the actual start time to pass to ungrib.ksh based on data in the SST file
LATEST_CYCLE=`wgrib2 ${SST_FILE} | ${CUT} -d":" -f 3 | ${CUT} -d"=" -f 2`
YYYY=`${ECHO} ${LATEST_CYCLE} | ${CUT} -c1-4`
MM=`${ECHO} ${LATEST_CYCLE} | ${CUT} -c5-6`
DD=`${ECHO} ${LATEST_CYCLE} | ${CUT} -c7-8`
HH=`${ECHO} ${LATEST_CYCLE} | ${CUT} -c9-10`
export START_TIME=`${DATE} +"%Y%m%d %H" -d "${MM}/${DD}/${YYYY} ${HH}:00:00"`

${ECHO} "SST START_TIME = ${START_TIME}"
${ECHO}

# Call ungrib.ksh
${SCRIPTS}/ungrib_SST.ksh
error=$?
if [ ${error} -ne 0 ]; then
  ${ECHO} "ERROR: ungrib.ksh crashed  Exit status=${error}"
  exit ${error}
fi

# Make a link to the SST file
cd  ${DATAHOME}/extprd
${RM} -f SST
${LN} -s SST:`${DATE} +"%Y-%m-%d_%H" -d "${START_TIME}"` SST
exit $?
