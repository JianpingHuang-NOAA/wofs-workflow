#!/bin/bash

set -euo pipefail

cd "$DATA"

: "${WOFS_PYTHON:?WOFS_PYTHON is required}"
: "${METGRID_MPI_TASKS:?METGRID_MPI_TASKS is required}"

export OMP_NUM_THREADS=1

ulimit -s unlimited

echo "===== Prepare METGRID ====="

"$WOFS_PYTHON" \
    "$USHwofs/load_wps_metgrid_config.py" \
    --homewofs "$HOMEwofs" \
    --comout "$COMOUT" \
    --cdate "$CDATE" \
    --region "$region" \
    --stage "$WPS_STAGE" \
    --member "$MEMBER" \
    --wps-config "$WPS_CONFIG"

cat namelist.wps

echo "===== Execute METGRID ====="

echo "MPI tasks: $METGRID_MPI_TASKS"

srun --mpi=pmi2 \
    -n "$METGRID_MPI_TASKS" \
    "$EXECwofs/metgrid.exe"

echo "===== Check METGRID output ====="

COUNT=0

while IFS= read -r file; do

    if [[ ! -s "$file" ]]; then

        echo "[ERROR] Missing METGRID output: $file"

        exit 1

    fi

    COUNT=$((COUNT + 1))

done < expected_files.txt

echo "[PASS] Generated $COUNT METGRID files"

echo "===== Validate METGRID atmospheric and soil levels ====="

"$WOFS_PYTHON" \
    "$USHwofs/validate_wps_metgrid.py" \
    --manifest expected_files.txt \
    --atmospheric-levels 51 \
    --soil-levels 9

if [[ "$SENDCOM" == "YES" ]]; then

    PARENT="$(dirname "$COMOUT_METGRID")"

    mkdir -p "$PARENT"

    # Prevent simultaneous publication for the same member.
    exec 9>"$PARENT/.mem${MEM2}.lock"

    flock -x 9

    if [[ -e "$COMOUT_METGRID" ]]; then

        echo "[ERROR] Output directory already exists:"

        echo "$COMOUT_METGRID"

        exit 1

    fi

    TMP_COM="$(mktemp -d \
        "$PARENT/.mem${MEM2}.XXXXXXXX")"

    chmod g+rx "$TMP_COM"

    trap 'rm -rf -- "$TMP_COM"' EXIT

    while IFS= read -r file; do

        cp -p "$file" "$TMP_COM/"

    done < expected_files.txt

    cp -p namelist.wps \
          expected_files.txt \
          "$TMP_COM/"

    shopt -s nullglob

    LOGS=(metgrid.log*)

    if (( ${#LOGS[@]} > 0 )); then

        cp -p "${LOGS[@]}" "$TMP_COM/"

    fi

    touch "$TMP_COM/METGRID_SUCCESS"

    mv -T -- "$TMP_COM" "$COMOUT_METGRID"

    trap - EXIT

fi

echo "[SUCCESS] METGRID_${WPS_STAGE} $region mem${MEM2}"
