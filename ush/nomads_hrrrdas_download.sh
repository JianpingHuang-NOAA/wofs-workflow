#!/bin/bash
set -euo pipefail

: "${INIT_TIME:?INIT_TIME must be defined}"
: "${WORK_DIR:?WORK_DIR must be defined}"

START_MEMBER=${START_MEMBER:-33}
END_MEMBER=${END_MEMBER:-36}
MAX_PARALLEL=${MAX_PARALLEL:-6}

BASE_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/hrrr/prod/nwges"

STATIC_FILE="hrrr_${INIT_TIME}f001"
STATIC_URL="${BASE_URL}/hrrrges_sfc/conus/${STATIC_FILE}"

MIN_STATIC_SIZE=16057259932
MIN_MEMBER_SIZE=6805776072

[[ "$START_MEMBER" =~ ^[0-9]+$ ]] &&
[[ "$END_MEMBER" =~ ^[0-9]+$ ]] &&
[[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] || {
    echo "ERROR: Invalid member range or concurrency"
    exit 1
}

(( START_MEMBER >= 1 &&
   END_MEMBER <= 36 &&
   START_MEMBER <= END_MEMBER &&
   MAX_PARALLEL >= 1 )) || {
    echo "ERROR: Invalid member range or concurrency"
    exit 1
}

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=================================================="
echo "WoFS IC HRRRDAS parallel download"
echo "HOST         = $(hostname)"
echo "INIT_TIME    = $INIT_TIME"
echo "WORK_DIR     = $WORK_DIR"
echo "MEMBERS      = $START_MEMBER-$END_MEMBER"
echo "MAX_PARALLEL = $MAX_PARALLEL"
echo "=================================================="

download_file() {
    local filename="$1"
    local url="$2"
    local expected_size="$3"
    local part="${filename}.part"
    local size

    # Skip verified completed files.
    if [[ -f "$filename" ]]; then
        size=$(stat -c %s "$filename")
        if (( size >= expected_size )); then
            echo "[SKIP] $filename ($size bytes)"
            return 0
        fi

        echo "[WARN] Incomplete final file: $filename"
        mv "$filename" "$part"
    fi

    echo "[START] $filename"

    # Resume an existing .part file when supported by the server.
    if ! wget \
        --inet4-only \
        --continue \
        --tries=5 \
        --timeout=120 \
        --waitretry=10 \
        --progress=dot:giga \
        -O "$part" \
        "$url"; then
        echo "[FAIL] wget failed: $filename"
        return 1
    fi

    size=$(stat -c %s "$part")

    if (( size < expected_size )); then
        echo "[FAIL] $filename: $size bytes, expected >= $expected_size"
        return 1
    fi

    mv -f "$part" "$filename"

    echo "[DONE] $filename ($size bytes)"
}

# --------------------------------------------------
# Step 1: Download the static HRRR file.
# --------------------------------------------------

download_file \
    "$STATIC_FILE" \
    "$STATIC_URL" \
    "$MIN_STATIC_SIZE"

ln -sfn "$STATIC_FILE" "hrrr.t${INIT_TIME:8:2}z.wrf_inout"

# --------------------------------------------------
# Step 2: Download ensemble members concurrently.
# --------------------------------------------------

pids=()
names=()
failed=0

wait_batch() {
    local i

    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            echo "[FAIL] ${names[$i]}"
            failed=1
        fi
    done

    pids=()
    names=()
}

for ((m=START_MEMBER; m<=END_MEMBER; m++)); do
    printf -v mem "%04d" "$m"

    filename="hrrrdas_small_d02_${INIT_TIME}00f01_mem${mem}"
    url="${BASE_URL}/hrrrdasges/${filename}"

    download_file \
        "$filename" \
        "$url" \
        "$MIN_MEMBER_SIZE" &

    pids+=("$!")
    names+=("$filename")

    if (( ${#pids[@]} >= MAX_PARALLEL )); then
        wait_batch
    fi
done

if (( ${#pids[@]} > 0 )); then
    wait_batch
fi

if (( failed != 0 )); then
    echo "ERROR: One or more HRRRDAS downloads failed."
    exit 1
fi

echo "=================================================="
echo "All requested HRRRDAS downloads completed."
echo "=================================================="
