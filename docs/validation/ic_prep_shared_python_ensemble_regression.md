# IC_PREP Shared Python Full-Ensemble Regression

## 1. Objective

Validate the scientific reproducibility and workflow reliability
of the WoFS v1.0 IC_PREP workflow after integrating the shared
portable Python runtime into the develop branch.

## 2. Test configuration

| Parameter | Value |
|---|---|
| Platform | NOAA Ursa |
| Workflow branch | develop |
| Tested workflow revision | f20891e4f3f44a218159043bc344a0d474097fef |
| Initialization time | 2026110214 |
| Valid time | 2026110215 |
| Ensemble size | 36 |
| Forecast hour | 01 |
| MPI tasks per member | 160 |
| Nodes per member | 1 |
| Requested memory per member | 300G |
| Slurm array | 1-36%6 |
| Python version | 3.11.12 |
| Ensemble job ID | 26572896 |
| Validation job ID | 26580623 |

## 3. Runtime provenance

Python interpreter:

```text
/scratch3/NCEPDEV/wofs/Jianping.Huang/python_envs/wofs_py311_p2_20261115_042228/bin/python3
```

The shared Python environment passed package-version,
installation-location, native-library, and dependency-consistency
validation.

Workflow and executable checksums:

```text
013585a20c8ba52e28a682c13fb2f0520ade9579c615ecafa56ca2204a9fe466  scripts/exwofs_ic_prep.sh
b2644e7ee9801f59a847846e289f77dc13ba4d1298616aac4becbebeb3b1b12f  ush/lock_ic_prep.sh
a6e49957c373cecfb3168bb5daefbc569176999fbd63735a752cceb2236eb764  ush/publish_ic_prep_grib2.sh
6c6f42c6748b06ab98e5bcb1532c75fa17f3502fcc3ce81dc264677593aa43bf  ush/load_wofs_python.sh
e0cae188fef2d5b3c3bcdf6d6decd98f6423657ddf5bcf3777e5fdce8fa9b302  exec/upp.x
```

The UPP executable checksum matches the R13 reference executable.

## 4. Single-member pilot

A single-member pilot was completed before submitting the full
ensemble.

- Pilot job ID: 26572208
- Member: 01
- Runtime: 124 seconds
- Validation: 13 PASS, 0 FAIL
- Final WRFNAT inventory: 1167 GRIB2 records
- Scientific comparison: bitwise identical to R13

## 5. Full-ensemble execution

All 36 ensemble members completed successfully with Slurm
exit code 0:0.

```text
Completed members: 36
Distinct compute nodes: 24
Maximum simultaneous allocations: 6
Minimum elapsed seconds: 121
Maximum elapsed seconds: 166
Mean elapsed seconds: 133.61
```

The six-member concurrency limit was verified using Slurm
accounting timestamps.

## 6. Scientific and reliability validation

The independent validation job completed successfully with
exit code 0:0 in 87 seconds.

Expected GRIB2 inventories per member:

| Product | Expected records |
|---|---:|
| Raw WRFNAT | 1000 |
| Raw WRFTWO | 169 |
| Processed WRFTWO | 167 |
| Final WORK WRFNAT | 1167 |
| Final COM WRFNAT | 1167 |

Validation category results:

```text
COM_lock_exists           PASS=36 FAIL=0 TOTAL=36
COM_lock_released         PASS=36 FAIL=0 TOTAL=36
Final_COM_WRFNAT          PASS=36 FAIL=0 TOTAL=36
Final_work_WRFNAT         PASS=36 FAIL=0 TOTAL=36
Processed_WRFTWO          PASS=36 FAIL=0 TOTAL=36
R13_bitwise               PASS=36 FAIL=0 TOTAL=36
Raw_WRFNAT                PASS=36 FAIL=0 TOTAL=36
Raw_WRFTWO                PASS=36 FAIL=0 TOTAL=36
Slurm                     PASS=36 FAIL=0 TOTAL=36
Temporary_COM             PASS=36 FAIL=0 TOTAL=36
Work_COM_bitwise          PASS=36 FAIL=0 TOTAL=36
Work_lock_exists          PASS=36 FAIL=0 TOTAL=36
Work_lock_released        PASS=36 FAIL=0 TOTAL=36
```

Final validation summary:

```text
PASS: 468
FAIL: 0
TOTAL: 468
```

All 36 final COM products were bitwise identical to their
corresponding R13 reference products.

All 36 final WORK products were bitwise identical to their
corresponding COM products.

All persistent WORK and COM lock files passed existence and
lock-release checks. No temporary COM publication products
remained after successful completion.

## 7. Performance comparison

| Metric | R13 | Shared Python ensemble |
|---|---:|---:|
| Ensemble members | 36 | 36 |
| Maximum simultaneous allocations | 36 | 6 |
| Minimum elapsed seconds | 119 | 121 |
| Maximum elapsed seconds | 131 | 166 |
| Mean elapsed seconds | 121.44 | 133.61 |

The mean member runtime increased by approximately 10 percent.
The experiments used different concurrency levels, compute-node
allocations, and filesystem conditions. The timing difference
cannot be attributed specifically to the shared Python runtime.

## 8. Experiment locations

Pilot:

```text
/scratch3/NCEPDEV/stmp/Jianping.Huang/ic_prep_regression/P8_pilot_20261115_182647.jIC6AsNb
```

Full ensemble:

```text
/scratch3/NCEPDEV/stmp/Jianping.Huang/ic_prep_regression/P8_ensemble_20261115_183330.y15W6xPT
```

Scientific reference:

```text
/scratch3/NCEPDEV/stmp/Jianping.Huang/ic_prep_regression/R13_final_ensemble_20261115_035753
```

Independent validation report:

```text
/scratch3/NCEPDEV/stmp/Jianping.Huang/ic_prep_regression/P8_ensemble_20261115_183330.y15W6xPT/validation_26580623
```

## 9. Storage retention

Following successful scientific validation, redundant WORK
directories from the earlier R2 and R3 UPP regression
experiments were removed.

All 36 R2 and all 36 R3 final COM products were retained,
together with their configuration files, provenance records,
logs, and comparison reports.

The R1, R13, and P8 full-ensemble WORK and COM directories
were retained.

The removed WORK intermediates must be regenerated if future
investigations require those files.

## 10. Acceptance conclusion

The IC_PREP workflow integrated into the WoFS v1.0 develop
branch successfully completed the full 36-member scientific
regression using the shared portable Python runtime.

All 468 scientific and workflow reliability checks passed.
All final COM GRIB2 products reproduced the R13 reference
products bit for bit.

The shared Python runtime integration therefore preserves
IC_PREP scientific reproducibility and workflow reliability
for the tested initialization cycle.

## 11. Scope and limitations

- Scientific acceptance applies to the tested initialization
  cycle and runtime configuration.
- GRIB2 inventory counts and bitwise comparisons establish
  reproducibility relative to R13, not independent
  meteorological forecast accuracy.
- Executable and FIX resources were provisioned through
  existing runtime resources on Ursa.
- Historical input and FIX checksums were not independently
  established for every resource.
- Full BC_PREP scientific acceptance remains a separate
  validation milestone.
