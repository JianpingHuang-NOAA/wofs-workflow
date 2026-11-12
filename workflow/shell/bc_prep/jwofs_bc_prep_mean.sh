#!/bin/bash
# ============================================================================
# jwofs_bc_prep_mean.sh
# WoFS v1.0 BC_PREP MEAN workflow shell wrapper
#
# Purpose:
#   Compute the ensemble mean WRF input for one GEFS forecast valid time.
#
# Required environment:
#   HOMEwofs    WoFS workflow repository
#   DATAROOT    Runtime data directory
#   PDY         WoFS cycle date
#   cyc         WoFS cycle hour
#
# Optional environment:
#   CDATE
#   CYCLE_TIME
#   BC_DATA
#   DATAHOME_GEFS
#   ENS_SIZE
#   ENSEMBLE_SIZE
#   MEAN_PROC
#   WOFS_PYTHON
#
# Resources:
#   40 MPI tasks
# ============================================================================

#SBATCH --job-name=wofs_bc_mean
#SBATCH --partition=u1-compute
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --mem=20G
#SBATCH --time=00:10:00

set -euo pipefail

# ============================================================================
# WoFS installation
# ============================================================================

: "${HOMEwofs:?ERROR: HOMEwofs must be exported before submission}"

export HOMEwofs

for file in \
    "${HOMEwofs}/versions/run.ver" \
    "${HOMEwofs}/versions/bc_prep.ver" \
    "${HOMEwofs}/versions/build.ver"
do
    if [[ ! -r "${file}" ]]; then
        echo "ERROR: Cannot read ${file}" >&2
        exit 1
    fi
done

# ============================================================================
# Centralized runtime environment
# ============================================================================

source "${HOMEwofs}/versions/run.ver"
source "${HOMEwofs}/versions/bc_prep.ver"
source "${HOMEwofs}/versions/build.ver"

export wofs_component=bc_prep

module use "${HOMEwofs}/modulefiles"

# Use the same compiler, MPI, NetCDF, and Parallel-NetCDF
# environment used to build average_netcdf_files_parallel.x.
module load ursa_wrf

# Python runtime for YAML configuration.
module load "python/${python_ver}"

export WOFS_PYTHON="${WOFS_PYTHON:-$(command -v python3 || true)}"

# ============================================================================
# BC_PREP configuration
# ============================================================================

source "${HOMEwofs}/ush/load_bc_prep_config.sh"

# ============================================================================
# Cycle configuration
# ============================================================================

export PDY="${PDY:?ERROR: PDY must be defined}"
export cyc="${cyc:?ERROR: cyc must be defined}"

export CDATE="${CDATE:-${PDY}${cyc}}"

# CYCLE_TIME represents the GEFS forecast valid time.
# Preserve an explicitly supplied value.
export CYCLE_TIME="${CYCLE_TIME:-${CDATE}}"

