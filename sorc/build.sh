#!/usr/bin/env bash
#
# Centralized WoFS v1.0 build controller for NOAA Ursa.
#
# Usage:
#   ./sorc/build.sh
#   ./sorc/build.sh --all
#   ./sorc/build.sh --checkout
#   ./sorc/build.sh --status
#   ./sorc/build.sh --help
#
# Optional:
#   BUILD_ACCOUNT=wofs ./sorc/build.sh --all
#

set -euo pipefail

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ============================================================
# 1. Resolve repository
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

export HOMEwofs="$(cd "$SCRIPT_DIR/.." && pwd -P)"

cd "$HOMEwofs"

export EXECwofs="$HOMEwofs/exec"

CHECKOUT="$HOMEwofs/manage_externals/checkout_externals"

usage() {
    cat <<EOF
WoFS v1.0 centralized build utility

Usage:
    $0 --all       Build and install all executables
    $0 --checkout  Download external source repositories
    $0 --status    Report external and executable status
    $0 --help      Display this message

Default: --all

Optional environment:
    BUILD_ACCOUNT  Override Slurm account
EOF
}

# ============================================================
# 2. Command-line options
# ============================================================

case "${1:---all}" in

    --help|-h)
        usage
        exit 0
        ;;

    --checkout)
        exec "$CHECKOUT"
        ;;

    --status)
        "$CHECKOUT" --status || true

        echo
        echo "===== Installed executables ====="

        for exe in \
            wrf.exe real.exe ndown.exe tc.exe \
            geogrid.exe ungrib.exe metgrid.exe \
            upp.x average_netcdf_files_parallel.x
        do
            if [[ -s "$EXECwofs/$exe" && -x "$EXECwofs/$exe" ]]; then
                ls -lh "$EXECwofs/$exe"
            else
                echo "[MISSING] $exe"
            fi
        done

        exit 0
        ;;

    --all)
        ;;

    *)
        usage
        die "Unknown option: $1"
        ;;
esac

# ============================================================
# 3. Validate external source repositories
# ============================================================

echo "===== WoFS source validation ====="

"$CHECKOUT" --status

source "$HOMEwofs/versions/build.ver"

export WRF_SOURCE_DIR="$HOMEwofs/sorc/WRF"
export WPS_SOURCE_DIR="$HOMEwofs/sorc/WPS"
export UPP_SOURCE_DIR="$HOMEwofs/sorc/UPP"

export WRF_MODULEFILES_DIR="$HOMEwofs/modulefiles"

export UPP_EXPECTED_COMMIT="$(
    git -C "$UPP_SOURCE_DIR" rev-parse HEAD
)"

# ============================================================
# 4. Create unique build directory
# ============================================================

mkdir -p "$HOMEwofs/staging" "$EXECwofs"

export BUILD_ROOT="$(
    mktemp -d "$HOMEwofs/staging/build_all_XXXXXXXX"
)"

export WRF_BUILD="$BUILD_ROOT/WRF"
export WRF_BUILD_DIR="$WRF_BUILD"

export WPS_BUILD_DIR="$BUILD_ROOT/WPS"

export UTILS_EXEC_DIR="$BUILD_ROOT/utils_exec"

mkdir -p "$BUILD_ROOT/logs"
mkdir -p "$UTILS_EXEC_DIR"

cp -p "$HOMEwofs/Externals.cfg" "$BUILD_ROOT/"
cp -p "$HOMEwofs/versions/build.ver" "$BUILD_ROOT/"

git rev-parse HEAD > "$BUILD_ROOT/workflow_commit.txt"

git status --short > "$BUILD_ROOT/workflow_status.txt"

echo "=========================================="
echo "WoFS v1.0 centralized build"
echo "=========================================="
echo "HOMEwofs:  $HOMEwofs"
echo "Branch:    $(git branch --show-current)"
echo "Build:     $BUILD_ROOT"
echo "WRF:       $WRF_BUILD_DIR"
echo "WPS:       $WPS_BUILD_DIR"
echo "=========================================="

# ============================================================
# 5. Slurm submission helper
# ============================================================

ACCOUNT_ARGS=()

if [[ -n "${BUILD_ACCOUNT:-}" ]]; then
    ACCOUNT_ARGS=(--account="$BUILD_ACCOUNT")
