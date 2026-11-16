#!/bin/bash
#
# Compare all 18 BC_PREP members for forecast hours 00-25.
#
set -euo pipefail

CYCLE="${1:-2026111512}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0

echo "=================================================="
echo "WoFS BC_PREP Full-Ensemble Comparison"
echo "Cycle:          $CYCLE"
echo "Members:        0001-0018"
echo "Forecast hours: 00-25"
echo "Expected pairs: 468"
echo "=================================================="

for m in $(seq 1 18); do

    MEM4=$(printf '%04d' "$m")

    echo
    echo "===== Comparing member $MEM4 ====="

    if bash "$SCRIPT_DIR/compare_wofs_pert_grib2.sh" \
        "$CYCLE" "$m"; then

        PASS=$((PASS+1))

    else

        FAIL=$((FAIL+1))

    fi

done

echo
echo "=================================================="
echo " FULL-ENSEMBLE COMPARISON SUMMARY"
echo "=================================================="
echo "Cycle:              $CYCLE"
echo "Expected members:   18"
echo "Expected pairs:     468"
echo "Members passed:     $PASS"
echo "Members failed:     $FAIL"
echo "=================================================="

if [[ "$PASS" -eq 18 ]]; then
    echo "[PASS] All 468 GRIB2 file pairs are BYTE-IDENTICAL"
    exit 0
else
    echo "[FAIL] Some ensemble members did not pass"
    exit 1
fi
