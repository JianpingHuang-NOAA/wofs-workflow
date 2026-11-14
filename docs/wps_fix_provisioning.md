# WoFS v1.0 WPS FIX provisioning

## Purpose

The WPS FIX provisioning utility reproduces the validated
WoFS static datasets, customized WPS tables, namelists,
and relative symbolic links.

The generated fix/WPS directory is not tracked in Git.

## Source provenance

The WPS external is pinned in Externals.cfg at:

40e6a3115d25cbf21241bbc6e2d5f231f146f596

The provisioning sources consist of:

- Eight configuration files maintained in parm/wps.
- Vtable.SST from the pinned WPS external.
- Two externally distributed NetCDF static datasets.

All 11 regular files are verified against
parm/wps/wps_fix.sha256.

The three relative symbolic links are defined in
parm/wps/wps_fix.links.

## External static datasets

The external static directory must contain:

- geo_em.d01_modis15s_lake_Saltlake_modisalb_newtopo_newsoil_lakemod.new_GWD_fields.nc
- GWD_mdt_10newfields.HRRR.nc_20190220

Both datasets are byte-identical to the validated legacy
WoFS datasets.

The permanent operational distribution location is
configurable and is not hardcoded in the utility.

## Scientific configuration

The GEOGRID dataset describes the WoFS 3-km domain
with mass-grid dimensions of 1799 by 1059.

All 20 GWD variables in the separate GWD dataset are
bitwise identical to the corresponding variables
embedded in the GEOGRID dataset.

No additional GWD processing is required during
provisioning.

Both smoke and no-smoke RAP Vtables and METGRID
tables are preserved.

The smoke-enabled configurations include MASSDEN.

The active namelist.wps.GFSENS uses the portable
METGRID table path:

    opt_metgrid_tbl_path = './metgrid/',

The original namelist is retained for historical
provenance and is not the active runtime namelist.

## Provisioning

Run from the workflow repository root:

    export WPS_STATIC_SOURCE=/path/to/static/WPS
    bash ush/setup_wps_fix.sh

The default destination is fix/WPS.

An alternative destination may be specified:

    bash ush/setup_wps_fix.sh /path/to/test/WPS

The utility refuses to overwrite an existing destination.

## Installed directory

The provisioned directory contains:

- 11 regular files.
- Three relative symbolic links.
- No broken symbolic links.

Regular files have mode 644.
The destination directory has mode 2755.

## Verification

From the workflow repository root:

    ROOT="$(pwd -P)"
    (
        cd fix/WPS
        sha256sum -c "$ROOT/parm/wps/wps_fix.sha256"
    )

Verify symbolic link targets:

    (
        cd fix/WPS
        find . -maxdepth 1 -type l -printf '%f\t%l\n' |
            LC_ALL=C sort
    ) | cmp - parm/wps/wps_fix.links

## Validation on Ursa

Static provisioning was validated on November 14, 2026.

The following checks passed:

- Pinned WPS source revision.
- All 11 source file checksums.
- Independent isolated provisioning.
- All 11 provisioned file checksums.
- Full directory comparison with the original WPS FIX.
- Exact reproduction of all three symbolic links.
- Directory and regular file permissions.
- Existing destination overwrite protection.
- Fresh installation candidate provisioning.
- Post-installation integrity verification.
- All five directly referenced BC_PREP WPS FIX paths.
- Preservation of the installed WRF FIX contents.

The original WPS FIX directory was retained as a backup.

The full workflow runtime regression using the newly
installed static directories remains a separate
validation step.

## Legacy formatting

Customized tables and historical namelists preserve
their validated byte contents.

Inherited formatting, including trailing whitespace
where present, must not be normalized without reviewing
and updating the checksum baseline.
