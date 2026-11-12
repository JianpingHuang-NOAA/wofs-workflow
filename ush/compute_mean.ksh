#!/bin/ksh
# ============================================================================
# compute_mean.ksh
#
# WoFS BC_PREP ensemble mean computation.
#
# Runtime modules must be initialized by the calling workflow wrapper.
# Preserve the inherited compiler, MPI, NetCDF, and Parallel-NetCDF
# runtime environment.
#
# Required environment:
#   EXEC_ROOT
#   WORK_ROOT
#   ENSEMBLE_SIZE
#   MEAN_PROC
#
# Output:
#   ${WORK_ROOT}/mean/wrfinput_d01
#   ${WORK_ROOT}/mean/stdout_mean
#   ${WORK_ROOT}/mean/mean_finished
# ============================================================================

set -eu

# ============================================================================
# Required environment
# ============================================================================

: "${EXEC_ROOT:?ERROR: EXEC_ROOT must be defined}"
: "${WORK_ROOT:?ERROR: WORK_ROOT must be defined}"
: "${ENSEMBLE_SIZE:?ERROR: ENSEMBLE_SIZE must be defined}"
: "${MEAN_PROC:?ERROR: MEAN_PROC must be defined}"

echo "=============================================================="
echo "WoFS BC_PREP ensemble mean computation"
echo "=============================================================="
echo "EXEC_ROOT     = ${EXEC_ROOT}"
echo "WORK_ROOT     = ${WORK_ROOT}"
echo "ENSEMBLE_SIZE = ${ENSEMBLE_SIZE}"
echo "MEAN_PROC     = ${MEAN_PROC}"
echo "=============================================================="

# ============================================================================
# Validate ensemble size and MPI tasks
# ============================================================================

case "${ENSEMBLE_SIZE}" in
    ''|*[!0-9]*)
        echo "ERROR: Invalid ENSEMBLE_SIZE=${ENSEMBLE_SIZE}" >&2
        exit 1
        ;;
esac

case "${MEAN_PROC}" in
    ''|*[!0-9]*)
        echo "ERROR: Invalid MEAN_PROC=${MEAN_PROC}" >&2
        exit 1
        ;;
esac

if (( ENSEMBLE_SIZE < 1 || MEAN_PROC < 1 )); then
    echo "ERROR: Invalid ensemble size or MPI task count" >&2
    exit 1
fi

if [[ -n "${SLURM_NTASKS:-}" ]]; then
    if (( SLURM_NTASKS != MEAN_PROC )); then
        echo "ERROR: MPI task mismatch" >&2
        echo "SLURM_NTASKS=${SLURM_NTASKS}" >&2
        echo "MEAN_PROC=${MEAN_PROC}" >&2
        exit 1
    fi
fi

# ============================================================================
# MEAN executable
# ============================================================================

AVERAGE_EXE="${EXEC_ROOT}/average_netcdf_files_parallel.x"

if [[ ! -x "${AVERAGE_EXE}" ]]; then
    echo "ERROR: MEAN executable not found:" >&2
    echo "       ${AVERAGE_EXE}" >&2
    exit 1
fi

echo "[PASS] MEAN executable: ${AVERAGE_EXE}"

# ============================================================================
# Verify inherited runtime libraries
# ============================================================================

echo
echo "===== MEAN runtime library check ====="

if ! LDD_OUTPUT="$(ldd -r "${AVERAGE_EXE}" 2>&1)"; then
    echo "ERROR: Unable to inspect MEAN runtime libraries" >&2
    echo "${LDD_OUTPUT}" >&2
    exit 1
fi

echo "${LDD_OUTPUT}"

if echo "${LDD_OUTPUT}" | grep -Ei 'not found|undefined symbol'; then
    echo "ERROR: MEAN runtime dependencies are unresolved" >&2
    exit 1
fi

echo "[PASS] All MEAN runtime libraries resolved"

