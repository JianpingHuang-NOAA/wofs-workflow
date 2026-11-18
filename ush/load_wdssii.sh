#!/bin/bash
#=======================================================================
# Initialize the WoFS WDSS-II runtime environment.
#
# Usage:
#   source "$HOMEwofs/ush/load_wdssii.sh"
#=======================================================================

if [[ -z "${HOMEwofs:-}" ]]; then

    echo "[ERROR] HOMEwofs is not defined" >&2

    return 1

fi

export TZ=UTC

export WDSSII_HOME="${WDSSII_HOME:-$HOMEwofs/exec/WDSSII}"

if [[ ! -f "$WDSSII_HOME/INSTALL_SUCCESS" ]]; then

    echo "[ERROR] WDSS-II installation is incomplete" >&2

    return 1

fi

if [[ -z "${WDSSII_SSL_HOME:-}" ]]; then

    export WDSSII_SSL_HOME="$(cat "$WDSSII_HOME/SSL_HOME")"

fi

if [[ ! -d "$WDSSII_SSL_HOME/lib" ]]; then

    echo "[ERROR] Missing OpenSSL compatibility environment" >&2

    return 1

fi

export WDSSPATH="$WDSSII_HOME"

export W2_CONFIG_LOCATION="$WDSSII_HOME/w2config"

export PATH="$WDSSII_HOME/bin:$PATH"

export LD_LIBRARY_PATH="$WDSSII_HOME/lib:$WDSSII_SSL_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

export PERL5LIB="$WDSSII_HOME/bin${PERL5LIB:+:$PERL5LIB}"

echo "[PASS] WDSS-II runtime initialized"
