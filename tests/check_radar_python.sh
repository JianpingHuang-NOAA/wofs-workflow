#!/bin/bash
#=======================================================================
# Validate WoFS radar Python runtime.
#=======================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

export HOMEwofs="$ROOT"

cd "$ROOT"

source versions/bc_prep.ver

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

export PYTHONNOUSERSITE=1

unset PYTHONPATH PYTHONHOME

PY="$ROOT/python_env/bin/python3"

"$PY" - <<'PYTHON'
import importlib
import sys
import traceback
from pathlib import Path

modules = [
    "wofs_radar",
    "wofs_radar.utils.cressman",
    "wofs_radar.utils.sparsey",
    "wofs_radar.vr.load_mrms_ppi",
    "wofs_radar.vr.mrms",
    "wofs_radar.vr",
    "wofs_radar.refl.prep_mrms",
    "wofs_radar.refl",
    "wofs_radar.__main__",
]

failed = []

root = Path(sys.prefix).resolve()

for name in modules:

    try:
        mod = importlib.import_module(name)

        if getattr(mod, "__file__", None):
            path = Path(mod.__file__).resolve()
        else:
            path = Path(next(iter(mod.__path__))).resolve()

        if not path.is_relative_to(root):
            raise RuntimeError(f"Unexpected module location: {path}")

        print(f"[PASS] {name}", flush=True)

    except Exception:

        print(f"[FAIL] {name}", flush=True)
        traceback.print_exc()
        failed.append(name)

print("\n===== Radar Python import summary =====")
print(f"Total:  {len(modules)}")
print(f"Passed: {len(modules) - len(failed)}")
print(f"Failed: {len(failed)}")

if failed:
    raise SystemExit(1)

print("[PASS] WoFS radar Python runtime")

PYTHON
