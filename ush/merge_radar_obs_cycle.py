#!/usr/bin/env python3
"""Merge station-level DBZ and VR products into one WoFS observation cycle."""

import argparse
from contextlib import ExitStack
from datetime import datetime
from pathlib import Path
import json
import re
from tempfile import TemporaryDirectory

import numpy as np
from netCDF4 import Dataset


def merge_product(paths, stations, kind, cycle, output):
    with ExitStack() as stack:
        inputs = [stack.enter_context(Dataset(path)) for path in paths]
        reference = inputs[0]
        counts = [len(ds.dimensions["index"]) for ds in inputs]
        if any(count <= 0 for count in counts):
            raise ValueError(f"{kind}: each station must have observations")

        offsets = np.cumsum([0, *counts], dtype=np.int64)
        total = int(offsets[-1])
        index_base = int(reference["index"][0])

        for ds, station, count in zip(inputs, stations, counts):
            if set(ds.dimensions) != set(reference.dimensions):
                raise ValueError(f"{kind} {station}: dimension names differ")
            if set(ds.variables) != set(reference.variables):
                raise ValueError(f"{kind} {station}: variable names differ")
            for name, dimension in reference.dimensions.items():
                if name != "index" and len(ds.dimensions[name]) != len(dimension):
                    raise ValueError(f"{kind} {station}: dimension {name} differs")
            for name, var in reference.variables.items():
                other = ds[name]
                if (var.dimensions, var.dtype) != (other.dimensions, other.dtype):
                    raise ValueError(f"{kind} {station}: schema differs for {name}")

            if not np.array_equal(ds["index"][:], np.arange(index_base, index_base + count)):
                raise ValueError(f"{kind} {station}: unexpected observation indices")

            if kind == "vrobs":
                names = ds["radar_name"][:].tolist()
                starts = ds["radar_start"][:].tolist()
                ends = ds["radar_end"][:].tolist()
                if names != [station] or starts != [0] or ends != [count]:
                    raise ValueError(
                        f"{station}: expected VR range [0, {count}), "
                        f"found {names}, {starts}, {ends}"
                    )

        # Concatenate stored values without decoding and re-encoding them.
        for ds in inputs:
            ds.set_auto_maskandscale(False)
            ds.set_auto_chartostring(False)

        with Dataset(output, "w", format=reference.file_format) as out:
            for name, dimension in reference.dimensions.items():
                size = {"index": total, "radar": len(stations)}.get(name, len(dimension))
                out.createDimension(name, size)

            out.setncatts({
                name: reference.getncattr(name)
                for name in reference.ncattrs()
                if name not in {"history", "radar_name"}
            })
            out.history = f"Merged radar observations for {cycle}: {', '.join(stations)}"

            for name, source in reference.variables.items():
                attrs = {attr: source.getncattr(attr) for attr in source.ncattrs()}
                fill = attrs.pop("_FillValue", None)
                dest = out.createVariable(
                    name, source.datatype, source.dimensions, fill_value=fill
                )
                dest.setncatts(attrs)
                dest.set_auto_maskandscale(False)
                dest.set_auto_chartostring(False)

                if name == "index":
                    dest[:] = np.arange(index_base, index_base + total)
                elif name == "radar_start":
                    dest[:] = offsets[:-1]
                elif name == "radar_end":
                    dest[:] = offsets[1:]
                elif "index" in source.dimensions or "radar" in source.dimensions:
                    dimension = "index" if "index" in source.dimensions else "radar"
                    axis = source.dimensions.index(dimension)
                    dest[:] = np.concatenate([ds[name][:] for ds in inputs], axis=axis)
                else:
                    dest[...] = source[...]

    with Dataset(output) as check:
        if len(check.dimensions["index"]) != total:
            raise ValueError(f"{output.name}: merged count differs")
        if kind == "vrobs":
            if check["radar_name"][:].tolist() != list(stations):
                raise ValueError("Merged VR radar names differ")
            if not (
                np.array_equal(check["radar_start"][:], offsets[:-1])
                and np.array_equal(check["radar_end"][:], offsets[1:])
            ):
                raise ValueError("Merged VR radar ranges differ")
            for station, start, end in zip(stations, offsets[:-1], offsets[1:]):
                print(f"VR {station}: [{start}, {end})")
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("station_root", type=Path, help="Root containing station subdirectories")
    parser.add_argument("cycle", help="UTC analysis time in YYYYMMDDHHMM")
    parser.add_argument("output_root", type=Path)
    parser.add_argument("stations", nargs="+", help="Station IDs in output order")
    args = parser.parse_args()

    analysis = datetime.strptime(args.cycle, "%Y%m%d%H%M")
    if analysis.strftime("%Y%m%d%H%M") != args.cycle:
        parser.error("cycle must use YYYYMMDDHHMM")
    if any(re.fullmatch(r"[A-Z0-9]{4}", station) is None for station in args.stations):
        parser.error("station IDs must contain four uppercase letters or digits")
    if len(set(args.stations)) != len(args.stations):
        parser.error("station IDs must be unique")

    destination = args.output_root / args.cycle
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"Cycle already exists: {destination}")
    args.output_root.mkdir(parents=True, exist_ok=True)

    hhmm = args.cycle[-4:]
    counts = {}
    with TemporaryDirectory(prefix=f".{args.cycle}.", dir=args.output_root) as temp:
        pending = Path(temp) / "publish"
        pending.mkdir()
        manifests = {}
        no_eligible_input = []
        for station in args.stations:
            station_dir = args.station_root / station / args.cycle
            summary = json.loads((station_dir / "station_complete.json").read_text())
            if (summary.get("station"), summary.get("cycle")) != (station, args.cycle):
                raise ValueError(f"Wrong station or cycle in {station_dir}")
            manifests[station] = summary["counts"]
            if summary.get("status") == "no_eligible_input":
                if manifests[station] != {"dbzobs": 0, "vrobs": 0}:
                    raise ValueError(f"{station}: no eligible input with nonzero counts")
                no_eligible_input.append(station)

        for kind in ("dbzobs", "vrobs"):
            name = f"{hhmm}-{kind}.nc"
            paths, contributors = [], []
            for station in args.stations:
                count = manifests[station][kind]
                if type(count) is not int or count < 0:
                    raise ValueError(f"{station}: invalid {kind} count {count!r}")
                path = args.station_root / station / args.cycle / name
                if count:
                    with Dataset(path) as ds:
                        if len(ds.dimensions["index"]) != count:
                            raise ValueError(f"{path}: count differs from completion summary")
                    paths.append(path)
                    contributors.append(station)
                elif path.exists():
                    raise ValueError(f"{path}: unexpected file for zero-observation product")
            counts[name] = (
                merge_product(paths, contributors, kind, args.cycle, pending / name)
                if paths else 0
            )

        (pending / "cycle_complete.json").write_text(json.dumps({
            "cycle": args.cycle, "stations": args.stations, "counts": counts,
            "no_eligible_input": no_eligible_input,
        }) + "\n")
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"Cycle already exists: {destination}")
        pending.rename(destination)

    for name, count in counts.items():
        print(f"PASS: {name}: {count:,} observations; cycle directory: {destination}")


if __name__ == "__main__":
    main()
