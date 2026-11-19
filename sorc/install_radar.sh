#!/bin/bash
#=======================================================================
# Install WoFS radar Python package and Fortran extensions.
#
# Platform: NOAA Ursa
#
# Usage:
#   ./sorc/install_radar.sh
#
# Python-only source changes do not require Fortran recompilation.
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

RADAR_SOURCE="$ROOT/sorc/RADAR"

PY="$ROOT/python_env/bin/python3"

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

#-----------------------------------------------------------------------
# 1. Initialize Python environment
#-----------------------------------------------------------------------

source "$ROOT/versions/bc_prep.ver"

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME

export PATH="$ROOT/python_env/bin:$PATH"

[[ -x "$PY" ]] ||
    die "Missing WoFS Python interpreter"

[[ -d "$RADAR_SOURCE/wofs_radar" ]] ||
    die "Missing RADAR source package"

# Require committed source files.

[[ -z "$(git -C "$RADAR_SOURCE" status --porcelain)" ]] ||
    die "RADAR source contains uncommitted changes"

#-----------------------------------------------------------------------
# 2. Locate successful radar build
#-----------------------------------------------------------------------

BUILD_POINTER="$ROOT/staging/latest_radar_build_path.txt"

[[ -s "$BUILD_POINTER" ]] ||
    die "Missing radar build pointer"

BUILD_ROOT="$(cat "$BUILD_POINTER")"

[[ -f "$BUILD_ROOT/BUILD_SUCCESS" ]] ||
    die "Radar build has not completed successfully"

RADAR_COMMIT="$(git -C "$RADAR_SOURCE" rev-parse HEAD)"

BUILD_COMMIT="$(cat "$BUILD_ROOT/radar_commit.txt")"

echo "===== RADAR revisions ====="

echo "Python source revision : $RADAR_COMMIT"

echo "Fortran build revision : $BUILD_COMMIT"

#-----------------------------------------------------------------------
# 3. Validate Fortran build compatibility
#-----------------------------------------------------------------------

EXT_SUFFIX="$(
    "$PY" -c \
        'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))'
)"

for name in cressman sparsey; do

    cmp \
        "$RADAR_SOURCE/wofs_radar/utils/${name}.f90" \
        "$BUILD_ROOT/$name/${name}.f90" ||
        die "Fortran source changed: ${name}.f90"

    [[ -s "$BUILD_ROOT/extensions/${name}${EXT_SUFFIX}" ]] ||
        die "Missing compiled extension: $name"

    echo "[PASS] Compatible Fortran extension: $name"

done

(
    cd "$BUILD_ROOT/extensions"

    sha256sum -c "$BUILD_ROOT/extensions.sha256"
)

#-----------------------------------------------------------------------
# 4. Determine Python installation directory
#-----------------------------------------------------------------------

SITE_PACKAGES="$(
    "$PY" -c \
        'import sysconfig; print(sysconfig.get_path("purelib"))'
)"

case "$SITE_PACKAGES" in

    "$ROOT/python_env/"*) ;;

    *) die "Installation directory outside WoFS Python environment" ;;

esac

DEST="$SITE_PACKAGES/wofs_radar"

#-----------------------------------------------------------------------
# 5. Reuse existing installation when appropriate
#-----------------------------------------------------------------------

if [[ -d "$DEST" && ! -L "$DEST" ]]; then

    if [[ -f "$DEST/SOURCE_COMMIT" &&
          -f "$DEST/FORTRAN_BUILD_COMMIT" &&
          -f "$BUILD_ROOT/INSTALL_SUCCESS" ]] &&
       [[ "$(cat "$DEST/SOURCE_COMMIT")" == "$RADAR_COMMIT" ]] &&
       [[ "$(cat "$DEST/FORTRAN_BUILD_COMMIT")" == "$BUILD_COMMIT" ]]
    then

        for name in cressman sparsey; do

            cmp \
                "$BUILD_ROOT/extensions/${name}${EXT_SUFFIX}" \
                "$DEST/utils/${name}${EXT_SUFFIX}" ||
                die "Installed extension differs: $name"

        done

        echo "[SKIP] RADAR package already installed"

        echo "Source revision: $RADAR_COMMIT"

        exit 0

    fi

    die "Existing RADAR installation differs; manual update required"

