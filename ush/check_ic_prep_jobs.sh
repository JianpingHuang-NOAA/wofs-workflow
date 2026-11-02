
#!/usr/bin/env bash
#
# WoFS v1.0 IC_PREP - GRIB2 output validation
#
# Checks the published wrfnat GRIB2 file for each ensemble member.
#
# Usage:
#   bash ush/check_ic_prep_jobs.sh
#   bash ush/check_ic_prep_jobs.sh /path/to/config.yaml
#
# Exit status:
#   0 = All ensemble members have readable GRIB2 files
#   1 = One or more members failed validation
#   2 = Configuration or required command error
#

set -euo pipefail

# ------------------------------------------------------------
# Locate workflow and configuration
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMEwofs="${HOMEwofs:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

CONFIG="${1:-${IC_PREP_CONFIG:-${HOMEwofs}/parm/ic_prep/config.yaml}}"

if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: Configuration file not found: ${CONFIG}" >&2
    exit 2
fi

# Use a configurable Python interpreter with PyYAML.
if [[ -n "${IC_PREP_PYTHON:-}" ]]; then
    PYTHON="${IC_PREP_PYTHON}"
elif [[ -n "${WOFS_PYTHON:-}" ]]; then
    PYTHON="${WOFS_PYTHON}"
else
    PYTHON="python3"
fi

if ! "${PYTHON}" -c 'import yaml' >/dev/null 2>&1; then
    echo "ERROR: Python interpreter lacks PyYAML: ${PYTHON}" >&2
    echo "Set IC_PREP_PYTHON to an interpreter with PyYAML." >&2
    exit 2
fi

if ! command -v wgrib2 >/dev/null 2>&1; then
    echo "ERROR: wgrib2 is not available in PATH." >&2
    echo "Load the appropriate Ursa module before running." >&2
    exit 2
fi

# ------------------------------------------------------------
# Read YAML and resolve output paths
# ------------------------------------------------------------
# Only explicitly defined values are used. INIT_TIME comes
# from YAML, not from an external environment variable.
#
# The Python helper emits shell-safe assignments.
# ------------------------------------------------------------
if ! config_exports="$("${PYTHON}" - "${CONFIG}" "${HOMEwofs}" <<'PY'
import os
import re
import shlex
import sys
from datetime import datetime, timedelta

import yaml

config_file = sys.argv[1]
homewofs = sys.argv[2]

with open(config_file, "r", encoding="utf-8") as handle:
    cfg = yaml.safe_load(handle)

workflow = cfg["workflow"]
paths = cfg["paths"]
files = cfg["files"]

init_time = str(workflow["INIT_TIME"]).strip()

if not re.fullmatch(r"\d{10}", init_time):
    raise ValueError("workflow.INIT_TIME must be YYYYMMDDHH")

init_dt = datetime.strptime(init_time, "%Y%m%d%H")
forecast_hour = int(workflow.get("forecast_hour", 1))
ens_size = int(workflow.get("ens_size", 36))

if forecast_hour < 0:
    raise ValueError("forecast_hour cannot be negative")

if ens_size <= 0:
    raise ValueError("ens_size must be positive")

valid_dt = init_dt + timedelta(hours=forecast_hour)

values = {
    "HOMEwofs": homewofs,
    "INIT_TIME": init_time,
    "PDY": valid_dt.strftime("%Y%m%d"),
    "cyc": valid_dt.strftime("%H"),
    "FCST_TIME": f"{forecast_hour:02d}",
    "ENS_SIZE": str(ens_size),
}

values["DATAROOT"] = str(paths["dataroot"])

pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")

def expand(template, context):
    value = str(template)

    for _ in range(12):
        updated = pattern.sub(
            lambda m: str(context[m.group(1)])
            if m.group(1) in context else m.group(0),
            value,
        )
        if updated == value:
            break
        value = updated

    unresolved = pattern.findall(value)
    if unresolved:
        raise ValueError(
            "Unresolved configuration variables: "
            + ", ".join(sorted(set(unresolved)))
        )

    return value

