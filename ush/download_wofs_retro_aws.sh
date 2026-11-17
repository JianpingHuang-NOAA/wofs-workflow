#!/bin/bash
#SBATCH --job-name=wofs_retro_download
#SBATCH --partition=u1-service
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=9
#SBATCH --mem=12G
#SBATCH --time=04:00:00
#SBATCH --output=wofs_retro_download_%j.out
#SBATCH --error=wofs_retro_download_%j.err

# ============================================================================
# Download historical HRRRDAS, HRRRGES, HRRR, GEFS and SST data
# for an arbitrary retrospective WoFS cycle from NOAA AWS S3.
#
# Usage:
#   ./download_wofs_retro_aws.sh YYYYMMDDHH
#
# Examples:
#  sbatch ./download_wofs_retro_aws.sh 2026110215
#   ./download_wofs_retro_aws.sh 2026072717
#
# Optional settings:
#   DATAROOT=/path/to/data/root
#   ARCHIVE_ROOT=/path/to/archive
#   MAX_PARALLEL=9
#   DOWNLOAD_WRFPRS=NO
#   DOWNLOAD_IC=YES
#   DOWNLOAD_BC=YES
# ============================================================================

set -euo pipefail

export TZ=UTC

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ============================================================================
# 1. Configuration
# ============================================================================

