# WoFS v1.0 UPP Scientific Baseline Validation

## Objective

Recover and rebuild the original legacy UPP scientific baseline
using the portable WoFS v1.0 build infrastructure on NOAA Ursa.

The objective is to preserve the scientific reproducibility of
the legacy IC_PREP workflow while eliminating dependence on
a precompiled legacy executable.

## Validated UPP source

- Repository: https://github.com/JianpingHuang-NOAA/UPP
- Branch: feature/wofs-v1.0
- Commit: 170c09eccf76bc3885c17fdfb3537b2d902eefbb
- Original upstream baseline:
  70e9f1361022396d7afbc513006efb487292728b
- UPP version: 11.0.0

## Build configuration

- Platform: NOAA Ursa
- Intel oneAPI: 2024.2.1
- Intel MPI: 2021.13.1
- CMake: 3.27.9
- Build modulefile: modulefiles/ursa_upp_build.lua
- Build script: sorc/build_upp_ursa.sh
- Build job ID: 26484652
- Build elapsed time: 00:01:54
- Build status: COMPLETED
- Dynamic library compatibility: PASS

## Executable checksums

Original legacy UPP:

    0f0556c3bc888635eb5947a0c035f56ed726bfdbf4c44d7fbaa049e451a34639

Rebuilt newer UPP:

    693982952027f2c47f17a2b7f4399650795d8ae23edaa257cbcaed3906e44bf3

Rebuilt legacy UPP:

    e0cae188fef2d5b3c3bcdf6d6decd98f6423657ddf5bcf3777e5fdce8fa9b302

## Scientific regression experiments

HRRRDAS initialization: 2026110214

WoFS initialization: 2026110215

Ensemble size: 36

All experiments used the same IC_PREP input data, runtime
parameter files, and isolated UPP runtime environment.

| Experiment | UPP configuration |
|------------|-------------------|
| R1 | Original legacy UPP executable |
| R2 | Rebuilt newer UPP, commit ead2925 |
| R3 | Rebuilt legacy UPP, commit 170c09e |

## R1 versus R2

- Ensemble members compared: 36
- GRIB2 records compared: 42,012
- Identical records: 41,937
- Different records: 75

The differences were associated with upstream changes to
freezing-level height calculations in FRZLVL.f and FRZLVL2.f.

Affected fields included:

- HGT at the 0-degree Celsius isotherm
- HGT at local level type 204
- HGT at the 263 K isotherm

The newer scientific algorithms were not adopted for the
WoFS v1.0 legacy reproducibility baseline.

## R1 versus R3

- Comparison job ID: 26486808
- Comparison elapsed time: 00:01:03
- Job status: COMPLETED
- Ensemble members compared: 36
- Members passed: 36
- Members failed: 0
- File-size comparison: PASS
- SHA256 comparison: PASS
- Byte-by-byte comparison: PASS

All 36 final native-grid GRIB2 files produced by the rebuilt
legacy UPP were bitwise identical to those produced by the
original legacy UPP.

## Conclusion

The recovered UPP source and portable build procedure
successfully reproduce the original legacy IC_PREP scientific
results for the complete 36-member ensemble.

WoFS v1.0 pins UPP to commit
170c09eccf76bc3885c17fdfb3537b2d902eefbb.

The newer UPP scientific development branch is retained for
future evaluation.

## Scope and limitations

This validation establishes bitwise reproducibility of the
final native-grid IC_PREP GRIB2 products for the tested case.

It does not establish reproducibility for every possible
meteorological case or every UPP product.

The separate stale-output-file issue in the UPP workflow
will be addressed independently of this scientific baseline
integration.
