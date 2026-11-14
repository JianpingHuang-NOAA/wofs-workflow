#!/bin/bash
#
# Execute UPP in an isolated Intel runtime environment.
#
# Usage:
#   run_upp.sh <upp_executable> <mpi_tasks> <itag_file>
#

set -eo pipefail

: "${HOMEwofs:?HOMEwofs must be defined}"

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <upp_executable> <mpi_tasks> <itag_file>" >&2
    exit 2
fi

POST="$(realpath "$1")"
NTASKS="$2"
ITAG="$(realpath "$3")"

[[ -x "$POST" ]] || exit 1
[[ -s "$ITAG" ]] || exit 1
[[ "$NTASKS" =~ ^[1-9][0-9]*$ ]] || exit 1

unset CRTM_FIX
source "$HOMEwofs/ush/load_upp_environment.sh"

# -------------------------------------------------------
# Stage CRTM coefficients
# -------------------------------------------------------
if [[ "${CRTM:-0}" == "1" ]]; then
    CRTM_FIX_DIR="${CRTM_FIX_DIR:-auto}"

    if [[ "${CRTM_FIX_DIR}" == "auto" ]]; then
        : "${CRTM_FIX:?Missing module-provided CRTM_FIX}"
        CRTM_FIX_DIR="${CRTM_FIX}"
    fi

    CRTM_FIX_DIR="$(realpath -e "${CRTM_FIX_DIR}")"

    echo "CRTM_FIX_DIR = ${CRTM_FIX_DIR}"

    [[ -d "${CRTM_FIX_DIR}" ]] || {
        echo "ERROR: Missing CRTM directory: ${CRTM_FIX_DIR}" >&2
        exit 1
    }

    # Validate the approved CRTM coefficient inventory.
    manifest="$HOMEwofs/parm/crtm/crtm_fix.sha256"

    [[ -s "$manifest" && -r "$manifest" ]] || {
        echo "[ERROR] Missing CRTM manifest: $manifest" >&2
        exit 1
    }

    declare -A expected_crtm=()

    while read -r checksum filename; do
        name="${filename#./}"

        if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ||
              "$filename" != ./* ||
              "$name" == */* ||
              "$name" != *bin ]]; then
            echo "[ERROR] Invalid CRTM manifest entry: $filename" >&2
            exit 1
        fi

        if [[ -n "${expected_crtm[$name]+present}" ]]; then
            echo "[ERROR] Duplicate CRTM entry: $name" >&2
            exit 1
        fi

        expected_crtm["$name"]=1
    done < "$manifest"

    (( ${#expected_crtm[@]} > 0 )) || {
        echo "[ERROR] Empty CRTM manifest" >&2
        exit 1
    }

    # Validate every required source file before staging.
    for name in "${!expected_crtm[@]}"; do
        file="$CRTM_FIX_DIR/$name"

        if [[ ! -f "$file" || ! -r "$file" || ! -s "$file" ]]; then
            echo "[ERROR] Invalid CRTM coefficient: $file" >&2
            exit 1
        fi
    done

    shopt -s nullglob
    crtm_files=( "$CRTM_FIX_DIR"/*bin )
    existing_files=( ./*bin )
    shopt -u nullglob

    # Reject unexpected source coefficients.
    for file in "${crtm_files[@]}"; do
        name="${file##*/}"

        if [[ -z "${expected_crtm[$name]+present}" ]]; then
            echo "[ERROR] Unexpected CRTM coefficient: $file" >&2
            exit 1
        fi
    done

    # Protect existing working-directory files.
    for file in "${existing_files[@]}"; do
        name="${file##*/}"

        if [[ -z "${expected_crtm[$name]+present}" ]]; then
            echo "[ERROR] Unexpected POST binary entry: $file" >&2
            exit 1
        fi

        if [[ ! -L "$file" ]]; then
            echo "[ERROR] Refusing to overwrite: $file" >&2
            exit 1
        fi
    done

    # Stage coefficients only after all checks pass.
    for name in "${!expected_crtm[@]}"; do
        ln -sfnT -- "$CRTM_FIX_DIR/$name" "$name"
    done

    echo "[PASS] Staged ${#expected_crtm[@]} CRTM coefficients"
fi

module list > upp_runtime_modules.log 2>&1

echo "===== UPP executable ====="
echo "$POST"

echo "===== UPP shared library verification ====="

ldd -r "$POST" > upp_runtime_ldd.log 2>&1

if grep -E 'not found|undefined symbol' upp_runtime_ldd.log; then
    echo "[ERROR] UPP shared library verification failed" >&2
    exit 1
fi

echo "===== UPP NetCDF Fortran library ====="
grep 'libnetcdff' upp_runtime_ldd.log

echo "===== Running UPP with $NTASKS MPI tasks ====="

srun -n "$NTASKS" "$POST" < "$ITAG"

echo "[PASS] UPP execution completed"
