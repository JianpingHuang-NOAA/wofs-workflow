# WoFS WRF FIX Provisioning

## Purpose

Provision a self-contained WRF FIX directory for WoFS v1.0
without dependencies on another development checkout.

## Source provenance

The WRF static files are obtained from the WRF external
repository pinned in Externals.cfg.

Validated WRF revision:

328a9503a8f8fd724412edec6be298b7b51e7691

The REAL namelist is preserved from the legacy WoF_BC
static/WRF directory.

The 36 ensemble namelists are byte-identical to the legacy
templates_JH/namelists.WOFS directory.

These ensemble namelists are used by legacy initialization
and cycling workflows. They must not be confused with the
separate namelists.WOFS.fcst forecast templates.

## Repository configuration

- parm/bc_prep/real.nl.32and4levels
- parm/bc_prep/wrf_fix.sha256
- parm/wrf/namelists.WOFS/
- ush/setup_wrf_fix.sh

## Provisioning

After checking out the pinned WRF external, run from the
WoFS workflow repository root:

    export HOMEwofs="$(pwd -P)"
    bash ush/setup_wrf_fix.sh

The default destination is:

    ${HOMEwofs}/fix/WRF

An alternative destination may be supplied:

    bash ush/setup_wrf_fix.sh /path/to/test/WRF

The destination must not already exist. The utility refuses
to overwrite existing directories or symbolic links.

## Static file inventory

| Category | Count |
|---|---:|
| WRF run static files | 67 |
| REAL namelist | 1 |
| Ensemble namelists | 36 |
| Total | 104 |

The utility validates the pinned WRF revision and verifies
all source and provisioned files using SHA256 checksums.

Provisioned directories have mode 2755.
Provisioned static files have mode 644.

## Integrity verification

From the repository root:

    export HOMEwofs="$(pwd -P)"

    (
        cd "$HOMEwofs/fix/WRF"
        sha256sum -c \
            "$HOMEwofs/parm/bc_prep/wrf_fix.sha256"
    )

## Validation results

Validated on NOAA Ursa on November 14, 2026.

- All 104 files reproduced byte for byte.
- All 104 SHA256 checks passed.
- Complete directory comparison reported no differences.
- No symbolic links remain inside the provisioned directory.
- All 39 BC_PREP REAL static dependencies verified.
- IC_PREP ETAMPNEW_DATA verified.
- All 36 ensemble namelists verified.
- Existing destination overwrite protection passed.
- Reproducible directory permissions verified.

The original external WRF FIX symbolic link was replaced
with a physical directory in the workflow repository.

Full workflow execution using the newly provisioned FIX
directory remains part of subsequent integration testing.

## Scope

This utility provisions WRF static files only.

WPS static data, UPP control files, CRTM coefficients,
and the separate forecast namelist family are handled
independently.

Generated FIX data are excluded from Git. The configuration
files, checksum manifest, and provisioning utility are
version controlled.

## Legacy namelist formatting

The 36 ensemble namelists preserve their original byte
contents, including inherited trailing whitespace.

These formatting characteristics are intentionally retained
to maintain exact legacy provenance and SHA256 reproducibility.

Whitespace normalization must not be performed without
explicitly reviewing and updating the validation baseline.
