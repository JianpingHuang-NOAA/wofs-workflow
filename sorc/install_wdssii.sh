#!/bin/bash
#=======================================================================
# Install the WDSS-II binary distribution for WoFS v1.0.
#
# Platform: NOAA Ursa
#
# Usage:
#   ./sorc/install_wdssii.sh SOURCE_DIRECTORY SSL_DIRECTORY
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

source "$ROOT/versions/obs_radar.ver"

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || \
    die "Usage: $0 SOURCE_DIRECTORY SSL_DIRECTORY"

SOURCE="$(realpath -e "$1")"

SSL_HOME="$(realpath -e "$2")"

DEST="$ROOT/exec/WDSSII"

[[ -d "$SOURCE" ]] || die "Missing WDSS-II source"

[[ -d "$SSL_HOME/lib" ]] || \
    die "Missing OpenSSL compatibility libraries"

[[ ! -e "$DEST" && ! -L "$DEST" ]] || \
    die "Installation already exists: $DEST"

echo "===== WDSS-II installation configuration ====="

echo "Version     : $wdssii_ver"
echo "Source      : $SOURCE"
echo "Destination : $DEST"
echo "SSL_HOME    : $SSL_HOME"

#-----------------------------------------------------------------------
# Required distribution directories
#-----------------------------------------------------------------------

for dir in bin lib etc include share w2config; do

    [[ -d "$SOURCE/$dir" ]] || \
        die "Missing source directory: $dir"

done

[[ -s "$SOURCE/VERSION" ]] || \
    die "Missing WDSS-II VERSION file"

#-----------------------------------------------------------------------
# Create a temporary installation directory
#-----------------------------------------------------------------------

mkdir -p "$ROOT/exec"

STAGE="$(mktemp -d "$ROOT/exec/.WDSSII_install.XXXXXXXX")"

trap 'rm -rf "$STAGE"' EXIT

echo
echo "===== Copy WDSS-II binary distribution ====="

for dir in bin lib etc include share w2config; do

    mkdir -p "$STAGE/$dir"

    rsync -a "$SOURCE/$dir/" "$STAGE/$dir/"

    echo "[PASS] Copied $dir"

done

cp -p "$SOURCE/VERSION" "$STAGE/VERSION"

#-----------------------------------------------------------------------
# Validate runtime dependencies
#-----------------------------------------------------------------------

export WDSSII_HOME="$STAGE"

export WDSSPATH="$WDSSII_HOME"

export W2_CONFIG_LOCATION="$WDSSII_HOME/w2config"

export PATH="$WDSSII_HOME/bin:$PATH"

export LD_LIBRARY_PATH="$WDSSII_HOME/lib:$SSL_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo
echo "===== Required WDSS-II executables ====="

for exe in ldm2netcdf w2qcnndp dealiasVel; do

    file="$STAGE/bin/$exe"

    [[ -x "$file" ]] || \
        die "Missing executable: $exe"

    libs="$(ldd "$file" 2>&1)" || {
        echo "$libs"
        die "Cannot inspect shared libraries: $exe"
    }

    if grep -q 'not found' <<< "$libs"; then

        echo "$libs"

        die "Unresolved shared libraries: $exe"

    fi

    echo "[PASS] Executable and libraries: $exe"

done

echo
echo "===== Required WDSS-II utility scripts ====="

for exe in makeIndex.pl replaceIndex; do

    [[ -x "$STAGE/bin/$exe" ]] || \
        die "Missing utility: $exe"

    echo "[PASS] Utility: $exe"

done

#-----------------------------------------------------------------------
# Record installation provenance
#-----------------------------------------------------------------------

printf '%s\n' "$SOURCE" > "$STAGE/INSTALL_SOURCE"

printf '%s\n' "$SSL_HOME" > "$STAGE/SSL_HOME"

printf '%s\n' "$wdssii_ver" > "$STAGE/WOFS_WDSSII_VERSION"

date -u +%FT%TZ > "$STAGE/INSTALL_DATE"

if [[ -s "$SOURCE/$wdssii_archive" ]]; then

    sha256sum "$SOURCE/$wdssii_archive" \
        > "$STAGE/DISTRIBUTION_ARCHIVE.sha256"

fi

(
    cd "$STAGE"

    sha256sum \
        bin/ldm2netcdf \
        bin/w2qcnndp \
        bin/dealiasVel \
        bin/makeIndex.pl \
        bin/replaceIndex \
        > EXECUTABLES.sha256
)

#-----------------------------------------------------------------------
# Publish the installation
#-----------------------------------------------------------------------

touch "$STAGE/INSTALL_SUCCESS"

mv -T "$STAGE" "$DEST"

trap - EXIT

echo
echo "===== Installed WDSS-II version ====="

cat "$DEST/VERSION"

echo
echo "===== Installation size ====="

du -sh "$DEST"

echo
echo "[PASS] WDSS-II installation completed"

echo "Installation: $DEST"