fi

submit_job() {

    local result

    result="$(
        sbatch \
            --parsable \
            --export=ALL \
            --kill-on-invalid-dep=yes \
            "${ACCOUNT_ARGS[@]}" \
            "$@"
    )"

    result="${result%%;*}"

    [[ "$result" =~ ^[0-9]+$ ]] ||
        die "Invalid Slurm job ID: $result"

    printf '%s\n' "$result"
}

# ============================================================
# 6. Submit WRF compilation
# ============================================================

WRF_JOB="$(
    submit_job \
        --output="$BUILD_ROOT/logs/wrf_%j.out" \
        --error="$BUILD_ROOT/logs/wrf_%j.err" \
        "$WRF_SOURCE_DIR/build_wrf_ursa.sh"
)"

echo "WRF_JOB=$WRF_JOB" | tee -a "$BUILD_ROOT/jobs.txt"

# ============================================================
# 7. Submit WPS compilation
# ============================================================

WPS_JOB="$(
    submit_job \
        --dependency="afterok:$WRF_JOB" \
        --output="$BUILD_ROOT/logs/wps_%j.out" \
        --error="$BUILD_ROOT/logs/wps_%j.err" \
        "$WPS_SOURCE_DIR/build_wps_ursa.sh"
)"

echo "WPS_JOB=$WPS_JOB" | tee -a "$BUILD_ROOT/jobs.txt"

# ============================================================
# 8. Submit UPP compilation
# ============================================================

UPP_JOB="$(
    submit_job \
        --output="$BUILD_ROOT/logs/upp_%j.out" \
        --error="$BUILD_ROOT/logs/upp_%j.err" \
        "$HOMEwofs/sorc/build_upp_ursa.sh"
)"

echo "UPP_JOB=$UPP_JOB" | tee -a "$BUILD_ROOT/jobs.txt"

export UPP_BUILD_DIR="$HOMEwofs/staging/UPP_build_${UPP_JOB}"

# ============================================================
# 9. Prepare internal utility compilation job
# ============================================================

cat > "$BUILD_ROOT/build_utils.sh" <<'UTILS'
#!/usr/bin/env bash
#SBATCH --job-name=wofs_build_utils
#SBATCH --partition=u1-compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:30:00

set -euo pipefail

source "$HOMEwofs/versions/build.ver"

module purge
module use "$HOMEwofs/modulefiles"
module load ursa_wrf

# Compile a clean snapshot of the internal utility.

UTIL_SOURCE="$BUILD_ROOT/utils_source"

mkdir -p "$UTIL_SOURCE"

REV="$(cat "$BUILD_ROOT/workflow_commit.txt")"

git -C "$HOMEwofs" archive "$REV" \
    sorc/average_netcdf_files_parallel |
    tar -xf - -C "$UTIL_SOURCE"

cd "$UTIL_SOURCE/sorc/average_netcdf_files_parallel"

make clean

make EXEC_DIR="$UTILS_EXEC_DIR"

EXE="$UTILS_EXEC_DIR/average_netcdf_files_parallel.x"

[[ -s "$EXE" && -x "$EXE" ]]

ls -lh "$EXE"

sha256sum "$EXE"

echo "[PASS] Ensemble mean utility compilation"
UTILS

chmod +x "$BUILD_ROOT/build_utils.sh"

UTILS_JOB="$(
    submit_job \
        --output="$BUILD_ROOT/logs/utils_%j.out" \
        --error="$BUILD_ROOT/logs/utils_%j.err" \
        "$BUILD_ROOT/build_utils.sh"
)"

echo "UTILS_JOB=$UTILS_JOB" | tee -a "$BUILD_ROOT/jobs.txt"

# ============================================================
# 10. Prepare final installation job
# ============================================================

cat > "$BUILD_ROOT/install_all.sh" <<'INSTALL'
#!/usr/bin/env bash
#SBATCH --job-name=wofs_install_all
#SBATCH --partition=u1-compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:15:00

set -euo pipefail

FINAL_EXEC="$HOMEwofs/exec"

STAGED_EXEC="$BUILD_ROOT/install_exec"

BACKUP="$BUILD_ROOT/exec_backup"

