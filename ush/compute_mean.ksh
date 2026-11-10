#!/bin/ksh --login

# Runtime modules are loaded by the BC_PREP Slurm wrapper.
# Preserve the inherited environment.


RM=/bin/rm
CP=/bin/cp
MV=/bin/mv
LN=/bin/ln
MKDIR=/bin/mkdir
CAT=/bin/cat
ECHO=/bin/echo
LS=/bin/ls
CUT=/bin/cut
WC=/usr/bin/wc
DATE=/bin/date
AWK="/bin/awk --posix"
SED=/bin/sed
TAIL=/usr/bin/tail
MPIRUN=srun
#MPIRUN=mpirun


if [ ! ${MEAN_PROC} ]; then
  ${ECHO} "ERROR:  MEAN_PROC was not specified"
  exit 1
fi
${ECHO} "MEAN_PROC = ${MEAN_PROC}"

# Check to make sure the required environmental variables were specified
if [ ! "${EXEC_ROOT}" ]; then
  ${ECHO} "ERROR: \$EXEC_ROOT is not defined!"
  exit 1
fi
${ECHO} "EXEC_ROOT = ${EXEC_ROOT}"

if [ ! "${WORK_ROOT}" ]; then
  ${ECHO} "ERROR: \$WORK_ROOT is not defined!"
  exit 1
fi
${ECHO} "WORK_ROOT = ${WORK_ROOT}"

if [ ! "${ENSEMBLE_SIZE}" ]; then
  ${ECHO} "ERROR: \$ENSEMBLE_SIZE is not defined!"
  exit 1
fi
${ECHO} "ENSEMBLE_SIZE = ${ENSEMBLE_SIZE}"


#####################################################
# Set up workdir
#####################################################
workdir=${WORK_ROOT}/mean
if [ ! -d ${workdir} ]; then
  mkdir -p $workdir
fi
cd $workdir

#################################################################
# Compute mean
#################################################################

AVERAGE_EXE=${EXEC_ROOT}/average_netcdf_files_parallel.x
if [ ! -x "${AVERAGE_EXE}" ]; then
  ${ECHO} "ERROR: ${AVERAGE_EXE} does not exist!"
  exit 1
fi

mem=1
while [[ $mem -le $ENSEMBLE_SIZE ]];do

  ensmemid=`printf %2.2i $mem`
  filename=${WORK_ROOT}/mem${ensmemid}/wrfprd/wrfinput_d01
  if [ ! -r "${filename}" ]; then
    ${ECHO} "ERROR: ${filename} does not exist!"
    exit 1
  else
    ${LN} -sf ${filename} wrfinput.mem0${ensmemid}
  fi

  (( mem += 1 ))

done

cp ${WORK_ROOT}/mem01/wrfprd/wrfinput_d01 ./wrfinput_d01

${ECHO} "computing ensemble mean at `${DATE}`"

#mpirun ${AVERAGE_EXE} 1 ${workdir} wrfinput_d01 wrfinput.mem ${ENSEMBLE_SIZE} > stdout_mean 2>&1
#mpirun ${AVERAGE_EXE} 2 ${workdir} wrfinput_d01 wrfinput.mem ${ENSEMBLE_SIZE} > stdout_mean 2>&1
${MPIRUN} ${AVERAGE_EXE} 2 ${workdir} wrfinput_d01 wrfinput.mem ${ENSEMBLE_SIZE} > stdout_mean 2>&1
rc=$?

if [ ${rc} -ne 0 ]; then
  ${ECHO} "ERROR: ${AVERAGE_EXE} failed with return code ${rc}"
  ${ECHO} "ERROR: Ensemble mean was not completed."
  exit ${rc}
fi

if [ ! -s "${workdir}/wrfinput_d01" ]; then
  ${ECHO} "ERROR: Ensemble mean output is missing or empty:"
  ${ECHO} "ERROR: ${workdir}/wrfinput_d01"
  exit 1
fi

${ECHO} "finished computing ensemble mean at `${DATE}`"
${ECHO} "" > mean_finished

exit 0
