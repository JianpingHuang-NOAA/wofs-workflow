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

WRAPPER="$HOMEwofs/workflow/shell/wps/jwofs_wps_real.sh"

LOG_ROOT="$DATAROOT/logs/wofsv1.0/wps/$CDATE/real"

mkdir -p "$LOG_ROOT"

LOG_DIR="$(mktemp -d "$LOG_ROOT/submit.XXXXXXXX")"

get_stage_config()
{
    "$PYTHON" - "$WPS_CONFIG" "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)

stage = sys.argv[2].lower()

r = cfg["real"][stage]
u = cfg["ungrib"][stage]

print(
    u["ens_size"],
    r["mpi_tasks"],
    r["memory"],
    r["walltime"],
    r["partition"],
    r["qos"],
)
PY
}

# Check required METGRID completion markers.
for region in "$@"; do

    [[ "$region" =~ ^[A-Za-z0-9_-]+$ ]] || exit 1

    for stage in "${STAGES[@]}"; do

        SETTINGS="$(get_stage_config "$stage")"

        read -r ENS_SIZE NTASKS MEMORY WALLTIME PARTITION QOS \
            <<< "$SETTINGS"

        for ((m=1; m<=ENS_SIZE; m++)); do

            MEM2="$(printf '%02d' "$m")"

            DIR="$COMOUT/$region/WPS/$stage/mem${MEM2}"

            if [[ ! -f "$DIR/METGRID_SUCCESS" ]]; then

                echo "[ERROR] Missing METGRID output: $DIR"

                exit 1

            fi

        done

    done

done

printf 'REGION\tSTAGE\tJOBID\tMEMBERS\tMPI_TASKS\n' \
    > "$LOG_DIR/jobs.tsv"

for region in "$@"; do

    export region

    for stage in "${STAGES[@]}"; do

        export WPS_STAGE="$stage"

        SETTINGS="$(get_stage_config "$stage")"

        read -r ENS_SIZE NTASKS MEMORY WALLTIME PARTITION QOS \
            <<< "$SETTINGS"

        export REAL_MPI_TASKS="$NTASKS"

        # Submit only members without completed REAL outputs.
        PENDING=()

        case "$stage" in
            BC) OUTPUT=wrfbdy_d01 ;;
            IC) OUTPUT=wrfinput_d01_ic ;;
            *) exit 1 ;;
        esac

        for ((m=1; m<=ENS_SIZE; m++)); do

            MEM2="$(printf '%02d' "$m")"

            DIR="$COMOUT/$region/REAL/$stage/mem${MEM2}"

            if [[ -f "$DIR/REAL_SUCCESS" &&
                  -s "$DIR/$OUTPUT" ]]; then

                echo "[SKIP] $region REAL_${stage} mem${MEM2}"
                continue

            fi

            if [[ -e "$DIR" ]]; then
                echo "[ERROR] Incomplete existing output: $DIR"
                exit 1
            fi

            PENDING+=("$m")

        done

        if [[ ${#PENDING[@]} -eq 0 ]]; then

            echo "[PASS] $region REAL_${stage} already complete"
            continue

        fi

        ARRAY_SPEC="$(IFS=,; echo "${PENDING[*]}")"

        NUM_PENDING="${#PENDING[@]}"

        echo "$region REAL_${stage}: submitting $NUM_PENDING/$ENS_SIZE members"

        JOBID="$(sbatch --parsable \
            --export=ALL \
            --partition="$PARTITION" \
            --qos="$QOS" \
            --ntasks="$NTASKS" \
            --mem="$MEMORY" \
            --time="$WALLTIME" \
            --array="$ARRAY_SPEC" \
            --job-name="wofs_real_${stage}_${region}" \
            --output="$LOG_DIR/${region}_${stage}_%A_%a.out" \
            --error="$LOG_DIR/${region}_${stage}_%A_%a.err" \
            "$WRAPPER")"

        JOBID="${JOBID%%;*}"

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$region" "$stage" "$JOBID" \
            "$NUM_PENDING" "$NTASKS" \
            >> "$LOG_DIR/jobs.tsv"

        echo "$region REAL_${stage}: job $JOBID"

    done

done

echo

echo "Submission directory: $LOG_DIR"

cat "$LOG_DIR/jobs.tsv"
