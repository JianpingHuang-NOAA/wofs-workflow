#!/usr/bin/env bash
#
# Execute BC_PREP PERTURB in a private working directory.
#
# The scientific utility remains unchanged.
# Publish the working GRIB2 only after successful execution.
#
# Hold the working-product lock through COM publication.

set -euo pipefail

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

: "${HOMEwofs:?ERROR: HOMEwofs is required}"
: "${DATAHOME:?ERROR: DATAHOME is required}"
: "${MEMBER:?ERROR: MEMBER is required}"
: "${FCST_LEAD_TIME:?ERROR: FCST_LEAD_TIME is required}"
: "${MIN_FILE_SIZE:?ERROR: MIN_FILE_SIZE is required}"

VALIDATOR="${HOMEwofs}/ush/validate_bc_perturb_paths.sh"
UTILITY="${HOMEwofs}/ush/perturb_hrrr.ksh"
STAGER="${HOMEwofs}/ush/stage_bc_perturb.sh"

[[ -x "$VALIDATOR" ]] ||
    die "Path validator is unavailable: $VALIDATOR"

[[ -x "$UTILITY" ]] ||
    die "Scientific utility is unavailable: $UTILITY"

[[ -x "$STAGER" ]] ||
    die "COM staging utility is unavailable: $STAGER"

export SENDCOM="${SENDCOM:-YES}"
export COM_OVERWRITE="${COM_OVERWRITE:-NO}"

WORK_OVERWRITE="${WORK_OVERWRITE:-NO}"
KEEP_INTERMEDIATE="${KEEP_INTERMEDIATE:-NO}"
KEEP_FAILED_RUN="${KEEP_FAILED_RUN:-NO}"

for FLAG in SENDCOM COM_OVERWRITE WORK_OVERWRITE \
    KEEP_INTERMEDIATE KEEP_FAILED_RUN
do
    [[ "${!FLAG}" == YES || "${!FLAG}" == NO ]] ||
        die "Invalid ${FLAG}=${!FLAG}"
done

[[ "$MIN_FILE_SIZE" =~ ^[1-9][0-9]*$ ]] ||
    die "Invalid MIN_FILE_SIZE"

# Validate all configured paths before filesystem modifications.
"$VALIDATOR"

printf -v MEM2 '%02d' "$((10#$MEMBER))"
printf -v MEM4 '%04d' "$((10#$MEMBER))"
printf -v FHOUR '%02d' "$((10#$FCST_LEAD_TIME))"

export MEMBER="$MEM2"
export FCST_LEAD_TIME="$FHOUR"
export KEEP_INTERMEDIATE

WORK_DIR=$(realpath -m -- "$DATAHOME")

FILENAME="wrfnat_pert_hrrr_mem${MEM4}_${FHOUR}.grib2"

FINAL_FILE="${WORK_DIR}/${FILENAME}"

mkdir -p -- "$WORK_DIR"

[[ -d "$WORK_DIR" && ! -L "$WORK_DIR" ]] ||
    die "Invalid working directory"

export DATAHOME="$WORK_DIR"

# Repeat validation after creating the working directory.
"$VALIDATOR"

# Use a persistent lock file for each member and forecast hour.
# Never remove this lock file during cleanup.
LOCK_FILE="${WORK_DIR}/.perturb_${MEM4}_${FHOUR}.lock"

if [[ ! -e "$LOCK_FILE" && ! -L "$LOCK_FILE" ]]; then
    (
        umask 077
        set -o noclobber
        : > "$LOCK_FILE"
    ) 2>/dev/null || true
fi

[[ -f "$LOCK_FILE" && ! -L "$LOCK_FILE" ]] ||
    die "Unsafe lock file: $LOCK_FILE"

[[ -O "$LOCK_FILE" ]] ||
    die "Lock file is not owned by the current user"

[[ "$(stat -c '%h' "$LOCK_FILE")" == 1 ]] ||
    die "Lock file has multiple hard links"

# Open without truncating an existing lock file.
exec 9<>"$LOCK_FILE"

STATUS=0

flock -n -E 75 9 || STATUS=$?

case "$STATUS" in
    0)
        echo "[PASS] Acquired PERTURB task lock"
        ;;
    75)
        die "Another PERTURB execution holds the task lock"
        ;;
    *)
        die "Unable to acquire task lock: status=$STATUS"
        ;;
