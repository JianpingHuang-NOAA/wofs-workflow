#!/usr/bin/env bash

# Publish one BC_PREP GRIB2 product into the WoFS COM directory.
#
# Required environment:
#   COMROOT
#   WOF_CYCLE_TIME
#   DATAHOME
#   MEMBER
#   FCST_LEAD_TIME
#
# Optional:
#   SENDCOM       YES or NO (default YES)
#   COM_OVERWRITE YES or NO (default NO)

set -euo pipefail

: "${COMROOT:?ERROR: COMROOT is required}"
: "${WOF_CYCLE_TIME:?ERROR: WOF_CYCLE_TIME is required}"
: "${DATAHOME:?ERROR: DATAHOME is required}"
: "${MEMBER:?ERROR: MEMBER is required}"
: "${FCST_LEAD_TIME:?ERROR: FCST_LEAD_TIME is required}"

SENDCOM="${SENDCOM:-YES}"
COM_OVERWRITE="${COM_OVERWRITE:-NO}"

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ "$SENDCOM" == YES || "$SENDCOM" == NO ]] ||
    die "Invalid SENDCOM"

[[ "$COM_OVERWRITE" == YES || "$COM_OVERWRITE" == NO ]] ||
    die "Invalid COM_OVERWRITE"

if [[ "$SENDCOM" == NO ]]; then
    echo "[SKIP] SENDCOM=NO"
    exit 0
fi

[[ "$WOF_CYCLE_TIME" =~ ^[0-9]{10}$ ]] ||
    die "Invalid WOF_CYCLE_TIME"

[[ "$MEMBER" =~ ^[0-9]{1,4}$ ]] ||
    die "Invalid MEMBER"

[[ "$FCST_LEAD_TIME" =~ ^[0-9]{1,2}$ ]] ||
    die "Invalid FCST_LEAD_TIME"

