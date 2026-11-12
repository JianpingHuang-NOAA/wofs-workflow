# WoFS v1.0 BC_PREP Python Runtime

## 1. Purpose

The BC_PREP PERTURB workflow uses a standardized Python 3.11
environment for converting perturbed HRRR atmospheric fields
from NetCDF to GRIB2.

The runtime replaces the legacy Python 3.6 environment while
preserving scientific results and eliminating dependencies on
personal Python user-site packages.

## 2. Runtime architecture

The Python runtime consists of:

- NOAA python/3.11 module on Ursa.
- A WoFS virtual environment using system-site-packages.
- Four explicitly pinned packages installed in the virtual
  environment.
- Runtime version and package-location validation.
- Python user-site isolation in the PERTURB Slurm wrapper.

The virtual environment depends on the NOAA base Python
installation and is not a standalone Python distribution.

## 3. Repository components

| File | Purpose |
| --- | --- |
| versions/bc_prep.ver | Validated runtime version metadata |
| modulefiles/ursa_bc_prep.lua | BC_PREP runtime modules |
| sorc/requirements_bc_prep.txt | Pinned virtual environment packages |
| sorc/install_bc_prep_python.sh | Python environment installer |
| tests/check_bc_prep_python.sh | Comprehensive runtime validator |
| workflow/shell/bc_prep/jwofs_bc_prep_perturb.sh | Runtime initialization and isolation |

## 4. Validated Python packages

| Package | Version | Installation location |
| --- | --- | --- |
| Python | 3.11.12 | NOAA base environment |
| PyYAML | 6.0.2 | NOAA base environment |
| NumPy | 2.2.5 | NOAA base environment |
| SciPy | 1.15.2 | NOAA base environment |
| packaging | 25.0 | NOAA base environment |
| certifi | 2025.4.26 | NOAA base environment |
| netCDF4 | 1.7.4 | WoFS virtual environment |
| cftime | 1.6.5 | WoFS virtual environment |
| pyproj | 3.7.2 | WoFS virtual environment |
| pygrib | 2.1.8 | WoFS virtual environment |

## 5. Validated native libraries

| Library | Version |
| --- | --- |
| ecCodes | 2.44.0 |
| PROJ | 9.5.1 |
| Python NetCDF | 4.9.3 |
| Python HDF5 | 1.14.6 |

These versions are reported by the installed Python packages.
They are distinct from the NetCDF and HDF5 modules used by
compiled WoFS applications.

The pygrib package provides its own ecCodes definitions.
A separate ecCodes module is not required for this runtime.

## 6. Installation on Ursa

Run the following commands from the WoFS repository root.

    export HOMEwofs="$(pwd -P)"

    export WOFS_VENV=/absolute/path/to/wofs_py311

    bash "$HOMEwofs/sorc/install_bc_prep_python.sh" "$WOFS_VENV"

The destination must be an absolute path that does not
already exist.

The installer loads the standardized BC_PREP modules,
validates the NOAA base Python environment, creates a
virtual environment, installs the pinned packages, and
validates the completed environment.

Installation requires access to the required Python wheels,
either through the configured package index or a local cache.

## 7. Runtime validation

    source "$HOMEwofs/versions/bc_prep.ver"

    module purge
    module use "$HOMEwofs/modulefiles"
    module load "$wofs_modulefile"

    export WOFS_PYTHON="$WOFS_VENV/bin/python3"

    bash "$HOMEwofs/tests/check_bc_prep_python.sh" "$WOFS_PYTHON"

The validator checks:

- Exact Python version.
- Active virtual environment.
- Disabled personal user-site packages.
- Python package versions.
- Python package installation locations.
- Requirements and version metadata consistency.
- Native library versions.
- ecCodes definitions and installation location.
- Python package dependency consistency.

Do not resolve WOFS_PYTHON to the underlying NOAA Python
executable. The virtual environment interpreter path must
be preserved.

## 8. PERTURB execution

Before submitting a PERTURB job, explicitly select the
validated Python environment:

    export WOFS_PYTHON="$WOFS_VENV/bin/python3"

The PERTURB Slurm wrapper loads the BC_PREP modules and
enforces:

    export PYTHONNOUSERSITE=1
    unset PYTHONPATH
    unset PYTHONHOME

The wrapper invokes the comprehensive runtime validator
before executing JWOFS_BC_PREP_PERTURB.

An invalid runtime causes the job to terminate before
scientific processing begins.

The Python interpreter is inherited by the scientific
PERTURB utility and the NetCDF-to-GRIB2 converter.

No developer-specific Python environment path is hardcoded
in the PERTURB wrapper.

## 9. Scientific regression validation

Validation date: November 12, 2026.

Platform: NOAA Ursa.

### 9.1 Clean three-way Python regression

Slurm job: 26246072.

Three Python environments were compared using identical
NetCDF inputs and GRIB2 templates:

- Legacy Python 3.6.12 environment.
- Original modern Python 3.11.12 environment.
- Portable Python 3.11.12 environment.

Results:

- Five atmospheric variables: TMP, UGRD, VGRD, SPFH, HGT.
- 15 successful conversions.
- 10 successful binary comparisons.
- 50 GRIB2 records per variable.
- 250 GRIB2 records per environment.
- All corresponding GRIB2 outputs were byte-for-byte identical.

All conversion output paths were initially absent.

This is important because the legacy NetCDF-to-GRIB2
converter opens its output files in append mode.

### 9.2 Negative runtime integration test

The original modern Python environment depended on netCDF4
and cftime packages installed in a personal user-site
directory.

After disabling user-site packages, the runtime validator
correctly rejected this environment.

The negative wrapper test confirmed:

- Return code 1.
- Missing netCDF4 and cftime detected.
- Scientific J-job not reached.
- No working output created.
- No COM output created.

The test used a temporary wrapper copy with a sentinel
in place of the scientific J-job invocation.

### 9.3 Complete PERTURB integration regression

Slurm job: 26247375.

| Parameter | Value |
| --- | --- |
| HRRR initialization | 2026111212 |
| WoFS cycle | 2026111215 |
| Ensemble member | 01 |
| HRRR forecast hour | 01 |
| Python | 3.11.12 |
| pygrib | 2.1.8 |
| ecCodes | 2.44.0 |
| Scientific conversions | 5/5 passed |
| Final GRIB2 records | 1155 |
| Final GRIB2 size | 1148524277 bytes |
| Working and COM permissions | 664 |
| Standard error | Empty |

The existing validation reference, new working GRIB2 file,
and published COM GRIB2 file were byte-for-byte identical.

SHA256:

    47c0caecfc8bb7b1a988933fc8913649488c837b09c2543c6e65e7fd2f07d7fa

The COM publication preserved the working file permissions.

The intermediate NetCDF file and the five GRIB2 templates
and conversion outputs were removed as expected.

## 10. Validation scope and limitations

The clean Python regression validated all five atmospheric
variables.

The complete PERTURB integration regression validated one
ensemble member and one forecast hour against an existing
BC_PREP validation reference.

The provenance of that reference as a direct legacy
workflow output was not independently established by
this integration test.

A new full 18-member, 26-hour ensemble regression was
not performed with the portable Python environment.

The virtual environment depends on the validated NOAA
python/3.11 module and its inherited packages.

The installer pins package versions but does not provide
a hash-locked wheelhouse or an independent Python
distribution.

The runtime validator intentionally rejects version changes.
Changes to the NOAA Python module or Python packages require
review and regression validation before updating the
version metadata.

This migration applies to BC_PREP PERTURB. IC_PREP and the
other BC_PREP stages are outside the scope of this change.
