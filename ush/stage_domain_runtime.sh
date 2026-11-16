#!/bin/bash
#
# Stage domain-specific WPS and WRF runtime resources.
#
set -euo pipefail

: "${HOMEwofs:?HOMEwofs is required}"
: "${WORK_ROOT:?WORK_ROOT is required}"

EXECwofs="$HOMEwofs/exec"
FIXwofs="$HOMEwofs/fix"
PARMwofs="$HOMEwofs/parm"

WRF_RUN="$WORK_ROOT/WRF_RUN"
WRF_STATIC="$FIXwofs/WRF/run"

[[ -d "$WRF_RUN" ]] || {
    echo "[ERROR] Missing directory: $WRF_RUN"
    exit 1
}

[[ -d "$WRF_STATIC" ]] || {
    echo "[ERROR] Missing directory: $WRF_STATIC"
    exit 1
}

linked=0
missing=0

stage_link() {

    local src="$1"
    local dst="$2"

    if [[ ! -f "$src" || ! -r "$src" ]]; then
        echo "[MISSING] $src"
        missing=$((missing + 1))
        return 0
    fi

    if [[ -e "$dst" || -L "$dst" ]]; then

        if [[ ! -L "$dst" ]] ||
           [[ "$(readlink -f "$dst")" != "$(readlink -f "$src")" ]]; then

            echo "[ERROR] Conflicting destination: $dst"
            exit 1

        fi

    else
        ln -s "$src" "$dst"
    fi

    echo "[PASS] ${dst##*/}"

    linked=$((linked + 1))
}

echo "===== Stage WPS and WRF executables ====="

for exe in \
    geogrid.exe \
    ungrib.exe \
    metgrid.exe \
    real.exe \
    wrf.exe \
    ndown.exe
do

    if [[ ! -x "$EXECwofs/$exe" ]]; then
        echo "[ERROR] Missing executable: $exe"
        exit 1
    fi

    stage_link "$EXECwofs/$exe" "$WRF_RUN/$exe"

done

echo
echo "===== Stage WPS tables ====="

mkdir -p "$WRF_RUN/geogrid"
mkdir -p "$WRF_RUN/metgrid"

stage_link \
    "$PARMwofs/wps/GEOGRID.TBL" \
    "$WRF_RUN/geogrid/GEOGRID.TBL"

stage_link \
    "$PARMwofs/wps/METGRID.TBL" \
    "$WRF_RUN/metgrid/METGRID.TBL"

for table in \
    METGRID.TBL.nosmoke \
    Vtable.GFSENS \
    Vtable.RAP \
    Vtable.RAP.nosmoke
do
    stage_link \
        "$PARMwofs/wps/$table" \
        "$WRF_RUN/$table"
done

stage_link \
    "$FIXwofs/WPS/Vtable.SST" \
    "$WRF_RUN/Vtable.SST"

echo
echo "===== Stage WRF static resources ====="

for name in \
    CCN_ACTIVATE.BIN \
    ETAMPNEW_DATA \
    GENPARM.TBL \
    LANDUSE.TBL \
    RRTM_DATA \
    RRTMG_SW_DATA \
    RRTMG_LW_DATA \
    SOILPARM.TBL \
    VEGPARM.TBL \
    gribmap.txt \
    grib2map.tbl \
    masses.asc \
    MPTABLE.TBL \
    RRTMG_LW_DATA_DBL \
    RRTMG_SW_DATA_DBL \
    termvels.asc \
    tr49t67 \
    tr49t85 \
    tr67t85
do
    stage_link "$WRF_STATIC/$name" "$WRF_RUN/$name"
done

echo
echo "===== Stage additional WRF physics tables ====="

shopt -s nullglob

declare -A seen

for src in \
    "$WRF_STATIC"/*.formatted \
    "$WRF_STATIC"/bulk* \
    "$WRF_STATIC"/CAM* \
    "$WRF_STATIC"/CLM* \
    "$WRF_STATIC"/co2* \
    "$WRF_STATIC"/coeff_* \
    "$WRF_STATIC"/kernels* \
    "$WRF_STATIC"/ozone* \
    "$WRF_STATIC"/aerosol*
do
    [[ -f "$src" ]] || continue

    name="${src##*/}"

    [[ -z "${seen[$name]:-}" ]] || continue

    seen["$name"]=1

    stage_link "$src" "$WRF_RUN/$name"
done

echo
echo "===== Stage WRF namelist templates ====="

TEMPLATE_DIR="$WORK_ROOT/namelists.WOFS"

mkdir -p "$TEMPLATE_DIR"

for member in $(seq 1 36); do

    name="namelist.input.member${member}"

    src="$PARMwofs/wrf/namelists.WOFS/$name"
    dst="$TEMPLATE_DIR/$name"

    if [[ ! -f "$src" ]]; then
        echo "[ERROR] Missing template: $src"
        exit 1
    fi

    if [[ -L "$dst" ]]; then
        echo "[ERROR] Unexpected template symlink: $dst"
        exit 1
    elif [[ -e "$dst" ]]; then
        echo "[KEEP] $name"
    else
        cp -p "$src" "$dst"
        echo "[PASS] $name"
    fi

done

echo
echo "===== Runtime staging summary ====="

echo "Resource links verified : $linked"
echo "Missing static resources: $missing"
echo "WRF namelist templates  : 36"

echo
echo "Deferred resources:"
echo "  link_grib.csh"
echo "  Domain-specific namelist.wps"
echo "  Domain-specific geo_em.d01.nc"
echo "  DART utilities"
echo "  GSI/EnKF executables and fix files"

if (( missing > 0 )); then
    echo "[INCOMPLETE] Some static resources are missing"
    exit 1
fi

echo "[PASS] Selected WPS/WRF resources staged"

