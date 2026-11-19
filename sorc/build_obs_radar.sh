#!/bin/bash
#=======================================================================
# Centralized WoFS radar software installation controller.
#
# Platform: NOAA Ursa
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

PY="$ROOT/python_env/bin/python3"

RADAR_SOURCE="$ROOT/sorc/RADAR"

WDSSII_DEST="$ROOT/exec/WDSSII"

BUILD_POINTER="$ROOT/staging/latest_radar_build_path.txt"

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

usage()
{
    cat <<'EOF'
Usage:
    ./sorc/build_obs_radar.sh OPTION

Options:
    --all       Install all radar software components
    --python    Install radar Python dependencies
    --radar     Build and install RADAR package
    --wdssii    Install WDSS-II binary distribution
    --status    Display software installation status
    --help      Display this message

For a new WDSS-II installation, define:

    WDSSII_SOURCE
    WDSSII_SSL_HOME

Existing completed installations are reused.
EOF
}

#-----------------------------------------------------------------------
# Determine installed RADAR package directory
#-----------------------------------------------------------------------

radar_install_dir()
{
    [[ -x "$PY" ]] || return 1

    "$PY" -c \
        'import sysconfig; print(sysconfig.get_path("purelib") + "/wofs_radar")'
}

#-----------------------------------------------------------------------
# Check Python dependencies
#-----------------------------------------------------------------------

python_ready()
(
    source "$ROOT/versions/bc_prep.ver"

    module purge
    module use "$ROOT/modulefiles"
    module load "$wofs_modulefile"

    export PYTHONNOUSERSITE=1

    unset PYTHONPATH PYTHONHOME

    [[ -x "$PY" ]] || exit 1

    "$PY" - <<'PYTHON'
import importlib.metadata as md

from pathlib import Path

requirements = Path("sorc/requirements_radar.txt")

for line in requirements.read_text().splitlines():

    line = line.split("#", 1)[0].strip()

    if not line:
        continue

    if "==" not in line:
        raise RuntimeError(f"Unpinned requirement: {line}")

    name, expected = line.split("==", 1)

    actual = md.version(name.strip())

    if actual != expected.strip():
        raise RuntimeError(
            f"{name}: expected {expected}, found {actual}"
        )

print("[PASS] Radar Python dependency versions")
PYTHON
)

install_python()
{
    echo "===== Radar Python dependencies ====="

    if python_ready; then

        echo "[SKIP] Radar Python dependencies already installed"

    else

        "$ROOT/sorc/install_radar_python.sh"

        python_ready

    fi
}

#-----------------------------------------------------------------------
# Check Fortran build
#-----------------------------------------------------------------------

fortran_ready()
{
    [[ -s "$BUILD_POINTER" ]] || return 1

    local build

    build="$(cat "$BUILD_POINTER")"

    [[ -f "$build/BUILD_SUCCESS" ]] || return 1

    for name in cressman sparsey; do

        cmp -s \
            "$RADAR_SOURCE/wofs_radar/utils/${name}.f90" \
            "$build/$name/${name}.f90" ||
            return 1

        compgen -G \
            "$build/extensions/${name}*.so" \
            > /dev/null || return 1

    done

    (
        cd "$build/extensions"

        sha256sum -c "$build/extensions.sha256" \
            > /dev/null
    )
}

#-----------------------------------------------------------------------
# Check RADAR package
#-----------------------------------------------------------------------

