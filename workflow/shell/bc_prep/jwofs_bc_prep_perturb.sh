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
: "${TEST_ROOT:?ERROR: TEST_ROOT must be defined}"
: "${START_TIME:?ERROR: START_TIME must be defined}"
: "${FCST_LEAD_TIME:?ERROR: FCST_LEAD_TIME must be defined}"
: "${WOF_CYCLE_TIME:?ERROR: WOF_CYCLE_TIME must be defined}"
: "${COMROOT:?ERROR: COMROOT must be defined}"

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

# Default outputs to isolated test locations.
export DATAHOME="${DATAHOME:-${TEST_ROOT}/pert_hrrr/${START_TIME}/postprd_mem00${MEMBER}}"
export DATAHOME_GEFS="${DATAHOME_GEFS:?ERROR: DATAHOME_GEFS must be defined}"

# Load legacy scientific dependencies through the utility.
# Do not source the legacy repository's WRF module list here.

echo "============================================================"
echo "WoFS v1.0 BC_PREP PERTURB Slurm job"
echo "============================================================"
echo "HOMEwofs         = ${HOMEwofs}"
echo "START_TIME       = ${START_TIME}"
echo "FCST_LEAD_TIME   = ${FCST_LEAD_TIME}"
echo "WOF_CYCLE_TIME   = ${WOF_CYCLE_TIME}"
echo "MEMBER           = ${MEMBER}"
echo "DATAHOME         = ${DATAHOME}"
echo "DATAHOME_GEFS    = ${DATAHOME_GEFS}"
echo "COMROOT          = ${COMROOT}"
echo "TEST_ROOT        = ${TEST_ROOT}"
echo "SLURM_JOB_ID     = ${SLURM_JOB_ID:-not_set}"
echo "============================================================"

"${HOMEwofs}/jobs/JWOFS_BC_PREP_PERTURB"
