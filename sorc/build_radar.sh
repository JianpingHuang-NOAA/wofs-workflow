#!/bin/bash
#=======================================================================
# WoFS v1.0 radar Fortran extension build on NOAA Ursa.
#
# Compile:
#   cressman.f90
#   sparsey.f90
#
# Python: 3.11
# Backend: NumPy F2PY / Meson
# Compiler: GNU Fortran
#
# Usage:
#   ./sorc/build_radar.sh
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

RADAR_SOURCE="$ROOT/sorc/RADAR"
UTILS_SOURCE="$RADAR_SOURCE/wofs_radar/utils"

PY="$ROOT/python_env/bin/python3"

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

#-----------------------------------------------------------------------
# 1. Initialize build environment
#-----------------------------------------------------------------------

source "$ROOT/versions/bc_prep.ver"

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME

export PATH="$ROOT/python_env/bin:$PATH"

export CC=/usr/bin/gcc
export FC=/usr/bin/gfortran

unset F77 F90 CFLAGS FFLAGS FCFLAGS LDFLAGS

[[ -x "$PY" ]] || die "Missing WoFS Python: $PY"
[[ -x "$CC" ]] || die "Missing GCC compiler"
[[ -x "$FC" ]] || die "Missing GNU Fortran compiler"

command -v meson >/dev/null || die "Missing Meson"
command -v ninja >/dev/null || die "Missing Ninja"

#-----------------------------------------------------------------------
# 2. Validate source files
#-----------------------------------------------------------------------

for name in cressman sparsey; do
    [[ -s "$UTILS_SOURCE/${name}.f90" ]] ||
        die "Missing source: ${name}.f90"
done

RADAR_COMMIT="$(git -C "$RADAR_SOURCE" rev-parse HEAD)"

#-----------------------------------------------------------------------
# 3. Create independent build directory
#-----------------------------------------------------------------------

mkdir -p "$ROOT/staging"

BUILD_ROOT="$(mktemp -d "$ROOT/staging/RADAR_build_XXXXXXXX")"

mkdir -p "$BUILD_ROOT/logs"
mkdir -p "$BUILD_ROOT/extensions"

printf '%s\n' "$BUILD_ROOT" \
    > "$ROOT/staging/latest_radar_build_path.txt"

printf '%s\n' "$RADAR_COMMIT" \
    > "$BUILD_ROOT/radar_commit.txt"

git -C "$RADAR_SOURCE" status --short \
    > "$BUILD_ROOT/radar_source_status.txt"

echo "=================================================="
echo "WoFS radar Fortran extension build"
echo "=================================================="
echo "Repository : $ROOT"
echo "RADAR      : $RADAR_SOURCE"
echo "Commit     : $RADAR_COMMIT"
echo "Python     : $PY"
echo "Compiler   : $FC"
echo "Build root : $BUILD_ROOT"
echo "=================================================="

#-----------------------------------------------------------------------
# 4. Record compiler and Python versions
#-----------------------------------------------------------------------

{
    "$PY" --version

    "$PY" -c \
        'import numpy; print("NumPy:", numpy.__version__)'

    "$CC" --version
    "$FC" --version

    meson --version
    ninja --version

} | tee "$BUILD_ROOT/build_versions.txt"

module list > "$BUILD_ROOT/modules.txt" 2>&1

EXT_SUFFIX="$(
    "$PY" -c \
        'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))'
)"

[[ -n "$EXT_SUFFIX" ]] || die "Missing Python extension suffix"

echo "Python extension suffix: $EXT_SUFFIX"

#-----------------------------------------------------------------------
# 5. Compile each Fortran extension
#-----------------------------------------------------------------------

for name in cressman sparsey; do

    echo
    echo "===== Compile ${name}.f90 ====="

    WORK="$BUILD_ROOT/$name"

    mkdir -p "$WORK"

    cp -p "$UTILS_SOURCE/${name}.f90" "$WORK/"

    (
        cd "$WORK"

        "$PY" -m numpy.f2py \
            -c \
            --backend meson \
            -m "$name" \
            "${name}.f90"

    ) 2>&1 | tee "$BUILD_ROOT/logs/${name}.log"

    LIB="$WORK/${name}${EXT_SUFFIX}"

    [[ -s "$LIB" ]] ||
        die "Compilation did not produce $LIB"

    install -m 755 \
        "$LIB" \
        "$BUILD_ROOT/extensions/${name}${EXT_SUFFIX}"

    echo "[PASS] Compiled $name"

    ls -lh "$LIB"

done

#-----------------------------------------------------------------------
# 6. Validate compiled libraries
#-----------------------------------------------------------------------

cd "$BUILD_ROOT/extensions"

for name in cressman sparsey; do

    LIB="${name}${EXT_SUFFIX}"

    echo
    echo "===== Native dependencies: $LIB ====="

    ldd "$LIB" | tee "$BUILD_ROOT/logs/${name}_ldd.log"

    if grep -q 'not found' "$BUILD_ROOT/logs/${name}_ldd.log"; then
        die "Missing native library for $name"
    fi

done

echo
echo "===== Python extension import validation ====="

"$PY" - <<'PYTHON'
import cressman
import sparsey

print("[PASS] cressman:", cressman.__file__)
print("[PASS] sparsey :", sparsey.__file__)

assert callable(sparsey.sparse_decompress)

print("[PASS] sparse_decompress is available")

print("Cressman exported functions:")

for name in dir(cressman):
    if not name.startswith("_"):
        print("  ", name)

PYTHON

sha256sum ./*.so > "$BUILD_ROOT/extensions.sha256"

touch "$BUILD_ROOT/BUILD_SUCCESS"

echo
echo "=================================================="
echo "[PASS] WoFS radar Fortran compilation completed"
echo "Build root: $BUILD_ROOT"
echo "Extensions: $BUILD_ROOT/extensions"
echo "=================================================="

ls -lh "$BUILD_ROOT/extensions"
