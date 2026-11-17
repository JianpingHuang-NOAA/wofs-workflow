#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 CDATE REGION [REGION ...]"
    exit 1
fi

export HOMEwofs="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &&
    pwd -P
)"

export CDATE="$1"

shift

[[ "$CDATE" =~ ^[0-9]{10}$ ]] || exit 1

: "${DATAROOT:?DATAROOT is required}"

export PDY="${CDATE:0:8}"
export cyc="${CDATE:8:2}"

export COMROOT="${COMROOT:-$DATAROOT/com/wofs/v1.0}"

export SENDCOM=YES

LOG_ROOT="$DATAROOT/logs/wofsv1.0/wps/$CDATE/geogrid"

mkdir -p "$LOG_ROOT"

for region in "$@"; do

    [[ "$region" =~ ^[A-Za-z0-9_-]+$ ]] || exit 1

    CFG="$COMROOT/wofs.${PDY}/${cyc}/${region}/realtime.cfg.${PDY}.${region}"

    if [[ ! -s "$CFG" ]]; then
        echo "[ERROR] Missing $CFG"
        exit 1
    fi

done

for region in "$@"; do

    export region

    JOBID=$(sbatch --parsable \
        --export=ALL \
        --job-name="wofs_geogrid_${region}" \
        --output="$LOG_ROOT/${region}_%j.out" \
        --error="$LOG_ROOT/${region}_%j.err" \
        "$HOMEwofs/workflow/shell/wps/jwofs_wps_geogrid.sh")

    echo "$region GEOGRID job: $JOBID"

done
