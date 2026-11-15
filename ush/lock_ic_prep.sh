#!/usr/bin/env bash
#
# WoFS IC_PREP persistent advisory locking.
#
# Source this helper from the execution script.
# Keep lock descriptors open throughout processing.
# Never remove persistent lock files during cleanup.

ic_prep_lock_error()
{
    echo "ERROR: IC_PREP lock: $*" >&2
    return 1
}

acquire_ic_prep_lock()
{
    local lock_file="$1"
    local label="$2"
    local fd
    local status=0
    local links

    # Create a private persistent lock file if absent.
    if [[ ! -e "$lock_file" && ! -L "$lock_file" ]]; then
        (
            umask 077
            set -o noclobber
            : > "$lock_file"
        ) 2>/dev/null || true
    fi

    if [[ ! -f "$lock_file" || -L "$lock_file" ]]; then
        ic_prep_lock_error "Unsafe lock file: $lock_file"
        return 1
    fi

    if [[ ! -O "$lock_file" ]]; then
        ic_prep_lock_error "Lock file not owned by current user"
        return 1
    fi

    if ! links=$(stat -c '%h' -- "$lock_file"); then
        ic_prep_lock_error "Cannot inspect lock file"
        return 1
    fi

    if [[ "$links" != 1 ]]; then
        ic_prep_lock_error "Lock file has multiple hard links"
        return 1
    fi

    # Allocate a descriptor without truncating the file.
    if ! exec {fd}<>"$lock_file"; then
        ic_prep_lock_error "Cannot open $lock_file"
        return 1
    fi

    flock -n -E 75 "$fd" || status=$?

    case "$status" in
        0)
            ;;
        75)
            echo "ERROR: IC_PREP lock conflict: $label" >&2
            echo "  Lock: $lock_file" >&2
            exec {fd}>&-
            return 75
            ;;
        *)
            ic_prep_lock_error "flock failed: status=$status"
            exec {fd}>&-
            return 1
            ;;
    esac

    # Verify the locked descriptor still refers to the
    # expected persistent file.
    if [[ ! -f "$lock_file" ||
          -L "$lock_file" ||
          ! -O "$lock_file" ||
          ! "$lock_file" -ef "/proc/$$/fd/$fd" ]]; then

        ic_prep_lock_error "Lock-file identity changed"
        exec {fd}>&-
        return 1
    fi

    if ! links=$(stat -c '%h' -- "$lock_file"); then
        exec {fd}>&-
        return 1
    fi

    if [[ "$links" != 1 ]]; then
        ic_prep_lock_error "Locked file has multiple hard links"
        exec {fd}>&-
        return 1
    fi

    # Retain the descriptor in the calling shell.
    IC_PREP_LOCK_FDS+=("$fd")

    echo "[PASS] Acquired IC_PREP lock: $label"
    echo "  Lock: $lock_file"
}

release_ic_prep_locks()
{
    local fd

    for fd in "${IC_PREP_LOCK_FDS[@]}"; do
        exec {fd}>&-
    done

    IC_PREP_LOCK_FDS=()
}

initialize_ic_prep_locks()
{
    local work_dir="$1"
    local output_file="$2"
    local output_dir
    local output_name
    local status

    IC_PREP_LOCK_FDS=()

    if ! work_dir=$(realpath -e -- "$work_dir"); then
        ic_prep_lock_error "Invalid working directory"
        return 1
    fi

    if ! output_dir=$(realpath -e -- "$(dirname -- "$output_file")"); then
        ic_prep_lock_error "Invalid COM directory"
        return 1
    fi

    output_name=$(basename -- "$output_file")

    if [[ ! -d "$work_dir" || ! -d "$output_dir" ]]; then
        ic_prep_lock_error "Invalid lock directory"
        return 1
    fi

    # Always acquire locks in the same order.
    if acquire_ic_prep_lock \
        "$work_dir/.ic_prep_work.lock" \
        "working directory"; then
        :
    else
        status=$?
        release_ic_prep_locks
        return "$status"
    fi

    if acquire_ic_prep_lock \
        "$output_dir/.${output_name}.lock" \
        "COM destination"; then
        :
    else
        status=$?
        release_ic_prep_locks
        return "$status"
    fi

    echo "[PASS] Both IC_PREP locks acquired"
}
