#!/bin/bash
#SBATCH --job-name=build_upp_ursa
#SBATCH --partition=u1-compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=build_upp_%j.out
#SBATCH --error=build_upp_%j.err

set -euo pipefail

# ============================================================
# 1. Resolve workflow repository
# ============================================================

if [[ -n "${HOMEwofs:-}" ]]; then
    HOMEwofs="$(cd "$HOMEwofs" && pwd -P)"
elif [[ -f "${SLURM_SUBMIT_DIR:-}/versions/build.ver" ]]; then
    HOMEwofs="$(cd "$SLURM_SUBMIT_DIR" && pwd -P)"
elif [[ -f "${SLURM_SUBMIT_DIR:-}/../versions/build.ver" ]]; then
    HOMEwofs="$(cd "$SLURM_SUBMIT_DIR/.." && pwd -P)"
else
    echo "[ERROR] Cannot determine HOMEwofs" >&2
    exit 1
fi

export HOMEwofs

UPP_SOURCE_DIR="${UPP_SOURCE_DIR:-$HOMEwofs/sorc/UPP}"

UPP_SOURCE_DIR="$(cd "$UPP_SOURCE_DIR" && pwd -P)"

BUILD_JOBS="${SLURM_CPUS_PER_TASK:-8}"

BUILD_ID="${SLURM_JOB_ID:-$(date -u +%Y%m%d_%H%M%S)}"

STAGING="$HOMEwofs/staging/UPP_build_${BUILD_ID}"

SOURCE="$STAGING/source"
BUILD="$STAGING/build"
INSTALL="$STAGING/install"

echo "===== WoFS UPP build ====="
echo "HOMEwofs=$HOMEwofs"
echo "UPP_SOURCE_DIR=$UPP_SOURCE_DIR"
echo "STAGING=$STAGING"
echo "BUILD_JOBS=$BUILD_JOBS"

# ============================================================
# 2. Validate source repository
# ============================================================

[[ -f "$UPP_SOURCE_DIR/CMakeLists.txt" ]]
[[ -f "$UPP_SOURCE_DIR/VERSION" ]]

UPP_COMMIT="$(git -C "$UPP_SOURCE_DIR" rev-parse HEAD)"

if [[ -n "$(git -C "$UPP_SOURCE_DIR" status --porcelain)" ]]; then
    echo "[ERROR] UPP source repository is not clean" >&2
    exit 1
fi

if [[ -n "${UPP_EXPECTED_COMMIT:-}" ]]; then
    if [[ "$UPP_COMMIT" != "$UPP_EXPECTED_COMMIT" ]]; then
        echo "[ERROR] Unexpected UPP source revision" >&2
        echo "Expected: $UPP_EXPECTED_COMMIT"
        echo "Actual:   $UPP_COMMIT"
        exit 1
    fi
fi

echo "UPP_COMMIT=$UPP_COMMIT"
echo "UPP_VERSION=$(cat "$UPP_SOURCE_DIR/VERSION")"

# Protect existing build directories.

if [[ -e "$STAGING" ]]; then
    echo "[ERROR] Build directory already exists: $STAGING"
    exit 1
fi

mkdir -p "$SOURCE" "$BUILD" "$INSTALL"

# ============================================================
# 3. Preserve build provenance
# ============================================================

printf '%s\n' "$UPP_COMMIT" \
    > "$STAGING/source_commit.txt"

git -C "$UPP_SOURCE_DIR" log -1 \
    > "$STAGING/source_revision.txt"

git -C "$HOMEwofs" rev-parse HEAD \
    > "$STAGING/workflow_commit.txt"

git -C "$HOMEwofs" status --short \
    > "$STAGING/workflow_status.txt"

cp -p "$HOMEwofs/versions/build.ver" "$STAGING/"
cp -p "$HOMEwofs/versions/run.ver" "$STAGING/"

cp -p "$HOMEwofs/modulefiles/ursa_upp.lua" "$STAGING/"
cp -p "$HOMEwofs/modulefiles/upp_common.lua" "$STAGING/"
cp -p "$HOMEwofs/modulefiles/ursa_upp_build.lua" "$STAGING/"

cp -p "$HOMEwofs/sorc/build_upp_ursa.sh" "$STAGING/"

# Build only committed source files.

