#!/bin/bash
#SBATCH -J wofs_ic_post
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH --nodes=1
#SBATCH --ntasks=160
#SBATCH -t 00:10:00
#SBATCH --array=1-36
#SBATCH -o /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_post_%A_%a.out
#SBATCH -e /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs/wofs_ic_post_%A_%a.err

set -euo pipefail

# WoFS workflow repository
export HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"

# Ursa environment
module use "${HOMEwofs}/modulefiles"
module load ursa_intel

# Required forecast cycle
: "${INIT_TIME:?INIT_TIME must be supplied by the workflow}"
: "${SLURM_ARRAY_TASK_ID:?Submit as a SLURM array job}"

exec "${HOMEwofs}/jobs/JWOFS_IC_PREP"