esac

# Confirm that the locked descriptor still refers to the
# expected persistent lock file.
[[ -f "$LOCK_FILE" &&
   ! -L "$LOCK_FILE" &&
   -O "$LOCK_FILE" &&
   "$LOCK_FILE" -ef "/proc/$$/fd/9" ]] ||
    die "Working lock-file identity changed"

[[ "$(stat -c '%h' "$LOCK_FILE")" == 1 ]] ||
    die "Working lock file has multiple hard links"

# Revalidate while holding the task lock.
"$VALIDATOR"

# Recover an interrupted hard-link publication.
#
# Only remove a verified link inside a private execution
# directory belonging to this member and forecast hour.
recover_publication()
{
    local LINKS
    local DIR
    local MODE
    local CANDIDATE
    local -a RECOVERABLE=()

    [[ -e "$FINAL_FILE" ]] || return 0

    [[ -f "$FINAL_FILE" && ! -L "$FINAL_FILE" ]] ||
        die "Unsafe existing working product"

    [[ -O "$FINAL_FILE" ]] ||
        die "Existing working product is not owned by current user"

    LINKS=$(stat -c '%h' "$FINAL_FILE")

    [[ "$LINKS" -gt 1 ]] || return 0

    echo "[WARNING] Existing working product has $LINKS hard links"

    for DIR in "$WORK_DIR"/.perturb_"${MEM4}"_"${FHOUR}".*
    do
        [[ -d "$DIR" && ! -L "$DIR" && -O "$DIR" ]] ||
            continue

        MODE=$(stat -c '%a' "$DIR")

        (( (8#$MODE & 0777) == 0700 )) ||
            continue

        CANDIDATE="$DIR/$FILENAME"

        [[ -f "$CANDIDATE" &&
           ! -L "$CANDIDATE" &&
           -O "$CANDIDATE" ]] ||
            continue

        [[ "$CANDIDATE" -ef "$FINAL_FILE" ]] ||
            continue

        RECOVERABLE+=("$CANDIDATE")
    done

    # Fail closed if any hard link cannot be accounted for.
    (( ${#RECOVERABLE[@]} == LINKS - 1 )) ||
        die "Unrecognized hard links to existing working product"

    for CANDIDATE in "${RECOVERABLE[@]}"
    do
        [[ -f "$CANDIDATE" &&
           ! -L "$CANDIDATE" &&
           "$CANDIDATE" -ef "$FINAL_FILE" ]] ||
            die "Recovery candidate changed unexpectedly"

        rm -- "$CANDIDATE"

        echo "[PASS] Removed interrupted publication link: $CANDIDATE"
    done

    [[ "$(stat -c '%h' "$FINAL_FILE")" == 1 ]] ||
        die "Working product still has multiple hard links"

    echo "[PASS] Interrupted publication recovered"
}

recover_publication

RUN_DIR=""

cleanup()
{
    local STATUS=$?

    trap - EXIT

    if [[ -n "$RUN_DIR" &&
          -d "$RUN_DIR" &&
          ! -L "$RUN_DIR" &&
          -O "$RUN_DIR" ]]; then

        local CANDIDATE="$RUN_DIR/$FILENAME"

        # Never retain a generated product that aliases another
        # file through a symbolic link or multiple hard links.
        if [[ -L "$CANDIDATE" ]]; then

            rm -- "$CANDIDATE" || {
                echo "[WARNING] Unsafe generated link remains" >&2
                KEEP_FAILED_RUN=NO
                KEEP_INTERMEDIATE=NO
            }

        elif [[ -f "$CANDIDATE" ]]; then

            local LINKS

            LINKS=$(stat -c '%h' "$CANDIDATE") || LINKS=0

            if [[ "$LINKS" != 1 ]]; then

                rm -- "$CANDIDATE" || {
                    echo "[WARNING] Unsafe generated alias remains" >&2
                    KEEP_FAILED_RUN=NO
                    KEEP_INTERMEDIATE=NO
                }

            fi
        fi

        if [[ "$STATUS" -eq 0 &&
              "$KEEP_INTERMEDIATE" == YES ]]; then

            echo "Retained execution directory: $RUN_DIR"

        elif [[ "$STATUS" -ne 0 &&
                "$KEEP_FAILED_RUN" == YES ]]; then

            echo "Retained failed execution directory: $RUN_DIR"

        else
            # Only remove the unique directory created by mktemp.
            case "$RUN_DIR" in
                "$WORK_DIR"/.perturb_"${MEM4}"_"${FHOUR}".*)
                    rm -rf -- "$RUN_DIR" ||
                        echo "[WARNING] Cleanup failed: $RUN_DIR" >&2
                    ;;
                *)
                    echo "[WARNING] Refusing unsafe cleanup" >&2
                    ;;
            esac
        fi
    fi

    # Release the advisory lock but preserve the lock file.
    exec 9>&-

    exit "$STATUS"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

RUN_DIR=$(mktemp -d \
    "${WORK_DIR}/.perturb_${MEM4}_${FHOUR}.XXXXXXXX")

MODE=$(stat -c '%a' "$RUN_DIR")

(( (8#$MODE & 0777) == 0700 )) ||
    die "Execution directory is not private"

[[ -O "$RUN_DIR" && ! -L "$RUN_DIR" ]] ||
    die "Invalid private execution directory"

[[ "$(stat -c '%d' "$WORK_DIR")" == \
   "$(stat -c '%d' "$RUN_DIR")" ]] ||
    die "Execution and publication directories differ in filesystem"

echo "[PASS] Private execution directory created"
echo "WORK_DIR = $WORK_DIR"
echo "RUN_DIR  = $RUN_DIR"

# Run the original scientific utility in isolation.
(
    export DATAHOME="$RUN_DIR"

    cd "$RUN_DIR"

    "$UTILITY"
)

GENERATED_FILE="${RUN_DIR}/${FILENAME}"

[[ -f "$GENERATED_FILE" &&
   ! -L "$GENERATED_FILE" &&
   -s "$GENERATED_FILE" ]] ||
    die "Scientific utility did not generate a valid output file"

[[ "$(stat -c '%h' "$GENERATED_FILE")" == 1 ]] ||
    die "Generated product has multiple hard links"

SIZE=$(stat -c '%s' "$GENERATED_FILE")

(( SIZE >= MIN_FILE_SIZE )) ||
    die "Generated GRIB2 is smaller than MIN_FILE_SIZE"

echo "[PASS] Generated GRIB2 size: $SIZE bytes"

# Verify that the GRIB2 inventory is readable.
wgrib2 "$GENERATED_FILE" -s > "$RUN_DIR/grib_inventory.txt"

[[ -s "$RUN_DIR/grib_inventory.txt" ]] ||
    die "Generated GRIB2 inventory is empty"

RECORDS=$(wc -l < "$RUN_DIR/grib_inventory.txt")

echo "[PASS] Generated GRIB2 records: $RECORDS"

# Revalidate final output paths before publication.
"$VALIDATOR"

if [[ -e "$FINAL_FILE" ]]; then

    [[ -f "$FINAL_FILE" && ! -L "$FINAL_FILE" ]] ||
        die "Unsafe existing working product"

    if cmp -s "$GENERATED_FILE" "$FINAL_FILE"; then

        echo "[PASS] Existing working product is identical"

    elif [[ "$WORK_OVERWRITE" == YES ]]; then

        mv -fT -- "$GENERATED_FILE" "$FINAL_FILE"

        echo "[PASS] Working product atomically replaced"

    else

        die "Different working product exists; WORK_OVERWRITE=NO"

    fi

else

    # Atomic publication without replacing an existing product.
    ln -T -- "$GENERATED_FILE" "$FINAL_FILE" ||
        die "Unable to publish working product without overwrite"

    # Remove the private link so retained diagnostics cannot
    # modify the published product through a shared inode.
    rm -- "$GENERATED_FILE"

    echo "[PASS] Working product atomically published"

fi

[[ -s "$FINAL_FILE" && ! -L "$FINAL_FILE" ]] ||
    die "Final working product validation failed"

[[ "$(stat -c '%h' "$FINAL_FILE")" == 1 ]] ||
    die "Published working product has multiple hard links"

# The working-product lock remains held during COM staging.
# DATAHOME points to the canonical working directory, not RUN_DIR.
echo "[PASS] Working product validated"
echo "Working product: $FINAL_FILE"

echo "SENDCOM       = $SENDCOM"
echo "COM_OVERWRITE = $COM_OVERWRITE"

"$STAGER"

echo "[PASS] COM staging phase completed"
echo "[PASS] Isolated PERTURB execution completed"