git -C "$UPP_SOURCE_DIR" archive "$UPP_COMMIT" |
    tar -xf - -C "$SOURCE"

echo "[PASS] Clean source snapshot created"

# ============================================================
# 4. Load isolated UPP build environment
# ============================================================

source "$HOMEwofs/ush/load_upp_environment.sh"

source "$HOMEwofs/versions/build.ver"

module use "$HOMEwofs/modulefiles"

module load ursa_upp_build

module list > "$STAGING/modules.log" 2>&1

# Prevent inherited user compiler flags.

unset CFLAGS CXXFLAGS FFLAGS FCFLAGS CPPFLAGS LDFLAGS

for CMD in cmake mpiicx mpiicpx mpiifort
do
    command -v "$CMD" >/dev/null
    echo "[PASS] $CMD=$(command -v "$CMD")"
done

{
    cmake --version
    mpiicx --version
    mpiicpx --version
    mpiifort --version
} > "$STAGING/compiler_versions.txt" 2>&1

ACTUAL_CMAKE="$(cmake --version | awk 'NR==1 {print $3}')"

if [[ "$ACTUAL_CMAKE" != "$cmake_ver" ]]; then
    echo "[ERROR] Unexpected CMake version: $ACTUAL_CMAKE"
    exit 1
fi

echo "[PASS] Build environment loaded"

# ============================================================
# 5. Configure UPP
# ============================================================

echo "===== Configure UPP ====="

cmake \
    -S "$SOURCE" \
    -B "$BUILD" \
    -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$(command -v mpiicx)" \
    -DCMAKE_CXX_COMPILER="$(command -v mpiicpx)" \
    -DCMAKE_Fortran_COMPILER="$(command -v mpiifort)" \
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" \
    -DCMAKE_Fortran_FLAGS_RELEASE="-O3" \
    -DOPENMP=ON \
    -DBUILD_POSTEXEC=ON \
    -DBUILD_WITH_NEMSIO=ON \
    -DBUILD_WITH_WRFIO=ON \
    -DBUILD_WITH_GTG=OFF \
    -DBUILD_WITH_IFI=OFF \
    -DREQUIRE_IFI=OFF \
    -DENABLE_DOCS=OFF \
    -DBUILD_IFI_EXECUTABLES=OFF \
    2>&1 | tee "$STAGING/configure.log"

echo "[PASS] CMake configuration"

# ============================================================
# 6. Compile and install
# ============================================================

echo "===== Compile UPP ====="

cmake --build "$BUILD" \
    --parallel "$BUILD_JOBS" \
    2>&1 | tee "$STAGING/compile.log"

echo "[PASS] UPP compilation"

echo "===== Install UPP ====="

cmake --install "$BUILD" \
    2>&1 | tee "$STAGING/install.log"

UPP_EXE="$INSTALL/bin/upp.x"

if [[ ! -s "$UPP_EXE" || ! -x "$UPP_EXE" ]]; then
    echo "[ERROR] Missing executable: $UPP_EXE"
    exit 1
fi

echo "[PASS] UPP installation"

# ============================================================
# 7. Validate executable and record build information
# ============================================================

ldd -r "$UPP_EXE" \
    > "$STAGING/upp_ldd.txt" 2>&1

if grep -Ei 'not found|undefined symbol' \
    "$STAGING/upp_ldd.txt"
then
    echo "[ERROR] UPP library compatibility check failed"
    exit 1
fi

echo "[PASS] Dynamic library compatibility"

find "$BUILD" -name flags.make \
    -print -exec cat {} \; \
    > "$STAGING/compiler_flags_files.txt"

cp -p "$BUILD/CMakeCache.txt" "$STAGING/"

sha256sum "$UPP_EXE" \
    > "$STAGING/upp.sha256"

# ============================================================
# 8. Report successful build
# ============================================================

printf '%s\n' "$STAGING" \
    > "$HOMEwofs/staging/upp_build_${BUILD_ID}_path.txt"

echo
echo "========================================"
echo "[PASS] UPP build completed successfully"
echo "========================================"
echo "UPP_COMMIT=$UPP_COMMIT"
echo "UPP_EXE=$UPP_EXE"
echo "STAGING=$STAGING"

ls -lh "$UPP_EXE"

cat "$STAGING/upp.sha256"

echo
echo "Existing workflow executable was NOT modified."
