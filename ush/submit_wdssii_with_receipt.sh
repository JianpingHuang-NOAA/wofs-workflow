#!/bin/bash
set -euo pipefail

if (( $# != 1 )); then
    echo "Usage: $0 /absolute/path/to/submit_wdssii_array.sh" >&2
    exit 2
fi

launcher=$(realpath -e -- "$1")
: "${RADAR_RUN_ROOT:?Set RADAR_RUN_ROOT}"
: "${CDATE:?Set CDATE}"
: "${DOMAIN:?Set DOMAIN}"

receipt_dir=$(mktemp -d "$RADAR_RUN_ROOT/.wdssii-receipt.XXXXXXXX")
trap 'rm -f -- "$receipt_dir/stage.json"; rmdir -- "$receipt_dir"' EXIT

export WOFS_WDSSII_RECEIPT="$receipt_dir/stage.json"
export WOFS_WDSSII_RECEIPT_PYTHON="${RADAR_CONFIG_PYTHON:-python3}"
ush_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
export WOFS_WDSSII_RECEIPT_WRITER="$ush_dir/write_wdssii_receipt.py"

bash "$launcher" "$CDATE" "$DOMAIN" ALL >&2
if [[ ! -s "$WOFS_WDSSII_RECEIPT" ]]; then
    echo "WDSS-II launcher did not report a staging receipt. Check its output before retrying." >&2
    exit 1
fi
cat -- "$WOFS_WDSSII_RECEIPT"
