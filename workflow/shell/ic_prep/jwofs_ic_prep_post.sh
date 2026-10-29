#!/bin/bash
#SBATCH -J wofs_ic_post
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH --nodes=1
#SBATCH --ntasks=160
#SBATCH -t 00:25:00
#SBATCH --array=1-36
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_post_%A_%a.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_post_%A_%a.err

set -euo pipefail
export HOMEwofs=/scratch4/NCEPDEV/fv3-cam/Jianping.Huang/wofsv1.0
export DATAROOT=/scratch3/NCEPDEV/stmp/Jianping.Huang
export PARMWOfS=${HOMEwofs}/parm

module use ${HOMEwofs}/modulefiles
module load ursa_intel

#module load ncl

export HOMEwofs=/scratch4/NCEPDEV/fv3-cam/Jianping.Huang/wofsv1.0
export DATAROOT=/scratch3/NCEPDEV/stmp/Jianping.Huang

: "${INIT_TIME:?INIT_TIME must be defined}"
: "${CRTM:?CRTM must be defined}"

export PDY="${INIT_TIME:0:8}"
export cyc="${INIT_TIME:8:2}"
export envir=test

export IC_PREP_STAGE=POST
export MEMBER="${SLURM_ARRAY_TASK_ID}"

export FCST_TIME=01
export FHOUR=1
export ENS_SIZE=36
export DOMAIN=2
export MODEL=RAP
export EXPECTED_NUM_FIELDS=163

export DATAHOME="${DATAROOT}/WoF_IC/hrrrdas/${INIT_TIME}"
export WRFOUT_SMALL_DIR="${DATAHOME}"
export WRFINPUT_STATIC_DIR="${DATAHOME}"


# HRRRDAS input cycle
export INIT_TIME="${INIT_TIME:-2026102814}"

# Output cycle for the target WoFS run
TARGET_TIME=$(date -u -d "${INIT_TIME:0:8} ${INIT_TIME:8:2}:00:00 UTC + 1 hour" +%Y%m%d%H)

export PDY="${TARGET_TIME:0:8}"
export cyc="${TARGET_TIME:8:2}"


# NCO-style COM output directory on scratch3
export COMROOT="${DATAROOT}/com/wofs/v1.0"
export COMOUT="${COMROOT}/wofs.${PDY}/${cyc}"
export INPUTDIR="${COMOUT}/INPUT"

mkdir -p "${INPUTDIR}"

exec "${HOMEwofs}/jobs/JWOFS_IC_PREP"
