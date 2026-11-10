#!/bin/bash
# ============================================================
# WoFS IC_PREP - Parallel HRRRDAS Downloader
#
# Downloads:
#   1 deterministic HRRR file (independent worker)
#   36 HRRRDAS small-domain ensemble files
#
# Concurrent workers:
#   1 deterministic + MAX_PARALLEL ensemble downloads
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# 1. Runtime configuration
# ------------------------------------------------------------
INIT_TIME="${1:-${INIT_TIME:-}}"
WORK_DIR="${2:-${WORK_DIR:-}}"

: "${INIT_TIME:?INIT_TIME is required}"
: "${WORK_DIR:?WORK_DIR is required}"

if [[ ! "$INIT_TIME" =~ ^[0-9]{10}$ ]]; then
    echo "[ERROR] Invalid INIT_TIME: $INIT_TIME" >&2
    exit 1
fi

HH="${INIT_TIME:8:2}"

NOMADS="${NOMADS:-https://nomads.ncep.noaa.gov/pub/data/nccf/com/hrrr/prod/nwges}"

MAX_PARALLEL="${MAX_PARALLEL:-8}"
MAX_RETRIES="${MAX_RETRIES:-5}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-120}"

START_MEMBER="${START_MEMBER:-1}"
END_MEMBER="${END_MEMBER:-36}"

MIN_ENS_SIZE=6805776072
MIN_HRRR_SIZE=16057259932

