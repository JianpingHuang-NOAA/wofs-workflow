#!/bin/bash

# The grouped radar helper owns DATA for these three J-jobs.
case "${0##*/}" in
    JWOFS_RADAR_DOWNLOAD|JWOFS_RADAR_WDSSII|JWOFS_RADAR_PROCESSING)
        ;;
    *)
        # OBS_RADAR job-local data and logs.
        export DATAROOT="${DATAROOT:-${TMPDIR:-/tmp}}"
        export DATA="${DATA:-${DATAROOT%/}/${0##*/}.${SLURM_JOB_ID:-${jobid:-$$}}}"
        export LOG_DIR="${LOG_DIR:-${DATA%/}/logs}"

        if [[ "$DATAROOT" != /* || "$DATA" != /* || "$LOG_DIR" != /* ]]; then
            printf 'ERROR: DATAROOT, DATA, and LOG_DIR must be absolute paths.\n' >&2
            return 1
        fi

        mkdir -p -- "$DATA" "$LOG_DIR" || return 1
        export TMPDIR="$DATA"
        printf 'DATAROOT=%s\nDATA=%s\nLOG_DIR=%s\n' "$DATAROOT" "$DATA" "$LOG_DIR"
        ;;
esac

# Shared environment for JWOFS_RADAR jobs.
: "${HOMEwofs:?ERROR: HOMEwofs must be defined}"
export HOMEwofs
export EXECwofs="${EXECwofs:-$HOMEwofs/exec}"
export PARMwofs="${PARMwofs:-$HOMEwofs/parm}"
export USHwofs="${USHwofs:-$HOMEwofs/ush}"
export FIXwofs="${FIXwofs:-$HOMEwofs/fix}"
export SORCwofs="${SORCwofs:-$HOMEwofs/sorc}"

if [[ -n "${CDATE:-}" ]]; then
    if [[ ! "$CDATE" =~ ^[0-9]{10}$ ]]; then
        echo "ERROR: CDATE must be YYYYMMDDHH" >&2
        exit 1
    fi
    export PDY="${PDY:-${CDATE:0:8}}"
    export cyc="${cyc:-${CDATE:8:2}}"
elif [[ -n "${PDY:-}" && -n "${cyc:-}" ]]; then
    export CDATE="${PDY}${cyc}"
fi

if [[ -n "${CDATE:-}" && "$CDATE" != "${PDY}${cyc}" ]]; then
    echo "ERROR: CDATE does not agree with PDY and cyc" >&2
    exit 1
fi

# Derive the case only when the caller has supplied no case arguments.
# An explicit CASE_YAML or --prepare invocation is handled by the ex-script.
if [[ -z "${RADAR_CASE_YAML:-}" ]] &&
   { (( $# == 0 )) || { (( $# == 1 )) && [[ "${1:-}" == --local-inputs ]]; }; }; then
    : "${COMROOT:?ERROR: COMROOT must be defined}"
    : "${RUN:?ERROR: RUN must be defined}"
    : "${PDY:?ERROR: Set PDY or CDATE}"
    : "${cyc:?ERROR: Set cyc or CDATE}"
    : "${domain:?ERROR: domain must be defined}"
    com_version="${RADAR_COM_VERSION:-${wofs_ver:-}}"
    : "${com_version:?ERROR: Set RADAR_COM_VERSION or wofs_ver}"

    if [[ "$COMROOT" != /* || ! "$PDY" =~ ^[0-9]{8}$ ||
          ! "$cyc" =~ ^(0[0-9]|1[0-9]|2[0-3])$ ||
          ! "$domain" =~ ^[A-Z0-9_]+$ ]]; then
        echo "ERROR: Invalid COMROOT, PDY, cyc, or domain" >&2
        exit 1
    fi

    export RADAR_CASE_YAML="${COMROOT%/}/wofs/${com_version}/${RUN}.${PDY}/${cyc}/${domain}/config.yaml"
fi
