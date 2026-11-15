# IC_PREP shared Python runtime validation

## Objective

Integrate the shared WoFS Python runtime into the IC_PREP
DOWNLOAD and POST workflows without changing the validated
scientific processing or output reliability mechanisms.

## Implementation

- Initialize Python through ush/load_wofs_python.sh.
- Use one validated interpreter for WOFS_PYTHON and
  IC_PREP_PYTHON.
- Remove implicit system Python fallback.
- Preserve the selected interpreter during YAML processing.
- Disable personal user-site packages.
- Preserve existing UPP, inventory, locking and atomic
  publication logic.

## Runtime environment

| Component | Version |
|---|---|
| Python | 3.11.12 |
| PyYAML | 6.0.2 |
| NumPy | 2.2.5 |
| SciPy | 1.15.2 |
| netCDF4 | 1.7.4 |
| cftime | 1.6.5 |
| pygrib | 2.1.8 |
| pyproj | 3.7.2 |
| packaging | 25.0 |
| certifi | 2025.4.26 |
| ecCodes | 2.44.0 |
| PROJ | 9.5.1 |
| Python NetCDF | 4.9.3 |
| Python HDF5 | 1.14.6 |

## Preliminary validation

- Shared Python loader: 17/17 checks passed.
- IC_PREP inventory configuration: 10/10 passed.
- Atomic publication: 23/23 passed.
- IC_PREP locking: 23/23 passed.
- Bash syntax and Git whitespace validation passed.

## Runtime regression

Validation date: 2026-11-15 UTC.

Initialization time: 2026110214.

POST member: 26.

| Test | Slurm job | Partition | Elapsed | Result |
|---|---|---|---|---|
| DOWNLOAD | 26500111 | u1-service | 00:00:04 | PASS |
| POST | 26500112_26 | u1-compute | 00:02:02 | PASS |
| UPP | 26500112_26.0 | u1-compute | 00:00:55 | PASS |

Both batch jobs and the UPP step completed with exit code 0:0.

The DOWNLOAD fixture verified the actual workflow wrapper,
J-job, YAML configuration, Python imports and interpreter
preservation, without downloading external data.

The POST regression used 160 MPI tasks and 300 GB of memory.

## GRIB2 inventory

| Product | Expected | Actual |
|---|---:|---:|
| Raw WRFNAT | 1000 | 1000 |
| Raw WRFTWO | 169 | 169 |
| Processed WRFTWO | 167 | 167 |
| Final work WRFNAT | 1167 | 1167 |
| Final COM WRFNAT | 1167 | 1167 |

## Scientific reproducibility

The R1 reference, new working product and new COM product
were bitwise identical.

SHA256:

99d8b707d3e8c7839a9507bada5c2a2d8d82692741156f5b6de213ffeeca3799

The work and COM locks were released successfully.
No temporary COM publication files remained.

## Regression summary

| Category | Passed |
|---|---:|
| Slurm accounting | 2 |
| DOWNLOAD runtime | 5 |
| POST runtime | 2 |
| GRIB2 inventories | 5 |
| Scientific comparisons | 2 |
| Locking and publication | 5 |
| Total | 21 |

All 21 runtime regression checks passed.

## Limitations

The DOWNLOAD fixture does not test external connectivity
or actual HRRRDAS data transfer.

The scientific regression covers one initialization cycle
and one ensemble member. It supplements the previously
completed 36-member IC_PREP reliability regression.

The submission helper's ensemble scheduling behavior was
not independently exercised by this regression.
