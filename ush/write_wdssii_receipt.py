#!/usr/bin/env python3
"""Write the Slurm staging job ID and output path for a WDSS-II submission."""

import argparse
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("job_id")
    parser.add_argument("cloud_root", type=Path)
    args = parser.parse_args()
    # sbatch --parsable can return jobid;cluster.
    job_id = args.job_id.split(";", 1)[0]
    if not re.fullmatch(r"[1-9][0-9]*", job_id):
        parser.error("expected the staging job ID from sbatch --parsable")
    if not args.cloud_root.is_absolute():
        parser.error("CLOUD_ROOT must be absolute")
    with args.receipt.open("x") as stream:
        json.dump({"stage_job_id": job_id, "cloud_root": str(args.cloud_root)}, stream)
        stream.write("\n")


if __name__ == "__main__":
    main()
