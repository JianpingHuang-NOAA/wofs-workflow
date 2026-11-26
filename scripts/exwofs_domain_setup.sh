#!/bin/bash
#
# WoFS v1.0 DOMAIN_SETUP execution script
#

set -euo pipefail

: "${HOMEwofs:?HOMEwofs is required}"
# =========================================================
# Controller mode: submit all enabled domains.
# =========================================================

if [[ "${DOMAIN_SETUP_MODE:-worker}" == controller ]]; then

    : "${DOMAIN_SETUP_CONFIG:?DOMAIN_SETUP_CONFIG is required}"

    echo "===== DOMAIN_SETUP: Submit enabled domains ====="

    exec python3         "${HOMEwofs}/ush/submit_domain_setup.py"         --config "${DOMAIN_SETUP_CONFIG}"         "$@"

fi

# =========================================================
# Worker mode: execute domain-specific processing.
# =========================================================

: "${WOFS_PYTHON:?WOFS_PYTHON is required}"
: "${DATA:?DATA is required}"
: "${COMOUT_DOMAIN:?COMOUT_DOMAIN is required}"

USH="${HOMEwofs}/ush"

cd "${DATA}"

echo "===== Step 1: Generate domain and radar settings ====="

"${WOFS_PYTHON}" "${RADAR_SCRIPT}" \
    --latlon "${CENTER_LAT}" "${CENTER_LON}" \
    --width "${WIDTH_KM}" \
    --region "${region}" \
    --event "${PDY}" \
    --start-hour "${cyc}" \
    --station-dir "${STATION_DIR}" \
    --output-dir "${DATA}" \
    --plot

echo
echo "===== Step 2: Generate runtime configuration ====="

"${WOFS_PYTHON}" \
    "${USH}/generate_domain_runtime_config.py"

echo
echo "===== Step 3: Validate domain products ====="

products=(
    "${RADAR_CONFIG}"
    "${DOMAIN_PLOT}"
    "${RUNTIME_CONFIG}"
)

for name in "${products[@]}"; do

    src="${DATA}/${name}"

    if [[ ! -s "${src}" ]]; then
        echo "[ERROR] Missing or empty product: ${src}" >&2
        exit 1
    fi

    echo "[PASS] ${name}"
done

echo
echo "===== Step 4: Publish domain products ====="

if [[ "${SENDCOM}" == YES ]]; then

    mkdir -p "${COMOUT_DOMAIN}"

    # Serialize publication to the same COM domain.
    exec 8>>"${COMOUT_DOMAIN}/.domain_publish.lock"

    if ! flock -n 8; then
        echo "[ERROR] COM domain publication is locked" >&2
        exit 75
    fi

    publish_file() (

        set -euo pipefail

        local_src="$1"
        local_dst="$2"

        tmp="$(mktemp "${COMOUT_DOMAIN}/.publish.XXXXXXXX")"

        trap 'rm -f -- "$tmp"' EXIT

        cp -p -- "${local_src}" "${tmp}"

        cmp -s -- "${local_src}" "${tmp}"

        mv -fT -- "${tmp}" "${local_dst}"

        cmp -s -- "${local_src}" "${local_dst}"

        echo "[PASS] Published ${local_dst}"
    )

    for name in "${products[@]}"; do

        publish_file \
            "${DATA}/${name}" \
            "${COMOUT_DOMAIN}/${name}"

    done

    radar_template="${OBS_RADAR_TEMPLATE:-${HOMEwofs}/parm/obs_radar/config.template.yaml}"
    if [[ -e "${radar_template}" || -L "${radar_template}" || -n "${OBS_RADAR_TEMPLATE:-}" ]]; then
        "${WOFS_PYTHON}" "${USH}/publish_obs_radar_config.py" \
            "${radar_template}" "${COMOUT_DOMAIN}" "${CDATE}" "${region}"
    fi

else

    echo "SENDCOM=NO: COM publication skipped"

fi

echo
echo "======================================================"
echo " DOMAIN_SETUP SUCCESS"
echo " CDATE  = ${CDATE}"
echo " region = ${region}"
echo " WORK   = ${DATA}"
echo " COM    = ${COMOUT_DOMAIN}"
echo "======================================================"

