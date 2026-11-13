#!/usr/bin/env bash

# Publish one BC_PREP GRIB2 product into the WoFS COM directory.
#
# Required environment:
#   HOMEwofs
#   START_TIME
#   BC_PREP_MODE and mode-specific output configuration
#   BC_PROTECTED_WORK_ROOT
#   BC_PROTECTED_COM_ROOT
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

# Use the same path policy as the J-job and isolated runner.
: "${HOMEwofs:?ERROR: HOMEwofs is required}"

VALIDATOR="${HOMEwofs}/ush/validate_bc_perturb_paths.sh"

[[ -x "$VALIDATOR" ]] ||
    die "Missing path validator: $VALIDATOR"

"$VALIDATOR"

# Even when publication is disabled, validate the configuration.
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

# The shared validator has already checked:
#   - regression or operational execution mode
#   - authorized and protected output roots
#   - canonical work and COM path containment
#   - source and target file types
#
# Recheck immediately before creating the COM directory.

"$VALIDATOR"

[[ -f "$SOURCE_FILE" && ! -L "$SOURCE_FILE" &&
   -s "$SOURCE_FILE" ]] ||
    die "Missing, empty, or unsafe source file: $SOURCE_FILE"

[[ "$(stat -c '%h' "$SOURCE_FILE")" == 1 ]] ||
    die "Working source has multiple hard links"

mkdir -p -- "$COMOUT"

# Revalidate after creating the destination directory.
"$VALIDATOR"

# Resolve aliases before constructing the persistent COM lock.
COMOUT=$(realpath -e -- "$COMOUT")
TARGET_FILE="${COMOUT}/${FILENAME}"

# Different working directories can publish the same COM target.
# Serialize publication using a separate persistent target lock.
LOCK_FILE="${COMOUT}/.${FILENAME}.lock"

if [[ ! -e "$LOCK_FILE" && ! -L "$LOCK_FILE" ]]; then
    (
        umask 077
        set -o noclobber
        : > "$LOCK_FILE"
    ) 2>/dev/null || true
fi

[[ -f "$LOCK_FILE" &&
   ! -L "$LOCK_FILE" &&
   -O "$LOCK_FILE" ]] ||
    die "Unsafe COM lock file: $LOCK_FILE"

[[ "$(stat -c '%h' "$LOCK_FILE")" == 1 ]] ||
    die "COM lock file has multiple hard links"

exec 8<>"$LOCK_FILE"

STATUS=0

flock -n -E 75 8 || STATUS=$?

case "$STATUS" in
    0)
        echo "[PASS] Acquired COM target lock"
        ;;
    75)
        die "Another PERTURB execution holds the COM target lock"
        ;;
    *)
        die "Unable to acquire COM target lock: status=$STATUS"
        ;;
esac

[[ -f "$LOCK_FILE" &&
   ! -L "$LOCK_FILE" &&
   -O "$LOCK_FILE" &&
   "$LOCK_FILE" -ef "/proc/$$/fd/8" ]] ||
    die "COM lock-file identity changed"

[[ "$(stat -c '%h' "$LOCK_FILE")" == 1 ]] ||
    die "COM lock file has multiple hard links"

"$VALIDATOR"

# Recover only recognizable interrupted publication links.
recover_com_publication()
{
    local LINKS
    local CANDIDATE
    local -a RECOVERABLE=()

    [[ -e "$TARGET_FILE" ]] || return 0

    [[ -f "$TARGET_FILE" && ! -L "$TARGET_FILE" ]] ||
        die "Unsafe existing COM target"

    LINKS=$(stat -c '%h' "$TARGET_FILE")

    [[ "$LINKS" -gt 1 ]] || return 0

    [[ -O "$TARGET_FILE" ]] ||
        die "Cannot recover COM target owned by another user"

    for CANDIDATE in "$COMOUT"/."${FILENAME}".tmp.*
    do
        [[ -f "$CANDIDATE" &&
           ! -L "$CANDIDATE" &&
           -O "$CANDIDATE" ]] ||
            continue

        [[ "$CANDIDATE" -ef "$TARGET_FILE" ]] ||
            continue

        RECOVERABLE+=("$CANDIDATE")
    done

    # Do not remove anything if any alias is unrecognized.
    (( ${#RECOVERABLE[@]} == LINKS - 1 )) ||
        die "Unrecognized hard links to existing COM target"

    for CANDIDATE in "${RECOVERABLE[@]}"
    do
        [[ -f "$CANDIDATE" &&
           ! -L "$CANDIDATE" &&
           -O "$CANDIDATE" &&
           "$CANDIDATE" -ef "$TARGET_FILE" ]] ||
            die "COM recovery candidate changed unexpectedly"

        rm -- "$CANDIDATE"

        echo "[PASS] Removed interrupted COM link: $CANDIDATE"
    done

    [[ "$(stat -c '%h' "$TARGET_FILE")" == 1 ]] ||
        die "COM target still has multiple hard links"

    echo "[PASS] Interrupted COM publication recovered"
}

recover_com_publication

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
    local STATUS=$?

    trap - EXIT

    if [[ -n "$TEMP_FILE" ]]; then
        rm -f -- "$TEMP_FILE" ||
            echo "[WARNING] COM temporary-file cleanup failed" >&2
    fi

    # Release the lock but never remove its persistent file.
    exec 8>&-

    exit "$STATUS"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TEMP_FILE=$(mktemp "${COMOUT}/.${FILENAME}.tmp.XXXXXXXX")

cp -p -- "$SOURCE_FILE" "$TEMP_FILE"

cmp -s -- "$SOURCE_FILE" "$TEMP_FILE" ||
    die "Copied file differs from source"

[[ -f "$TEMP_FILE" &&
   ! -L "$TEMP_FILE" &&
   -O "$TEMP_FILE" ]] ||
    die "Unsafe temporary COM product"

[[ "$(stat -c '%h' "$TEMP_FILE")" == 1 ]] ||
    die "Temporary COM product has multiple hard links"

"$VALIDATOR"

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

[[ -f "$TARGET_FILE" &&
   ! -L "$TARGET_FILE" &&
   -s "$TARGET_FILE" ]] ||
    die "Published COM product is invalid"

[[ "$(stat -c '%h' "$TARGET_FILE")" == 1 ]] ||
    die "Published COM product has multiple hard links"

cmp -s -- "$SOURCE_FILE" "$TARGET_FILE" ||
    die "Published COM product differs from working source"

echo "[PASS] Published: $TARGET_FILE"