# ============================================================================
# Validate all ensemble input files
# ============================================================================

echo
echo "===== Validate ensemble inputs ====="

mem=1

while (( mem <= ENSEMBLE_SIZE )); do

    ensmemid="$(printf '%02d' "${mem}")"

    filename="${WORK_ROOT}/mem${ensmemid}/wrfprd/wrfinput_d01"

    if [[ ! -r "${filename}" || ! -s "${filename}" ]]; then
        echo "ERROR: Missing or empty ensemble input:" >&2
        echo "       ${filename}" >&2
        exit 1
    fi

    echo "[PASS] ${filename}"

    (( mem += 1 ))

done

echo "[PASS] All ${ENSEMBLE_SIZE} ensemble inputs available"

# ============================================================================
# Set up MEAN working directory
# ============================================================================

workdir="${WORK_ROOT}/mean"

mkdir -p "${workdir}"

cd "${workdir}"

# Remove the previous completion marker.
# It must only exist after a successful MEAN computation.
rm -f mean_finished

echo
echo "MEAN working directory: ${workdir}"

# ============================================================================
# Link ensemble input files
#
# Preserve legacy naming convention:
#   wrfinput.mem001
#   wrfinput.mem002
#   ...
#   wrfinput.mem018
# ============================================================================

mem=1

while (( mem <= ENSEMBLE_SIZE )); do

    ensmemid="$(printf '%02d' "${mem}")"

    filename="${WORK_ROOT}/mem${ensmemid}/wrfprd/wrfinput_d01"

    ln -sfn "${filename}" "wrfinput.mem0${ensmemid}"

    (( mem += 1 ))

done

# ============================================================================
# Initialize the output file using ensemble member 01.
#
# The averaging executable updates this file.
# Preserve the legacy scientific processing method.
# ============================================================================

rm -f wrfinput_d01

cp "${WORK_ROOT}/mem01/wrfprd/wrfinput_d01" \
    ./wrfinput_d01

if [[ ! -s wrfinput_d01 ]]; then
    echo "ERROR: Failed to initialize MEAN output file" >&2
    exit 1
fi

# ============================================================================
# Compute ensemble mean
#
# Preserve legacy algorithm argument: 2
# ============================================================================

echo
echo "Computing ensemble mean at $(date -u)"

echo "MPI tasks: ${MEAN_PROC}"
echo "Executable: ${AVERAGE_EXE}"

if srun -n "${MEAN_PROC}" \
    "${AVERAGE_EXE}" \
    2 \
    "${workdir}" \
    wrfinput_d01 \
    wrfinput.mem \
    "${ENSEMBLE_SIZE}" \
    > stdout_mean 2>&1
then

    echo "[PASS] Ensemble averaging executable completed"

else

    rc=$?

    echo "ERROR: Ensemble averaging failed with rc=${rc}" >&2

    echo "===== Last 50 lines of stdout_mean =====" >&2

    tail -50 stdout_mean >&2 || true

    # Do not leave an incomplete output that could be mistaken
    # for a successfully computed ensemble mean.
    rm -f wrfinput_d01 mean_finished

    exit "${rc}"

fi

# ============================================================================
# Validate final output
# ============================================================================

if [[ ! -s "${workdir}/wrfinput_d01" ]]; then
    echo "ERROR: MEAN output is missing or empty:" >&2
    echo "       ${workdir}/wrfinput_d01" >&2
    exit 1
fi

# Create completion marker only after successful execution.
touch mean_finished

echo
echo "=============================================================="
echo "WoFS BC_PREP ensemble mean completed successfully"
echo "=============================================================="
echo "MEAN_FILE = ${workdir}/wrfinput_d01"
echo "MEAN_LOG  = ${workdir}/stdout_mean"
echo "FINISHED  = ${workdir}/mean_finished"
echo "END_TIME  = $(date -u)"
echo "=============================================================="

exit 0