[[ $# -eq 1 ]] ||
    die "Usage: $0 YYYYMMDDHH"

WOFS_CDATE="$1"

[[ "$WOFS_CDATE" =~ ^[0-9]{10}$ ]] ||
    die "WOFS_CDATE must be YYYYMMDDHH"

export DATAROOT="${DATAROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang}"

ARCHIVE_ROOT="${ARCHIVE_ROOT:-${DATAROOT}/data}"

ARCHIVE_ROOT="$(realpath -m "$ARCHIVE_ROOT")"

BASE_URL="${BASE_URL:-https://noaa-hrrr-bdp-pds.s3.amazonaws.com}"

HRRRDAS_PREFIX="${HRRRDAS_PREFIX:-nwges/hrrrdasges}"

HRRRGES_PREFIX="${HRRRGES_PREFIX:-nwges/hrrrges_sfc/conus}"

GEFS_BASE_URL="${GEFS_BASE_URL:-https://noaa-gefs-pds.s3.amazonaws.com}"

SST_BASE_URL="${SST_BASE_URL:-https://noaa-gfs-bdp-pds.s3.amazonaws.com}"

GEFS_MEM_START=1
GEFS_MEM_END=18

GEFS_FH_START=6
GEFS_FH_END=36
GEFS_FH_INTERVAL=3

MAX_PARALLEL="${MAX_PARALLEL:-9}"

DOWNLOAD_WRFPRS="${DOWNLOAD_WRFPRS:-NO}"
DOWNLOAD_IC="${DOWNLOAD_IC:-YES}"
DOWNLOAD_BC="${DOWNLOAD_BC:-YES}"

MEM_START=1
MEM_END=36

BC_FH_START=0
BC_FH_END=25

[[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]] ||
    die "MAX_PARALLEL must be a positive integer"

for setting in \
    "$DOWNLOAD_WRFPRS" \
    "$DOWNLOAD_IC" \
    "$DOWNLOAD_BC"
do
    [[ "$setting" == YES || "$setting" == NO ]] ||
        die "Download settings must be YES or NO"
done

[[ "$DOWNLOAD_IC" == YES || "$DOWNLOAD_BC" == YES ]] ||
    die "At least one download component must be enabled"

# ============================================================================
# 2. Derive initialization times
# ============================================================================

WOFS_DATE="${WOFS_CDATE:0:8}"
WOFS_HOUR="${WOFS_CDATE:8:2}"

WOFS_DATETIME="${WOFS_CDATE:0:4}-${WOFS_CDATE:4:2}-${WOFS_CDATE:6:2} ${WOFS_HOUR}:00:00"

WOFS_EPOCH="$(date -u -d "$WOFS_DATETIME" +%s)" ||
    die "Invalid WoFS cycle"

[[ "$(date -u -d "@$WOFS_EPOCH" +%Y%m%d%H)" == "$WOFS_CDATE" ]] ||
    die "Invalid WoFS cycle"

# HRRRDAS and deterministic IC: WoFS cycle minus one hour.
IC_EPOCH=$((WOFS_EPOCH - 3600))

IC_INIT="$(date -u -d "@$IC_EPOCH" +%Y%m%d%H)"

IC_DATE="${IC_INIT:0:8}"
IC_CYCLE="${IC_INIT:8:2}"

# BC HRRR: most recent 00, 06, 12, or 18 UTC cycle.
BC_HOUR=$((10#$WOFS_HOUR / 6 * 6))

BC_CYCLE="$(printf '%02d' "$BC_HOUR")"

BC_INIT="${WOFS_DATE}${BC_CYCLE}"

BC_DATE="${BC_INIT:0:8}"

BC_DATETIME="${BC_DATE:0:4}-${BC_DATE:4:2}-${BC_DATE:6:2} ${BC_CYCLE}:00:00"

BC_EPOCH="$(date -u -d "$BC_DATETIME" +%s)"

# GEFS initialization: BC HRRR cycle minus six hours.
GEFS_EPOCH=$((BC_EPOCH - 6 * 3600))

GEFS_INIT="$(date -u -d "@$GEFS_EPOCH" +%Y%m%d%H)"

GEFS_DATE="${GEFS_INIT:0:8}"
GEFS_CYCLE="${GEFS_INIT:8:2}"

# SST source date: GEFS initialization minus 24 hours.
SST_EPOCH=$((GEFS_EPOCH - 24 * 3600))

SST_INIT="$(date -u -d "@$SST_EPOCH" +%Y%m%d)00"

SST_DATE="${SST_INIT:0:8}"

# ============================================================================
# 3. Output directories
# ============================================================================

HRRRDAS_OUTDIR="${ARCHIVE_ROOT}/hrrrdas/conus/wrfnat/grib2/${IC_INIT}"

HRRR_IC_OUTDIR="${ARCHIVE_ROOT}/hrrrges_sfc/conus/${IC_INIT}"

GEFS_OUTDIR="${ARCHIVE_ROOT}/gefs/gefs_${GEFS_DATE}/${GEFS_CYCLE}"

SST_OUTDIR="${ARCHIVE_ROOT}/sst/nsst.${SST_DATE}"

HRRR_BC_OUTDIR="${ARCHIVE_ROOT}/hrrr/hrrr.${BC_DATE}/${BC_CYCLE}"

LOG_DIR="${ARCHIVE_ROOT}/logs/${WOFS_CDATE}"

mkdir -p "$LOG_DIR"

# ============================================================================
# 4. Submit through Slurm when running outside a batch job
# ============================================================================

if [[ -z "${SLURM_JOB_ID:-}" ]]; then

    SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"

    echo "============================================================"
    echo "Submit WoFS retrospective AWS download"
    echo "============================================================"
    echo "WOFS_CDATE      = $WOFS_CDATE"
    echo "IC_INIT         = $IC_INIT"
    echo "BC_INIT         = $BC_INIT"
    echo "GEFS_INIT       = $GEFS_INIT"
    echo "SST_INIT        = $SST_INIT"
    echo "ARCHIVE_ROOT    = $ARCHIVE_ROOT"
    echo "DOWNLOAD_IC     = $DOWNLOAD_IC"
    echo "DOWNLOAD_BC     = $DOWNLOAD_BC"
    echo "DOWNLOAD_WRFPRS = $DOWNLOAD_WRFPRS"
    echo "MAX_PARALLEL    = $MAX_PARALLEL"
    echo "============================================================"

    export ARCHIVE_ROOT BASE_URL HRRRDAS_PREFIX
    export HRRRGES_PREFIX GEFS_BASE_URL SST_BASE_URL
    export MAX_PARALLEL DOWNLOAD_WRFPRS DOWNLOAD_IC DOWNLOAD_BC

    JOB_ID="$(
        sbatch \
            --parsable \
            --export=ALL \
            --cpus-per-task="$MAX_PARALLEL" \
            --output="$LOG_DIR/download_%j.out" \
            --error="$LOG_DIR/download_%j.err" \
            "$SCRIPT_PATH" "$WOFS_CDATE"
    )"

    echo "DOWNLOAD_JOB_ID=$JOB_ID"

    exit 0

fi

# ============================================================================
# 5. Running inside Slurm
# ============================================================================

echo "============================================================"
echo "WoFS retrospective AWS download"
echo "============================================================"
echo "SLURM_JOB_ID    = $SLURM_JOB_ID"
echo "WOFS_CDATE      = $WOFS_CDATE"
echo "IC_INIT         = $IC_INIT"
echo "BC_INIT         = $BC_INIT"
echo "GEFS_INIT       = $GEFS_INIT"
echo "SST_INIT        = $SST_INIT"
echo "HRRRDAS_OUTDIR  = $HRRRDAS_OUTDIR"
echo "HRRR_IC_OUTDIR  = $HRRR_IC_OUTDIR"
echo "HRRR_BC_OUTDIR  = $HRRR_BC_OUTDIR"
echo "GEFS_OUTDIR     = $GEFS_OUTDIR"
echo "SST_OUTDIR      = $SST_OUTDIR"
echo "MAX_PARALLEL    = $MAX_PARALLEL"
echo "============================================================"

command -v curl >/dev/null ||
    die "curl is not available"

# ============================================================================
# 6. Build download manifest
# ============================================================================

MANIFEST="$LOG_DIR/download_manifest_${SLURM_JOB_ID}.tsv"

RAW_MANIFEST="${MANIFEST}.raw"

: > "$RAW_MANIFEST"

add_file() {

    local category="$1"
    local url="$2"
    local outfile="$3"

    printf '%s\t%s\t%s\n' \
        "$category" "$url" "$outfile" >> "$RAW_MANIFEST"

}

add_hrrr() {

    local category="$1"
    local date="$2"
    local cycle="$3"
    local hour="$4"
    local outdir="$5"

    local fhr filename product

    fhr="$(printf '%02d' "$hour")"

    local -a products=(wrfnat)

    if [[ "$DOWNLOAD_WRFPRS" == YES ]]; then
        products+=(wrfprs)
    fi

    for product in "${products[@]}"; do

        filename="hrrr.t${cycle}z.${product}f${fhr}.grib2"

        add_file \
            "$category" \
            "${BASE_URL}/hrrr.${date}/conus/${filename}" \
            "${outdir}/${filename}"

    done

}

# ============================================================================
# 7. HRRRDAS and deterministic HRRR for IC_PREP
# ============================================================================

if [[ "$DOWNLOAD_IC" == YES ]]; then

    mkdir -p "$HRRRDAS_OUTDIR" "$HRRR_IC_OUTDIR"

    for (( member=MEM_START; member<=MEM_END; member++ )); do

        MEMBER="$(printf '%04d' "$member")"

        FILENAME="hrrrdas_small_d02_${IC_INIT}00f01_mem${MEMBER}"

        add_file \
            HRRRDAS \
            "${BASE_URL}/${HRRRDAS_PREFIX}/${FILENAME}" \
            "${HRRRDAS_OUTDIR}/${FILENAME}"

    done

    FILENAME="hrrr_${IC_INIT}f001"

    add_file \
        HRRRGES_SFC \
        "${BASE_URL}/${HRRRGES_PREFIX}/${FILENAME}" \
        "${HRRR_IC_OUTDIR}/${FILENAME}"

fi

# ============================================================================
# 8. Deterministic HRRR for BC_PREP
# ============================================================================

if [[ "$DOWNLOAD_BC" == YES ]]; then

    mkdir -p "$HRRR_BC_OUTDIR"

    for (( hour=BC_FH_START; hour<=BC_FH_END; hour++ )); do

        add_hrrr \
            HRRR_BC \
            "$BC_DATE" \
            "$BC_CYCLE" \
            "$hour" \
            "$HRRR_BC_OUTDIR"

    done

fi

# ============================================================
# GEFS ensemble and SST for BC_PREP
# ============================================================

if [[ "$DOWNLOAD_BC" == YES ]]; then

    mkdir -p "$GEFS_OUTDIR" "$SST_OUTDIR"

    for (( member=GEFS_MEM_START; member<=GEFS_MEM_END; member++ )); do

        MEMBER="$(printf '%02d' "$member")"

        for (( hour=GEFS_FH_START; hour<=GEFS_FH_END; hour+=GEFS_FH_INTERVAL )); do

            FHR="$(printf '%03d' "$hour")"

            for GRID in a b; do

                FILENAME="gep${MEMBER}.t${GEFS_CYCLE}z.pgrb2${GRID}.0p50.f${FHR}"

                REMOTE_DIR="gefs.${GEFS_DATE}/${GEFS_CYCLE}/atmos/pgrb2${GRID}p5"

                add_file \
                    "GEFS_${GRID}" \
                    "${GEFS_BASE_URL}/${REMOTE_DIR}/${FILENAME}" \
                    "${GEFS_OUTDIR}/${FILENAME}"

            done

        done

    done

    FILENAME="rtgssthr_grb_0.083.grib2"

    add_file \
        SST \
        "${SST_BASE_URL}/nsst.${SST_DATE}/${FILENAME}" \
        "${SST_OUTDIR}/${FILENAME}"

fi

# Remove duplicate destinations from the download manifest.
awk -F '\t' '!seen[$3]++' "$RAW_MANIFEST" > "$MANIFEST"

rm -f "$RAW_MANIFEST"

EXPECTED="$(wc -l < "$MANIFEST")"

echo "Expected unique files: $EXPECTED"
echo "Download manifest: $MANIFEST"

# ============================================================================
# 9. Download one file
# ============================================================================

download_file() {

    local category="$1"
    local url="$2"
    local outfile="$3"

    local filename tmpfile

    filename="$(basename "$outfile")"

    tmpfile="${outfile}.part.${SLURM_JOB_ID}.${BASHPID}"

    if [[ -s "$outfile" ]]; then
        echo "[SKIP] $category $filename"
        return 0
    fi

    mkdir -p "$(dirname "$outfile")"

    echo "[START] $category $filename"

    if curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 5 \
        --connect-timeout 30 \
        --max-time 1800 \
        --silent \
        --show-error \
        "$url" \
        --output "$tmpfile"
    then

        if [[ -s "$tmpfile" ]]; then

            if mv -f "$tmpfile" "$outfile"; then

                echo "[SUCCESS] $category $filename"

                return 0

            fi

        fi

    fi

    rm -f "$tmpfile"

    echo "[FAILED] $category $filename" >&2
    echo "[URL] $url" >&2

    return 1

}

# ============================================================================
# 10. Parallel downloads
# ============================================================================

PIDS=()
FAILED=0

wait_batch() {

    local pid

    for pid in "${PIDS[@]}"; do

        if ! wait "$pid"; then
            FAILED=$((FAILED + 1))
        fi

    done

    PIDS=()

}

while IFS=$'\t' read -r CATEGORY URL OUTFILE; do

    download_file "$CATEGORY" "$URL" "$OUTFILE" &

    PIDS+=("$!")

    if (( ${#PIDS[@]} >= MAX_PARALLEL )); then

        wait_batch

    fi

done < "$MANIFEST"

wait_batch

# ============================================================================
# 11. Validate downloaded files
# ============================================================================

SUCCESS=0
MISSING=0

MISSING_LIST="$LOG_DIR/missing_${SLURM_JOB_ID}.tsv"

: > "$MISSING_LIST"

while IFS=$'\t' read -r CATEGORY URL OUTFILE; do

    if [[ -s "$OUTFILE" ]]; then

        SUCCESS=$((SUCCESS + 1))

    else

        echo "[MISSING] $OUTFILE"

        printf '%s\t%s\t%s\n' \
            "$CATEGORY" "$URL" "$OUTFILE" >> "$MISSING_LIST"

        MISSING=$((MISSING + 1))

    fi

done < "$MANIFEST"

# ============================================================================
# 12. Final summary
# ============================================================================

echo
echo "============================================================"
echo "WoFS retrospective AWS download summary"
echo "============================================================"
echo "WOFS_CDATE   = $WOFS_CDATE"
echo "IC_INIT      = $IC_INIT"
echo "BC_INIT      = $BC_INIT"
echo "GEFS_INIT    = $GEFS_INIT"
echo "SST_INIT     = $SST_INIT"
echo "Expected     = $EXPECTED"
echo "Present      = $SUCCESS"
echo "Missing      = $MISSING"
echo "Failed tasks = $FAILED"
echo "Manifest     = $MANIFEST"
echo "Missing list = $MISSING_LIST"
echo "Archive root = $ARCHIVE_ROOT"
echo "============================================================"

if (( MISSING == 0 && FAILED == 0 )); then

    touch "$LOG_DIR/DOWNLOAD_SUCCESS_${SLURM_JOB_ID}"

    echo "[PASS] All requested historical WoFS input files are present."

    exit 0

else

    echo "[FAIL] Historical data download incomplete."

    exit 1

fi