for value in MAX_PARALLEL MAX_RETRIES DOWNLOAD_TIMEOUT START_MEMBER END_MEMBER; do
    if [[ ! "${!value}" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid integer: $value=${!value}" >&2
        exit 1
    fi
done

if (( MAX_PARALLEL < 6 || MAX_RETRIES < 1 ||
      DOWNLOAD_TIMEOUT < 1 || START_MEMBER < 1 ||
      END_MEMBER > 36 || START_MEMBER > END_MEMBER )); then
    echo "[ERROR] Invalid download settings" >&2
    exit 1
fi

command -v wget >/dev/null || {
    echo "[ERROR] wget not found" >&2
    exit 1
}

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

LOG_DIR="${LOG_DIR:-${WORK_DIR}/download_logs}"
mkdir -p "$LOG_DIR"

echo "=================================================="
echo "WoFS HRRRDAS Parallel Download"
echo "=================================================="
echo "INIT_TIME      : $INIT_TIME"
echo "WORK_DIR       : $WORK_DIR"
echo "MAX_PARALLEL   : $MAX_PARALLEL ensemble workers"
echo "HRRR_WORKERS   : 1 independent worker"
echo "MEMBER_RANGE   : $START_MEMBER - $END_MEMBER"
echo "MAX_RETRIES    : $MAX_RETRIES"
echo "=================================================="

# ------------------------------------------------------------
# 2. Download function
# ------------------------------------------------------------
download_file() {
    local url="$1"
    local filename="$2"
    local min_size="$3"

    local part="${filename}.part"
    local log="${LOG_DIR}/${filename}.log"
    local size=0
    local attempt

    if [[ -f "$filename" ]]; then
        size=$(stat -c %s "$filename")

        if (( size >= min_size )); then
            echo "[SKIP] $filename ($size bytes)"
            return 0
        fi

        echo "[WARN] Incomplete existing file: $filename"
        if [[ -f "$part" ]]; then
            local part_size
            part_size=$(stat -c %s "$part")
            if (( part_size > size )); then
                rm -f "$filename"
            else
                rm -f "$part"
                mv "$filename" "$part"
            fi
        else
            mv "$filename" "$part"
        fi
    fi

    for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
        echo "[START] $filename attempt $attempt/$MAX_RETRIES"

        if wget \
            --continue \
            --tries=3 \
            --timeout="$DOWNLOAD_TIMEOUT" \
            --waitretry=10 \
            --output-document="$part" \
            "$url" >> "$log" 2>&1; then

            size=$(stat -c %s "$part")

            if (( size >= min_size )); then
                mv -f "$part" "$filename"
                echo "[OK] $filename ($size bytes)"
                return 0
            fi

            echo "[WARN] $filename too small: $size bytes"
        else
            echo "[WARN] wget failed for $filename"
        fi

        if (( attempt < MAX_RETRIES )); then
            sleep 10
        fi
    done

    echo "[FAILED] $filename" >&2
    return 1
}

# ------------------------------------------------------------
# 3. Start deterministic HRRR download immediately
# ------------------------------------------------------------
HRRR_FILE="hrrr_${INIT_TIME}f001"

HRRR_URL="${NOMADS}/hrrrges_sfc/conus/${HRRR_FILE}"

echo "[INFO] Launching deterministic HRRR download"

download_file \
    "$HRRR_URL" \
    "$HRRR_FILE" \
    "$MIN_HRRR_SIZE" &

HRRR_PID=$!

# ------------------------------------------------------------
# 4. Start concurrent ensemble downloads
# ------------------------------------------------------------
declare -a ACTIVE_PIDS=()
declare -a ALL_PIDS=()

FAILED=0

# Wait for one completed ensemble worker.
# This frees a slot while the deterministic HRRR
# download continues independently.
wait_for_slot() {
    local pid

    while (( ${#ACTIVE_PIDS[@]} >= MAX_PARALLEL )); do
        local remaining=()

        for pid in "${ACTIVE_PIDS[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                if ! wait "$pid"; then
                    FAILED=1
                fi
            else
                remaining+=("$pid")
            fi
        done

        ACTIVE_PIDS=("${remaining[@]}")

        if (( ${#ACTIVE_PIDS[@]} >= MAX_PARALLEL )); then
            sleep 2
        fi
    done
}

echo "[INFO] Launching HRRRDAS ensemble downloads"

for ((member=START_MEMBER; member<=END_MEMBER; member++)); do

    wait_for_slot

    printf -v MEMBER04 "%04d" "$member"

    FILE="hrrrdas_small_d02_${INIT_TIME}00f01_mem${MEMBER04}"

    URL="${NOMADS}/hrrrdasges/${FILE}"

    download_file \
        "$URL" \
        "$FILE" \
        "$MIN_ENS_SIZE" &

    pid=$!
    ACTIVE_PIDS+=("$pid")
    ALL_PIDS+=("$pid")

done

# ------------------------------------------------------------
# 5. Wait for remaining ensemble workers
# ------------------------------------------------------------
echo "[INFO] Waiting for ensemble downloads"

for pid in "${ACTIVE_PIDS[@]}"; do
    if ! wait "$pid"; then
        FAILED=1
    fi
done

# ------------------------------------------------------------
# 6. Wait for deterministic HRRR
# ------------------------------------------------------------
echo "[INFO] Waiting for deterministic HRRR download"

if ! wait "$HRRR_PID"; then
    FAILED=1
fi

# ------------------------------------------------------------
# 7. Create deterministic HRRR symlink
# ------------------------------------------------------------
if [[ -f "$HRRR_FILE" ]]; then
    ln -sfn "$HRRR_FILE" "hrrr.t${HH}z.wrf_inout"
fi

# ------------------------------------------------------------
# 8. Validate ensemble files
# ------------------------------------------------------------
SUCCESS_COUNT=0
FAILED_COUNT=0

for ((member=START_MEMBER; member<=END_MEMBER; member++)); do

    printf -v MEMBER04 "%04d" "$member"

    FILE="hrrrdas_small_d02_${INIT_TIME}00f01_mem${MEMBER04}"

    if [[ -f "$FILE" ]]; then
        SIZE=$(stat -c %s "$FILE")

        if (( SIZE >= MIN_ENS_SIZE )); then
            ((SUCCESS_COUNT+=1))
            continue
        fi
    fi

    echo "[FAILED] Validation: $FILE"
    ((FAILED_COUNT+=1))
done

# ------------------------------------------------------------
# 9. Validate deterministic HRRR
# ------------------------------------------------------------
HRRR_OK=0

if [[ -f "$HRRR_FILE" ]]; then
    SIZE=$(stat -c %s "$HRRR_FILE")

    if (( SIZE >= MIN_HRRR_SIZE )); then
        HRRR_OK=1
    fi
fi

# ------------------------------------------------------------
# 10. Final summary
# ------------------------------------------------------------
echo "=================================================="
echo "HRRRDAS DOWNLOAD SUMMARY"
echo "=================================================="
echo "INIT_TIME         : $INIT_TIME"
echo "Ensemble success  : $SUCCESS_COUNT"
echo "Ensemble failed   : $FAILED_COUNT"
echo "Deterministic HRRR: $HRRR_OK"
echo "=================================================="

if (( FAILED != 0 || FAILED_COUNT != 0 || HRRR_OK != 1 )); then
    echo "[ERROR] HRRRDAS download incomplete" >&2
    exit 1
fi

echo "[SUCCESS] All requested HRRRDAS files downloaded"
exit 0
