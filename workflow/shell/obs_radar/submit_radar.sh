#!/bin/bash
set -euo pipefail

if (( $# != 2 )); then
    echo "Usage: $0 /absolute/case.yaml /absolute/run_root" >&2
    exit 2
fi

shell_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
export HOMEwofs=$(cd -- "$shell_dir/../../.." && pwd -P)
config=$(realpath -e -- "$1")
run_root=$(realpath -m -- "$2")

# The controller uses the same YAML runtime as the stage wrappers.
if [[ "${RADAR_LOAD_MODULES:-YES}" == YES ]]; then
    source "$HOMEwofs/versions/obs_radar.ver"
    module use "$HOMEwofs/modulefiles"
    module load "$wofs_modulefile"
fi
"${RADAR_CONFIG_PYTHON:-python3}" - "$config" "$run_root" <<'PY'
from pathlib import Path
import sys
import yaml

config, root = sys.argv[1:]
configured = Path(yaml.safe_load(Path(config).read_text())["run_root"])
if not configured.is_absolute() or configured.resolve() != Path(root):
    raise SystemExit("run_root must match the absolute path in case.yaml")
PY

mkdir -- "$run_root"
cp -- "$config" "$run_root/case.yaml"
config="$run_root/case.yaml"

sbatch --wait --parsable --output="$run_root/download-%j.out" \
    "$shell_dir/jswofs_radar_download.sh" "$config"
sbatch --wait --parsable --output="$run_root/wdssii-%j.out" \
    "$shell_dir/jswofs_radar_wdssii.sh" "$config"

stage_job=$("${RADAR_CONFIG_PYTHON:-python3}" -c \
    'import json, sys; print(json.load(open(sys.argv[1]))["stage_job_id"])' \
    "$run_root/wdssii.json")
[[ "$stage_job" =~ ^[1-9][0-9]*$ ]]
sbatch --parsable --dependency="afterok:$stage_job" --kill-on-invalid-dep=yes \
    --output="$run_root/processing-%j.out" \
    "$shell_dir/jswofs_radar_processing.sh" "$config"
