#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

cd "$SCRIPT_DIR"

export HOMEwofs="${HOMEwofs:-$(git rev-parse --show-toplevel)}"

echo "===== WoFS BC_PREP ensemble mean build ====="

echo "HOMEwofs = $HOMEwofs"
echo "Source   = $SCRIPT_DIR"

# Load centralized dependency versions.
source "$HOMEwofs/versions/build.ver"

# Load the validated Intel/NetCDF environment.
module use "$HOMEwofs/modulefiles"

module load ursa_wrf

echo
echo "===== Loaded modules ====="

module list

echo
echo "===== Build environment ====="

for cmd in mpiifort nc-config nf-config pnetcdf-config; do

    command -v "$cmd" || {
        echo "[ERROR] Missing required command: $cmd"
        exit 1
    }

done

echo
echo "===== Clean ====="

make clean

echo
echo "===== Compile and install ====="

make EXEC_DIR="$HOMEwofs/exec"

echo
echo "===== Installed executable ====="

ls -lh "$HOMEwofs/exec/average_netcdf_files_parallel.x"

echo
echo "===== SHA256 checksum ====="

sha256sum "$HOMEwofs/exec/average_netcdf_files_parallel.x"

echo
echo "[SUCCESS] Ensemble mean utility build completed."