mkdir -p "$STAGED_EXEC" "$BACKUP" "$FINAL_EXEC"

# Install WRF/WPS into staging first.

EXECwofs="$STAGED_EXEC" \
BACKUP_DIR="$BUILD_ROOT/wrf_wps_install_backup" \
    bash "$HOMEwofs/sorc/install_wrf_wps.sh"

# Stage UPP and internal averaging utility.

install -m 755 \
    "$UPP_BUILD_DIR/install/bin/upp.x" \
    "$STAGED_EXEC/upp.x"

install -m 755 \
    "$UTILS_EXEC_DIR/average_netcdf_files_parallel.x" \
    "$STAGED_EXEC/average_netcdf_files_parallel.x"

EXES=(
    wrf.exe
    real.exe
    ndown.exe
    tc.exe
    geogrid.exe
    ungrib.exe
    metgrid.exe
    upp.x
    average_netcdf_files_parallel.x
)

# Validate every executable before changing exec/.

for exe in "${EXES[@]}"; do

    [[ -s "$STAGED_EXEC/$exe" ]]
    [[ -x "$STAGED_EXEC/$exe" ]]
    [[ ! -L "$STAGED_EXEC/$exe" ]]

    echo "[PASS] Staged $exe"

done

# Prepare installation files on the destination filesystem.

TEMP_DIR="$(mktemp -d "$FINAL_EXEC/.build_install.XXXXXXXX")"

trap 'rm -rf -- "$TEMP_DIR"' EXIT

for exe in "${EXES[@]}"; do

    install -m 755 \
        "$STAGED_EXEC/$exe" \
        "$TEMP_DIR/$exe"

    cmp -s "$STAGED_EXEC/$exe" "$TEMP_DIR/$exe"

done

# Back up existing executables and symbolic links.

for exe in "${EXES[@]}"; do

    dst="$FINAL_EXEC/$exe"

    if [[ -e "$dst" || -L "$dst" ]]; then

        cp -a -- "$dst" "$BACKUP/$exe"

    fi

done

# Replace existing executable links safely.

for exe in "${EXES[@]}"; do

    mv -fT -- "$TEMP_DIR/$exe" "$FINAL_EXEC/$exe"

    echo "[INSTALL] $exe"

done

# Final verification.

cd "$FINAL_EXEC"

for exe in "${EXES[@]}"; do

    [[ -s "$exe" && -x "$exe" && ! -L "$exe" ]]

    cmp -s "$exe" "$STAGED_EXEC/$exe"

    ls -lh "$exe"

done

sha256sum "${EXES[@]}" > "$BUILD_ROOT/executables.sha256"

touch "$BUILD_ROOT/BUILD_SUCCESS"

echo "=========================================="
echo "[PASS] WoFS build completed successfully"
echo "Executables: $FINAL_EXEC"
echo "Build root:  $BUILD_ROOT"
echo "Backup:      $BACKUP"
echo "=========================================="
INSTALL

chmod +x "$BUILD_ROOT/install_all.sh"

# ============================================================
# 11. Submit final installation
# ============================================================

INSTALL_JOB="$(
    submit_job \
        --dependency="afterok:${WPS_JOB}:${UPP_JOB}:${UTILS_JOB}" \
        --output="$BUILD_ROOT/logs/install_%j.out" \
        --error="$BUILD_ROOT/logs/install_%j.err" \
        "$BUILD_ROOT/install_all.sh"
)"

echo "INSTALL_JOB=$INSTALL_JOB" | tee -a "$BUILD_ROOT/jobs.txt"

# ============================================================
# 12. Record build information
# ============================================================

printf '%s\n' "$BUILD_ROOT" \
    > "$HOMEwofs/staging/latest_build_path.txt"

echo
echo "=========================================="
echo "WoFS build jobs submitted"
echo "=========================================="

cat "$BUILD_ROOT/jobs.txt"

echo
echo "Build root: $BUILD_ROOT"

echo
echo "Monitor with:"
echo "squeue -j $WRF_JOB,$WPS_JOB,$UPP_JOB,$UTILS_JOB,$INSTALL_JOB"

echo
echo "Build submission completed."
echo "Compilation and installation are still pending."