values["COMROOT"] = expand(paths["comroot"], values)
values["COMOUT"] = expand(paths["comout"], values)
values["INPUT_OUTPUT_DIR"] = expand(
    paths["input_output_dir"], values
)

# Filename is resolved per member in Bash.
values["WRFNAT_TEMPLATE"] = str(files["final_wrfnat"])

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")

PY
)"; then
    echo "ERROR: Failed to load IC_PREP configuration." >&2
    exit 2
fi

eval "${config_exports}"

# ------------------------------------------------------------
# Print configuration
# ------------------------------------------------------------
echo "============================================================"
echo "WoFS v1.0 IC_PREP - GRIB2 Completion Check"
echo "============================================================"
echo "Configuration : ${CONFIG}"
echo "INIT_TIME     : ${INIT_TIME}"
echo "Valid time    : ${PDY}${cyc}"
echo "Forecast hour : ${FCST_TIME}"
echo "Members       : ${ENS_SIZE}"
echo "Output dir    : ${INPUT_OUTPUT_DIR}"
echo "wgrib2        : $(command -v wgrib2)"
echo "============================================================"

# ------------------------------------------------------------
# Validate each ensemble member
# ------------------------------------------------------------
passed=0
failed=0

printf '\n%-8s %-12s %-12s %-12s %s\n' \
    "MEMBER" "EXISTS" "READABLE" "RECORDS" "RESULT"

printf '%s\n' \
    "----------------------------------------------------------------"

for ((member=1; member<=ENS_SIZE; member++)); do

    printf -v MEMBER02 '%02d' "${member}"
    printf -v MEMBER04 '%04d' "${member}"

    # Expand member-dependent filename placeholders.
    filename="${WRFNAT_TEMPLATE}"
    filename="${filename//\$\{MEMBER04\}/${MEMBER04}}"
    filename="${filename//\$\{MEMBER02\}/${MEMBER02}}"
    filename="${filename//\$\{FCST_TIME\}/${FCST_TIME}}"
    filename="${filename//\$\{INIT_TIME\}/${INIT_TIME}}"

    output_file="${INPUT_OUTPUT_DIR}/mem${MEMBER02}/${filename}"

    exists="NO"
    readable="NO"
    records=0
    result="FAIL"

    if [[ -s "${output_file}" ]]; then
        exists="YES"

        # Generate an inventory without loading the full
        # GRIB2 data into memory.
        if inventory="$(wgrib2 "${output_file}" -s 2>/dev/null)"; then

            records="$(
                printf '%s\n' "${inventory}" |
                awk 'NF {count++} END {print count+0}'
            )"

            if ((records > 0)); then
                readable="YES"
                result="PASS"
                ((passed+=1))
            else
                ((failed+=1))
            fi
        else
            ((failed+=1))
        fi
    else
        ((failed+=1))
    fi

    printf '%-8s %-12s %-12s %-12s %s\n' \
        "${MEMBER04}" "${exists}" "${readable}" \
        "${records}" "${result}"

    if [[ "${result}" == "FAIL" ]]; then
        echo "  File: ${output_file}"
    fi

done

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "============================================================"
echo "IC_PREP GRIB2 VALIDATION SUMMARY"
echo "============================================================"
printf 'Total members : %d\n' "${ENS_SIZE}"
printf 'Passed        : %d\n' "${passed}"
printf 'Failed        : %d\n' "${failed}"
echo "============================================================"

if ((failed == 0 && passed == ENS_SIZE)); then
    echo "SUCCESS: All ${ENS_SIZE} IC_PREP GRIB2 files are available and readable."
    exit 0
else
    echo "ERROR: ${failed} IC_PREP members failed GRIB2 validation."
    exit 1
fi
