# OBS_RADAR scheduler tasks

The scheduler submits the tasks and owns their dependencies. A submitted
wrapper calls its J-job, execution script and Python utility. Each task
finishes its assigned work synchronously. The production chain uses no
manual submit drivers or submission receipts.

| Wrapper in workflow/shell/obs_radar | Arguments | Work |
|---|---|---|
| jswofs_radar_domains.sh | OUTPUT_DIR SHARED_YAML | Generate one task config per DOMAIN_SETUP domain |
| jswofs_radar_download.sh | CASE_YAML | Run the site acquisition command if configured, then check archives |
| jswofs_radar_wdssii.sh | CASE_YAML STATION | Decode and quality-control the configured station window |
| jswofs_radar_stage.sh | CASE_YAML | Stage all stations after the WDSS-II tasks succeed |
| jswofs_radar_processing.sh | CASE_YAML YYYYMMDDHHMM STATION | Generate the station VR file |
| jswofs_radar_merge.sh | CASE_YAML YYYYMMDDHHMM | Combine station VR and generate mosaic MRMS DBZ |
| jswofs_radar_publish.sh | CASE_YAML | After all merges succeed, publish that domain to COM |

Set HOMEwofs to the checkout root. WDSS-II uses ush/load_wdssii.sh, with the
default installation under exec/WDSSII. Set radar_python, radar_source,
radar_app_config and wdssii_worker to verified site inputs. The Level II worker
must support the five positional arguments from the legacy runwdssii.py
and complete synchronously under the assigned task. Its own configuration
and any runtime data must be available on the execution host. Inspect legacy
worker-internal absolute paths before using the worker operationally.

For the 2026110215 retrospective, add cdate "2026110215", start "202611021500",
end "202611021530", and a fresh absolute run_root to a copy of
parm/obs_radar/config.yaml in the cycle COM directory. Run the domain
preparation wrapper with a fresh OUTPUT_DIR. Use one generated case YAML
per domain. Its stations and geometry come from DOMAIN_SETUP. Schedule one
merge per time, with dependencies on all station-time tasks for that time.
The same-day WDSS-II window with 15 minutes of padding is 14:45–15:45 UTC.
Use local archived inputs. The MRMS feed is a dated directory template with
a literal {} replaced by the UTC date. Use the validated radar application
INI with its MRMS and RASS settings and the installed GRIB2-capable reader.
The archive check verifies the presence of GRIB2 data per date. The science
worker must produce the requested cycle before the merge can publish it.

Products are written to run_root/processing/obs/CYCLE. Each successful
cycle has HHMM-vrobs.nc, HHMM-dbzobs.nc and cycle_complete.json.
The publication task needs publish_root and refuses to overwrite an
existing domain OBS_RADAR directory.

The WDSS-II entry in the legacy C-shell driver processes Level II scans
and stages Velocity and ReflectivityQC by UTC date. These staged fields
feed radial-velocity processing, including its reflectivity masking.
The separate mosaic reflectivity routine reads the MRMS feed and supplies
the final DBZ file. The legacy Python driver combines those operations
inside one invocation. This scheduler layout calls the science routines
directly and checks their outputs before advancing.
