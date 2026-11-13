#!/bin/bash
#SBATCH -J wofs_bc_perturb
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH -N 1
#SBATCH -n 12
#SBATCH --mem=22G
#SBATCH -t 00:30:00
#SBATCH -o wofs_bc_perturb_%j.out
#SBATCH -e wofs_bc_perturb_%j.err

# ============================================================================
# WoFS v1.0 BC_PREP PERTURB Slurm wrapper
#
# One Slurm job processes one HRRR forecast hour and one GEFS member.
# For ensemble execution, submit a Slurm array explicitly.
# ============================================================================

set -euo pipefail

: "${HOMEwofs:?ERROR: HOMEwofs must be defined}"
: "${START_TIME:?ERROR: START_TIME must be defined}"
: "${FCST_LEAD_TIME:?ERROR: FCST_LEAD_TIME must be defined}"
: "${WOF_CYCLE_TIME:?ERROR: WOF_CYCLE_TIME must be defined}"

# For Slurm arrays, the array task ID determines the member.
# For single-member tests, use the exported MEMBER.
if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    MEMBER="${SLURM_ARRAY_TASK_ID}"
else
    : "${MEMBER:?ERROR: MEMBER must be defined}"
fi

[[ "${MEMBER}" =~ ^[0-9]{1,2}$ ]] || {
    echo "ERROR: Invalid MEMBER"
    exit 1
}

MEMBER=$(printf "%02d" "$((10#${MEMBER}))")
export MEMBER

# Preserve independent HRRR and WoFS cycles.
export CYCLE_TIME="${START_TIME}"
export BC_PREP_STAGE=PERTURB
export model=wofs

# Load the standardized BC_PREP runtime environment.
source "${HOMEwofs}/versions/bc_prep.ver"

module purge
module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

# Isolate Python from personal and inherited package settings.
export PYTHONNOUSERSITE=1
unset PYTHONPATH
unset PYTHONHOME

# Use the explicitly selected WoFS Python virtual environment.
: "${WOFS_PYTHON:?ERROR: WOFS_PYTHON must be defined}"
export WOFS_PYTHON

echo "WOFS_PYTHON = ${WOFS_PYTHON}"
echo "PYTHONNOUSERSITE = ${PYTHONNOUSERSITE}"

# Validate the complete BC_PREP Python runtime before computation.
if ! bash "${HOMEwofs}/tests/check_bc_prep_python.sh" \
    "${WOFS_PYTHON}"
then
    echo "ERROR: Invalid BC_PREP Python runtime" >&2
    exit 1
fi

echo "[PASS] PERTURB Python runtime validated"

# Load standardized BC_PREP configuration.
# Existing nonempty environment values take precedence.
source "${HOMEwofs}/ush/load_bc_prep_config.sh"

# Preserve UTC cycle calculations.
export TZ=UTC

module list

echo "============================================================"
echo "WoFS v1.0 BC_PREP PERTURB Slurm job"
echo "============================================================"
echo "HOMEwofs         = ${HOMEwofs}"
echo "START_TIME       = ${START_TIME}"
echo "FCST_LEAD_TIME   = ${FCST_LEAD_TIME}"
echo "WOF_CYCLE_TIME   = ${WOF_CYCLE_TIME}"
echo "MEMBER           = ${MEMBER}"
echo "BC_PREP_MODE     = ${BC_PREP_MODE}"
echo "DATAROOT         = ${DATAROOT}"
echo "DATAHOME         = ${DATAHOME:-resolved_by_J_job}"
echo "DATAHOME_GEFS    = ${DATAHOME_GEFS}"
echo "COMROOT          = ${COMROOT:-resolved_by_J_job}"
echo "TEST_ROOT        = ${TEST_ROOT:-not_set}"
echo "SLURM_JOB_ID     = ${SLURM_JOB_ID:-not_set}"
echo "============================================================"

"${HOMEwofs}/jobs/JWOFS_BC_PREP_PERTURB"
