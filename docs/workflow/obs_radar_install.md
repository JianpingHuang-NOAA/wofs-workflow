# WoFS v1.0 Radar Software Installation

## Overview

The WoFS radar observation preprocessing system consists of:

- WoFS Python runtime environment
- RADAR Python dependencies
- RADAR Python package
- F2PY Fortran extensions
- WDSS-II binary distribution

The installation controller supports NOAA Ursa.

## RADAR external

The RADAR source repository is managed through Externals.cfg.

Repository:
https://github.com/JianpingHuang-NOAA/wofsv1_radar_data_processing

Source revision:
874454eef079f30f1e2a12865d81549b97cb1be0

## Installation controller

    ./sorc/build_obs_radar.sh --help

Supported options:

    --all
    --python
    --radar
    --wdssii
    --status

The controller reuses existing completed installations.

## Fresh installation

Check out the RADAR external using the workflow external
management procedure.

Set the WDSS-II binary distribution and OpenSSL compatibility
environment locations:

    export WDSSII_SOURCE=/path/to/WDSSII
    export WDSSII_SSL_HOME=/path/to/openssl11/environment

Install all radar software components:

    ./sorc/build_obs_radar.sh --all

Check installation status:

    ./sorc/build_obs_radar.sh --status

## Installed components

Python environment:

    python_env/

RADAR Python package:

    python_env/lib/python3.11/site-packages/wofs_radar/

WDSS-II binary distribution:

    exec/WDSSII/

## Runtime initialization

Set HOMEwofs to the workflow repository root.

Initialize the WoFS Python runtime:

    source "$HOMEwofs/ush/load_wofs_python.sh"

Initialize WDSS-II:

    source "$HOMEwofs/ush/load_wdssii.sh"

## Fortran extensions

The RADAR package contains two compiled Fortran extensions:

- cressman
- sparsey

They are compiled using NumPy F2PY and the Meson backend.

Python-only source changes do not require Fortran recompilation
when the Fortran source files remain unchanged.

Both Python source and Fortran build revisions are recorded.

## MRMS GRIB2 compatibility

The legacy PyNIO backend has been replaced with pygrib.

The replacement reader preserves:

- Original reflectivity values
- Latitude and longitude orientation
- 0-360 degree longitude convention
- Missing-data value of -99
- No-coverage value of -999
- Legacy reflectivity variable names

Validation using the MRMS sample from 20261102 at 150039 UTC
confirmed identical values at all 24,500,000 grid points
relative to directly decoded GRIB2 data.

## WDSS-II

WDSS-II version 26-4 is installed from an existing binary
distribution.

Required commands include:

- ldm2netcdf
- w2qcnndp
- dealiasVel
- makeIndex.pl
- replaceIndex

The OpenSSL 1.1 compatibility environment remains an external
runtime dependency.

## Validation status

Validated on NOAA Ursa on November 18, 2026:

- Radar Python dependency versions
- RADAR Fortran extension compilation
- RADAR Python package imports
- MRMS GRIB2 reader compatibility
- WDSS-II executable checksums
- Centralized controller --status
- Centralized controller --all
- Reuse of existing installations

The fresh-installation path of the updated controller has not
yet been exercised as a complete installation.

End-to-end radar observation generation is addressed separately
during radar workflow integration.
