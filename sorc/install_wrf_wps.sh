#!/usr/bin/env bash
#
# Install WRF and WPS executables into the WoFS exec directory.
#
# Required environment variables:
#   WRF_BUILD_DIR
#   WPS_BUILD_DIR
#
# Optional environment variables:
#   HOMEwofs
#   EXECwofs
#   BACKUP_DIR
#

set -euo pipefail

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ============================================================
# Resolve repository and build directories
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

HOMEwofs="${HOMEwofs:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"

HOMEwofs="$(cd "$HOMEwofs" && pwd -P)"

[[ -f "$HOMEwofs/Externals.cfg" ]] ||
    die "Invalid WoFS repository: $HOMEwofs"

: "${WRF_BUILD_DIR:?WRF_BUILD_DIR must be defined}"
: "${WPS_BUILD_DIR:?WPS_BUILD_DIR must be defined}"

[[ -d "$WRF_BUILD_DIR" ]] ||
    die "Missing WRF build directory: $WRF_BUILD_DIR"

[[ -d "$WPS_BUILD_DIR" ]] ||
    die "Missing WPS build directory: $WPS_BUILD_DIR"

WRF_BUILD_DIR="$(cd "$WRF_BUILD_DIR" && pwd -P)"
WPS_BUILD_DIR="$(cd "$WPS_BUILD_DIR" && pwd -P)"

EXECwofs="${EXECwofs:-$HOMEwofs/exec}"

STAMP="$(date +%Y%m%d_%H%M%S)"

BACKUP_DIR="${BACKUP_DIR:-$HOMEwofs/staging/exec_backup_${STAMP}_$$}"

echo "=========================================="
echo "WoFS WRF/WPS executable installation"
echo "=========================================="
echo "HOMEwofs:      $HOMEwofs"
echo "WRF_BUILD_DIR: $WRF_BUILD_DIR"
echo "WPS_BUILD_DIR: $WPS_BUILD_DIR"
echo "EXECwofs:      $EXECwofs"
echo "BACKUP_DIR:    $BACKUP_DIR"

# ============================================================
# Define source executable locations
# ============================================================

EXES=(
    wrf.exe
    real.exe
    ndown.exe
    tc.exe
    geogrid.exe
    ungrib.exe
    metgrid.exe
)

declare -A SOURCES

SOURCES[wrf.exe]="$WRF_BUILD_DIR/main/wrf.exe"
SOURCES[real.exe]="$WRF_BUILD_DIR/main/real.exe"
SOURCES[ndown.exe]="$WRF_BUILD_DIR/main/ndown.exe"
SOURCES[tc.exe]="$WRF_BUILD_DIR/main/tc.exe"

SOURCES[geogrid.exe]="$WPS_BUILD_DIR/geogrid/src/geogrid.exe"
SOURCES[ungrib.exe]="$WPS_BUILD_DIR/ungrib/src/ungrib.exe"
SOURCES[metgrid.exe]="$WPS_BUILD_DIR/metgrid/src/metgrid.exe"

# ============================================================
# Validate all source executables before modifying exec/
# ============================================================

echo
echo "===== Source executable validation ====="

for exe in "${EXES[@]}"; do

    src="${SOURCES[$exe]}"

    [[ -f "$src" && -x "$src" && -s "$src" ]] ||
        die "Invalid source executable: $src"

    echo "[PASS] $src"

done

# ============================================================
# Prepare installation and backup directories
# ============================================================

mkdir -p "$EXECwofs"
mkdir -p "$(dirname "$BACKUP_DIR")"
mkdir "$BACKUP_DIR"

TEMP_DIR="$(mktemp -d "$EXECwofs/.install.XXXXXXXX")"

trap 'rm -rf -- "$TEMP_DIR"' EXIT

# ============================================================
# Prepare and verify new executables
# ============================================================

echo
echo "===== Preparing new executables ====="

for exe in "${EXES[@]}"; do

    src="${SOURCES[$exe]}"

    install -m 755 "$src" "$TEMP_DIR/$exe"

    cmp -s "$src" "$TEMP_DIR/$exe" ||
        die "Copy verification failed: $exe"

    echo "[PASS] Prepared $exe"

done

# ============================================================
# Back up all existing executables and symbolic links
# ============================================================

echo
echo "===== Backing up existing executables ====="

for exe in "${EXES[@]}"; do

    dst="$EXECwofs/$exe"

    if [[ -e "$dst" || -L "$dst" ]]; then

        cp -a -- "$dst" "$BACKUP_DIR/$exe"

        echo "[BACKUP] $dst"

    fi

done

# ============================================================
# Install new executables
# ============================================================

echo
echo "===== Installing executables ====="

for exe in "${EXES[@]}"; do

    dst="$EXECwofs/$exe"

    mv -fT -- "$TEMP_DIR/$exe" "$dst"

    echo "[INSTALL] $dst"

done

# ============================================================
# Final executable validation
# ============================================================

echo
echo "===== Installed executable validation ====="

for exe in "${EXES[@]}"; do

    src="${SOURCES[$exe]}"
    dst="$EXECwofs/$exe"

    [[ -f "$dst" && -x "$dst" && ! -L "$dst" ]] ||
        die "Invalid installed executable: $dst"

    SRC_HASH="$(sha256sum "$src" | awk '{print $1}')"
    DST_HASH="$(sha256sum "$dst" | awk '{print $1}')"

    [[ "$SRC_HASH" == "$DST_HASH" ]] ||
        die "Checksum mismatch: $exe"

    echo "[PASS] $exe"
    ls -lh "$dst"

done

echo
echo "===== UPP executable ====="

if [[ -x "$EXECwofs/upp.x" ]]; then
    echo "[INFO] Existing upp.x preserved"
    ls -lh "$EXECwofs/upp.x"
else
    echo "[WARNING] upp.x is not available"
fi

echo
echo "=========================================="
echo "[PASS] WRF/WPS installation completed"
echo "Executables: $EXECwofs"
echo "Backup:      $BACKUP_DIR"
echo "=========================================="
