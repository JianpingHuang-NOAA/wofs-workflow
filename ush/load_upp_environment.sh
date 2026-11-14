#!/bin/bash
#
# Initialize the isolated WoFS UPP runtime environment.
# Source only from an isolated shell or subprocess.
#

: "${HOMEwofs:?HOMEwofs must be defined}"

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