if [[ ! "${CDATE}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: CDATE must be YYYYMMDDHH" >&2
    exit 1
fi

if [[ ! "${CYCLE_TIME}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: CYCLE_TIME must be YYYYMMDDHH" >&2
    exit 1
fi

# ============================================================================
# Ensemble configuration
# ============================================================================

export ENS_SIZE="${ENS_SIZE:-18}"
export ENSEMBLE_SIZE="${ENSEMBLE_SIZE:-${ENS_SIZE}}"
export MEAN_PROC="${MEAN_PROC:-40}"

if [[ ! "${ENS_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Invalid ENS_SIZE=${ENS_SIZE}" >&2
    exit 1
fi

if [[ "${ENS_SIZE}" != "${ENSEMBLE_SIZE}" ]]; then
    echo "ERROR: Ensemble size mismatch" >&2
    echo "ENS_SIZE=${ENS_SIZE}" >&2
    echo "ENSEMBLE_SIZE=${ENSEMBLE_SIZE}" >&2
    exit 1
fi

if [[ "${SLURM_NTASKS:-}" != "${MEAN_PROC}" ]]; then
    echo "ERROR: MEAN MPI task mismatch" >&2
    echo "MEAN_PROC=${MEAN_PROC}" >&2
    echo "SLURM_NTASKS=${SLURM_NTASKS:-undefined}" >&2
    exit 1
fi

# ============================================================================
# BC data locations
# ============================================================================

export DATAHOME_GEFS="${DATAHOME_GEFS:-${BC_DATA}/gefs}"

export WORK_ROOT="${WORK_ROOT:-${DATAHOME_GEFS}/${CYCLE_TIME}}"

export EXEC_ROOT="${EXEC_ROOT:-${EXECSWOfS:-${EXECwofs}}}"

export BC_PREP_STAGE=MEAN

# ============================================================================
# Verify MEAN executable
# ============================================================================

MEAN_RUNTIME_EXE="${EXEC_ROOT}/average_netcdf_files_parallel.x"

if [[ ! -x "${MEAN_RUNTIME_EXE}" ]]; then
    echo "ERROR: MEAN executable not found:" >&2
    echo "       ${MEAN_RUNTIME_EXE}" >&2
    exit 1
fi

# ============================================================================
# Verify runtime libraries
# ============================================================================

echo "===== MEAN runtime library check ====="

if ! MEAN_LDD="$(ldd -r "${MEAN_RUNTIME_EXE}" 2>&1)"; then
    echo "ERROR: Unable to inspect MEAN runtime libraries" >&2
    echo "${MEAN_LDD}" >&2
    exit 1
fi

echo "${MEAN_LDD}"

if grep -Ei 'not found|undefined symbol' <<< "${MEAN_LDD}"; then
    echo "ERROR: MEAN runtime dependency check failed" >&2
    exit 1
fi

echo "[PASS] All MEAN runtime libraries resolved"

# ============================================================================
# Verify all ensemble REAL outputs
# ============================================================================

echo
echo "===== Ensemble input validation ====="

MISSING=0

for (( member=1; member<=ENS_SIZE; member++ )); do

    MEMBER02="$(printf '%02d' "${member}")"

    INPUT_FILE="${WORK_ROOT}/mem${MEMBER02}/wrfprd/wrfinput_d01"

    if [[ ! -s "${INPUT_FILE}" ]]; then
        echo "[FAIL] ${INPUT_FILE}" >&2
        MISSING=$((MISSING + 1))
    else
        echo "[PASS] ${INPUT_FILE}"
    fi

done

if (( MISSING > 0 )); then
    echo "ERROR: ${MISSING} ensemble input files are missing" >&2
    exit 1
fi

echo "[PASS] All ${ENS_SIZE} ensemble inputs available"

# ============================================================================
# Configuration summary
# ============================================================================

echo
echo "=============================================================="
echo " WoFS BC_PREP MEAN"
echo "=============================================================="
echo "HOMEwofs           = ${HOMEwofs}"
echo "BC_PREP_CONFIG     = ${BC_PREP_CONFIG}"
echo "WOFS_PYTHON        = ${WOFS_PYTHON}"
echo "DATAROOT           = ${DATAROOT}"
echo "BC_DATA            = ${BC_DATA}"
echo "PDY                = ${PDY}"
echo "cyc                = ${cyc}"
echo "CDATE              = ${CDATE}"
echo "CYCLE_TIME         = ${CYCLE_TIME}"
echo "ENS_SIZE           = ${ENS_SIZE}"
echo "ENSEMBLE_SIZE      = ${ENSEMBLE_SIZE}"
echo "MEAN_PROC          = ${MEAN_PROC}"
echo "DATAHOME_GEFS      = ${DATAHOME_GEFS}"
echo "WORK_ROOT          = ${WORK_ROOT}"
echo "EXEC_ROOT          = ${EXEC_ROOT}"
echo "MEAN_RUNTIME_EXE   = ${MEAN_RUNTIME_EXE}"
echo "SLURM_JOB_ID       = ${SLURM_JOB_ID:-}"
echo "SLURM_NTASKS       = ${SLURM_NTASKS}"
echo "=============================================================="

module list

# ============================================================================
# Execute J-job
# ============================================================================

cd "${HOMEwofs}"

"${HOMEwofs}/jobs/JWOFS_BC_PREP_MEAN"

echo
echo "WoFS BC_PREP MEAN completed successfully"
echo "CYCLE_TIME=${CYCLE_TIME}"

date -u
