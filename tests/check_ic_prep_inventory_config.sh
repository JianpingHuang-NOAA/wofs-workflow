#!/bin/bash
set -euo pipefail

export HOMEwofs="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

cd "$HOMEwofs"

export INIT_TIME=2026110214
export MEMBER=26
export IC_PREP_STAGE=POST

source "${HOMEwofs}/ush/load_wofs_python.sh"

"${WOFS_PYTHON}" - <<'PY'
import copy
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

config = Path("parm/ic_prep/config.yaml")
loader = Path("ush/load_ic_prep_config.py").resolve()

base = yaml.safe_load(config.read_text())

expected = {
    "EXPECTED_RAW_WRFNAT_FIELDS": "1000",
    "EXPECTED_RAW_WRFTWO_FIELDS": "169",
    "EXPECTED_FINAL_WRFTWO_FIELDS": "167",
    "EXPECTED_FINAL_WRFNAT_FIELDS": "1167",
}

passed = 0
failed = 0

def test(name, data, success, exports=None, error=None):
    global passed, failed

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "config.yaml"
        path.write_text(yaml.safe_dump(data))

        result = subprocess.run(
            [sys.executable, str(loader), str(path)],
            env=os.environ.copy(),
            capture_output=True,
            text=True,
        )

    ok = (result.returncode == 0) == success

    if not success and error:
        ok = ok and error in result.stderr

    if success and ok and exports:
        actual = {}

        for line in result.stdout.splitlines():
            parts = shlex.split(line)

            if len(parts) == 2 and parts[0] == "export":
                key, value = parts[1].split("=", 1)
                actual[key] = value

        ok = all(
            actual.get(key) == value
            for key, value in exports.items()
        )

    if ok:
        passed += 1
        print(f"[PASS] {name}")
    else:
        failed += 1
        print(f"[FAIL] {name}")
        print(result.stderr)

# 1. Current configuration.
test("Current YAML", base, True, expected)

# 2. Legacy configuration.
old = copy.deepcopy(base)

for key in expected:
    old["workflow"].pop(key.lower(), None)

test("Legacy YAML defaults", old, True, expected)

# 3. Customized inventory.
custom = copy.deepcopy(base)
custom["workflow"]["expected_raw_wrfnat_fields"] = 1001
custom["workflow"]["expected_final_wrfnat_fields"] = 1168

custom_expected = dict(expected)
custom_expected["EXPECTED_RAW_WRFNAT_FIELDS"] = "1001"
custom_expected["EXPECTED_FINAL_WRFNAT_FIELDS"] = "1168"

test("Valid custom inventory", custom, True, custom_expected)

# 4-8. Invalid count values.
for value in [0, -1, 1000.5, "invalid", True]:
    bad = copy.deepcopy(base)
    bad["workflow"]["expected_raw_wrfnat_fields"] = value

    test(
        f"Reject invalid count {value!r}",
        bad,
        False,
        error="must be a positive integer",
    )

# 9. Inconsistent final WRFNAT.
bad = copy.deepcopy(base)
bad["workflow"]["expected_final_wrfnat_fields"] = 1168

test(
    "Reject inconsistent final WRFNAT",
    bad,
    False,
    error="expected_final_wrfnat_fields must equal",
)

# 10. Excessive processed WRFTWO.
bad = copy.deepcopy(base)
bad["workflow"]["expected_final_wrftwo_fields"] = 170
bad["workflow"]["expected_final_wrfnat_fields"] = 1170

test(
    "Reject excessive processed WRFTWO",
    bad,
    False,
    error="expected_final_wrftwo_fields cannot exceed",
)

print()
print("===== Configuration test summary =====")
print(f"PASS: {passed}")
print(f"FAIL: {failed}")

sys.exit(1 if failed else 0)
PY
