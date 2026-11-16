#!/bin/bash
#
# Summarize WoFS BC_PREP GRIB2 comparison results.
#
# Usage:
#   ./summarize_wofs_pert_grib2.sh [CYCLE]
#
set -euo pipefail

CYCLE="${1:-2026111512}"
ENS_SIZE=18
N_HOURS=26

REPORT_ROOT="/scratch3/NCEPDEV/stmp/Jianping.Huang/compare_pert_grb2_${CYCLE}"

if [[ ! -d "$REPORT_ROOT" ]]; then
    echo "[ERROR] Missing report directory: $REPORT_ROOT"
    exit 1
fi

python3 - "$REPORT_ROOT" "$CYCLE" "$ENS_SIZE" "$N_HOURS" <<'PY'
import sys
import re
from pathlib import Path
from collections import Counter

root = Path(sys.argv[1])
cycle = sys.argv[2]
nmem = int(sys.argv[3])
nhour = int(sys.argv[4])

statuses = [
    "IDENTICAL",
    "DIFFERENT",
    "LEGACY_ONLY",
    "TARGET_ONLY",
    "MISSING_BOTH",
    "ERROR",
    "NO_RESULT",
]

symbols = {
    "IDENTICAL": "I",
    "DIFFERENT": "D",
    "LEGACY_ONLY": "L",
    "TARGET_ONLY": "T",
    "MISSING_BOTH": "M",
    "ERROR": "E",
    "NO_RESULT": "-",
}

matrix = {}
incomplete = []

pattern = re.compile(
    r"^\s*f(\d{2})\s+\S+\s+\S+\s+"
    r"(IDENTICAL|DIFFERENT|LEGACY_ONLY|TARGET_ONLY|"
    r"MISSING_BOTH|ERROR)\s*$"
)

# Read all member comparison reports.

for m in range(1, nmem + 1):

    report = root / f"mem{m:02d}" / "summary.txt"

    results = {}

    if report.is_file():

        content = report.read_text()

        for line in content.splitlines():

            match = pattern.match(line)

            if match:
                h = int(match.group(1))
                results[h] = match.group(2)

        if (
            len(results) != nhour
            or "COMPARISON SUMMARY" not in content
            or not re.search(r"^\[(PASS|FAIL)\]", content, re.M)
        ):
            incomplete.append(m)

    else:

        incomplete.append(m)

    for h in range(nhour):
        matrix[m, h] = results.get(h, "NO_RESULT")


# Summary by ensemble member.

member_file = root / "summary_by_member.tsv"

with member_file.open("w") as f:

    f.write("Member\t" + "\t".join(statuses) + "\tResult\n")

    for m in range(1, nmem + 1):

        counts = Counter(matrix[m, h] for h in range(nhour))

        passed = (
            counts["IDENTICAL"] == nhour
            and m not in incomplete
        )

        result = "PASS" if passed else "FAIL"

        values = "\t".join(str(counts[s]) for s in statuses)

        f.write(f"mem{m:02d}\t{values}\t{result}\n")


# Summary by forecast hour.

hour_file = root / "summary_by_hour.tsv"

with hour_file.open("w") as f:

    f.write("Fhour\t" + "\t".join(statuses) + "\tResult\n")

    for h in range(nhour):

        counts = Counter(
            matrix[m, h] for m in range(1, nmem + 1)
        )

        result = (
            "PASS" if counts["IDENTICAL"] == nmem
            else "FAIL"
        )

        values = "\t".join(str(counts[s]) for s in statuses)

        f.write(f"f{h:02d}\t{values}\t{result}\n")


# Full comparison matrix.

matrix_file = root / "comparison_matrix.txt"

with matrix_file.open("w") as f:

    f.write("Member " + " ".join(
        f"{h:02d}" for h in range(nhour)
    ) + "\n")

    for m in range(1, nmem + 1):

        row = "  ".join(
            symbols[matrix[m, h]] for h in range(nhour)
        )

        f.write(f"mem{m:02d}   {row}\n")

    f.write("\nLegend:\n")

    for status in statuses:
        f.write(f"  {symbols[status]} = {status}\n")


# List all non-identical or unavailable comparisons.

failed_file = root / "failed_comparisons.tsv"

with failed_file.open("w") as f:

    f.write("Member\tFhour\tFilename\tResult\n")

    for m in range(1, nmem + 1):

        for h in range(nhour):

            status = matrix[m, h]

            if status != "IDENTICAL":

                name = (
                    f"wrfnat_pert_hrrr_mem{m:04d}"
                    f"_{h:02d}.grib2"
                )

                f.write(
                    f"mem{m:02d}\tf{h:02d}\t"
                    f"{name}\t{status}\n"
                )


# Overall ensemble summary.

total = Counter(matrix.values())

expected = nmem * nhour

passed_members = sum(
    all(matrix[m, h] == "IDENTICAL" for h in range(nhour))
    and m not in incomplete
    for m in range(1, nmem + 1)
)

passed_hours = sum(
    all(matrix[m, h] == "IDENTICAL"
        for m in range(1, nmem + 1))
    for h in range(nhour)
)

passed = (
    total["IDENTICAL"] == expected
    and not incomplete
)

lines = [
    "=" * 60,
    "WoFS BC_PREP FULL-ENSEMBLE COMPARISON SUMMARY",
    "=" * 60,
    f"Cycle:                    {cycle}",
    f"Ensemble members:         {nmem}",
    f"Forecast hours:           00-{nhour-1:02d}",
    f"Expected file pairs:      {expected}",
    f"Byte-identical files:     {total['IDENTICAL']}",
    f"Different files:          {total['DIFFERENT']}",
    f"Legacy-only files:        {total['LEGACY_ONLY']}",
    f"Target-only files:        {total['TARGET_ONLY']}",
    f"Missing in both:          {total['MISSING_BOTH']}",
    f"Comparison errors:        {total['ERROR']}",
    f"No comparison result:     {total['NO_RESULT']}",
    f"Incomplete reports:       {len(incomplete)}",
    "-" * 60,
    f"Members passed:           {passed_members}/{nmem}",
    f"Forecast hours passed:    {passed_hours}/{nhour}",
    f"Identical percentage:     "
    f"{100.0 * total['IDENTICAL'] / expected:.2f}%",
    "=" * 60,
]

if incomplete:
    lines.append(
        "Incomplete members: " +
        ", ".join(f"mem{m:02d}" for m in incomplete)
    )

if passed:
    lines.append(
        f"[PASS] All {expected} GRIB2 file pairs "
        "are BYTE-IDENTICAL"
    )
else:
    lines.append(
        "[FAIL] Not all comparisons passed"
    )

lines.extend([
    "",
    "Generated reports:",
    str(root / "summary.txt"),
    str(member_file),
    str(hour_file),
    str(matrix_file),
    str(failed_file),
])

summary = "\n".join(lines) + "\n"

(root / "summary.txt").write_text(summary)

print(summary)

sys.exit(0 if passed else 1)

PY