radar_ready()
{
    local dest source_commit build

    dest="$(radar_install_dir)" || return 1

    [[ -f "$dest/SOURCE_COMMIT" ]] || return 1

    [[ -f "$dest/FORTRAN_BUILD_COMMIT" ]] || return 1

    [[ -s "$BUILD_POINTER" ]] || return 1

    build="$(cat "$BUILD_POINTER")"

    [[ -f "$build/INSTALL_SUCCESS" ]] || return 1

    source_commit="$(
        git -C "$RADAR_SOURCE" rev-parse HEAD
    )" || return 1

    [[ "$(cat "$dest/SOURCE_COMMIT")" == "$source_commit" ]] ||
        return 1

    [[ "$(cat "$dest/FORTRAN_BUILD_COMMIT")" == "$(cat "$build/radar_commit.txt")" ]] ||
        return 1

    fortran_ready || return 1

    for lib in "$build"/extensions/*.so; do

        cmp -s \
            "$lib" "$dest/utils/$(basename "$lib")" ||
            return 1

    done
}

install_radar()
{
    echo "===== RADAR package ====="

    python_ready ||
        die "Install radar Python dependencies first"

    [[ -d "$RADAR_SOURCE/wofs_radar" ]] ||
        die "RADAR external has not been checked out"

    if radar_ready; then

        echo "[SKIP] RADAR package already installed"

        return 0

    fi

    local dest

    dest="$(radar_install_dir)"

    [[ ! -e "$dest" && ! -L "$dest" ]] ||
        die "Existing RADAR installation requires manual update"

    if fortran_ready; then

        echo "[SKIP] Reusing existing Fortran extensions"

    else

        "$ROOT/sorc/build_radar.sh"

    fi

    "$ROOT/sorc/install_radar.sh"
}

#-----------------------------------------------------------------------
# Check WDSS-II installation
#-----------------------------------------------------------------------

wdssii_ready()
(
    [[ -f "$WDSSII_DEST/INSTALL_SUCCESS" ]] || exit 1

    [[ -s "$WDSSII_DEST/SSL_HOME" ]] || exit 1

    local_ssl="${WDSSII_SSL_HOME:-$(cat "$WDSSII_DEST/SSL_HOME")}"

    [[ -d "$local_ssl/lib" ]] || exit 1

    cd "$WDSSII_DEST"

    sha256sum -c EXECUTABLES.sha256 > /dev/null
)

install_wdssii()
{
    echo "===== WDSS-II binary distribution ====="

    if wdssii_ready; then

        echo "[SKIP] WDSS-II already installed"

        return 0

    fi

    [[ ! -e "$WDSSII_DEST" && ! -L "$WDSSII_DEST" ]] ||
        die "Existing WDSS-II installation requires manual repair"

    [[ -n "${WDSSII_SOURCE:-}" ]] ||
        die "Define WDSSII_SOURCE"

    [[ -n "${WDSSII_SSL_HOME:-}" ]] ||
        die "Define WDSSII_SSL_HOME"

    "$ROOT/sorc/install_wdssii.sh" \
        "$WDSSII_SOURCE" \
        "$WDSSII_SSL_HOME"
}

#-----------------------------------------------------------------------
# Report software status
#-----------------------------------------------------------------------

show_status()
{
    local failures=0

    echo "=================================================="
    echo "WoFS radar software status"
    echo "=================================================="
    echo "HOMEwofs: $ROOT"
    echo "Branch  : $(git branch --show-current)"
    echo "=================================================="

    if python_ready > /dev/null 2>&1; then
        echo "[PASS] Radar Python dependencies"
    else
        echo "[FAIL] Radar Python dependencies"
        failures=$((failures+1))
    fi

    if fortran_ready; then
        echo "[PASS] RADAR Fortran extensions"
    else
        echo "[FAIL] RADAR Fortran extensions"
        failures=$((failures+1))
    fi

    if radar_ready; then
        echo "[PASS] RADAR Python package"
    else
        echo "[FAIL] RADAR Python package"
        failures=$((failures+1))
    fi

    if wdssii_ready; then
        echo "[PASS] WDSS-II installation"
    else
        echo "[FAIL] WDSS-II installation"
        failures=$((failures+1))
    fi

    echo "=================================================="

    if (( failures == 0 )); then

        echo "[PASS] All radar software components ready"

        return 0

    fi

    echo "[FAIL] $failures software components not ready"

    return 1
}

#-----------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------

[[ $# -eq 1 ]] || {
    usage
    exit 1
}

case "$1" in

    --all)

        install_python

        install_radar

        install_wdssii

        show_status
        ;;

    --python)

        install_python
        ;;

    --radar)

        install_radar
        ;;

    --wdssii)

        install_wdssii
        ;;

    --status)

        show_status
        ;;

    --help|-h)

        usage
        ;;

    *)

        usage

        exit 1
        ;;

esac
