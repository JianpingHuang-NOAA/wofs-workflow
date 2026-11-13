# BC_PREP PERTURB Execution Architecture

## 1. Purpose

The WoFS v1.0 BC_PREP PERTURB workflow generates
ensemble-perturbed HRRR GRIB2 boundary-condition products
using GEFS ensemble perturbations.

The execution architecture separates scientific processing
from configuration, path validation, execution isolation,
concurrency control, and product publication.

The scientific utilities remain unchanged by this
execution-architecture modernization.

## 2. Workflow components

| Component | Responsibility |
|---|---|
| workflow/shell/bc_prep/jwofs_bc_prep_perturb.sh | Slurm entry point and runtime initialization |
| jobs/JWOFS_BC_PREP_PERTURB | NCO-style environment and task configuration |
| scripts/exwofs_bc_prep_perturb.sh | Application orchestration |
| ush/load_bc_prep_config.sh | YAML and environment configuration |
| ush/validate_bc_perturb_paths.sh | Shared execution-path validation |
| ush/run_bc_perturb_isolated.sh | Private execution and working-product publication |
| ush/perturb_hrrr.ksh | Existing scientific processing |
| util/perturb_hrrr.ncl | Existing NCL perturbation calculations |
| util/netcdf_to_grib.py | Existing NetCDF-to-GRIB2 conversion |
| ush/stage_bc_perturb.sh | Verified COM publication |
| parm/bc_prep/config.yaml | BC_PREP configuration |
| versions/bc_prep.ver | Runtime version metadata |

## 3. Execution sequence

1. Initialize the BC_PREP module environment.
2. Validate the portable Python runtime.
3. Load YAML configuration and environment overrides.
4. Resolve member, forecast hour, and cycle information.
5. Validate execution and publication paths.
6. Acquire the persistent member-hour working lock.
7. Recover recognized interrupted working publications.
8. Create a private execution directory.
9. Execute the existing scientific utility.
10. Validate the generated GRIB2 product.
11. Publish the working product.
12. Acquire the persistent COM target lock.
13. Validate and publish the COM product when enabled.
14. Clean private execution directories and temporary files.
15. Release locks and report successful completion.

The working lock is held through the COM publication phase.

## 4. Execution modes

The workflow supports regression and operational modes.

### 4.1 Regression mode

Regression is the default execution mode.

Regression execution requires an explicit TEST_ROOT and
COMROOT. Working and COM output paths must be contained
within the isolated test root.

Reference scientific products must not be overwritten.

GEFS input data may be supplied from an existing validated
dataset using DATAHOME_GEFS.

For reproducible regression testing, explicitly configure
DATAHOME_GEFS rather than relying on its default value.

### 4.2 Operational mode

Operational mode requires explicitly configured approved
working and COM roots.

TEST_ROOT must not be set.

Working and COM output paths must satisfy the shared path
validator and must not overlap the configured protected roots.

Operational mode is implemented and has been exercised
using isolated mock integration tests. Actual operational
deployment requires separately approved paths, ownership,
permissions, and workflow configuration.

## 5. Configuration

Configuration is provided through parm/bc_prep/config.yaml
and environment variables.

Nonempty environment overrides take precedence over the
corresponding YAML defaults.

| Variable | Purpose |
|---|---|
| BC_PREP_MODE | regression or operational |
| TEST_ROOT | Isolated regression execution root |
| BC_PERTURB_WORK_ROOT | Approved operational working root |
| BC_PERTURB_COM_ROOT | Approved operational COM root |
| BC_PROTECTED_WORK_ROOT | Protected working-data root |
| BC_PROTECTED_COM_ROOT | Protected COM-data root |
| DATAHOME_GEFS | GEFS scientific input root |
| DATAHOME_HRRR | PERTURB working-data root |
| DATAHOME | Member-specific working directory |
| COMROOT | COM publication root |
| START_TIME | HRRR initialization time |
| WOF_CYCLE_TIME | WoFS cycle time |
| MEMBER | Ensemble member |
| FCST_LEAD_TIME | HRRR forecast hour |
| WOFS_PYTHON | Explicit validated Python interpreter |
| MIN_FILE_SIZE | Minimum acceptable GRIB2 product size |

Supported ensemble members are 01 through 18.
Supported forecast hours are 00 through 25.

For Slurm array execution, the member can be resolved from
SLURM_ARRAY_TASK_ID.

## 6. Execution controls

| Variable | Default | Purpose |
|---|---|---|
| SENDCOM | YES | Enable COM publication |
| WORK_OVERWRITE | NO | Permit replacement of a differing working product |
| COM_OVERWRITE | NO | Permit replacement of a differing COM product |
| KEEP_INTERMEDIATE | NO | Retain successful private execution directories |
| KEEP_FAILED_RUN | NO | Retain failed private execution directories |

