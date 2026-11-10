#!/bin/bash
set -euo pipefail

: "${INIT_TIME:?INIT_TIME is required}"
: "${WORK_DIR:?WORK_DIR is required}"

MIN_STATIC_SIZE=16057259932
MIN_MEMBER_SIZE=6805776072

failed=0

check_file() {
    local file="$1"
    local minimum="$2"
    local size

    if [[ ! -f "$file" ]]; then
        echo "[MISSING] $file"
        failed=1
        return
    fi

    size=$(stat -c %s "$file")

    if (( size < minimum )); then
        echo "[INCOMPLETE] $file: $size bytes"
        failed=1
    else
        echo "[OK] $file: $size bytes"
    fi
}

check_file \
    "${WORK_DIR}/hrrr_${INIT_TIME}f001" \
    "$MIN_STATIC_SIZE"

for m in $(seq 1 36); do
    printf -v mem "%04d" "$m"

    check_file \
        "${WORK_DIR}/hrrrdas_small_d02_${INIT_TIME}00f01_mem${mem}" \
        "$MIN_MEMBER_SIZE"
done

if (( failed != 0 )); then
    echo "ERROR: HRRRDAS input validation failed"
    exit 1
fi

echo "SUCCESS: All 36 HRRRDAS members and HRRR input verified"
