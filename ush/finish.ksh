#!/bin/ksh --login


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
PDSH=/usr/local/bin/pdsh


# Make sure WOFDIR is specified
if [ ! "${WOFDIR}" ]; then
  ${ECHO} "ERROR: \$WOFDIR is not defined"
  exit 1
fi

# Make sure READY_FILE_NAME is specified
if [ ! "${READY_FILE_NAME}" ]; then
  ${ECHO} "ERROR: \$READY_FILE_NAME is not defined"
  exit 1
fi

if [ ! -d ${WOFDIR} ]; then

  ${ECHO} "directory ${WOFDIR} does not exist, exiting"
  exit 0

else

  cd ${WOFDIR}
  if [ ! -e ${READY_FILE_NAME} ]; then
     echo "" > ${READY_FILE_NAME}
  fi

fi

pwd
ls -al

exit 0
