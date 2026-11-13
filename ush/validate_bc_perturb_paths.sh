#!/usr/bin/env bash
#
# Validate WoFS BC_PREP PERTURB output directories.
#
# Usage:
#   validate_bc_perturb_paths.sh
#
# This utility performs no filesystem modifications.

set -euo pipefail

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

resolve_path()
{
    local path="$1"
    local resolved

    [[ "$path" == /* ]] ||
        die "Path must be absolute: $path"

    resolved=$(realpath -m -- "$path") ||
        die "Cannot resolve path: $path"

    [[ "$resolved" != / ]] ||
        die "Filesystem root is not permitted: $path"

    printf '%s\n' "$resolved"
}

within()
{
    local child="$1"
    local parent="$2"

    [[ "$child" == "$parent" ||
       "$child" == "$parent/"* ]]
}

overlaps()
{
    within "$1" "$2" || within "$2" "$1"
}

require_directory()
{
    local path="$1"

    [[ -d "$path" ]] ||
        die "Required directory does not exist: $path"
}

MODE="${BC_PREP_MODE:-regression}"

: "${DATAHOME:?ERROR: DATAHOME is required}"
: "${COMROOT:?ERROR: COMROOT is required}"
: "${START_TIME:?ERROR: START_TIME is required}"
: "${WOF_CYCLE_TIME:?ERROR: WOF_CYCLE_TIME is required}"
: "${MEMBER:?ERROR: MEMBER is required}"
: "${FCST_LEAD_TIME:?ERROR: FCST_LEAD_TIME is required}"

# Require explicit protection configuration.
: "${BC_PROTECTED_WORK_ROOT:?ERROR: BC_PROTECTED_WORK_ROOT is required}"
: "${BC_PROTECTED_COM_ROOT:?ERROR: BC_PROTECTED_COM_ROOT is required}"

SENDCOM="${SENDCOM:-YES}"
COM_OVERWRITE="${COM_OVERWRITE:-NO}"

[[ "$SENDCOM" == YES || "$SENDCOM" == NO ]] ||
    die "Invalid SENDCOM"

[[ "$COM_OVERWRITE" == YES || "$COM_OVERWRITE" == NO ]] ||
    die "Invalid COM_OVERWRITE"

validate_cycle()
{
    local cycle="$1"
    local checked

    [[ "$cycle" =~ ^[0-9]{10}$ ]] ||
        die "Invalid cycle: $cycle"

    checked=$(date -u \
        -d "${cycle:0:4}-${cycle:4:2}-${cycle:6:2} ${cycle:8:2}:00:00" \
        +%Y%m%d%H) ||
        die "Invalid cycle date: $cycle"

    [[ "$checked" == "$cycle" ]] ||
        die "Invalid cycle date: $cycle"
}

validate_cycle "$START_TIME"
validate_cycle "$WOF_CYCLE_TIME"

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

FILENAME="wrfnat_pert_hrrr_mem${MEM4}_${FHOUR}.grib2"

COMOUT="${COMROOT}/wofs.${PDY}/${cyc}/INPUT/mem${MEM2}"

SOURCE_FILE="${DATAHOME}/${FILENAME}"
TARGET_FILE="${COMOUT}/${FILENAME}"

WORK=$(resolve_path "$DATAHOME")
COM=$(resolve_path "$COMROOT")
OUT=$(resolve_path "$COMOUT")

PROTECTED_WORK=$(resolve_path "$BC_PROTECTED_WORK_ROOT")
PROTECTED_COM=$(resolve_path "$BC_PROTECTED_COM_ROOT")

# Validate execution-mode boundaries.
case "$MODE" in

    regression)
        : "${TEST_ROOT:?ERROR: TEST_ROOT is required in regression mode}"

        TEST=$(resolve_path "$TEST_ROOT")

        require_directory "$TEST"

        for path in "$WORK" "$COM" "$OUT"
        do
            within "$path" "$TEST" ||
                die "Path is outside TEST_ROOT: $path"

            [[ "$path" != "$TEST" ]] ||
                die "Output must be below TEST_ROOT"
        done
        ;;

    operational)
        : "${BC_PERTURB_WORK_ROOT:?ERROR: Operational work root is required}"
        : "${BC_PERTURB_COM_ROOT:?ERROR: Operational COM root is required}"

        [[ -z "${TEST_ROOT:-}" ]] ||
            die "Unset TEST_ROOT for operational mode"

        AUTH_WORK=$(resolve_path "$BC_PERTURB_WORK_ROOT")
        AUTH_COM=$(resolve_path "$BC_PERTURB_COM_ROOT")

        require_directory "$AUTH_WORK"
        require_directory "$AUTH_COM"

        if overlaps "$AUTH_WORK" "$AUTH_COM"; then
            die "Authorized work and COM roots overlap"
        fi

        within "$WORK" "$AUTH_WORK" ||
            die "DATAHOME is outside authorized work root"

        [[ "$WORK" != "$AUTH_WORK" ]] ||
            die "DATAHOME must be below authorized work root"

        within "$COM" "$AUTH_COM" ||
            die "COMROOT is outside authorized COM root"

        within "$OUT" "$AUTH_COM" ||
            die "COMOUT is outside authorized COM root"
        ;;

    *)
        die "Invalid BC_PREP_MODE: $MODE"
        ;;

esac

# COMOUT must remain below COMROOT.
within "$OUT" "$COM" ||
    die "COMOUT is outside COMROOT"

[[ "$OUT" != "$COM" ]] ||
    die "COMOUT must be below COMROOT"

# Prevent overlap between work and publication directories.
if overlaps "$WORK" "$COM"; then
    die "Working and COM directories overlap"
fi

# Protect historical directories, including their ancestors.
for path in "$WORK" "$COM" "$OUT"
do
    for protected in "$PROTECTED_WORK" "$PROTECTED_COM"
    do
        if overlaps "$path" "$protected"; then
            die "Output overlaps protected directory: $path"
        fi
    done
done

# Reject existing unsafe output-file types.
for file in "$SOURCE_FILE" "$TARGET_FILE"
do
    [[ ! -L "$file" ]] ||
        die "Symbolic-link output is not permitted: $file"

    if [[ -e "$file" && ! -f "$file" ]]; then
        die "Output is not a regular file: $file"
    fi
done

if [[ -e "$SOURCE_FILE" && -e "$TARGET_FILE" &&
      "$SOURCE_FILE" -ef "$TARGET_FILE" ]]; then
    die "Source and target refer to the same file"
fi

echo "[PASS] PERTURB path validation"
echo "BC_PREP_MODE = $MODE"
echo "DATAHOME     = $WORK"
echo "COMROOT      = $COM"
echo "COMOUT       = $OUT"
