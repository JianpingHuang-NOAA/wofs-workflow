#!/bin/bash
# ============================================================================
# jwofs_bc_prep_real.sh
# WoFS v1 BC_PREP REAL workflow shell wrapper
#
# Purpose:
#   Submit/run the WoFS v1 REAL J-job for one GEFS member and one
#   forecast valid time.
#
# Required environment:
#   CDATE      WoFS cycle, e.g. 2026100512
#   VALID_TIME GEFS forecast valid time, e.g. 2026100512
#
# Slurm mapping:
#   Array task 1  -> mem01
#   Array task 2  -> mem02
#   ...
#   Array task 18 -> mem18
#
# REAL resources:
#   160 MPI tasks
#   10 minutes
# ============================================================================

#SBATCH -J wofs_bc_real
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH --nodes=1
#SBATCH --ntasks=160
#SBATCH --mem=300G
#SBATCH -t 00:10:00
#SBATCH --array=1-18
#SBATCH -o wofs_bc_real_%A_%a.out
#SBATCH -e wofs_bc_real_%A_%a.err

: "${HOMEwofs:?ERROR: HOMEwofs must be exported before submission}"
export HOMEwofs

# ---------------------------------------------------------------------------
# WRF module environment
# ---------------------------------------------------------------------------

# Load the centralized WRF build/runtime environment.
# Use the same dependency versions as the installed real.exe.

WRF_VERSION_FILE="${HOMEwofs}/versions/build.ver"

if [[ ! -r "${WRF_VERSION_FILE}" ]]; then
    echo "ERROR: WRF version file not found: ${WRF_VERSION_FILE}" >&2
    exit 1
fi

source "${HOMEwofs}/versions/bc_prep.ver" || exit 1
source "${WRF_VERSION_FILE}" || exit 1

export wofs_component=bc_prep

module use "${HOMEwofs}/modulefiles" || exit 1
module load ursa_wrf || exit 1

# Python runtime for YAML configuration.
module load "python/${python_ver}" || exit 1

export PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME

export WOFS_PYTHON="${WOFS_PYTHON:-$(command -v python3)}"

# Load BC_PREP configuration, preserving environment overrides.
source "${HOMEwofs}/ush/load_bc_prep_config.sh" || exit 1

# Validate configured MPI tasks against the Slurm allocation.
if [[ ! "${REAL_NTASKS:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Invalid REAL_NTASKS=${REAL_NTASKS:-undefined}" >&2
    exit 1
fi

if [[ "${SLURM_NTASKS:-}" != "${REAL_NTASKS}" ]]; then
    echo "ERROR: REAL MPI task mismatch" >&2
    echo "REAL_NTASKS=${REAL_NTASKS}" >&2
    echo "SLURM_NTASKS=${SLURM_NTASKS:-undefined}" >&2
    exit 1
fi

echo "[PASS] REAL MPI configuration: ${REAL_NTASKS} tasks"

# Verify the installed REAL executable and runtime libraries.
REAL_RUNTIME_EXE="${REAL_EXE:-${EXECwofs:-${HOMEwofs}/exec}/real.exe}"

if [[ ! -x "${REAL_RUNTIME_EXE}" ]]; then
    echo "ERROR: REAL executable not found: ${REAL_RUNTIME_EXE}" >&2
    exit 1
fi

if ! REAL_LDD="$(ldd "${REAL_RUNTIME_EXE}" 2>&1)"; then
    echo "ERROR: Unable to inspect REAL runtime libraries." >&2
    echo "${REAL_LDD}" >&2
    exit 1
fi

if grep -q "not found" <<< "${REAL_LDD}"; then
    echo "ERROR: Missing REAL runtime libraries:" >&2
    echo "${REAL_LDD}" >&2
    exit 1
fi

echo "[PASS] REAL runtime library check"


# ---------------------------------------------------------------------------
# WoFS settings
# ---------------------------------------------------------------------------

export model=wofs
# Cycle is derived after CDATE validation.

# Slurm array determines the ensemble member.
export MEMBER=$(printf "%02d" "${SLURM_ARRAY_TASK_ID}")

# ---------------------------------------------------------------------------
# Required inputs
# ---------------------------------------------------------------------------

if [[ -z "${CDATE:-}" ]]; then
    echo "ERROR: CDATE must be exported before submitting the REAL job."
    echo "Example: export CDATE=2026100512"
    exit 1
fi

if [[ -z "${VALID_TIME:-}" ]]; then
    echo "ERROR: VALID_TIME must be exported before submitting the REAL job."
    echo "Example: export VALID_TIME=2026100512"
    exit 1
fi

export cyc="${CDATE:8:2}"

echo "============================================================"
echo "WoFS v1 BC_PREP REAL"
echo "============================================================"
echo "HOMEwofs   = ${HOMEwofs}"
echo "CDATE      = ${CDATE}"
echo "VALID_TIME = ${VALID_TIME}"
echo "MEMBER     = ${MEMBER}"
echo "SLURM_JOB_ID       = ${SLURM_JOB_ID}"
echo "SLURM_ARRAY_TASK_ID= ${SLURM_ARRAY_TASK_ID}"
echo "REAL_NTASKS        = ${REAL_NTASKS}"
echo "SLURM_NTASKS       = ${SLURM_NTASKS}"
echo "============================================================"

module list

"${HOMEwofs}/jobs/JWOFS_BC_PREP_REAL"
