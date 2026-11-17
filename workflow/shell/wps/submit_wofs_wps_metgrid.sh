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

export WPS_CONFIG="${WPS_CONFIG:-$HOMEwofs/parm/wps/config.yaml}"

export SENDCOM=YES

unset MEMBER

PYTHON="$HOMEwofs/python_env/bin/python3"

WRAPPER="$HOMEwofs/workflow/shell/wps/jwofs_wps_metgrid.sh"

LOG_ROOT="$DATAROOT/logs/wofsv1.0/wps/$CDATE/metgrid"

mkdir -p "$LOG_ROOT"

LOG_DIR="$(mktemp -d "$LOG_ROOT/submit.XXXXXXXX")"

# Verify required GEOGRID products.
for region in "$@"; do

    [[ "$region" =~ ^[A-Za-z0-9_-]+$ ]] || exit 1

    GEO="$COMOUT/$region/WPS/GEOGRID"

    if [[ ! -f "$GEO/GEOGRID_SUCCESS" ||
          ! -s "$GEO/geo_em.d01.nc" ||
          ! -s "$GEO/namelist.wps" ]]; then

        echo "[ERROR] Incomplete GEOGRID output: $region"

        exit 1

    fi

done

get_stage_config()
{
    "$PYTHON" - "$WPS_CONFIG" "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)

stage = sys.argv[2].lower()

m = cfg["metgrid"][stage]
u = cfg["ungrib"][stage]

print(
    u["ens_size"],
    m["mpi_tasks"],
    m["memory"],
    m["walltime"],
    m["partition"],
    m["qos"],
)
PY
}

# Verify all shared UNGRIB members before submission.
for stage in "${STAGES[@]}"; do

    SETTINGS="$(get_stage_config "$stage")"

    read -r ENS_SIZE NTASKS MEMORY WALLTIME PARTITION QOS \
        <<< "$SETTINGS"

    for ((m=1; m<=ENS_SIZE; m++)); do

        MEM2="$(printf '%02d' "$m")"

        DIR="$COMOUT/WPS/UNGRIB/$stage/mem${MEM2}"

        if [[ ! -f "$DIR/UNGRIB_SUCCESS" ]]; then

            echo "[ERROR] Missing UNGRIB output: $DIR"

            exit 1

        fi

    done

done

printf 'REGION\tSTAGE\tJOBID\tMEMBERS\tMPI_TASKS\n' \
    > "$LOG_DIR/jobs.tsv"

# Submit one BC and one IC array for each domain.
for region in "$@"; do

    export region

    for stage in "${STAGES[@]}"; do

        export WPS_STAGE="$stage"

        SETTINGS="$(get_stage_config "$stage")"

        read -r ENS_SIZE NTASKS MEMORY WALLTIME PARTITION QOS \
            <<< "$SETTINGS"

        export METGRID_MPI_TASKS="$NTASKS"

        JOBID="$(sbatch --parsable \
            --export=ALL \
            --partition="$PARTITION" \
            --qos="$QOS" \
            --ntasks="$NTASKS" \
            --mem="$MEMORY" \
            --time="$WALLTIME" \
            --array="1-${ENS_SIZE}" \
            --job-name="wofs_metgrid_${stage}_${region}" \
            --output="$LOG_DIR/${region}_${stage}_%A_%a.out" \
            --error="$LOG_DIR/${region}_${stage}_%A_%a.err" \
            "$WRAPPER")"

        JOBID="${JOBID%%;*}"

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$region" "$stage" "$JOBID" \
            "$ENS_SIZE" "$NTASKS" \
            >> "$LOG_DIR/jobs.tsv"

        echo "$region METGRID_${stage}: job $JOBID"

    done

done

echo

echo "Submission directory: $LOG_DIR"

cat "$LOG_DIR/jobs.tsv"
