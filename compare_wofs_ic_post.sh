#!/usr/bin/env bash
#
# Compare legacy and target WoFS IC_PREP POST GRIB2 outputs
# for all 36 ensemble members.
#
# Usage:
#   ./compare_wofs_ic_post.sh [INIT_TIME] [PDY] [cyc] [FHOUR]
#
# Example:
#   ./compare_wofs_ic_post.sh 2026111514 20261115 15 01
#
set -euo pipefail

CYCLE="${1:-2026111514}"
PDY="${2:-20261115}"
cyc="$(printf '%02d' "$((10#${3:-15}))")"
FHOUR="$(printf '%02d' "$((10#${4:-1}))")"

ENS_SIZE="${ENS_SIZE:-36}"

LEGACY_ROOT="${LEGACY_ROOT:-/scratch4/NCEPDEV/stmp/Jianping.Huang/WoF_IC/hrrrdas}"

TARGET_ROOT="${TARGET_ROOT:-/scratch3/NCEPDEV/stmp/Jianping.Huang/com/wofs/v1.0}"

REPORT_DIR="${REPORT_DIR:-$(pwd)/compare_ic_post_${CYCLE}_f${FHOUR}_$(date +%Y%m%d_%H%M%S)}"

mkdir -p "$REPORT_DIR"

SUMMARY="$REPORT_DIR/summary.txt"
DETAILS="$REPORT_DIR/details.txt"
RESULTS="$REPORT_DIR/results.tsv"
CHECKSUMS="$REPORT_DIR/checksums.txt"

: > "$DETAILS"
: > "$CHECKSUMS"

printf 'Member\tLegacy_bytes\tTarget_bytes\tResult\n' > "$RESULTS"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/wofs_grib_compare.XXXXXXXX")"

trap 'rm -rf "$WORK"' EXIT

# Save terminal output to the summary report.
exec > >(tee "$SUMMARY") 2>&1

echo "============================================================"
echo " WoFS IC_PREP POST Full-Ensemble GRIB2 Comparison"
echo "============================================================"
echo "Initialization : $CYCLE"
echo "PDY            : $PDY"
echo "WoFS cycle     : $cyc"
echo "Forecast hour  : $FHOUR"
echo "Ensemble size  : $ENS_SIZE"
echo "Legacy root    : $LEGACY_ROOT"
echo "Target root    : $TARGET_ROOT"
echo "Report dir     : $REPORT_DIR"
echo "Started        : $(date -u)"
echo "============================================================"
echo

IDENTICAL=0
DECODED_EQUAL=0
DIFFERENT=0
MISSING=0
ERRORS=0

printf '%-8s %15s %15s %-20s\n' \
    "Member" "Legacy bytes" "Target bytes" "Result"

printf '%s\n' \
    "----------------------------------------------------------------"

for ((m=1; m<=ENS_SIZE; m++)); do

    MEMBER="$(printf '%04d' "$m")"
    MEMBER2="$(printf '%02d' "$m")"

    NAME="wrfnat_hrrre_newse_mem${MEMBER}_${FHOUR}.grib2"

    LEGACY="${LEGACY_ROOT}/${CYCLE}/postprd_mem${MEMBER}/${NAME}"

    TARGET="${TARGET_ROOT}/wofs.${PDY}/${cyc}/INPUT/mem${MEMBER2}/${NAME}"

    LSIZE="-"
    TSIZE="-"
    STATUS=""

    # --------------------------------------------------------
    # 1. Check file availability
    # --------------------------------------------------------

    if [[ -f "$LEGACY" ]]; then
        LSIZE="$(stat -c '%s' "$LEGACY")"
    fi

    if [[ -f "$TARGET" ]]; then
        TSIZE="$(stat -c '%s' "$TARGET")"
    fi

    if [[ ! -s "$LEGACY" || ! -s "$TARGET" ]]; then

        STATUS="MISSING"
        ((MISSING+=1))

        {
            echo "===== Member $MEMBER ====="
            [[ -s "$LEGACY" ]] || \
                echo "Missing or empty legacy: $LEGACY"
            [[ -s "$TARGET" ]] || \
                echo "Missing or empty target: $TARGET"
            echo
        } >> "$DETAILS"

    else

        # ----------------------------------------------------
        # 2. Byte-for-byte comparison
        # ----------------------------------------------------

        CMP_STATUS=0

        cmp -s "$LEGACY" "$TARGET" || CMP_STATUS=$?

        if [[ "$CMP_STATUS" -eq 0 ]]; then

            STATUS="IDENTICAL"
            ((IDENTICAL+=1))

        elif [[ "$CMP_STATUS" -gt 1 ]]; then

            STATUS="ERROR"
            ((ERRORS+=1))

            echo "Member $MEMBER: cmp failed" >> "$DETAILS"

        else

            # ------------------------------------------------
            # 3. Detailed comparison for nonidentical files
            # ------------------------------------------------

            {
                echo "=================================================="
                echo "Member: $MEMBER"
                echo "Legacy: $LEGACY"
                echo "Target: $TARGET"
                echo "Legacy size: $LSIZE"
                echo "Target size: $TSIZE"
                echo "=================================================="
            } >> "$DETAILS"

            {
                echo "===== Member $MEMBER ====="
                sha256sum "$LEGACY" "$TARGET"
                echo
            } >> "$CHECKSUMS"

            if ! command -v wgrib2 >/dev/null; then

                STATUS="ERROR"
                ((ERRORS+=1))

                echo "wgrib2 is unavailable" >> "$DETAILS"

            elif ! wgrib2 "$LEGACY" -s > "$WORK/legacy.inv" \
                2>> "$DETAILS" ||
                 ! wgrib2 "$TARGET" -s > "$WORK/target.inv" \
                2>> "$DETAILS"; then

                STATUS="ERROR"
                ((ERRORS+=1))

                echo "GRIB2 inventory extraction failed" >> "$DETAILS"

            else

                NLEGACY="$(wc -l < "$WORK/legacy.inv")"
                NTARGET="$(wc -l < "$WORK/target.inv")"

                {
                    echo "Legacy messages: $NLEGACY"
                    echo "Target messages: $NTARGET"
                } >> "$DETAILS"

                if [[ "$NLEGACY" -eq 0 || "$NTARGET" -eq 0 ]]; then

                    STATUS="ERROR"
                    ((ERRORS+=1))

                    echo "Empty GRIB2 inventory" >> "$DETAILS"

                elif [[ "$NLEGACY" -ne "$NTARGET" ]]; then

                    STATUS="DIFFERENT"
                    ((DIFFERENT+=1))

                    echo "GRIB2 message counts differ" >> "$DETAILS"

                    diff -u \
                        "$WORK/legacy.inv" \
                        "$WORK/target.inv" \
                        >> "$DETAILS" || true

                else

                    # Remove byte offsets from inventories.
                    # Offsets may differ because of GRIB2 packing.

                    cut -d: -f1,3- "$WORK/legacy.inv" \
                        > "$WORK/legacy.normalized.inv"

                    cut -d: -f1,3- "$WORK/target.inv" \
                        > "$WORK/target.normalized.inv"

                    INV_MATCH=0

                    if cmp -s \
                        "$WORK/legacy.normalized.inv" \
                        "$WORK/target.normalized.inv"; then

                        INV_MATCH=1

                        echo "Normalized inventories match" \
                            >> "$DETAILS"

                    else

                        echo "Normalized inventories differ" \
                            >> "$DETAILS"

                        diff -u \
                            "$WORK/legacy.normalized.inv" \
                            "$WORK/target.normalized.inv" \
                            >> "$DETAILS" || true

                    fi

                    # ----------------------------------------
                    # 4. Compare decoded meteorological fields
                    # ----------------------------------------

                    FIELD_PASS=0
                    FIELD_FAIL=0
                    FIELD_ERRORS=0

                    for ((i=1; i<=NLEGACY; i++)); do

                        rm -f "$WORK/legacy.bin" "$WORK/target.bin"

                        # Use inventory record identifiers,
                        # including submessage identifiers.

                        LREC="$(sed -n "${i}p" "$WORK/legacy.inv")"
                        TREC="$(sed -n "${i}p" "$WORK/target.inv")"

                        LREC="${LREC%%:*}"
                        TREC="${TREC%%:*}"

                        if ! wgrib2 "$LEGACY" -d "$LREC" \
                            -no_header -bin "$WORK/legacy.bin" \
                            > /dev/null 2>> "$DETAILS"; then

                            ((FIELD_ERRORS+=1))

                            echo "Cannot decode legacy field $LREC" \
                                >> "$DETAILS"

                            continue
                        fi

                        if ! wgrib2 "$TARGET" -d "$TREC" \
                            -no_header -bin "$WORK/target.bin" \
                            > /dev/null 2>> "$DETAILS"; then

                            ((FIELD_ERRORS+=1))

                            echo "Cannot decode target field $TREC" \
                                >> "$DETAILS"

                            continue
                        fi

                        if [[ ! -s "$WORK/legacy.bin" ||
                              ! -s "$WORK/target.bin" ]]; then

                            ((FIELD_ERRORS+=1))

                            echo "Empty decoded field $i" \
                                >> "$DETAILS"

                            continue
                        fi

                        if cmp -s \
                            "$WORK/legacy.bin" \
                            "$WORK/target.bin"; then

                            ((FIELD_PASS+=1))

                        else

                            ((FIELD_FAIL+=1))

                            {
                                echo "[DIFFERENT] Field $i"

                                sed -n "${i}p" "$WORK/legacy.inv"

                                sed -n "${i}p" "$WORK/target.inv"

                            } >> "$DETAILS"

                        fi

                    done

                    {
                        echo "Decoded fields equal  : $FIELD_PASS"
                        echo "Decoded fields differ : $FIELD_FAIL"
                        echo "Decode errors         : $FIELD_ERRORS"
                        echo
                    } >> "$DETAILS"

                    if [[ "$FIELD_ERRORS" -gt 0 ]]; then

                        STATUS="ERROR"
                        ((ERRORS+=1))

                    elif [[ "$FIELD_FAIL" -eq 0 &&
                            "$INV_MATCH" -eq 1 &&
                            "$FIELD_PASS" -eq "$NLEGACY" ]]; then

                        STATUS="DECODED_EQUAL"
                        ((DECODED_EQUAL+=1))

                    else

                        STATUS="DIFFERENT"
                        ((DIFFERENT+=1))

                    fi

                fi

            fi

        fi

    fi

    printf '%-8s %15s %15s %-20s\n' \
        "$MEMBER" "$LSIZE" "$TSIZE" "$STATUS"

    printf '%s\t%s\t%s\t%s\n' \
        "$MEMBER" "$LSIZE" "$TSIZE" "$STATUS" \
        >> "$RESULTS"

done

# ------------------------------------------------------------
# 5. Full-ensemble summary
# ------------------------------------------------------------

TOTAL=$((IDENTICAL + DECODED_EQUAL + DIFFERENT + MISSING + ERRORS))

PASS=$((IDENTICAL + DECODED_EQUAL))

echo
echo "============================================================"
echo " FULL-ENSEMBLE COMPARISON SUMMARY"
echo "============================================================"
echo "Initialization          : $CYCLE"
echo "Forecast hour           : $FHOUR"
echo "Total members           : $TOTAL"
echo "Byte-identical          : $IDENTICAL"
echo "Decoded fields equal    : $DECODED_EQUAL"
echo "Different               : $DIFFERENT"
echo "Missing                 : $MISSING"
echo "Errors                  : $ERRORS"
echo "Total passed            : $PASS"
echo "============================================================"

if [[ "$IDENTICAL" -eq "$ENS_SIZE" ]]; then

    echo "[PASS] All $ENS_SIZE members are BYTE-IDENTICAL"
    FINAL_STATUS=0

elif [[ "$PASS" -eq "$ENS_SIZE" ]]; then

    echo "[PASS] All $ENS_SIZE members match in the tested comparisons"
    echo "[INFO] Some GRIB2 binary representations differ"
    FINAL_STATUS=0

else

    echo "[FAIL] Some ensemble members did not pass"
    FINAL_STATUS=1

fi

echo
echo "===== Reports ====="
echo "Summary   : $SUMMARY"
echo "Results   : $RESULTS"
echo "Checksums : $CHECKSUMS"
echo "Details   : $DETAILS"
echo
echo "Finished: $(date -u)"

exit "$FINAL_STATUS"

