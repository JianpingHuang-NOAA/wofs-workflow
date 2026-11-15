#!/bin/bash

# Atomically publish a validated IC_PREP GRIB2 product.
#
# Usage:
#   publish_ic_prep_grib2 SOURCE DESTINATION EXPECTED_COUNT
#
# Requires validate_grib2_count() from the calling script.
#
# A subshell isolates temporary-file cleanup and traps
# from the calling workflow.

publish_ic_prep_grib2() (
    set -euo pipefail

    if [[ "$#" -ne 3 ]]; then
        echo "ERROR: Invalid publication arguments" >&2
        exit 1
    fi

    local source_file="$1"
    local destination="$2"
    local expected="$3"

    local destination_dir
    local destination_name
    local temporary_file=""

    destination_dir="$(dirname -- "$destination")"
    destination_name="$(basename -- "$destination")"

    if [[ ! -s "$source_file" ]]; then
        echo "ERROR: Missing publication source: $source_file" >&2
        exit 1
    fi

    if [[ ! -d "$destination_dir" ]]; then
        echo "ERROR: Missing COM directory: $destination_dir" >&2
        exit 1
    fi

    if [[ -e "$destination" && "$source_file" -ef "$destination" ]]; then
        echo "ERROR: Source and destination are identical" >&2
        exit 1
    fi

    cleanup_publication() {
        local status=$?

        trap - EXIT

        if [[ -n "$temporary_file" ]]; then
            rm -f -- "$temporary_file" || true
        fi

        exit "$status"
    }

    trap cleanup_publication EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # The temporary file must be on the same filesystem
    # as the final destination.
    if ! temporary_file="$(mktemp -- \
        "${destination_dir}/.${destination_name}.tmp.XXXXXXXX")"; then

        echo "ERROR: Failed to create temporary COM file" >&2
        exit 1
    fi

    if [[ -z "$temporary_file" || ! -f "$temporary_file" ]]; then
        echo "ERROR: Invalid temporary COM file" >&2
        exit 1
    fi

    echo "===== Atomic COM publication ====="
    echo "Source:      $source_file"
    echo "Temporary:   $temporary_file"
    echo "Destination: $destination"

    if ! cp -- "$source_file" "$temporary_file"; then
        echo "ERROR: Failed to copy temporary COM product" >&2
        exit 1
    fi

    # Preserve source permissions instead of retaining
    # the restrictive permissions created by mktemp.
    if ! chmod --reference="$source_file" "$temporary_file"; then
        echo "ERROR: Failed to set temporary COM permissions" >&2
        exit 1
    fi

    if ! validate_grib2_count \
        "$temporary_file" "$expected" "Temporary COM WRFNAT"; then

        echo "ERROR: Temporary COM inventory validation failed" >&2
        exit 1
    fi

    if ! cmp -s -- "$source_file" "$temporary_file"; then
        echo "ERROR: Temporary COM product differs from source" >&2
        exit 1
    fi

    echo "[PASS] Temporary COM product is bitwise identical"

    # Rename only after all prepublication checks pass.
    if ! mv -fT -- "$temporary_file" "$destination"; then
        echo "ERROR: Atomic COM rename failed" >&2
        exit 1
    fi

    temporary_file=""

    echo "[PASS] Atomic COM publication: $destination"
)
