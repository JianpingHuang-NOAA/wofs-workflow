# WoFS v1.0 BC_PREP Configuration

## 1. Overview

The WoFS v1.0 BC_PREP workflow uses a shared YAML configuration
and a common shell configuration loader.

Configuration files:

- parm/bc_prep/config.yaml
- ush/load_bc_prep_config.sh

The configuration supports five stage-specific workflow components:

- UNGRIB
- METGRID
- REAL
- MEAN
- PERTURB

The configuration policy preserves the validated scientific
implementation while allowing runtime resources and data locations
to be configured independently.

## 2. Configuration policy

Configuration parameters are divided into three categories:

1. Fixed scientific and workflow constraints.
2. Configurable runtime resources and data locations.
3. Documentary placeholders.

Fixed YAML constraints must match the supported WoFS v1.0
implementation. Unsupported values are rejected rather than
silently ignored.

For configurable settings, nonempty environment variables take
precedence over YAML values. Empty environment variables fall
back to the YAML defaults.

Invalid fixed YAML settings cannot be masked by environment
overrides.

## 3. Fixed scientific and workflow constraints

| YAML setting | Supported value |
|---|---|
| paths.bc_subdir | WoF_BC |
| paths.gefs_subdir | gefs |
| paths.hrrr_subdir | pert_hrrr |
| gefs.ensemble_size | 18 |
| gefs.cycles | 11 |
| gefs.interval_hours | 3 |
| gefs.initialization_lag_hours | 6 |
| sst.cycle | "06" |
| sst.source_lag_from_gefs_init_hours | 24 |
| sst.source_hour | "00" |
| ungrib.members | 18 |
| metgrid.namelist | namelist.wps.GFSENS |
| real.namelist | real.nl.32and4levels |
| mean.ensemble_size | 18 |
| mean.executable | average_netcdf_files_parallel.x |
| perturb.ncl_script | perturb_hrrr.ncl |
| perturb.netcdf_to_grib_script | netcdf_to_grib.py |
| perturb.search_before_hours | 6 |
| perturb.search_after_hours | 6 |

The loader validates both the values and data types of these
19 fixed YAML settings.

These constraints describe the supported YAML configuration.
They do not remove existing stage-specific environment overrides,
such as the REAL namelist override.

## 4. GEFS and SST timing

GEFS and SST source timing must remain independent.

For a BC_PREP cycle identified by CDATE:

- GEFS initialization time is CDATE minus 6 hours.
- GEFS forecast hours range from 6 through 36 hours.
- The forecast interval is 3 hours.
- Eleven GEFS forecast times are processed.
- The SST reference date is derived from the GEFS initialization
  time minus 24 hours.
- The SST source file is selected at 00 UTC on that date.

Example:

    CDATE:               2026111212
    GEFS initialization: 2026111206
    GEFS forecast hours: 06, 09, ..., 36
    SST reference time:  2026111106
    SST source time:     2026111100

The SST cycle setting of "06" must not be interpreted as the
actual SST source-file hour.

Changes to GEFS or SST timing require coordinated modifications
to the scientific workflow and new regression validation.

## 5. Configurable runtime settings

The following runtime settings support nonempty environment
overrides.

| Environment variable | Default or source |
|---|---|
| GEFS_DIR | gefs.source_dir |
| HIGHRES_SST_DIR | sst.source_dir |
| HRRR_DIR | hrrr.wrfnat_dir |
| HRRR_WRFPRS_DIR | hrrr.wrfprs_dir |
| METGRID_PROC | 40 |
| REAL_NTASKS | 160 |
| MEAN_PROC | 40 |
| SOIL_FROM_WRFPRS | 0 |
| MIN_FILE_SIZE | 1000000000 bytes |
| BC_PREP_MODE | regression |
| SENDCOM | YES |
| COM_OVERWRITE | NO |
| BC_DATA | DATAROOT/WoF_BC |
| DATAHOME_GEFS | BC_DATA/gefs |
| DATAHOME_HRRR | BC_DATA/pert_hrrr |

METGRID_PROC, REAL_NTASKS, MEAN_PROC, and MIN_FILE_SIZE must
be positive integers.

SOIL_FROM_WRFPRS must be either 0 or 1.

SENDCOM and COM_OVERWRITE must be either YES or NO.

BC_PREP_MODE must be regression or operational.