fi

[[ ! -e "$DEST" && ! -L "$DEST" ]] ||
    die "Unexpected installation path: $DEST"

#-----------------------------------------------------------------------
# 6. Prepare staged package
#-----------------------------------------------------------------------

TMP_INSTALL="$(mktemp -d "$SITE_PACKAGES/.radar_install.XXXXXXXX")"

trap 'rm -rf "$TMP_INSTALL"' EXIT

# Extract committed source only.

git -C "$RADAR_SOURCE" archive \
    "$RADAR_COMMIT" wofs_radar |
    tar -xf - -C "$TMP_INSTALL"

# Remove legacy compiled extensions.

find "$TMP_INSTALL/wofs_radar" \
    -type f \
    \( -name '*.so' -o -name '*.pyc' \) \
    -delete

find "$TMP_INSTALL/wofs_radar" \
    -type d -name '__pycache__' \
    -prune -exec rm -rf {} +

# Install the current Fortran extensions.

for name in cressman sparsey; do

    install -m 755 \
        "$BUILD_ROOT/extensions/${name}${EXT_SUFFIX}" \
        "$TMP_INSTALL/wofs_radar/utils/${name}${EXT_SUFFIX}"

    echo "[PASS] Installed extension: $name"

done

printf '%s\n' "$RADAR_COMMIT" \
    > "$TMP_INSTALL/wofs_radar/SOURCE_COMMIT"

printf '%s\n' "$BUILD_COMMIT" \
    > "$TMP_INSTALL/wofs_radar/FORTRAN_BUILD_COMMIT"

#-----------------------------------------------------------------------
# 7. Validate staged package before publication
#-----------------------------------------------------------------------

cd "$TMP_INSTALL"

"$PY" - "$TMP_INSTALL" <<'PYTHON'
import sys
import importlib
from pathlib import Path

stage = Path(sys.argv[1]).resolve()

sys.path.insert(0, str(stage))

modules = [
    "wofs_radar",
    "wofs_radar.utils.cressman",
    "wofs_radar.utils.sparsey",
    "wofs_radar.vr.load_mrms_ppi",
    "wofs_radar.vr.mrms",
    "wofs_radar.vr",
    "wofs_radar.refl.grib2_reader",
    "wofs_radar.refl.prep_mrms",
    "wofs_radar.refl",
    "wofs_radar.__main__",
]

for name in modules:

    mod = importlib.import_module(name)

    if getattr(mod, "__file__", None):
        location = Path(mod.__file__).resolve()
    else:
        location = Path(next(iter(mod.__path__))).resolve()

    assert location.is_relative_to(stage), (
        f"{name} imported outside staged package: {location}"
    )

    print(f"[PASS] {name}")

from wofs_radar.utils.cressman import cressman
from wofs_radar.utils.cressman import obs_2_grid2d
from wofs_radar.utils.sparsey import sparse_decompress

assert callable(cressman)
assert callable(obs_2_grid2d)
assert callable(sparse_decompress)

print("[PASS] Staged RADAR package validated")
PYTHON

#-----------------------------------------------------------------------
# 8. Publish validated package
#-----------------------------------------------------------------------

mv -T "$TMP_INSTALL/wofs_radar" "$DEST"

printf '%s\n' "$RADAR_COMMIT" \
    > "$BUILD_ROOT/installed_source_commit.txt"

touch "$BUILD_ROOT/INSTALL_SUCCESS"

echo
echo "[PASS] WoFS radar package installation completed"

echo "Installed package: $DEST"

echo "Source revision: $RADAR_COMMIT"

echo "Fortran revision: $BUILD_COMMIT"
