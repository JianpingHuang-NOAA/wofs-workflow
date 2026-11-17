#!/bin/bash
# ============================================================================
# Stage historical AWS input data for WoFS IC_PREP and BC_PREP.
#
# Usage:
#   ./ush/stage_wofs_retro_inputs.sh YYYYMMDDHH
#
# Example:
#   ./ush/stage_wofs_retro_inputs.sh 2026110215
#
# All input files are staged using symbolic links.
# Existing files are not overwritten.
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

WOFS_CDATE="${1:-}"

[[ "$WOFS_CDATE" =~ ^[0-9]{10}$ ]] ||
    die "Usage: $0 YYYYMMDDHH"

DATAROOT="${DATAROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang}"

ARCHIVE_ROOT="${ARCHIVE_ROOT:-${DATAROOT}/data}"

STAGE_ROOT="${STAGE_ROOT:-${DATAROOT}/retro_inputs}"

HRRR_FH_WIDTH="${HRRR_FH_WIDTH:-6}"

[[ "$HRRR_FH_WIDTH" =~ ^[1-9]$ ]] ||
    die "Invalid HRRR_FH_WIDTH"

# ============================================================================
# 2. Determine initialization cycles
# ============================================================================

WOFS_ISO="${WOFS_CDATE:0:4}-${WOFS_CDATE:4:2}-${WOFS_CDATE:6:2} ${WOFS_CDATE:8:2}:00:00"

WOFS_EPOCH="$(date -u -d "$WOFS_ISO" +%s)"

[[ "$(date -u -d "@$WOFS_EPOCH" +%Y%m%d%H)" == "$WOFS_CDATE" ]] ||
    die "Invalid WoFS cycle"

IC_INIT="$(date -u -d "@$((WOFS_EPOCH - 3600))" +%Y%m%d%H)"

