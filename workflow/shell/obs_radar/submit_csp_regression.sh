#!/bin/bash
set -euo pipefail

if (( $# != 6 )); then
    echo "Usage: $0 RUN_ROOT NEXRAD_ROOT WDSSII_LAUNCHER OBS_LAUNCHER OBS_BASE_CONFIG COMROOT" >&2
    exit 2
fi

shell_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
export HOMEwofs=$(cd -- "$shell_dir/../../.." && pwd -P)
run_root=$(realpath -m -- "$1")
nexrad=$(realpath -e -- "$2")
wdssii=$(realpath -e -- "$3")
obs=$(realpath -e -- "$4")
base=$(realpath -e -- "$5")
export COMROOT
COMROOT=$(realpath -e -- "$6")
export WOFS_VERSION=v1.0
unset RADAR_LIST_OVERRIDE

# JSON is accepted by the YAML loader. This avoids shell interpolation in paths.
config=$(mktemp)
trap 'rm -f -- "$config"' EXIT
"${RADAR_CONFIG_PYTHON:-python3}" - "$config" "$run_root" "$nexrad" "$wdssii" "$obs" "$base" "$HOMEwofs" <<'PY'
import json
from pathlib import Path
import sys

config, root, nexrad, wdssii, obs, base, home = sys.argv[1:]
case = {
    "cdate": "2026110215",
    "domain": "CSP",
    "start": "202611021500",
    "end": "202611021530",
    "interval_minutes": 15,
    "stations": "KAMA KDDC KDYX KEAX KFDR KFWS KGLD KICT KINX KLBB KLZK KMAF KSGF KSHV KSJT KSRX KTLX KTWX KUEX KVNX".split(),
    "run_root": root,
    "nexrad_root": nexrad,
    "download_command": [],
    "wdssii_command": [str(Path(home) / "ush/submit_wdssii_with_receipt.sh"), wdssii],
    "obs_launcher": obs,
    "obs_base_config": base,
}
Path(config).write_text(json.dumps(case, indent=2) + "\n")
PY
export SBATCH_ACCOUNT="${SBATCH_ACCOUNT:-wofs}"
bash "$shell_dir/submit_radar.sh" "$config" "$run_root"
