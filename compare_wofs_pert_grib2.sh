#!/bin/bash
#
# Compare legacy and target WoF_BC HRRR perturbation GRIB2
# files for forecast hours 00-25.
#
# Usage:
#   ./compare_wofs_pert_grib2.sh [CYCLE] [MEMBER]
#
# Examples:
#   ./compare_wofs_pert_grib2.sh 2026111512 1
#   ./compare_wofs_pert_grib2.sh 2026111512 2
#
set -euo pipefail

CYCLE="${1:-2026111512}"
MEMBER="$(printf '%04d' "$((10#${2:-1}))")"

LEGACY_ROOT="${LEGACY_ROOT:-/scratch4/NCEPDEV/stmp/Jianping.Huang/WoF_BC}"

TARGET_ROOT="${TARGET_ROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang/WoF_BC_20261115_validation}"

LEGACY="${LEGACY_ROOT}/pert_hrrr/${CYCLE}/postprd_mem${MEMBER}"

TARGET="${TARGET_ROOT}/pert_hrrr/${CYCLE}/postprd_mem${MEMBER}"

PREFIX="wrfnat_pert_hrrr_mem${MEMBER}"

REPORT_DIR="${REPORT_DIR:-${PWD}/compare_pert_grib2_${CYCLE}_mem${MEMBER}}"

mkdir -p "$REPORT_DIR"

SUMMARY="${REPORT_DIR}/summary.txt"
CHECKSUMS="${REPORT_DIR}/checksums.txt"
INVENTORY="${REPORT_DIR}/inventory_comparison.txt"
DETAILS="${REPORT_DIR}/details.txt"

: > "$CHECKSUMS"
: > "$INVENTORY"
: > "$DETAILS"

exec > >(tee "$SUMMARY") 2>&1

echo "============================================================"
echo "WoF_BC GRIB2 comparison"
echo "Cycle:          $CYCLE"
echo "Member:         $MEMBER"
echo "Forecast hours: 00-25"
echo "Legacy:         $LEGACY"
echo "Target:         $TARGET"
echo "Report dir:     $REPORT_DIR"
echo "Started:        $(date)"
echo "============================================================"

if [[ ! -d "$LEGACY" || ! -d "$TARGET" ]]; then
    echo "[ERROR] Legacy or target directory is missing"
    exit 1
fi

legacy_count=0
target_count=0
common_count=0
legacy_only_count=0
target_only_count=0
missing_both_count=0

identical_count=0
different_count=0
error_count=0

echo
echo "===== GRIB2 file comparison ====="

printf '%-5s %15s %15s %-18s\n' \
    "Fhour" "Legacy bytes" "Target bytes" "Result"

echo "------------------------------------------------------------"

for fh in $(seq -w 0 25); do

    fname="${PREFIX}_${fh}.grib2"

    lf="${LEGACY}/${fname}"
    tf="${TARGET}/${fname}"

    lsize="-"
    tsize="-"

    if [[ -s "$lf" ]]; then
        legacy_count=$((legacy_count+1))
        lsize=$(stat -c '%s' "$lf")
    fi

    if [[ -s "$tf" ]]; then
        target_count=$((target_count+1))
        tsize=$(stat -c '%s' "$tf")
    fi

    if [[ -s "$lf" && -s "$tf" ]]; then

        common_count=$((common_count+1))

        # Compare the complete binary files.

        rc=0
        cmp -s "$lf" "$tf" || rc=$?

        if [[ "$rc" -eq 0 ]]; then

            status="IDENTICAL"
            identical_count=$((identical_count+1))

        elif [[ "$rc" -eq 1 ]]; then

            status="DIFFERENT"
            different_count=$((different_count+1))

            # Calculate checksums for different files.

            {
                echo "===== Forecast hour $fh ====="
                sha256sum "$lf" "$tf"
                echo
            } >> "$CHECKSUMS"

            # Compare GRIB2 inventories for different files.

            if command -v wgrib2 >/dev/null 2>&1; then

                lidx="${REPORT_DIR}/legacy_${fh}.idx"
                tidx="${REPORT_DIR}/target_${fh}.idx"
                dfile="${REPORT_DIR}/inventory_diff_${fh}.txt"

                if wgrib2 "$lf" -s > "$lidx" 2>> "$DETAILS" &&
                   wgrib2 "$tf" -s > "$tidx" 2>> "$DETAILS"; then

                    lmsg=$(wc -l < "$lidx")
                    tmsg=$(wc -l < "$tidx")

                    if diff -u "$lidx" "$tidx" > "$dfile"; then
                        inv_status="INVENTORY_IDENTICAL"
                    else
                        inv_status="INVENTORY_DIFFERENT"
                    fi

                    printf '%s %s legacy_messages=%s target_messages=%s\n' \
                        "$fname" "$inv_status" "$lmsg" "$tmsg" \
                        >> "$INVENTORY"

                    if [[ "$inv_status" == "INVENTORY_DIFFERENT" ]]; then
                        {
                            echo "===== $fname ====="
                            cat "$dfile"
                            echo
                        } >> "$DETAILS"
                    fi

                else

                    echo "Inventory extraction failed: $fname" \
                        >> "$DETAILS"

                fi

            else

                echo "wgrib2 unavailable: $fname" >> "$DETAILS"

            fi

        else

            status="ERROR"
            error_count=$((error_count+1))

            echo "cmp failed: $fname" >> "$DETAILS"

        fi

    elif [[ -s "$lf" ]]; then

        status="LEGACY_ONLY"
        legacy_only_count=$((legacy_only_count+1))

    elif [[ -s "$tf" ]]; then

        status="TARGET_ONLY"
        target_only_count=$((target_only_count+1))

    else

        status="MISSING_BOTH"
        missing_both_count=$((missing_both_count+1))

    fi

    printf 'f%-4s %15s %15s %-18s\n' \
        "$fh" "$lsize" "$tsize" "$status"

done

echo
echo "============================================================"
echo " COMPARISON SUMMARY"
echo "============================================================"
echo "Cycle:                 $CYCLE"
echo "Member:                $MEMBER"
echo "Expected files:        26"
echo "Legacy files:          $legacy_count"
echo "Target files:          $target_count"
echo "Common files:          $common_count"
echo "Byte-identical files:  $identical_count"
echo "Different files:       $different_count"
echo "Legacy-only files:     $legacy_only_count"
echo "Target-only files:     $target_only_count"
echo "Missing in both:       $missing_both_count"
echo "Comparison errors:     $error_count"
echo "============================================================"

echo
echo "===== Reports ====="
echo "Summary:      $SUMMARY"
echo "Checksums:    $CHECKSUMS"
echo "Inventories:  $INVENTORY"
echo "Differences:  $DETAILS"
echo
echo "Finished: $(date)"

if [[ "$identical_count" -eq 26 ]]; then

    echo "[PASS] All 26 forecast hours are BYTE-IDENTICAL"
    exit 0

else

    echo "[FAIL] Not all 26 forecast hours are byte-identical"
    exit 1

fi
