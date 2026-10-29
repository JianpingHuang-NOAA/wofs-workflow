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

# WoFS workflow repository
export HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"
export DATAROOT="${DATAROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang}"

# IC_PREP runtime configuration
export PARMWOfS="${PARMWOfS:-${HOMEwofs}/parm}"

# Temporary external dependencies during migration
export UPP_LEGACY_ROOT="${UPP_LEGACY_ROOT:-/scratch4/NCEPDEV/fv3-cam/Jianping.Huang/wofsv1.0}"
export EXE_ROOT="${EXE_ROOT:-${UPP_LEGACY_ROOT}/exec}"
export UPP_FIX_DIR="${UPP_FIX_DIR:-${UPP_LEGACY_ROOT}/fix/UPP}"
export STATICWRF_DIR="${STATICWRF_DIR:-${UPP_LEGACY_ROOT}/fix/WRF}"

# Ursa environment
module use "${HOMEwofs}/modulefiles"
module load ursa_ic_prep

: "${INIT_TIME:?INIT_TIME must be defined}"
: "${CRTM:?CRTM must be defined}"

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


# Output cycle for the target WoFS run
TARGET_TIME=$(date -u -d "${INIT_TIME:0:8} ${INIT_TIME:8:2}:00:00 UTC + 1 hour" +%Y%m%d%H)

export PDY="${TARGET_TIME:0:8}"
export cyc="${TARGET_TIME:8:2}"


# NCO-style COM output directory on scratch3
export COMROOT="${COMROOT:-${DATAROOT}/com/wofs/v1.0}"
export COMOUT="${COMOUT:-${COMROOT}/wofs.${PDY}/${cyc}}"
export INPUTDIR="${INPUTDIR:-${COMOUT}/INPUT}"

mkdir -p "${INPUTDIR}"

exec "${HOMEwofs}/jobs/JWOFS_IC_PREP"
