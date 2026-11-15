# WoFS v1.0 BC_PREP Shared Python Runtime Regression

## Overview

- Validation date: 2026-11-15
- Platform: NOAA Ursa
- Branch: feature/portable-python-runtime
- Base Git revision: 37efc2a50d1b970bd068f1eab7a49ccb91f747da
- Component: BC_PREP PERTURB
- Result: PASS (bitwise identical)

## Experiment configuration

| Parameter | Value |
|---|---|
| START_TIME | 2026111212 |
| WOF_CYCLE_TIME | 2026111215 |
| MEMBER | 01 |
| FCST_LEAD_TIME | 01 |
| SOIL_FROM_WRFPRS | 0 |
| Python | 3.11.12 |
| HRRR input records | 1133 |

Both experiments used the same workflow implementation,
scientific processing scripts, HRRR input, GEFS member
and mean inputs, and scientific configuration.

Only the selected Python virtual environment differed.

## Python environments

| Experiment | Environment | Slurm job | Result |
|---|---|---|---|
| A | wofs_py311_portable | 26566771 | COMPLETED |
| B | wofs_py311_p2_20261115_042228 | 26566772 | COMPLETED |

Both environments passed the shared WoFS Python runtime
validator, including dependency consistency, package
versions, native libraries, and ecCodes definitions.

## Scientific regression results

| Validation | Result |
|---|---|
| HRRR input checksum | PASS |
| GEFS input checksums (22 files) | PASS |
| Scientific code checksums (4 files) | PASS |
| Experiment A exit code | 0:0 |
| Experiment B exit code | 0:0 |
| Experiment A elapsed time | 00:01:44 |
| Experiment B elapsed time | 00:01:43 |
| Output GRIB2 records | 1133 |
| Output file size (bytes) | 1115639673 |
| A WORK versus A COM | Bitwise identical |
| B WORK versus B COM | Bitwise identical |
| A WORK versus B WORK | Bitwise identical |

All four GRIB2 products have the following SHA256:

    896c11a0bc03f1dad4f2a08edcc707def46a106222f20c571724dd992d90ebb1

## Historical reference discrepancy

The historical reference job 26247375 generated 1155
GRIB2 records, whereas the staged HRRR input and controlled
regression products contain 1133 records.

The 22-record discrepancy consists of additional
land-surface records in the historical reference:

- LAI: 1
- SOILW: 9
- TSOIL: 9
- VEG: 1
- VEGMAX: 1
- VEGMIN: 1

The original historical HRRR input was unavailable for
direct verification.

A controlled A/B regression was therefore conducted
using identical staged scientific inputs.

## Conclusion

The shared WoFS Python environment reproduces the
BC_PREP PERTURB GRIB2 product generated using the
previous portable Python environment byte for byte
for the tested member, cycle, and forecast hour.

The shared Python runtime integration passes the
controlled scientific regression.

## Regression evidence

- A/B regression directory: /scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC_P5_AB_20261115_172353.zsF4wqhP
- Input checksums: hrrr.sha256 and gefs.sha256
- Scientific code checksums: scientific_code.sha256
- Python validation logs: python_A.log and python_B.log
- Submission logs: submit_A.log and submit_B.log
- Scientific comparison: comparison.log
