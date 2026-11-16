#!/bin/bash
#
# Load WoFS DOMAIN_SETUP configuration.
#
# Usage:
#   source "${HOMEwofs}/ush/load_wofs_python.sh"
#   source "${HOMEwofs}/ush/load_domain_config.sh"
#

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "ERROR: This script must be sourced." >&2
    exit 1
fi

_wofs_load_domain_config() {

    local root
    local assignments

    root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." \
        && pwd -P)" || return 1

    export HOMEwofs="${HOMEwofs:-$root}"

    export DOMAIN_SETUP_CONFIG="${DOMAIN_SETUP_CONFIG:-\
${HOMEwofs}/parm/domain_setup/config.yaml}"

    if [[ ! -r "$DOMAIN_SETUP_CONFIG" ]]; then
        echo "ERROR: Cannot read $DOMAIN_SETUP_CONFIG" >&2
        return 1
    fi

    # Require the initialized shared WoFS Python runtime.
    if [[ "${WOFS_PYTHON:-}" != /* ||
          ! -x "${WOFS_PYTHON:-}" ||
          "${IC_PREP_PYTHON:-}" != "${WOFS_PYTHON:-}" ||
          "${PYTHONNOUSERSITE:-}" != 1 ||
          -n "${PYTHONPATH+x}" ||
          -n "${PYTHONHOME+x}" ]]; then

        echo "ERROR: Initialize shared WoFS Python first." >&2
        return 1
    fi

    assignments="$(
        "$WOFS_PYTHON" \
            "$HOMEwofs/ush/load_domain_config.py" \
            "$DOMAIN_SETUP_CONFIG"
    )" || {
        echo "ERROR: DOMAIN_SETUP configuration failed." >&2
        return 1
    }

    eval "$assignments" || return 1

    echo "[PASS] DOMAIN_SETUP configuration loaded"
    echo "Config : $DOMAIN_SETUP_CONFIG"
    echo "CDATE  : $CDATE"
    echo "Region : $region"
    echo "Center : $CENTER_LAT $CENTER_LON"
    echo "Width  : $WIDTH_KM km"
    echo "WORK   : $DOMAIN_WORK_ROOT"
    echo "COM    : $COMOUT_DOMAIN"
    echo "SENDCOM: $SENDCOM"
    echo "KEEPDATA: $KEEPDATA"

    return 0
}

if _wofs_load_domain_config; then
    unset -f _wofs_load_domain_config
    return 0
else
    unset -f _wofs_load_domain_config
    return 1
fi
