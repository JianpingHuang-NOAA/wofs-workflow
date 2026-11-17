#!/bin/bash

set -euo pipefail

cd "$DATA"

: "${WOFS_PYTHON:?WOFS_PYTHON is required}"

export OMP_NUM_THREADS=1

ulimit -s unlimited

read -r -a REGIONS <<< "$WPS_REGIONS"

echo "===== Prepare UNGRIB ====="

"$WOFS_PYTHON" \
    "$USHwofs/load_wps_ungrib_config.py" \
    --homewofs "$HOMEwofs" \
    --comout "$COMOUT" \
    --cdate "$CDATE" \
    --regions "${REGIONS[@]}" \
    --stage "$WPS_STAGE" \
    --member "$MEMBER" \
    --wps-config "$WPS_CONFIG"

cat namelist.wps

echo "===== Execute UNGRIB ====="

srun -n 1 "$EXECwofs/ungrib.exe"

echo "===== Check expected intermediate files ====="

COUNT=0

while IFS= read -r file; do

    if [[ ! -s "$file" ]]; then
        echo "[ERROR] Missing intermediate file: $file"
        exit 1
    fi

    COUNT=$((COUNT + 1))

done < expected_files.txt

echo "[PASS] Generated $COUNT required intermediate files"

if [[ "$SENDCOM" == "YES" ]]; then

    PARENT="$(dirname "$COMOUT_UNGRIB")"

    mkdir -p "$PARENT"

    # Do not overwrite previously published output.
    if [[ -e "$COMOUT_UNGRIB" ]]; then
        echo "[ERROR] Output directory already exists:"
        echo "$COMOUT_UNGRIB"
        exit 1
    fi

    TMP_COM="$(mktemp -d \
        "$PARENT/.mem${MEM2}.XXXXXXXX")"

    trap 'rm -rf -- "$TMP_COM"' EXIT

    while IFS= read -r file; do
        cp -p "$file" "$TMP_COM/"
    done < expected_files.txt

    cp -p namelist.wps \
          expected_files.txt \
          input_manifest.tsv \
          "$TMP_COM/"

    if [[ -f ungrib.log ]]; then
        cp -p ungrib.log "$TMP_COM/"
    fi

    touch "$TMP_COM/UNGRIB_SUCCESS"

    mv -T -- "$TMP_COM" "$COMOUT_UNGRIB"

    trap - EXIT

fi

echo "[SUCCESS] UNGRIB_${WPS_STAGE} mem${MEM2}"
