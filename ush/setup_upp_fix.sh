#!/usr/bin/env bash
#
# Provision reproducible UPP FIX files for WoFS v1.0.
#
# Usage:
#   bash ush/setup_upp_fix.sh [destination]
#
set -euo pipefail

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOMEwofs="${HOMEwofs:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
HOMEwofs="$(cd "$HOMEwofs" && pwd -P)"

PARM_DIR="$HOMEwofs/parm/upp"
MANIFEST="$PARM_DIR/upp_fix.sha256"
CONTROL="$PARM_DIR/upp_control.sha256"
SOURCE="$HOMEwofs/sorc/UPP"
EXTERNALS="$HOMEwofs/Externals.cfg"

DEST="${1:-$HOMEwofs/fix/UPP}"

[[ $# -le 1 ]] || die "Expected at most one destination"

[[ ! -e "$DEST" && ! -L "$DEST" ]] ||
    die "Destination already exists: $DEST"

for f in "$MANIFEST" "$CONTROL" "$EXTERNALS"
do
    [[ -s "$f" ]] || die "Missing file: $f"
done

EXPECTED="$(awk '
    /^\[UPP\]/ {active=1; next}
    /^\[/ {active=0}
    active && /^hash[[:space:]]*=/ {print $3}
' "$EXTERNALS")"

[[ "$EXPECTED" =~ ^[0-9a-f]{40}$ ]] ||
    die "Invalid pinned UPP revision"

ACTUAL="$(git -C "$SOURCE" rev-parse HEAD)"

[[ "$ACTUAL" == "$EXPECTED" ]] ||
    die "UPP source revision mismatch"

echo "[PASS] UPP source revision: $ACTUAL"

(
    cd "$HOMEwofs"
    sha256sum -c "$CONTROL"
)

(
    cd "$PARM_DIR"
    sha256sum -c "$MANIFEST"
)

mkdir -p "$(dirname "$DEST")"

TMP="$(mktemp -d "$(dirname "$DEST")/.upp_fix.XXXXXXXX")"

trap 'rm -rf -- "$TMP"' EXIT

install -m 644 \
    "$PARM_DIR/gtg.config.raphrrr" \
    "$TMP/gtg.config.raphrrr"

(
    cd "$TMP"
    sha256sum -c "$MANIFEST"
)

[[ "$(find "$TMP" -type f | wc -l)" -eq 1 ]] ||
    die "Unexpected regular file count"

[[ "$(find "$TMP" -type l | wc -l)" -eq 0 ]] ||
    die "Unexpected symbolic links"

chmod 2755 "$TMP"

mv -nT -- "$TMP" "$DEST"

[[ ! -e "$TMP" ]] ||
    die "Destination installation failed"

echo
echo "[PASS] UPP FIX provisioning completed"
echo "Destination: $DEST"
echo "Regular files: 1"
echo "Symbolic links: 0"
