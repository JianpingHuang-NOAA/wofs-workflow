#!/usr/bin/env bash
#
# Centralized FIX installation for WoFS v1.0.
#
# Usage:
#   export WPS_STATIC_SOURCE=/path/to/static/WPS
#   ./sorc/install_fix.sh
#
# Existing FIX datasets are verified, not overwritten.

set -euo pipefail

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Resolve repository root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

export HOMEwofs="$(cd "$SCRIPT_DIR/.." && pwd -P)"

FIX_ROOT="$HOMEwofs/fix"

# Usage.
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: WPS_STATIC_SOURCE=/path/to/static/WPS $0"
    exit 0
fi

[[ $# -eq 0 ]] || die "Unexpected arguments"

# Required installation scripts.
for script in \
    ush/setup_upp_fix.sh \
    ush/setup_wps_fix.sh \
    ush/setup_wrf_fix.sh \
    sorc/install_cartopy_data.sh
do
    [[ -s "$HOMEwofs/$script" ]] ||
        die "Missing installation script: $script"
done

# Use the repository-local Python environment.
export WOFS_PYTHON="$HOMEwofs/python_env/bin/python3"
export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME

[[ -x "$WOFS_PYTHON" ]] ||
    die "Install the WoFS Python environment first"

# Require external WPS static data for a new WPS installation.
if [[ ! -e "$FIX_ROOT/WPS" ]]; then

    : "${WPS_STATIC_SOURCE:?WPS_STATIC_SOURCE must be specified}"

    [[ -d "$WPS_STATIC_SOURCE" ]] ||
        die "Missing WPS static directory: $WPS_STATIC_SOURCE"

    export WPS_STATIC_SOURCE="$(cd "$WPS_STATIC_SOURCE" && pwd -P)"

fi

# Do not install into a linked FIX root.
[[ ! -L "$FIX_ROOT" ]] ||
    die "FIX root must not be a symbolic link"

mkdir -p "$FIX_ROOT"

# Prevent simultaneous FIX installations.
exec 9>"$FIX_ROOT/.install_fix.lock"
flock -n 9 || die "Another FIX installation is running"

echo "=================================================="
echo "WoFS centralized FIX installation"
echo "=================================================="
echo "Repository : $HOMEwofs"
echo "FIX root   : $FIX_ROOT"
echo "Python     : $WOFS_PYTHON"
echo "WPS source : ${WPS_STATIC_SOURCE:-Existing installation}"
echo "=================================================="

# Verify installed files using a checksum manifest.
verify_fix() {

    local dest="$1"
    local manifest="$2"

    [[ -d "$dest" && ! -L "$dest" ]] ||
        die "Invalid FIX directory: $dest"

    [[ -s "$manifest" ]] ||
        die "Missing checksum manifest: $manifest"

    (
        cd "$dest"
        sha256sum -c "$manifest" --quiet
    )

    echo "[PASS] Verified $dest"
}

# Install or verify one FIX component.
install_component() {

    local name="$1"
    local script="$2"
    local manifest="$3"

    local dest="$FIX_ROOT/$name"

    echo
    echo "===== $name FIX ====="

    if [[ -L "$dest" ]]; then

        die "FIX component must not be a symbolic link: $dest"

    elif [[ -e "$dest" ]]; then

        echo "[INFO] Existing installation; verifying"

    else

        bash "$HOMEwofs/$script" "$dest"

    fi

    verify_fix "$dest" "$manifest"
}

# 1. UPP FIX.
install_component \
    UPP \
    ush/setup_upp_fix.sh \
    "$HOMEwofs/parm/upp/upp_fix.sha256"

# 2. WPS FIX.
install_component \
    WPS \
    ush/setup_wps_fix.sh \
    "$HOMEwofs/parm/wps/wps_fix.sha256"

# Verify WPS symbolic links.
(
    cd "$FIX_ROOT/WPS"

    find . -maxdepth 1 -type l \
        -printf '%f\t%l\n' |
        LC_ALL=C sort |
        cmp - "$HOMEwofs/parm/wps/wps_fix.links"

    [[ "$(find . -xtype l | wc -l)" -eq 0 ]] ||
        die "Broken WPS symbolic links detected"
)

echo "[PASS] WPS symbolic links verified"

# 3. WRF FIX.
install_component \
    WRF \
    ush/setup_wrf_fix.sh \
    "$HOMEwofs/parm/bc_prep/wrf_fix.sha256"

# 4. Cartopy FIX.
echo
echo "===== Cartopy FIX ====="

CARTOPY_DEST="$FIX_ROOT/cartopy"
CARTOPY_MANIFEST="$HOMEwofs/parm/cartopy/cartopy_fix.sha256"

[[ ! -L "$CARTOPY_DEST" ]] ||
    die "Cartopy FIX must not be a symbolic link"

[[ -s "$CARTOPY_MANIFEST" ]] ||
    die "Missing Cartopy checksum manifest"

if [[ ! -e "$CARTOPY_DEST" ]]; then

    CARTOPY_TMP="$(mktemp -d "$FIX_ROOT/.cartopy.XXXXXXXX")"

    trap 'rm -rf -- "$CARTOPY_TMP"' EXIT

    bash "$HOMEwofs/sorc/install_cartopy_data.sh" \
        "$CARTOPY_TMP"

    verify_fix "$CARTOPY_TMP" "$CARTOPY_MANIFEST"

    chmod 2755 "$CARTOPY_TMP"

    mv -nT -- "$CARTOPY_TMP" "$CARTOPY_DEST"

    [[ ! -e "$CARTOPY_TMP" ]] ||
        die "Cartopy FIX installation failed"

    trap - EXIT

else

    echo "[INFO] Existing Cartopy installation; verifying"

fi

verify_fix "$CARTOPY_DEST" "$CARTOPY_MANIFEST"

# Final summary.
echo
echo "=================================================="
echo "[PASS] WoFS FIX installation completed"
echo "=================================================="

du -sh \
    "$FIX_ROOT/UPP" \
    "$FIX_ROOT/WPS" \
    "$FIX_ROOT/WRF" \
    "$FIX_ROOT/cartopy"

echo
echo "FIX root: $FIX_ROOT"

