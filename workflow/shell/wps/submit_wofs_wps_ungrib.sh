#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 CDATE [--stage BC|IC|ALL] REGION [REGION ...]"
    exit 1
fi

export HOMEwofs="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &&
    pwd -P
)"

export CDATE="$1"
shift

# Optional processing stage; default preserves existing behavior.
STAGES=(BC IC)

if [[ "${1:-}" == "--stage" ]]; then

    if [[ $# -lt 3 ]]; then
        echo "[ERROR] Expected --stage BC|IC|ALL followed by regions"
        exit 1
    fi

    case "${2^^}" in
        BC)  STAGES=(BC) ;;
        IC)  STAGES=(IC) ;;
        ALL) STAGES=(BC IC) ;;
        *)
            echo "[ERROR] Invalid stage: $2"
            exit 1
            ;;
    esac

    shift 2

fi

if [[ $# -lt 1 ]]; then
    echo "[ERROR] At least one region is required"
    exit 1
fi


[[ "$CDATE" =~ ^[0-9]{10}$ ]] || exit 1

: "${DATAROOT:?DATAROOT is required}"

export PDY="${CDATE:0:8}"
export cyc="${CDATE:8:2}"

export COMROOT="${COMROOT:-$DATAROOT/com/wofs/v1.0}"
export COMOUT="$COMROOT/wofs.${PDY}/${cyc}"

export WPS_REGIONS="$*"

export WPS_CONFIG="${WPS_CONFIG:-$HOMEwofs/parm/wps/config.yaml}"

export SENDCOM=YES

unset MEMBER

PYTHON="$HOMEwofs/python_env/bin/python3"

LOG_ROOT="$DATAROOT/logs/wofsv1.0/wps/$CDATE/ungrib"

mkdir -p "$LOG_ROOT"

LOG_DIR="$(mktemp -d "$LOG_ROOT/submit.XXXXXXXX")"

WRAPPER="$HOMEwofs/workflow/shell/wps/jwofs_wps_ungrib.sh"

for region in "$@"; do

    [[ "$region" =~ ^[A-Za-z0-9_-]+$ ]] || exit 1

    CFG="$COMOUT/$region/realtime.cfg.${PDY}.${region}"

    if [[ ! -s "$CFG" ]]; then
        echo "[ERROR] Missing $CFG"
        exit 1
    fi

done

printf 'STAGE\tJOBID\tMEMBERS\n' > "$LOG_DIR/jobs.tsv"

for stage in "${STAGES[@]}"; do

    export WPS_STAGE="$stage"

    ENS_SIZE="$(
        "$PYTHON" -c \
        'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["ungrib"][sys.argv[2].lower()]["ens_size"])' \
        "$WPS_CONFIG" "$stage"
    )"

    JOBID="$(sbatch --parsable \
        --export=ALL \
        --qos=debug \
        --array="1-${ENS_SIZE}" \
        --job-name="wofs_ungrib_${stage}" \
        --output="$LOG_DIR/${stage}_%A_%a.out" \
        --error="$LOG_DIR/${stage}_%A_%a.err" \
        "$WRAPPER")"

    JOBID="${JOBID%%;*}"

    printf '%s\t%s\t%s\n' \
        "$stage" "$JOBID" "$ENS_SIZE" \
        >> "$LOG_DIR/jobs.tsv"

    echo "UNGRIB_${stage}: job $JOBID ($ENS_SIZE members)"

done

echo
echo "Submission directory: $LOG_DIR"

cat "$LOG_DIR/jobs.tsv"
