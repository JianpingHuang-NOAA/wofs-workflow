#!/bin/bash
#SBATCH --account=wofs
#SBATCH --partition=u1-compute
#SBATCH --job-name=wofs_radar_obs
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=00:30:00

set -euo pipefail

if (( $# != 12 )); then
    echo "Usage: $0 YYYYMMDDHHMM STATION LON LAT DOMAIN CLOUD_ROOT OUTPUT_ROOT RADAR_SOURCE PYTHON BASE_CFG DBZ_VARIANCE LON_CONVENTION" >&2
    exit 2
fi

cd "$8"
MPLBACKEND=Agg "$9" -u - "$@" <<'RADAR_PYTHON'
from configparser import ConfigParser
from datetime import datetime
from pathlib import Path
from shutil import copyfile
import json
import sys
from tempfile import TemporaryDirectory

import numpy as np
from netCDF4 import Dataset, date2num

from wofs_radar.utils.combine_VR_ncdf import combine_from_pattern
from wofs_radar.vr import mrms, run_vr_for_radar_time


def write_dbz(path, ref, analysis, variance, lon_convention):
    dbz = np.ma.masked_invalid(ref.data)
    height = np.ma.masked_invalid(ref.zg + ref.radar_hgt)
    if dbz.ndim != 3 or height.shape != dbz.shape:
        raise ValueError(f"Unexpected DBZ and height shapes: {dbz.shape}, {height.shape}")
    if np.shape(ref.lats) != (dbz.shape[1],) or np.shape(ref.lons) != (dbz.shape[2],):
        raise ValueError("Expected one-dimensional latitude and longitude axes")

    mask = (
        ~np.ma.getmaskarray(dbz)
        & ~np.ma.getmaskarray(height)
        & (dbz.data >= 20.0)
    )
    k, j, i = np.where(mask)
    count = k.size
    if not count:
        return 0

    lat = np.asarray(ref.lats)[j]
    lon = (np.asarray(ref.lons)[i] + 180) % 360 - 180
    if lon_convention == "positive-west":
        lon = -lon
    if not (np.isfinite(lat).all() and np.isfinite(lon).all()):
        raise ValueError("Nonfinite DBZ coordinates")

    epoch = "seconds since 1970-01-01 00:00:00"
    dart_day = (analysis.date() - datetime(1601, 1, 1).date()).days
    seconds = analysis.hour * 3600 + analysis.minute * 60
    date_chars = np.frombuffer(
        analysis.strftime("%Y-%m-%d %H:%M:%S").encode("ascii"), dtype="S1"
    )
    columns = {
        "index": ("i8", np.arange(count, dtype=np.int64)),
        "value": ("f8", dbz.data[k, j, i]),
        "lat": ("f8", lat),
        "lon": ("f8", lon),
        "height": ("f8", height.data[k, j, i]),
        "error_var": ("f4", variance),
        "utime": ("f8", date2num(analysis, epoch)),
        "day": ("i8", dart_day),
        "second": ("i8", seconds),
    }

    with Dataset(path, "w", format="NETCDF4") as out:
        out.createDimension("index", count)
        out.createDimension("string19", 19)
        for name, (dtype, values) in columns.items():
            fill = np.nan if dtype.startswith("f") else None
            out.createVariable(name, dtype, ("index",), fill_value=fill)[:] = values
        for name in ("lat", "lon", "hgt", "dir1", "dir2", "dir3", "nyquist"):
            out.createVariable(f"platform_{name}", "f8", ("index",), fill_value=np.nan)
        out.createVariable("date", "S1", ("index", "string19"))[:] = np.tile(
            date_chars, (count, 1)
        )
        out["lat"].units = "degrees"
        out["lat"].description = "latitude of observation"
        out["lon"].units = "degrees"
        out["lon"].description = f"longitude of observation ({lon_convention})"
        out["height"].units = "meters"
        out["height"].description = "height above sea level"
        out["utime"].units = epoch
        out["utime"].description = "time of observation"
        out["date"].description = "date and time of observation"
        out.history = f"WDSS-II gridded reflectivity for {analysis:%Y%m%d%H%M}"
    return count


def main():
    (
        cycle, station, center_lon, center_lat, domain, cloud_root, output_root,
        _source, _python, base_cfg, variance_arg, lon_convention,
    ) = sys.argv[1:]
    analysis = datetime.strptime(cycle, "%Y%m%d%H%M")
    if analysis.strftime("%Y%m%d%H%M") != cycle:
        raise ValueError("Analysis time must use YYYYMMDDHHMM")

    day, hhmm = cycle[:8], cycle[8:]
    variance = float(variance_arg)
    if not np.isfinite(variance) or variance <= 0:
        raise ValueError("DBZ error variance must be positive and finite")
    if lon_convention not in {"signed-east", "positive-west"}:
        raise ValueError("Use signed-east or positive-west for longitude")

    domain, cloud_root, output_root, base_cfg = map(
        Path, (domain, cloud_root, output_root, base_cfg)
    )
    for path in (domain, cloud_root, output_root, base_cfg):
        if not path.is_absolute():
            raise ValueError(f"Expected an absolute path: {path}")
    if not domain.is_file():
        raise FileNotFoundError(domain)
    for field in ("ReflectivityQC", "Velocity"):
        path = cloud_root / day / "Radar" / station / field
        if not path.is_dir():
            raise FileNotFoundError(path)

    output_root.mkdir(parents=True, exist_ok=True)
    stage = output_root / cycle
    if stage.exists() or stage.is_symlink():
        raise FileExistsError(stage)

    with TemporaryDirectory(prefix=f".{cycle}.", dir=output_root) as temp:
        work = Path(temp)
        vr_root = work / "vr"
        vr_root.mkdir()

        cfg = ConfigParser(interpolation=None)
        cfg.optionxform = str
        if not cfg.read(base_cfg):
            raise FileNotFoundError(base_cfg)
        cfg["RASS"].update({
            "input": str(cloud_root / "{}" / "Radar"),
            "input_refl": "ReflectivityQC",
            "input_vel": "Velocity",
            "reflectivity_var": "ReflectivityQC",
            "output": str(vr_root),
            "plot": "",
            "write_dart": "False",
        })
        config_path = work / "app.radar.cfg"
        with config_path.open("w") as stream:
            cfg.write(stream)

        fields = []
        original_masking = mrms.dbz_masking

        def capture_dbz(*args, **kwargs):
            field = original_masking(*args, **kwargs)
            fields.append(field)
            return field

        mrms.dbz_masking = capture_dbz
        try:
            run_vr_for_radar_time(
                analysis, station, float(center_lon), float(center_lat),
                str(config_path), str(domain),
            )
        finally:
            mrms.dbz_masking = original_masking
        if len(fields) != 1:
            raise RuntimeError(f"Expected one reflectivity volume, got {len(fields)}")

        pending = work / "publish"
        pending.mkdir()
        dbz_output = pending / f"{hhmm}-dbzobs.nc"
        vr_output = pending / f"{hhmm}-vrobs.nc"

        dbz_count = write_dbz(dbz_output, fields[0], analysis, variance, lon_convention)
        vr_dir = vr_root / day
        station_vr = vr_dir / f"obs_seq_{station}_VR_{day}_{hhmm}.nc"
        with Dataset(station_vr) as dataset:
            vr_count = len(dataset.dimensions["index"])

        if vr_count:
            combine_from_pattern(f"_VR_{day}_{hhmm}.nc", str(vr_dir))
            copyfile(vr_dir / f"obs_seq_VR_{day}_{hhmm}.nc", vr_output)
            with Dataset(vr_output) as dataset:
                if len(dataset.dimensions["index"]) != vr_count:
                    raise RuntimeError("VR count changed during combination")

        counts = {"dbzobs": dbz_count, "vrobs": vr_count}
        (pending / "station_complete.json").write_text(json.dumps({
            "cycle": cycle, "station": station, "counts": counts,
        }) + "\n")
        pending.rename(stage)
        print(f"PASS: {station} {cycle} {counts}")



if __name__ == "__main__":
    main()
RADAR_PYTHON
