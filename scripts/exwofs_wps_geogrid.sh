#!/bin/bash

set -euo pipefail

cd "$DATA"

: "${WOFS_PYTHON:?WOFS_PYTHON is required}"

export OMP_NUM_THREADS=1

export WRF_GEOG_TILE_SIZE="$(
    "$WOFS_PYTHON" -c \
    'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["geogrid"]["wrf_geog_tile_size"])' \
    "$WPS_CONFIG"
)"

ulimit -s unlimited

echo "===== Generate namelist.wps ====="

"$WOFS_PYTHON" \
    "$USHwofs/generate_geogrid_namelist.py" \
    --homewofs "$HOMEwofs" \
    --domain-config "$DOMAIN_CONFIG" \
    --wps-config "$WPS_CONFIG" \
    --output namelist.wps

cat namelist.wps

echo "===== Execute GEOGRID ====="

srun -n 1 "$EXECwofs/geogrid.exe"

if [[ ! -s geo_em.d01.nc ]]; then
    echo "[ERROR] geo_em.d01.nc was not generated"
    exit 1
fi

echo "===== Validate GEOGRID output ====="

ncdump -h geo_em.d01.nc > geo_em.header

ls -lh geo_em.d01.nc

if [[ "$SENDCOM" == "YES" ]]; then

    mkdir -p "$COMOUT_GEOGRID"

    for file in namelist.wps geo_em.d01.nc geo_em.header; do
        cp -p "$file" "$COMOUT_GEOGRID/${file}.tmp.$$"
        mv "$COMOUT_GEOGRID/${file}.tmp.$$" \
           "$COMOUT_GEOGRID/$file"
    done

    if [[ -f geogrid.log ]]; then
        cp -p geogrid.log "$COMOUT_GEOGRID/"
    fi

    touch "$COMOUT_GEOGRID/GEOGRID_SUCCESS"

fi

echo "[SUCCESS] GEOGRID output generated"
