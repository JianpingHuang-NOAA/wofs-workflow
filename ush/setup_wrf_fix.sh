#!/usr/bin/env bash
#
# Provision validated WoFS WRF static files.
#
# Usage:
#   setup_wrf_fix.sh [destination]
#
# Default destination:
#   ${HOMEwofs}/fix/WRF
#
# Existing destinations are never overwritten.

set -euo pipefail

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOMEwofs="${HOMEwofs:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
HOMEwofs="$(cd "$HOMEwofs" && pwd -P)"

WRF_SOURCE="$HOMEwofs/sorc/WRF"
PARM_DIR="$HOMEwofs/parm/bc_prep"
MANIFEST="$PARM_DIR/wrf_fix.sha256"
EXTERNALS="$HOMEwofs/Externals.cfg"

DEST="${1:-$HOMEwofs/fix/WRF}"

[[ $# -le 1 ]] || die "Too many arguments"
[[ -s "$EXTERNALS" ]] || die "Missing Externals.cfg"
[[ -s "$MANIFEST" ]] || die "Missing WRF FIX manifest"
[[ -d "$WRF_SOURCE/run" ]] || die "Missing WRF source"

if [[ -e "$DEST" || -L "$DEST" ]]; then
    die "Destination already exists: $DEST"
fi

# Verify the WRF source revision.

EXPECTED_REV="$(awk '
    /^\[WRF\]/ { active=1; next }
    /^\[/ { active=0 }
    active && /^hash[[:space:]]*=/ { print $3 }
' "$EXTERNALS")"

[[ "$EXPECTED_REV" =~ ^[0-9a-f]{40}$ ]] ||
    die "Invalid WRF source revision"

ACTUAL_REV="$(git -C "$WRF_SOURCE" rev-parse HEAD)"

[[ "$ACTUAL_REV" == "$EXPECTED_REV" ]] ||
    die "WRF source revision mismatch"

echo "[PASS] WRF source revision: $ACTUAL_REV"

# Prepare an isolated temporary directory.

mkdir -p "$(dirname "$DEST")"

TEMP_DIR="$(mktemp -d "$(dirname "$DEST")/.wrf_fix.XXXXXXXX")"

trap 'rm -rf -- "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/run"

# Provision exactly the files listed in the manifest.

TOTAL=0

while read -r checksum relative_path; do

    [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] ||
        die "Invalid checksum entry"

    if [[ "$relative_path" == "real.nl.32and4levels" ]]; then
        SRC="$PARM_DIR/$relative_path"
    elif [[ "$relative_path" =~ ^namelist\.input\.member([1-9]|[12][0-9]|3[0-6])$ ]]; then
        SRC="$HOMEwofs/parm/wrf/namelists.WOFS/$relative_path"
    elif [[ "$relative_path" =~ ^run/[A-Za-z0-9._-]+$ ]]; then
        SRC="$WRF_SOURCE/$relative_path"
    else
        die "Invalid manifest path: $relative_path"
    fi

    [[ -s "$SRC" ]] || die "Missing source: $SRC"

    printf '%s  %s\n' "$checksum" "$SRC" |
        sha256sum -c --quiet

    install -m 644 "$SRC" "$TEMP_DIR/$relative_path"

    TOTAL=$((TOTAL + 1))

done < "$MANIFEST"

[[ "$TOTAL" -eq 104 ]] ||
    die "Unexpected manifest entry count: $TOTAL"

# Verify all provisioned files.

(
    cd "$TEMP_DIR"
    sha256sum -c "$MANIFEST" --quiet
)

[[ "$(find "$TEMP_DIR" -type f | wc -l)" -eq "$TOTAL" ]] ||
    die "Unexpected provisioned file count"

echo "[PASS] All $TOTAL WRF FIX files verified"

# Set permissions for shared static data access.

chmod 2755 "$TEMP_DIR" "$TEMP_DIR/run"

# Install without overwriting an existing destination.

mv -nT -- "$TEMP_DIR" "$DEST"

[[ ! -e "$TEMP_DIR" ]] ||
    die "Destination installation failed"

echo "[PASS] WRF FIX provisioning completed"
echo "Destination: $DEST"
echo "Files:       $TOTAL"
