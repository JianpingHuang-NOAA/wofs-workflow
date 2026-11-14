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

: "${LMOD_DIR:?LMOD_DIR must be defined}"

LMOD_INIT="$(realpath "$LMOD_DIR/../init/bash")"

test -s "$LMOD_INIT"

source "$LMOD_INIT"

module --force purge

SYSTEM_MODULEPATH="${LMOD_DEFAULT_MODULEPATH:-${MODULEPATH:-}}"

if [[ -z "$SYSTEM_MODULEPATH" ]]; then
    echo "[ERROR] No system module search path available" >&2
    exit 1
fi

# Remove inherited library and Python environment overrides.
unset LD_LIBRARY_PATH LD_PRELOAD
unset PYTHONPATH PYTHONHOME

export PATH=/usr/local/slurm/default/bin:/usr/bin:/bin
export MODULEPATH="$SYSTEM_MODULEPATH"
export SLURM_EXPORT_ENV=ALL

source "$HOMEwofs/versions/run.ver"

module use "$HOMEwofs/modulefiles"
module load "$upp_modulefile"

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
