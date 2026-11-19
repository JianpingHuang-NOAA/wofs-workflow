# OBS_RADAR workflow

The three Slurm wrappers in `workflow/shell/obs_radar` call their corresponding
`jobs/JWOFS_RADAR_*` and `scripts/exwofs_radar_*.sh` entry points. The wrappers
use the radar version file and the Ursa radar module to load the YAML runtime.
Install radar software using `sorc/build_obs_radar.sh --all`. That installer
manages the RADAR external, compiled Python extensions and `exec/WDSSII`.
The controller uses the tested observation interpreter and source specified
in the observation base configuration.

1. Copy `parm/obs_radar/config.yaml` and set absolute case paths. Choose a new
   run root whose parent already exists. The station list must match the
   list passed to the WDSS-II launcher.
2. For the CSP retrospective regression, leave `download_command: []` and
   point `nexrad_root` at the archived `YYYYMMDD/STATION/*V06` event layout.
   A configured downloader receives `NEXRAD_ROOT`, `CDATE`, `DOMAIN`,
   `RADAR_STATIONS`, `RADAR_START` and `RADAR_END`. Its exit status must
   reflect download success. The archive preflight checks for at least one
   nonempty Level II scan per station. The downloader or archive inventory
   must establish coverage for the requested schedule.
3. Install the Ursa-validated WDSS-II launcher and its worker scripts.
   Its submission adapter receives the same environment and writes one JSON
   object to stdout after submitting both the site array and dependent
   staging job. Send diagnostics to stderr. The adapter must report the
   actual staging job ID and absolute staged directory for this submission.

   ```json
   {"stage_job_id": 12345, "cloud_root": "/absolute/wdssii/run/CLOUD_OBS"}
   ```

4. Set `obs_launcher` to the tested `submit_obs_cycles.sh` and
   `obs_base_config` to the validated WDSS-II case configuration. It supplies
   the domain file, gridding settings, tested Python and concurrency.
5. From the worktree, run

   ```bash
   bash workflow/shell/obs_radar/submit_radar.sh /absolute/case.yaml /absolute/run_root
   ```

   The controller waits for archive preparation and WDSS-II submission,
   then schedules observation submission after successful WDSS-II staging.
   The observation launcher submits the station and merge arrays.
6. Check the station and merge IDs in `processing/jobs.tsv`. Final cycle
   manifests and NetCDF products are under `processing/obs/<cycle>/`.
   For the CSP regression, compare DBZ and VR counts at 15:00, 15:15, and
   15:30 UTC with 3218/2795, 3500/3226, and 3101/2841 respectively.

Use the tested observation Slurm launcher from the Ursa worktree for
the end-to-end regression. The WDSS-II receipt adapter is included here.

## Connect the tested WDSS-II launcher

In `submit_wdssii_array.sh`, immediately after the successful staging
`sbatch --parsable` call, add the following hook. Set `stage_job_id` to
the variable that receives **that staging submission's** parsable result.
The hook is inactive during standalone submissions and dry runs.

```bash
if [[ -n "${WOFS_WDSSII_RECEIPT:-}" ]]; then
    "$WOFS_WDSSII_RECEIPT_PYTHON" "$WOFS_WDSSII_RECEIPT_WRITER" \
        "$WOFS_WDSSII_RECEIPT" "$stage_job_id" "$CLOUD_ROOT" || exit 1
fi
```

The repository adapter `ush/submit_wdssii_with_receipt.sh` invokes the
launcher with `CDATE DOMAIN ALL` and routes its regular output to stderr.
A missing receipt causes the controller to stop before scheduling processing.
Inspect the submission log before retrying because the WDSS-II jobs may
already have been submitted.

## Submit the three-cycle CSP regression

```bash
bash workflow/shell/obs_radar/submit_csp_regression.sh \
    /absolute/new/run_root \
    /absolute/archived/NEXRAD \
    /absolute/wdssii/submit_wdssii_array.sh \
    "$PWD/workflow/shell/obs_radar/submit_obs_cycles.sh" \
    /absolute/validated/run/case.conf \
    /absolute/csp/com
```

The runner uses the 20 CSP stations and 15:00–15:30 UTC schedule. Point the
base configuration at the tested frdd-wofs-obs-radar_OSTI-derived runtime.
The regression exercises archive reuse, WDSS-II staging, and observation
generation. The general YAML configuration accepts a site downloader via
`download_command`. MRMS acquisition and processing require their own
case-specific integration and regression.