An identical existing product may be reused without
replacing its inode.

A differing existing product is rejected unless the
corresponding overwrite control explicitly permits replacement.

## 7. Path validation

The shared validator checks:

- Required execution-mode configuration.
- Valid member, forecast hour, and cycle values.
- Canonical absolute output paths.
- Regression-root containment.
- Operational-root containment.
- Separation of working and COM directories.
- Protection against overlap with configured protected roots.
- Unsafe source and target file types.
- Working and COM product inode independence.

The validator is a workflow safety mechanism, not a
replacement for filesystem access controls.

## 8. Private scientific execution

Each member-hour execution uses a private directory created
under its member-specific working directory.

Scientific intermediate files are generated inside that
private directory rather than directly in the shared
member directory.

The existing scientific processing includes:

- HRRR input selection.
- GEFS member and ensemble-mean input selection.
- GEFS perturbation calculation.
- NCL-based perturbation processing.
- NetCDF-to-GRIB2 conversion for TMP, UGRD, VGRD, SPFH,
  and HGT.
- Final GRIB2 assembly.

No changes to these scientific algorithms are introduced
by the execution-isolation implementation.

## 9. Concurrency control

Persistent advisory locks are used for member-hour working
products and individual COM targets.

Working lock:

    .perturb_<member4>_<hour2>.lock

COM lock:

    .<product_filename>.lock

A competing execution targeting an already locked product
is rejected.

Lock files remain after successful execution. Their
continued existence does not indicate an active lock.

Lock files must not be removed during active execution.

The tested Lustre filesystem supports cross-node flock
exclusion for cooperating processes.

## 10. Product publication and recovery

Generated working products are checked for acceptable
file type, size, and GRIB2 inventory before publication.

COM publication uses a temporary file in the destination
directory and verifies its contents against the working
product before final publication.

No-overwrite publication uses hard-link creation followed
by removal of the temporary source name.

Explicit overwrite publication uses same-filesystem
replacement.

Recognized interrupted hard-link publications can be
recovered on restart.

Unexpected or unaccounted-for hard-link aliases are rejected
rather than removed automatically.

Working and COM products are independent final files.

Working and COM publication are separate phases, not a
single transactional operation. A COM publication failure
can leave a valid working product available for restart.

## 11. Python runtime

The portable Python 3.11 environment is validated before
scientific execution.

Personal user-site packages are disabled.

The runtime configuration includes:

| Dependency | Version |
|---|---|
| Python | 3.11.12 |
| NumPy | 2.2.5 |
| SciPy | 1.15.2 |
| PyYAML | 6.0.2 |
| netCDF4 | 1.7.4 |
| cftime | 1.6.5 |
| pyproj | 3.7.2 |
| pygrib | 2.1.8 |
| ecCodes | 2.44.0 |

See bc_prep_python_runtime.md for installation, version
metadata, and runtime-validation details.

## 12. Safety and recovery validation

Development testing included:

- Shared path validation.
- Protected-root rejection.
- Regression and operational configuration.
- Filesystem publication primitives.
- Private execution isolation.
- Successful and failed-run retention.
- Working-product restart and recovery.
- Integrated application and COM publication.
- Concurrent working and COM target contention.
- Interrupted COM publication recovery.

A cumulative 141 successful test executions were recorded
across development iterations.

This count represents test executions across revisions,
not 141 distinct final-version test cases.

A separate cross-node Lustre locking test also passed.

## 13. Scientific regression validation

Validation was performed on NOAA Ursa using:

- HRRR initialization: 2026111212
- WoFS cycle: 2026111215
- Soil replacement from WRFPRS: disabled
- Portable Python 3.11 runtime
- Regression execution mode
- COM publication enabled
- Working and COM overwrite disabled

The comparison reference was the existing validated
BC_PREP dataset.

### 13.1 Single-member scientific regression

| Attribute | Result |
|---|---|
| Slurm job | 26266348 |
| Member | 01 |
| Forecast hour | 01 |
| Exit code | 0:0 |
| Elapsed time | 103 seconds |
| GRIB2 records | 1155 |
| File size | 1148524277 bytes |
| Scientific comparison | Bitwise identical |
| COM publication | PASS |
| Persistent locks | PASS |
| Private cleanup | PASS |

SHA256:

    47c0caecfc8bb7b1a988933fc8913649488c837b09c2543c6e65e7fd2f07d7fa

The reference, working, and COM products were identical.

### 13.2 Nine-task scientific pilot

| Forecast hour | Slurm array | Members |
|---|---|---|
| 00 | 26266656 | 01, 09, 18 |
| 13 | 26266657 | 01, 09, 18 |
| 25 | 26266658 | 01, 09, 18 |

All nine tasks completed with exit code 0:0.

