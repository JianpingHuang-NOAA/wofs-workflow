#!/bin/bash

set -euo pipefail

cd "$DATA"

: "${WOFS_PYTHON:?WOFS_PYTHON is required}"
: "${REAL_MPI_TASKS:?REAL_MPI_TASKS is required}"

export OMP_NUM_THREADS=1

ulimit -s unlimited

echo "===== Prepare REAL ====="

"$WOFS_PYTHON" \
    "$USHwofs/load_wps_real_config.py" \
    --homewofs "$HOMEwofs" \
    --comout "$COMOUT" \
    --cdate "$CDATE" \
    --region "$region" \
    --stage "$WPS_STAGE" \
    --member "$MEMBER" \
    --wps-config "$WPS_CONFIG"

cat namelist.input

echo "===== Execute REAL ====="

srun --mpi=pmi2 \
    -n "$REAL_MPI_TASKS" \
    "$EXECwofs/real.exe"

echo "===== Check REAL output ====="

if [[ ! -s wrfinput_d01 ]]; then

    echo "[ERROR] Missing wrfinput_d01"

    exit 1

fi

if [[ "$WPS_STAGE" == "BC" ]]; then

    if [[ ! -s wrfbdy_d01 ]]; then

        echo "[ERROR] Missing wrfbdy_d01"

        exit 1

    fi

    OUTPUT=wrfbdy_d01

else

    mv wrfinput_d01 wrfinput_d01_ic

    OUTPUT=wrfinput_d01_ic

fi

# Require the WRF REAL completion message.
if ! grep -q 'SUCCESS COMPLETE REAL_EM INIT' \
        rsl.out.0000 rsl.error.0000 2>/dev/null; then

    echo "[ERROR] REAL completion message not found"

    exit 1

fi

ls -lh "$OUTPUT"

if [[ "$SENDCOM" == "YES" ]]; then

    PARENT="$(dirname "$COMOUT_REAL")"

    mkdir -p "$PARENT"

    exec 9>"$PARENT/.mem${MEM2}.lock"

    flock -x 9

    if [[ -e "$COMOUT_REAL" ]]; then

        echo "[ERROR] Output directory already exists:"

        echo "$COMOUT_REAL"

        exit 1

    fi

    TMP_COM="$(mktemp -d \
        "$PARENT/.mem${MEM2}.XXXXXXXX")"

    trap 'rm -rf -- "$TMP_COM"' EXIT

    chmod g+rx "$TMP_COM"

    cp -p "$OUTPUT" \
          namelist.input \
          input_manifest.txt \
          "$TMP_COM/"

    shopt -s nullglob

    LOGS=(rsl.out.* rsl.error.*)

    if (( ${#LOGS[@]} > 0 )); then

        cp -p "${LOGS[@]}" "$TMP_COM/"

    fi

    touch "$TMP_COM/REAL_SUCCESS"

    mv -T -- "$TMP_COM" "$COMOUT_REAL"

    trap - EXIT

fi

echo "[SUCCESS] REAL_${WPS_STAGE} $region mem${MEM2}"
