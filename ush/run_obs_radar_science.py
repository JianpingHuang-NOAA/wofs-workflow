#!/usr/bin/env python3
"""Invoke one installed radar science routine and propagate its exit status."""

import argparse
from datetime import datetime
from pathlib import Path


def local_reflectivity(args):
    import netCDF4
    import numpy as np
    from wofs_radar.Config import AppConfiguration
    from wofs_radar.refl import prep_mrms

    day = args.cycle.strftime("%Y%m%d")
    feed = Path(args.feed)
    if not feed.is_absolute() or feed.name != day:
        raise ValueError(f"Expected an absolute MRMS archive directory ending in {day}: {feed}")
    settings = AppConfiguration.load(args.config)
    grid = prep_mrms._grid_dict
    window = prep_mrms._dt_window
    files = prep_mrms.Get_Closest_Elevations_Local(
        args.cycle, grid_dict=grid, window=window, data_root=str(feed.parent)
    )
    prefix = "MRMS_MergedReflectivityQC_"
    levels = {Path(path).name.removeprefix(prefix).split("_")[0] for path in files}
    expected = set(grid["levels"])
    if levels != expected or len(files) != len(expected):
        raise ValueError(f"Incomplete MRMS stack: missing levels {sorted(expected - levels)}")
    with netCDF4.Dataset(args.geometry) as geometry:
        lat = geometry.variables["XLAT" if "XLAT" in geometry.variables else "XLAT_M"][:]
        lon = geometry.variables["XLONG" if "XLONG" in geometry.variables else "XLONG_M"][:]
        nx = int(lat.shape[1] * (geometry.getncattr("DX") / 1000.0) * 1.4)
        ny = int(lat.shape[2] * (geometry.getncattr("DY") / 1000.0) * 1.4)
    reflectivity = prep_mrms.assemble_3D_grid_NCEP(
        files, loc=[args.lat, args.lon], debug=prep_mrms._debug,
        dbz_name=settings.mrms_refl_var_name, NX=nx, NY=ny,
    )
    reflectivity.time = args.cycle
    reflectivity = prep_mrms.dbz_masking(
        reflectivity, thin_zeros=grid["thin_zeros"], wlat=lat, wlon=lon
    )
    output = Path(settings.mrms_obs_seq.format(day)) / day
    output.mkdir(parents=True, exist_ok=True)
    name = args.cycle.strftime("obs_seq_RF_%Y%m%d_%H%M")
    prep_mrms.write_obs_seq_xarray(
        reflectivity, filename=str(output / name), levels=np.arange(len(grid["levels"])),
        obs_error=[grid["reflectivity"], grid["0reflectivity"]],
        QC_info=grid["QC_info"], zero_levels=grid["zero_levels"], volume_name=name,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    tools = parser.add_subparsers(dest="tool", required=True)
    for name in ("velocity", "reflectivity"):
        task = tools.add_parser(name)
        task.add_argument("cycle", type=lambda value: datetime.strptime(value, "%Y%m%d%H%M"))
        if name == "velocity":
            task.add_argument("station")
        task.add_argument("lon", type=float)
        task.add_argument("lat", type=float)
        task.add_argument("config")
        task.add_argument("geometry")
        if name == "reflectivity":
            task.add_argument("feed")
    combine = tools.add_parser("combine")
    combine.add_argument("pattern")
    combine.add_argument("directory")
    args = parser.parse_args()

    if args.tool == "velocity":
        from wofs_radar.Config import AppConfiguration
        from wofs_radar.vr import run_vr_for_radar_time
        from wofs_radar.vr.load_mrms_ppi import getTiltProducts

        AppConfiguration.load(args.config)
        if not any(tilt["files"] for tilt in getTiltProducts(args.station, args.cycle)):
            print(f"No eligible radar products for {args.station} at {args.cycle}")
            Path(args.config).with_name("no_eligible_scans").touch()
            return

        run_vr_for_radar_time(args.cycle, args.station, args.lon, args.lat,
                              args.config, args.geometry)
    elif args.tool == "reflectivity":
        local_reflectivity(args)
    else:
        from wofs_radar.utils.combine_VR_ncdf import combine_from_pattern

        combine_from_pattern(args.pattern, args.directory)


if __name__ == "__main__":
    main()
