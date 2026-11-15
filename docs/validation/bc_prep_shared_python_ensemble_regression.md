# BC_PREP Shared Python Full-Ensemble Regression

## Objective

Verify that the shared WoFS Python runtime reproduces the
BC_PREP scientific products generated using the previous
portable Python environment on NOAA Ursa.

## Test configuration

- Validation date: November 15, 2026
- Platform: NOAA Ursa
- Workflow branch: develop
- Tested workflow revision: 7fcd12319215694d74659ad1aa2b4696e8059d1f
- HRRR initialization: 2026111212
- WoFS cycle: 2026111215
- Forecast lead: 01
- Ensemble members: 18
- Previous Python environment: /scratch3/NCEPDEV/wofs/Jianping.Huang/python_envs/wofs_py311_portable
- Shared Python environment: /scratch3/NCEPDEV/wofs/Jianping.Huang/python_envs/wofs_py311_p2_20261115_042228

Both experiments used the same workflow code, configuration,
scientific inputs, and isolated output directories.

## Validation results

| Test | Slurm job | Result |
|---|---:|---|
| Single-member pilot | 26583446 | 13/13 PASS |
| Initial input checksums | 26584455 | 210 inputs |
| Experiment A execution | 26590163 | 18/18 completed |
| Experiment A validation | 26591345 | 236/236 PASS |
| Experiment B execution | 26591777 | 18/18 completed |
| Experiment B validation | 26592755 | 236/236 PASS |
| Full-ensemble A/B comparison | 26593243 | 73/73 PASS |
| Final input revalidation | 26594055 | 210/210 PASS |

## Scientific findings

- All 18 members completed successfully in both experiments.
- All 36 final COM products passed GRIB2 inventory validation.
- Each final product contained 1,133 GRIB2 records.
- All corresponding WORK and COM products were bitwise identical.
- All 18 Experiment A and B product pairs were bitwise identical.
- All 210 scientific input checksums matched the original manifest.
- All WORK and COM locks were released successfully.
- No temporary-file remnants matching the tested patterns were detected.

The full-ensemble A/B regression passed all 755 acceptance
checks, excluding the preceding single-member pilot.

## Scientific input provenance

- HRRR GRIB2 inputs: 1
- GEFS ensemble WRF inputs: 198
- GEFS ensemble mean inputs: 11
- Total: 210

The final checksum verification completed in 810 seconds
using four parallel workers, with no checksum or worker failures.

## Validation evidence

Regression directory:

/scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC_P8_ensemble_20261115_213134.lWFZZWx6

The directory contains:

- scientific_inputs.sha256
- workflow_files.sha256
- experiment_A/validation/
- experiment_B/validation/
- ab_comparison/
- input_revalidation/

## Conclusion

The shared WoFS Python runtime successfully reproduced the
previous portable Python runtime's BC_PREP products bitwise
for all 18 ensemble members at forecast lead 01.

Together with the successful 36-member IC_PREP regression,
these results establish scientific reproducibility of the
shared Python runtime for the tested IC_PREP and BC_PREP cases.

## Remaining work

This regression covers one initialization cycle and forecast
lead 01. Integrated upstream BC_PREP processing and all
required forecast hours remain to be validated.

The matching input checksums establish consistency at the
pre- and post-experiment verification points.
