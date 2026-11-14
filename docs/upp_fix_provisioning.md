# WoFS v1.0 UPP FIX Provisioning

## Purpose

The UPP FIX provisioning utility creates a reproducible
runtime static directory for WoFS IC_PREP post-processing.

The generated fix/UPP directory is excluded from Git.
Its contents are provisioned from version-controlled
configuration files.

## Pinned UPP source

UPP is pinned in Externals.cfg to:

    ead2925bb3e3f0d4996acb8036b2c1f35b88de78

The provisioning utility verifies the checked-out UPP
revision before installing the static configuration.

## UPP FIX contents

The generated fix/UPP directory contains one regular file:

    gtg.config.raphrrr

The file is maintained in:

    parm/upp/gtg.config.raphrrr

It is byte-identical to the legacy WoF_IC operational
configuration and the validated wofsv1.0 configuration.

The file is not available under the same filename in
the pinned UPP source.

Its SHA256 checksum is:

    92a6c4b32667184ead7245d5c4da5f18b5c57862f1dd5f63a2c82ae467275e5f

## UPP control files

The following existing workflow control files are
maintained at their original locations:

    parm/post_avblflds.xml
    parm/params_grib2_tbl_new
    parm/postcntrl.xml
    parm/postxconfig-NT.txt

All four files are byte-identical to the corresponding
legacy WoF_IC operational static files.

They differ from the corresponding pinned UPP source
configuration files and must not be replaced without
scientific regression testing.

The executable permission on post_avblflds.xml was
removed without changing its contents.

## Checksum manifests

Two checksum manifests are maintained:

    parm/upp/upp_fix.sha256
    parm/upp/upp_control.sha256

The first verifies the provisioned UPP FIX file.

The second verifies the four existing UPP control files
from the workflow repository root.

## Provisioning

From the workflow repository root:

    bash ush/setup_upp_fix.sh

The default destination is:

    fix/UPP

An alternative destination may be supplied:

    bash ush/setup_upp_fix.sh /path/to/UPP

The utility refuses to overwrite an existing destination.

It verifies the pinned UPP revision, validates the
configuration checksums, provisions the file in a
temporary directory, and verifies the resulting contents
before installing the destination.

The generated directory has mode 2755.
The generated regular file has mode 644.

## Independent verification

From the workflow repository root:

    ROOT="$(pwd -P)"

    (
        cd fix/UPP
        sha256sum -c "$ROOT/parm/upp/upp_fix.sha256"
    )

    sha256sum -c parm/upp/upp_control.sha256

The generated directory contains one regular file and
zero symbolic links.

## GTG configuration

The validated UPP executable was built with:

    BUILD_WITH_GTG=OFF

However, the current IC_PREP workflow explicitly
requires and stages gtg.config.

The GTG configuration and existing runtime staging
behavior are therefore preserved.

Whether the GTG-disabled executable actually reads
this configuration has not been independently verified.

## Other runtime dependencies

The WRF microphysics lookup table is provisioned
separately through the WRF FIX utility.

The IC_PREP itag template remains in parm/ic_prep.

CRTM coefficients are external runtime dependencies
and are handled separately from UPP FIX provisioning.

## Validation

Static provisioning and installation were validated
on Ursa on November 14, 2026.

Validation included:

- Legacy configuration byte-level comparisons.
- Pinned UPP revision verification.
- Independent provisioning runs.
- SHA256 checksum verification.
- Full directory comparisons.
- Destination overwrite protection.
- File and directory permission verification.
- Installed UPP executable integrity verification.
- WRF and WPS FIX integrity verification.

The installed UPP FIX directory is byte-identical
to the original directory and the independent test
directory.

No scientific configuration contents or UPP executable
contents were changed during this migration.

Inherited formatting in the legacy GTG configuration
is preserved to maintain byte-level reproducibility.

A new end-to-end workflow runtime regression remains
part of the subsequent integration validation.
