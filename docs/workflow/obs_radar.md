# OBS_RADAR scheduler tasks

The scheduler submits the tasks and owns their dependencies. A submitted
wrapper calls its J-job, execution script and Python utility. Each task
finishes its assigned work synchronously. The production chain uses no
manual submit drivers or submission receipts.

| Launcher | Argument | Purpose |
| --- | --- | --- |
| `jswofs_radar_download.sh` | `CASE_YAML` | Acquire and publish raw NEXRAD and MRMS inputs to DCOM |
| `jswofs_radar_wdssii.sh` | `CASE_YAML` | Convert radar data and publish the staged WDSS-II inputs to COM |
| `jswofs_radar_processing.sh` | `CASE_YAML` | Process and publish each radar observation cycle |

Set HOMEwofs to the checkout root. WDSS-II uses ush/load_wdssii.sh, with the
default installation under exec/WDSSII. Set radar_python, radar_source,
radar_app_config and wdssii_worker to verified site inputs. The Level II worker
must support the five positional arguments from the legacy runwdssii.py
and complete synchronously under the assigned task. Its own configuration
and any runtime data must be available on the execution host. Inspect legacy
worker-internal absolute paths before using the worker operationally.

For the 2026110215 retrospective, DOMAIN_SETUP uses
`parm/obs_radar/config.template.yaml` to publish a per-domain `config.yaml`
in cycle COM. The CSP example runs at 15:00, 15:15, and 15:30 UTC on
2026-11-02. The case YAML provides the radar stations, domain geometry,
analysis schedule, and publication root.

Set `DATAROOT` to a writable scratch directory and pass the same case
YAML to all three launchers. Wait for each job to succeed before submitting
the next. Each grouped job creates its own `DATA` directory. Set
`KEEP_DATA=YES` to retain successful job scratch for debugging.

Download publishes the raw NEXRAD and MRMS inputs to DCOM. WDSS-II publishes
the staged NetCDF inputs to `OBS_RADAR/wdssii` in domain COM. Processing
reads those inputs and publishes `HHMM-vrobs.nc`, `HHMM-dbzobs.nc`, and
`cycle_complete.json` under `OBS_RADAR/<cycle>/`. Use fresh DCOM and COM
destinations for a clean retest.

The WDSS-II entry in the legacy C-shell driver processes Level II scans
and stages Velocity and ReflectivityQC by UTC date. These staged fields
feed radial-velocity processing, including its reflectivity masking.
The separate mosaic reflectivity routine reads the MRMS feed and supplies
the final DBZ file. The legacy Python driver combines those operations
inside one invocation. This scheduler layout calls the science routines
directly and checks their outputs before advancing.
