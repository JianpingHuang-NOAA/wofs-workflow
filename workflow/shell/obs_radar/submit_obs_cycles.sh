#!/bin/bash
set -euo pipefail

if (( $# != 1 )); then
    echo "Usage: $0 /absolute/path/to/case.conf" >&2
    exit 2
fi

CONFIG=$(realpath -e -- "$1")
source "$CONFIG"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
cd "$ROOT"

: "${START:?}" "${END:?}" "${INTERVAL_MINUTES:?}" "${STATIONS:?}"
: "${RUN_ROOT:?}" "${RADAR_PYTHON:?}" "${RADAR_SOURCE:?}" "${BASE_CFG:?}"
: "${CLOUD_ROOT:?}" "${GEO:?}" "${LON:?}" "${LAT:?}"
: "${DBZ_VARIANCE:?}" "${LON_CONVENTION:?}"
: "${OBS_MAX_CONCURRENT:?}" "${MERGE_MAX_CONCURRENT:?}"

[[ "$INTERVAL_MINUTES" =~ ^[1-9][0-9]*$ ]]
[[ "$OBS_MAX_CONCURRENT" =~ ^[1-9][0-9]*$ ]]
[[ "$MERGE_MAX_CONCURRENT" =~ ^[1-9][0-9]*$ ]]
[[ "$RUN_ROOT" == /* ]]
test -x "$RADAR_PYTHON"
test -s "$GEO"
test -s "$BASE_CFG"
test -d "$RADAR_SOURCE/wofs_radar"

# A fresh root prevents mixing old results with a new array.
mkdir -- "$RUN_ROOT"
mkdir -- "$RUN_ROOT/logs" "$RUN_ROOT/stations"
cp -- "$CONFIG" "$RUN_ROOT/case.conf"

"$RADAR_PYTHON" - "$START" "$END" "$INTERVAL_MINUTES" "$STATIONS" "$RUN_ROOT" <<'PY'
from datetime import datetime, timedelta
from pathlib import Path
import re
import sys

start, end, interval, station_text, root = sys.argv[1:]
fmt = "%Y%m%d%H%M"
first, last = (datetime.strptime(value, fmt) for value in (start, end))
if first.strftime(fmt) != start or last.strftime(fmt) != end or last < first:
    raise SystemExit("Invalid analysis interval")
step = timedelta(minutes=int(interval))
if (last - first) % step:
    raise SystemExit("END must fall on the configured analysis schedule")

stations = station_text.replace(",", " ").split()
if not stations or len(set(stations)) != len(stations) or any(
    re.fullmatch(r"[A-Z0-9]{4}", station) is None for station in stations
):
    raise SystemExit("Provide unique four-character station IDs")

root = Path(root)
with (root / "cycles.txt").open("w") as cycles, (root / "tasks.tsv").open("w") as tasks:
    time = first
    while time <= last:
        cycle = time.strftime(fmt)
        cycles.write(cycle + "\n")
        for station in stations:
            tasks.write(f"{cycle}\t{station}\n")
        time += step
for station in stations:
    (root / "stations" / station).mkdir()
PY

# Snapshot the launchers used by this run.
cp workflow/shell/obs_radar/run_radar_obs_cycle.slurm "$RUN_ROOT/"
cp ush/merge_radar_obs_cycle.py "$RUN_ROOT/"

cat > "$RUN_ROOT/station.slurm" <<'SLURM'
#!/bin/bash
set -euo pipefail
run=$1
source "$run/case.conf"
IFS=$'\t' read -r cycle station < <(
    sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$run/tasks.tsv"
)
exec bash "$run/run_radar_obs_cycle.slurm" \
    "$cycle" "$station" "$LON" "$LAT" "$GEO" "$CLOUD_ROOT" \
    "$run/stations/$station" "$RADAR_SOURCE" "$RADAR_PYTHON" \
    "$BASE_CFG" "$DBZ_VARIANCE" "$LON_CONVENTION"
SLURM

cat > "$RUN_ROOT/merge.slurm" <<'SLURM'
#!/bin/bash
set -euo pipefail
run=$1
source "$run/case.conf"
cycle=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$run/cycles.txt")
read -r -a stations <<< "${STATIONS//,/ }"
mode=${DBZ_SOURCE:-wdssii}
case "$mode" in
    wdssii) output="$run/obs" ;;
    mrms) output="$run/wdssii-merged" ;;
    *) echo "DBZ_SOURCE must be wdssii or mrms" >&2; exit 2 ;;
esac

"$RADAR_PYTHON" "$run/merge_radar_obs_cycle.py" \
    "$run/stations" "$cycle" "$output" "${stations[@]}"

if [[ "$mode" == mrms ]]; then
    : "${MRMS_CFG:?Set MRMS_CFG for MRMS mode}"
    cd "$RADAR_SOURCE"
    MPLBACKEND=Agg "$RADAR_PYTHON" -u "$run/publish_mrms_cycle.py" \
        "$cycle" "$LON" "$LAT" "$GEO" "$MRMS_CFG" \
        "$output/$cycle" "$run/obs"
fi
SLURM

mode=${DBZ_SOURCE:-wdssii}
case "$mode" in
    wdssii) ;;
    mrms)
        test -s "${MRMS_CFG:?Set MRMS_CFG for MRMS mode}"
        cp ush/publish_mrms_cycle.py "$RUN_ROOT/"
        ;;
    *) echo "DBZ_SOURCE must be wdssii or mrms" >&2; exit 2 ;;
esac

tasks=$(wc -l < "$RUN_ROOT/tasks.tsv")
cycles=$(wc -l < "$RUN_ROOT/cycles.txt")
station_job=$(sbatch --parsable --account=wofs --partition=u1-compute \
    --job-name=wofs_radar_station --ntasks=1 --cpus-per-task=1 \
    --mem=16G --time=00:30:00 \
    --array="0-$((tasks - 1))%$OBS_MAX_CONCURRENT" \
    --output="$RUN_ROOT/logs/station-%A_%a.out" \
    --error="$RUN_ROOT/logs/station-%A_%a.err" \
    "$RUN_ROOT/station.slurm" "$RUN_ROOT")
station_job=${station_job%%;*}
printf 'station\t%s\n' "$station_job" | tee "$RUN_ROOT/jobs.tsv"

merge_job=$(sbatch --parsable --account=wofs --partition=u1-compute \
    --job-name=wofs_radar_merge --ntasks=1 --cpus-per-task=1 \
    --mem=16G --time=00:30:00 --dependency="afterok:$station_job" \
    --array="0-$((cycles - 1))%$MERGE_MAX_CONCURRENT" \
    --output="$RUN_ROOT/logs/merge-%A_%a.out" \
    --error="$RUN_ROOT/logs/merge-%A_%a.err" \
    "$RUN_ROOT/merge.slurm" "$RUN_ROOT")
printf 'merge\t%s\n' "${merge_job%%;*}" | tee -a "$RUN_ROOT/jobs.tsv"
printf 'Run directory: %s\n' "$RUN_ROOT"