member_num=$((10#$MEMBER))
hour_num=$((10#$FCST_LEAD_TIME))

(( member_num >= 1 && member_num <= 18 )) ||
    die "MEMBER must be between 1 and 18"

(( hour_num >= 0 && hour_num <= 25 )) ||
    die "FCST_LEAD_TIME must be between 0 and 25"

printf -v MEM2 "%02d" "$member_num"
printf -v MEM4 "%04d" "$member_num"
printf -v FHOUR "%02d" "$hour_num"

PDY="${WOF_CYCLE_TIME:0:8}"
cyc="${WOF_CYCLE_TIME:8:2}"

cycle_check=$(date -u \
    -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    +%Y%m%d%H) || die "Invalid cycle date"

[[ "$cycle_check" == "$WOF_CYCLE_TIME" ]] ||
    die "Invalid cycle date"

FILENAME="wrfnat_pert_hrrr_mem${MEM4}_${FHOUR}.grib2"

SOURCE_FILE="${DATAHOME}/${FILENAME}"

COMOUT="${COMROOT}/wofs.${PDY}/${cyc}/INPUT/mem${MEM2}"

TARGET_FILE="${COMOUT}/${FILENAME}"

[[ -f "$SOURCE_FILE" && -s "$SOURCE_FILE" ]] ||
    die "Missing or empty source: $SOURCE_FILE"

[[ "$COMROOT" == /* && "$COMROOT" != / ]] ||
    die "COMROOT must be an absolute non-root path"

[[ "$DATAHOME" == /* && "$DATAHOME" != / ]] ||
    die "DATAHOME must be an absolute non-root path"

[[ ! -L "$SOURCE_FILE" ]] ||
    die "Refusing symbolic-link source: $SOURCE_FILE"

# Protect historical outputs and isolated regression directories.
DATAHOME_RESOLVED=$(realpath -m -- "$DATAHOME")
COMROOT_RESOLVED=$(realpath -m -- "$COMROOT")
COMOUT_RESOLVED=$(realpath -m -- "$COMOUT")

[[ "$COMROOT_RESOLVED" != / ]] ||
    die "Resolved COMROOT must not be root"

[[ "$DATAHOME_RESOLVED" != / ]] ||
    die "Resolved DATAHOME must not be root"

HISTORICAL_PERTURB_ROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC/pert_hrrr"
HISTORICAL_COMROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/com/wofs/v1.0"

HIST_PERTURB_RESOLVED=$(realpath -m -- "$HISTORICAL_PERTURB_ROOT")
HIST_COM_RESOLVED=$(realpath -m -- "$HISTORICAL_COMROOT")

for DIR in "$DATAHOME_RESOLVED" "$COMROOT_RESOLVED" "$COMOUT_RESOLVED"
do
    case "${DIR}/" in
        "${HIST_PERTURB_RESOLVED}/"*|"${HIST_COM_RESOLVED}/"*)
            die "Path points into historical outputs: $DIR"
            ;;
    esac
done

# COMOUT must remain within the configured COMROOT.
case "${COMOUT_RESOLVED}/" in
    "${COMROOT_RESOLVED}/"*) ;;
    *)
        die "Resolved COMOUT is outside COMROOT"
        ;;
esac

# Enforce regression isolation when TEST_ROOT is configured.
if [[ -n "${TEST_ROOT:-}" ]]; then

    TEST_ROOT_RESOLVED=$(realpath -e -- "$TEST_ROOT") ||
        die "Invalid TEST_ROOT"

    [[ -d "$TEST_ROOT_RESOLVED" && "$TEST_ROOT_RESOLVED" != / ]] ||
        die "Invalid TEST_ROOT directory"

    for DIR in "$DATAHOME_RESOLVED" "$COMROOT_RESOLVED" "$COMOUT_RESOLVED"
    do
        case "${DIR}/" in
            "${TEST_ROOT_RESOLVED}/"*) ;;
            *)
                die "Path is outside TEST_ROOT: $DIR"
                ;;
        esac
    done

fi

mkdir -p -- "$COMOUT"

if [[ -L "$TARGET_FILE" ]]; then
    die "Refusing to overwrite symbolic link: $TARGET_FILE"
fi

if [[ -e "$TARGET_FILE" ]]; then

    [[ -f "$TARGET_FILE" ]] ||
        die "Target is not a regular file"

    if cmp -s -- "$SOURCE_FILE" "$TARGET_FILE"; then
        echo "[SKIP] Identical: $TARGET_FILE"
        exit 0
    fi

    [[ "$COM_OVERWRITE" == YES ]] ||
        die "Different target exists: $TARGET_FILE"
fi

TEMP_FILE=""

cleanup() {
    if [[ -n "$TEMP_FILE" ]]; then
        rm -f -- "$TEMP_FILE"
    fi
}

trap cleanup EXIT

TEMP_FILE=$(mktemp "${COMOUT}/.${FILENAME}.tmp.XXXXXXXX")

cp -p -- "$SOURCE_FILE" "$TEMP_FILE"

cmp -s -- "$SOURCE_FILE" "$TEMP_FILE" ||
    die "Copied file differs from source"

if [[ "$COM_OVERWRITE" == YES ]]; then

    mv -fT -- "$TEMP_FILE" "$TARGET_FILE"

else

    # Publish atomically without replacing an existing file.
    if ! ln -T -- "$TEMP_FILE" "$TARGET_FILE"; then

        if [[ -f "$TARGET_FILE" && ! -L "$TARGET_FILE" ]] &&
           cmp -s -- "$SOURCE_FILE" "$TARGET_FILE"; then

            echo "[SKIP] Identical target already published"
            exit 0
        fi

        die "Unable to publish without overwriting: $TARGET_FILE"
    fi

    rm -f -- "$TEMP_FILE"
fi

TEMP_FILE=""

[[ -s "$TARGET_FILE" ]] ||
    die "Published file is empty"

echo "[PASS] Published: $TARGET_FILE"
