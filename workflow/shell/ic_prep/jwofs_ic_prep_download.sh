#!/bin/bash
#SBATCH -J wofs_ic_download
#SBATCH -p u1-service
##SBATCH -q debug
#SBATCH -n 1
#SBATCH --mem=12G
#SBATCH -t 00:30:00
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_download_%j.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_download_%j.err

set -euo pipefail

export HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"
export DATAROOT=/scratch3/NCEPDEV/stmp/Jianping.Huang
: "${INIT_TIME:?INIT_TIME must be supplied by the workflow}"

: "${INIT_TIME:?INIT_TIME must be defined}"

export WORK_DIR="${DATAROOT}/WoF_IC/hrrrdas/${INIT_TIME}"

exec "${HOMEwofs}/jobs/JWOFS_IC_DOWNLOAD"