Acceptance of a runtime setting by the configuration loader
does not guarantee that the requested resources are compatible
with the Slurm allocation or scientifically validated.

Stage-specific resource and execution checks remain necessary.

## 6. Runtime directory configuration

HOMEwofs identifies the workflow repository.

DATAROOT identifies the runtime data root. DATA can provide
a fallback when DATAROOT is not explicitly defined.

Default BC_PREP working directories are derived as follows:

    BC_DATA=${DATAROOT}/WoF_BC
    DATAHOME_GEFS=${BC_DATA}/gefs
    DATAHOME_HRRR=${BC_DATA}/pert_hrrr

Nonempty environment overrides are preserved.

The following YAML entries are documentary placeholders:

- paths.homewofs
- paths.dataroot
- paths.comroot

They are not active runtime path assignments.

PERTURB execution applies additional mode-specific working
directory and COM publication requirements.

## 7. PERTURB execution modes

The default execution mode is regression.

The configuration loader supports these optional settings:

| Environment variable | YAML setting |
|---|---|
| BC_PREP_MODE | perturb.execution_mode |
| BC_PERTURB_WORK_ROOT | perturb.operational_work_root |
| BC_PERTURB_COM_ROOT | perturb.operational_com_root |
| BC_PROTECTED_WORK_ROOT | perturb.protected_work_root |
| BC_PROTECTED_COM_ROOT | perturb.protected_com_root |

The root settings default to empty strings and must be supplied
as required by the selected execution mode.

The configuration loader does not independently authorize
operational directories or validate all publication paths.

See docs/bc_prep_perturb_execution.md for execution isolation,
path validation, locking, restart behavior, and COM publication.

## 8. Configuration loader callers

All five BC_PREP Slurm wrappers load the shared configuration.

The UNGRIB and METGRID J-jobs also load the configuration
directly.

The seven direct callers were audited for failure propagation.

Six callers use Bash errexit through set -euo pipefail.
The REAL wrapper explicitly exits if the loader returns failure.

The loader must return a nonzero status for invalid configuration.

Configuration loading is not atomic. A failed invocation may
leave partially exported variables in the calling shell.

Callers must terminate execution when configuration loading fails.

## 9. Configuration regression testing

The permanent regression test is:

    tests/check_bc_prep_config.py

Run the test using a Python environment containing PyYAML:

    export PYTHONNOUSERSITE=1
    unset PYTHONPATH PYTHONHOME
    "$WOFS_PYTHON" -B tests/check_bc_prep_config.py

The test locates the repository relative to its own location.

It does not contain hardcoded personal runtime paths.

Each test invokes the configuration loader in an isolated
environment. Temporary YAML configurations and test logs are
stored in a newly created temporary directory.

The test does not submit Slurm jobs or execute scientific
applications.

## 10. Validation results

The permanent regression suite was executed successfully on
Ursa using the portable Python 3.11 environment and PyYAML 6.0.2.

| Test category | Passed | Failed |
|---|---:|---:|
| Default configuration | 16 | 0 |
| Valid environment overrides | 11 | 0 |
| Invalid environment settings | 20 | 0 |
| Invalid fixed YAML settings | 19 | 0 |
| YAML robustness and precedence | 12 | 0 |
| Total | 78 | 0 |

The additional static audit covered seven direct configuration
loader callers.

The robustness tests include malformed YAML, missing required
keys, incorrect data types, environment precedence, and empty
environment-variable fallback.

Expected regression test summary:

    PASS = 78
    FAIL = 0
    [PASS] All 78 BC_PREP configuration tests

## 11. Validation scope and limitations

The configuration regression suite validates configuration
loading and rejection behavior.

It does not establish scientific reproducibility for arbitrary
runtime settings, alternative MPI allocations, or alternative
soil-data processing options.

The configuration loader is not a complete YAML schema validator.
Unknown keys and duplicate YAML keys are not comprehensively
validated.

The caller audit is static and does not replace end-to-end
failure-injection testing.

Operational PERTURB execution requires separately approved
working and COM roots and operational runtime provisioning.

Full workflow validation remains necessary before operational
implementation.

## 12. Related documentation

- docs/bc_prep_python_runtime.md
- docs/bc_prep_perturb_execution.md
- parm/bc_prep/config.yaml
- tests/check_bc_prep_config.py
