# CRTM FIX Provisioning for WoFS v1.0

## 1. Purpose

The WoFS IC_PREP POST workflow uses the Community
Radiative Transfer Model (CRTM) through UPP.

CRTM coefficient files are external runtime dependencies.
They are not distributed within the wofs-workflow repository.

The workflow resolves the coefficient directory from the
configured UPP runtime environment instead of embedding
a machine-specific spack-stack installation path.

## 2. Runtime dependencies

The validated Ursa environment uses:

- spack-stack 1.9.2
- Intel oneAPI 2024.2.1
- Intel MPI 2021.13.1
- CRTM 2.4.0.1
- CRTM FIX 2.4.0.1_emc
- NetCDF Fortran 4.6.1

The UPP executable is linked against the CRTM static library.

The CRTM module provides the CRTM_FIX environment variable
pointing to the installed coefficient directory.

## 3. Configuration

The default configuration in parm/ic_prep/config.yaml is:

    workflow:
      crtm_enabled: true

    paths:
      crtm_fix_dir: auto

The configuration loader exports:

    CRTM=1
    CRTM_FIX_DIR=auto

With automatic resolution, ush/run_upp.sh obtains the
coefficient directory from the module-provided CRTM_FIX.

An explicit coefficient directory can also be configured:

    paths:
      crtm_fix_dir: /path/to/approved/crtm/fix

The explicit directory must satisfy the same approved
coefficient inventory requirements.

Setting crtm_enabled to false skips coefficient staging.
It does not independently disable CRTM calculations
requested by the UPP configuration.

## 4. Runtime implementation

The relevant workflow components are:

- parm/ic_prep/config.yaml
- scripts/exwofs_ic_prep.sh
- ush/load_upp_environment.sh
- ush/run_upp.sh
- parm/crtm/crtm_fix.sha256

The IC_PREP execution script prepares the UPP inputs
and invokes ush/run_upp.sh.

The UPP wrapper clears inherited CRTM_FIX and initializes
the isolated UPP environment using the shared environment
loader before resolving the coefficient directory.

The wrapper validates the approved inventory before
creating symbolic links in the member-specific POST
working directory.

The implementation rejects:

- Missing or unreadable coefficient directories.
- Missing, unreadable, or empty coefficient files.
- Invalid or duplicate manifest entries.
- Unexpected source coefficient entries.
- Unexpected binary entries in the POST directory.
- Existing non-symbolic-link coefficient entries.

Existing approved symbolic links can be replaced.
Repeated staging and repair of broken approved links
are supported.

The staging procedure assumes exclusive access to the
member-specific POST directory.

## 5. Approved coefficient inventory

The approved manifest is:

    parm/crtm/crtm_fix.sha256

It contains SHA256 checksums for 1671 coefficient files.

The manifest was generated from the legacy coefficient
installation and independently verified against the
spack-stack 1.9.2 installation.

All 1671 coefficient files were byte-identical.

The manifest SHA256 is:

    bd3d9d2b0d6cc0ab20d972420687ce8b923a00d00667d59b014f90739c17c575

Runtime staging validates the inventory and file
availability without recalculating every file checksum.

Independent checksum verification can be performed from
the POST working directory:

    sha256sum --quiet -c \
        "$HOMEwofs/parm/crtm/crtm_fix.sha256"

A nonzero exit status indicates a verification failure.

## 6. Validation on Ursa

Validation was performed on November 14, 2026 (UTC).

### 6.1 Coefficient compatibility

The legacy spack-stack 1.9.1 and candidate spack-stack
1.9.2 coefficient installations were compared.

Results:

- Approved coefficients: 1671
- Byte-identical coefficients: 1671
- Missing coefficients: 0
- Unexpected coefficients: 0
- Complete directory comparison: PASS

### 6.2 Runtime safety regression

The staging implementation was tested for automatic
resolution, explicit directory selection, repeated
staging, broken-link repair, missing coefficients,
unexpected coefficients, and overwrite protection.

All runtime safety regression tests passed.

### 6.3 Isolated UPP scientific regression

- Slurm job: 26397485
- MPI tasks: 160
- Exit code: 0:0
- Total runtime: 81 seconds
- UPP runtime: 72 seconds
- Coefficient links: 1671
- Broken links: 0

All three raw UPP GRIB2 products were byte-identical
to the rebuilt UPP reference.

All eight UPP input files remained unchanged.

### 6.4 Actual IC_PREP integration regression

- Slurm job: 26399092_1
- Initialization time: 2026111214
- Valid time: 2026111215
- Ensemble member: 0001
- MPI tasks: 160
- Exit code: 0:0
- Total runtime: 131 seconds
- UPP runtime: 66 seconds

The actual IC_PREP POST workflow used the installed
exec/upp.x and automatic CRTM coefficient resolution.

| Product | Records | Bytes | Comparison |
|---|---:|---:|---|
| WRFNAT | 1167 | 706575633 | Identical |
| WRFPRS | 767 | 414964748 | Identical |
| WRFTWO | 167 | 116827705 | Identical |
| Total | 2101 | 1238368086 | Identical |

The published COMOUT WRFNAT product was also
byte-identical to the reference.

All 1671 staged coefficients passed SHA256 verification
and resolved to the candidate coefficient installation.

The original HRRRDAS and HRRR inputs, installed UPP
executable, UPP control files, and CRTM manifest
remained unchanged.

## 7. Validation scope

The portable CRTM implementation has passed isolated
UPP and single-member IC_PREP integration regressions.

The full ensemble integration and default production
WORK and COM path validation remain separate tasks.

The CRTM coefficient inventory must be revalidated
when changing CRTM or CRTM FIX versions.

The coefficient files remain externally managed
runtime dependencies.