BC_HOUR=$((10#${WOFS_CDATE:8:2} / 6 * 6))

printf -v BC_CYCLE '%02d' "$BC_HOUR"

BC_INIT="${WOFS_CDATE:0:8}${BC_CYCLE}"

BC_ISO="${BC_INIT:0:4}-${BC_INIT:4:2}-${BC_INIT:6:2} ${BC_INIT:8:2}:00:00"

BC_EPOCH="$(date -u -d "$BC_ISO" +%s)"

GEFS_EPOCH=$((BC_EPOCH - 21600))

GEFS_INIT="$(date -u -d "@$GEFS_EPOCH" +%Y%m%d%H)"

GEFS_DATE="${GEFS_INIT:0:8}"
GEFS_CYCLE="${GEFS_INIT:8:2}"

GEFS_YJH="$(date -u -d "@$GEFS_EPOCH" +%y%j%H)"

SST_EPOCH=$((GEFS_EPOCH - 86400))

SST_DATE="$(date -u -d "@$SST_EPOCH" +%Y%m%d)"

SST_YJ="$(date -u -d "@$SST_EPOCH" +%y%j)"

HRRR_YJH="$(date -u -d "@$BC_EPOCH" +%y%j%H)"

# ============================================================================
# 3. Source directories
# ============================================================================

HRRRDAS_SRC="${ARCHIVE_ROOT}/hrrrdas/conus/wrfnat/grib2/${IC_INIT}"

HRRRGES_SRC="${ARCHIVE_ROOT}/hrrrges_sfc/conus/${IC_INIT}"

HRRR_SRC="${ARCHIVE_ROOT}/hrrr/hrrr.${BC_INIT:0:8}/${BC_CYCLE}"

GEFS_SRC="${ARCHIVE_ROOT}/gefs/gefs_${GEFS_DATE}/${GEFS_CYCLE}"

SST_SRC="${ARCHIVE_ROOT}/sst/nsst.${SST_DATE}"

# ============================================================================
# 4. Staging directories
# ============================================================================

IC_INPUT_ROOT="${DATAROOT}/WoF_IC/hrrrdas/${IC_INIT}"

RETRO_ROOT="${STAGE_ROOT}/${WOFS_CDATE}"

GEFS_DIR="${RETRO_ROOT}/gefs"

HIGHRES_SST_DIR="${RETRO_ROOT}/sst"

HRRR_DIR="${RETRO_ROOT}/hrrr/conus/wrfnat/grib2"

mkdir -p \
    "$IC_INPUT_ROOT" \
    "$GEFS_DIR" \
    "$HIGHRES_SST_DIR" \
    "$HRRR_DIR"

echo "============================================================"
echo "WoFS retrospective input staging"
echo "============================================================"
echo "WOFS_CDATE      = $WOFS_CDATE"
echo "IC_INIT         = $IC_INIT"
echo "BC_INIT         = $BC_INIT"
echo "GEFS_INIT       = $GEFS_INIT"
echo "SST_DATE        = $SST_DATE"
echo "ARCHIVE_ROOT    = $ARCHIVE_ROOT"
echo "IC_INPUT_ROOT   = $IC_INPUT_ROOT"
echo "GEFS_DIR        = $GEFS_DIR"
echo "HIGHRES_SST_DIR = $HIGHRES_SST_DIR"
echo "HRRR_DIR        = $HRRR_DIR"
echo "============================================================"

# ============================================================================
# 5. Safe symbolic-link creation
# ============================================================================

CREATED=0
SKIPPED=0

MANIFEST="${RETRO_ROOT}/staging_manifest.tsv"

printf 'CATEGORY\tSOURCE\tDESTINATION\n' > "$MANIFEST"

stage_file() {

    local category="$1"
    local source="$2"
    local target="$3"

    [[ -s "$source" ]] ||
        die "Missing or empty source: $source"

    mkdir -p "$(dirname "$target")"

    if [[ -e "$target" || -L "$target" ]]; then

        if [[ "$source" -ef "$target" ]] ||
           { [[ -f "$target" && -s "$target" ]] &&
             cmp -s "$source" "$target"; }; then

            echo "[SKIP] $category $(basename "$target")"

            SKIPPED=$((SKIPPED + 1))

        else

            die "Destination already exists: $target"

        fi

    else

        ln -s "$(realpath "$source")" "$target"

        echo "[SUCCESS] $category $(basename "$target")"

        CREATED=$((CREATED + 1))

    fi

    printf '%s\t%s\t%s\n' \
        "$category" "$source" "$target" >> "$MANIFEST"

}

# ============================================================================
# 6. Stage IC_PREP inputs
# ============================================================================

echo
echo "===== Stage HRRRDAS ensemble inputs ====="

for ((member=1; member<=36; member++)); do

    printf -v MEM4 '%04d' "$member"

    FILENAME="hrrrdas_small_d02_${IC_INIT}00f01_mem${MEM4}"

    stage_file \
        HRRRDAS \
        "${HRRRDAS_SRC}/${FILENAME}" \
        "${IC_INPUT_ROOT}/${FILENAME}"

done

echo
echo "===== Stage HRRRGES deterministic input ====="

FILENAME="hrrr_${IC_INIT}f001"

stage_file \
    HRRRGES_SFC \
    "${HRRRGES_SRC}/${FILENAME}" \
    "${IC_INPUT_ROOT}/${FILENAME}"

# ============================================================================
# 7. Stage GEFS pgrb2b inputs
# ============================================================================

echo
echo "===== Stage GEFS pgrb2b inputs ====="

for ((member=1; member<=18; member++)); do

    printf -v MEM2 '%02d' "$member"

    for ((hour=6; hour<=36; hour+=3)); do

        printf -v FH3 '%03d' "$hour"

        SOURCE_NAME="gep${MEM2}.t${GEFS_CYCLE}z.pgrb2b.0p50.f${FH3}"

        # Match exwofs_bc_prep_ungrib.sh:
        # GEFS_FILE_5=${GEFS_INIT_YJH}00000${FCST_HOUR}

        TARGET_NAME="${GEFS_YJH}00000${hour}"

        stage_file \
            GEFS_b \
            "${GEFS_SRC}/${SOURCE_NAME}" \
            "${GEFS_DIR}/pgrb2b/gep${MEM2}/${TARGET_NAME}"

    done

done

# ============================================================================
# 8. Stage high-resolution SST
# ============================================================================

echo
echo "===== Stage SST input ====="

stage_file \
    SST \
    "${SST_SRC}/rtgssthr_grb_0.083.grib2" \
    "${HIGHRES_SST_DIR}/${SST_YJ}00000000"

# ============================================================================
# 9. Stage deterministic HRRR boundary-condition inputs
# ============================================================================

echo
echo "===== Stage HRRR wrfnat inputs ====="

for ((hour=0; hour<=25; hour++)); do

    printf -v FH2 '%02d' "$hour"

    printf -v FH_SUFFIX '%0*d' "$HRRR_FH_WIDTH" "$hour"

    SOURCE_NAME="hrrr.t${BC_CYCLE}z.wrfnatf${FH2}.grib2"

    TARGET_NAME="${HRRR_YJH}${FH_SUFFIX}"

    stage_file \
        HRRR_BC \
        "${HRRR_SRC}/${SOURCE_NAME}" \
        "${HRRR_DIR}/${TARGET_NAME}"

done

# ============================================================================
# 10. Save runtime environment
# ============================================================================

ENV_FILE="${RETRO_ROOT}/retro_inputs.env"

{
    printf 'export DATAROOT=%q\n' "$DATAROOT"
    printf 'export WOFS_CDATE=%q\n' "$WOFS_CDATE"
    printf 'export INIT_TIME=%q\n' "$IC_INIT"
    printf 'export BC_CDATE=%q\n' "$BC_INIT"
    printf 'export WOF_CYCLE_TIME=%q\n' "$WOFS_CDATE"
    printf 'export GEFS_DIR=%q\n' "$GEFS_DIR"
    printf 'export HIGHRES_SST_DIR=%q\n' "$HIGHRES_SST_DIR"
    printf 'export HRRR_DIR=%q\n' "$HRRR_DIR"
} > "$ENV_FILE"

# ============================================================================
# 11. Final summary
# ============================================================================

EXPECTED=262

TOTAL=$((CREATED + SKIPPED))

echo
echo "============================================================"
echo "WoFS retrospective input staging summary"
echo "============================================================"
echo "WOFS_CDATE = $WOFS_CDATE"
echo "EXPECTED   = $EXPECTED"
echo "CREATED    = $CREATED"
echo "SKIPPED    = $SKIPPED"
echo "TOTAL      = $TOTAL"
echo "MANIFEST   = $MANIFEST"
echo "ENV_FILE   = $ENV_FILE"
echo "============================================================"

[[ "$TOTAL" -eq "$EXPECTED" ]] ||
    die "Unexpected number of staged files"

touch "${RETRO_ROOT}/STAGING_SUCCESS"

echo "[PASS] All requested historical inputs staged."

