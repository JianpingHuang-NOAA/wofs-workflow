#!/bin/bash
set -euo pipefail

# ============================================================
# WoFS v1.0 IC_PREP workflow submission
#
# Usage:
#   ./workflow/shell/ic_prep/submit_wofs_ic_prep.sh YYYYMMDDHH
#
# DOWNLOAD: u1-service
# POST:     u1-compute, 36 ensemble members
# ============================================================

INIT_TIME="${1:?Usage: $0 YYYYMMDDHH}"

if [[ ! "${INIT_TIME}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: INIT_TIME must be YYYYMMDDHH" >&2
    exit 1
fi

if ! date -u -d \
    "${INIT_TIME:0:8} ${INIT_TIME:8:2}:00:00 UTC" \
    +%Y%m%d%H >/dev/null 2>&1; then
    echo "ERROR: Invalid INIT_TIME" >&2
    exit 1
fi

HOMEwofs="${HOMEwofs:-/scratch3/NCEPDEV/wofs/Jianping.Huang/wofs-workflow}"

DOWNLOAD_SCRIPT="${HOMEwofs}/workflow/shell/ic_prep/jwofs_ic_prep_download.sh"
POST_SCRIPT="${HOMEwofs}/workflow/shell/ic_prep/jwofs_ic_prep_post.sh"

LOGDIR="/scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_IC/logs"

mkdir -p "${LOGDIR}"

for script in "${DOWNLOAD_SCRIPT}" "${POST_SCRIPT}"; do
    if [[ ! -f "${script}" ]]; then
        echo "ERROR: Missing ${script}" >&2
        exit 1
    fi
done

TARGET_TIME=$(date -u -d \
    "${INIT_TIME:0:8} ${INIT_TIME:8:2}:00:00 UTC + 1 hour" \
    +%Y%m%d%H)

echo "=================================================="
echo "WoFS v1.0 IC_PREP submission"
echo "=================================================="
echo "INIT_TIME   = ${INIT_TIME}"
echo "TARGET_TIME = ${TARGET_TIME}"
echo "MEMBERS     = 1-36"
echo "=================================================="

# Stage 1: HRRRDAS download
DOWNLOAD_JOBID=$(sbatch --parsable \
    --export=ALL,INIT_TIME="${INIT_TIME}" \
    "${DOWNLOAD_SCRIPT}")

echo "DOWNLOAD submitted: ${DOWNLOAD_JOBID}"

# Stage 2: UPP postprocessing
# Only starts after successful DOWNLOAD completion.
if POST_JOBID=$(sbatch --parsable \
    --dependency="afterok:${DOWNLOAD_JOBID}" \
    --array=1-36 \
    --export=ALL,INIT_TIME="${INIT_TIME}" \
    "${POST_SCRIPT}"); then
    echo "POST submitted: ${POST_JOBID}"
else
    echo "ERROR: POST submission failed." >&2
    echo "DOWNLOAD job ${DOWNLOAD_JOBID} may still run." >&2
    exit 1
fi

echo
echo "=================================================="
echo "WoFS IC_PREP jobs submitted"
echo "=================================================="
echo "DOWNLOAD_JOBID=${DOWNLOAD_JOBID}"
echo "POST_JOBID=${POST_JOBID}"
echo
echo "Monitor:"
echo "  squeue -j ${DOWNLOAD_JOBID},${POST_JOBID}"
echo "  sacct -j ${DOWNLOAD_JOBID},${POST_JOBID} --format=JobID,JobName,State,ExitCode,Elapsed"
