#!/usr/bin/env bash
#
# Provision reproducible WPS FIX files for WoFS v1.0.
#
# Usage:
#   WPS_STATIC_SOURCE=/path/to/static/WPS \
#       bash ush/setup_wps_fix.sh [destination]
#
set -euo pipefail

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Resolve repository paths.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOMEwofs="${HOMEwofs:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
HOMEwofs="$(cd "$HOMEwofs" && pwd -P)"

WPS_SOURCE="$HOMEwofs/sorc/WPS"
PARM_DIR="$HOMEwofs/parm/wps"
MANIFEST="$PARM_DIR/wps_fix.sha256"
LINK_MANIFEST="$PARM_DIR/wps_fix.links"
EXTERNALS="$HOMEwofs/Externals.cfg"

DEST="${1:-$HOMEwofs/fix/WPS}"

[[ $# -le 1 ]] || die "Too many arguments"

[[ -n "${WPS_STATIC_SOURCE:-}" ]] ||
    die "WPS_STATIC_SOURCE must be specified"

[[ -d "$WPS_STATIC_SOURCE" ]] ||
    die "Missing external WPS static directory"

WPS_STATIC_SOURCE="$(cd "$WPS_STATIC_SOURCE" && pwd -P)"

[[ -s "$EXTERNALS" ]] ||
    die "Missing Externals.cfg"

[[ -s "$MANIFEST" ]] ||
    die "Missing WPS checksum manifest"

[[ -s "$LINK_MANIFEST" ]] ||
    die "Missing WPS symbolic link manifest"

[[ -d "$WPS_SOURCE" ]] ||
    die "Missing WPS source directory"

# Never overwrite an existing destination.
if [[ -e "$DEST" || -L "$DEST" ]]; then
    die "Destination already exists: $DEST"
fi

# Verify the pinned WPS external revision.
EXPECTED_REV="$(awk '
    /^\[WPS\]/ { active=1; next }
    /^\[/ { active=0 }
    active && /^hash[[:space:]]*=/ { print $3 }
' "$EXTERNALS")"

[[ "$EXPECTED_REV" =~ ^[0-9a-f]{40}$ ]] ||
    die "Invalid pinned WPS revision"

ACTUAL_REV="$(git -C "$WPS_SOURCE" rev-parse HEAD)"

[[ "$ACTUAL_REV" == "$EXPECTED_REV" ]] ||
    die "WPS source revision mismatch"

echo "[PASS] WPS source revision: $ACTUAL_REV"

# Create a temporary directory on the destination filesystem.
mkdir -p "$(dirname "$DEST")"

TEMP_DIR="$(mktemp -d "$(dirname "$DEST")/.wps_fix.XXXXXXXX")"

trap 'rm -rf -- "$TEMP_DIR"' EXIT

TOTAL=0

# Provision all regular files.
while read -r checksum relative_path
do
    [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] ||
        die "Invalid checksum entry"

    name="${relative_path#./}"

    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "Invalid manifest filename: $name"

    case "$name" in
        Vtable.SST)
            SRC="$WPS_SOURCE/ungrib/Variable_Tables/$name"
            ;;

        geo_em.d01_modis15s_lake_Saltlake_modisalb_newtopo_newsoil_lakemod.new_GWD_fields.nc|\
        GWD_mdt_10newfields.HRRR.nc_20190220)
            SRC="$WPS_STATIC_SOURCE/$name"
            ;;

        GEOGRID.TBL|METGRID.TBL|METGRID.TBL.nosmoke|\
        Vtable.GFSENS|Vtable.RAP|Vtable.RAP.nosmoke|\
        namelist.wps.GFSENS|namelist.wps.GFSENS_orig)
            SRC="$PARM_DIR/$name"
            ;;

        *)
            die "Unexpected WPS FIX file: $name"
            ;;
    esac

    [[ -f "$SRC" && -s "$SRC" ]] ||
        die "Missing source file: $SRC"

    [[ ! -e "$TEMP_DIR/$name" ]] ||
        die "Duplicate manifest entry: $name"

    printf '%s  %s\n' "$checksum" "$SRC" |
        sha256sum -c --quiet

    install -m 644 "$SRC" "$TEMP_DIR/$name"

    TOTAL=$((TOTAL + 1))

    echo "[PASS] $name"

done < "$MANIFEST"

[[ "$TOTAL" -eq 11 ]] ||
    die "Unexpected regular file count: $TOTAL"

# Recreate relative symbolic links.
LINK_TOTAL=0

while IFS=$'\t' read -r name target
do
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "Invalid symbolic link name"

    [[ "$target" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "Invalid symbolic link target"

    [[ -f "$TEMP_DIR/$target" && ! -L "$TEMP_DIR/$target" ]] ||
        die "Missing symbolic link target: $target"

    [[ ! -e "$TEMP_DIR/$name" && ! -L "$TEMP_DIR/$name" ]] ||
        die "Duplicate symbolic link name: $name"

    ln -s "$target" "$TEMP_DIR/$name"

    LINK_TOTAL=$((LINK_TOTAL + 1))

    echo "[PASS] $name -> $target"

done < "$LINK_MANIFEST"

[[ "$LINK_TOTAL" -eq 3 ]] ||
    die "Unexpected symbolic link count: $LINK_TOTAL"

# Independently verify provisioned file contents.
(
    cd "$TEMP_DIR"
    sha256sum -c "$MANIFEST" --quiet
)

[[ "$(find "$TEMP_DIR" -type f | wc -l)" -eq 11 ]] ||
    die "Unexpected provisioned file count"

[[ "$(find "$TEMP_DIR" -type l | wc -l)" -eq 3 ]] ||
    die "Unexpected provisioned link count"

[[ "$(find "$TEMP_DIR" -xtype l | wc -l)" -eq 0 ]] ||
    die "Broken symbolic links detected"

# Independently verify exact symbolic link targets.
(
    cd "$TEMP_DIR"

    find . -maxdepth 1 -type l \
        -printf '%f\t%l\n' |
        LC_ALL=C sort |
        cmp - "$LINK_MANIFEST"
)

# Set shared directory permissions.
chmod 2755 "$TEMP_DIR"

# Install without overwriting an existing destination.
mv -nT -- "$TEMP_DIR" "$DEST"

[[ ! -e "$TEMP_DIR" ]] ||
    die "Destination installation failed"

echo
echo "[PASS] WPS FIX provisioning completed"
echo "Destination: $DEST"
echo "Regular files: $TOTAL"
echo "Symbolic links: $LINK_TOTAL"