Elapsed times ranged from 91 to 105 seconds.

Reported batch-step MaxRSS ranged from approximately
9.76 to 16.13 GiB under a 22 GiB memory allocation.

The selected cases exercise coincident GEFS input times,
temporal interpolation, next-day valid times, and ensemble
and forecast-hour boundaries.

### 13.3 Pilot validation results

| Validation | Result |
|---|---|
| Scientific cases | 9/9 PASS |
| Pairwise byte comparisons | 27/27 PASS |
| Scientific variable conversions | 45/45 PASS |
| Converted GRIB2 records | 2250 |
| Final GRIB2 records per product set | 10413 |
| Independent working and COM products | 18/18 PASS |
| Persistent locks | 18/18 PASS |
| Remaining private directories | 0 |
| Remaining COM temporary files | 0 |
| Nonempty standard-error logs | 0 |
| Bytes per product set | 10408747116 |
| Recorded script fingerprints | 12/12 unchanged |
| Scientific utilities | Unchanged |
| Scientific equivalence | BITWISE IDENTICAL |

### 13.4 Combined scientific validation

The single-member regression and nine-task pilot provide
ten distinct validated member-hour combinations.

Combined results:

- 10 successful scientific executions.
- 30 successful pairwise byte comparisons.
- 50 successful scientific variable conversions.
- 2500 converted GRIB2 records.
- 11568 final GRIB2 records per product set.
- 20 independent working and COM products.
- 20 successfully validated persistent locks.

All tested products reproduce their respective reference
products byte for byte.

## 14. Validation scope and operational limitations

The current scientific validation covers ten distinct
member-hour combinations from one HRRR initialization.

It does not establish equivalence for all 468 possible
member-hour combinations, other meteorological cases, or
the optional WRFPRS soil-replacement configuration.

Reference-product provenance was not independently
re-established during this validation.

Additional operational considerations include:

- Approved operational roots must be established.
- Runtime installation must be provisioned for the
  operational execution account.
- Filesystem ownership and default ACLs must be reviewed.
- Persistent lock files were observed with mode 664 on
  the tested Lustre filesystem.
- Advisory locks require cooperating execution processes.
- Path validation does not eliminate all filesystem
  race conditions or provide a security boundary.
- Working and COM publication are not transactional.
- Power-loss durability has not been established.
- Arbitrary orphan temporary files are not automatically
  removed by the recognized hard-link recovery mechanism.
- Existing scientific utilities retain their path-format
  assumptions.

Operational readiness requires additional end-to-end
workflow and deployment validation.

## 15. Conclusion

The BC_PREP PERTURB execution architecture provides
isolated scientific execution, explicit configuration,
shared path validation, advisory concurrency control,
verified product publication, and restart recovery.

The scientific regression results demonstrate bitwise
equivalence for all ten tested member-hour combinations
without modifying the existing scientific algorithms.

## Appendix A. Nine-task scientific fingerprints

| Member | Hour | Slurm task | Bytes | GRIB2 records | SHA256 |
|---|---|---|---:|---:|---|
| 01 | 00 | 26266656_1 | 1099234522 | 1155 | `0898cdb35b904075c77ddca8f5e8e99c2dee7fee66a7b6e534497482e5cac346` |
| 01 | 13 | 26266657_1 | 1169975041 | 1158 | `18d38cad7fd903e70eac5ade20b464ef9e52ff5ca5d4fd3cb22e3da306b8d6c0` |
| 01 | 25 | 26266658_1 | 1200452188 | 1158 | `903c4700ddcd8beab4875db5571e52dfd9d3b996374943d4f9580acdeb9aec21` |
| 09 | 00 | 26266656_9 | 1098996381 | 1155 | `eecb3c90657379c96cca08cf52752645b9567fc3cf142afb69961111847df057` |
| 09 | 13 | 26266657_9 | 1170213185 | 1158 | `df945f79bfb2420e6711055c4e30787c01cd11bb765128621a2f6e9a931e3dcc` |
| 09 | 25 | 26266658_9 | 1199261473 | 1158 | `9ff5d91dc2d1fa1958f0d06afdca81f9d732a972b1b78f40c493196ada19dafc` |
| 18 | 00 | 26266656_18 | 1099948953 | 1155 | `21e7a9802bedb6007d9dd66658e0d5f4926a8bd63b1c04b4a525a110a5a467c5` |
| 18 | 13 | 26266657_18 | 1171403900 | 1158 | `ce095c16a03f02687b0e5f72edd009ee4cccf2980939147ad674a8ae9e9aadcf` |
| 18 | 25 | 26266658_18 | 1199261473 | 1158 | `9bcb136e29ad3e9a906c10be7e575ef39bf5a41efa98413c15f3e8dbb1387908` |
