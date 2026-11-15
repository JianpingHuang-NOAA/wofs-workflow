#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "$ROOT/ush/publish_ic_prep_grib2.sh"

TEST_DIR="$(mktemp -d \
    "${TMPDIR:-/tmp}/ic_prep_atomic_test.XXXXXXXX")"

trap 'rm -rf -- "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/com"

SOURCE="$TEST_DIR/source.grib2"
DEST="$TEST_DIR/com/final.grib2"
REFERENCE="$TEST_DIR/reference.grib2"

PASS=0
FAIL=0

check() {
    local label="$1"
    shift

    if "$@"; then
        echo "[PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $label"
        FAIL=$((FAIL + 1))
    fi
}

# Simulated inventory validator.
# Each text line represents one GRIB2 record.
validate_grib2_count() {
    local file="$1"
    local expected="$2"
    local actual

    [[ -s "$file" ]] || return 1

    actual="$(wc -l < "$file")"

    [[ "$actual" -eq "$expected" ]]
}

publish() {
    publish_ic_prep_grib2 "$@" \
        > "$TEST_DIR/publication.log" 2>&1
}

expect_failure() {
    if publish "$@"; then
        return 1
    fi

    return 0
}

no_temporary_files() {
    local count

    count="$(find "$TEST_DIR/com" \
        -maxdepth 1 \
        -name '.*.tmp.*' \
        -print | wc -l)"

    [[ "$count" -eq 0 ]]
}

# --------------------------------------------------
# 1. Initial publication
# --------------------------------------------------

printf 'record 1\nrecord 2\n' > "$SOURCE"

check "Initial publication" \
    publish "$SOURCE" "$DEST" 2

check "Initial product is bitwise identical" \
    cmp -s "$SOURCE" "$DEST"

# --------------------------------------------------
# 2. Replace existing product
# --------------------------------------------------

printf 'new record 1\nnew record 2\n' > "$SOURCE"

check "Replace existing COM product" \
    publish "$SOURCE" "$DEST" 2

check "Replacement product is bitwise identical" \
    cmp -s "$SOURCE" "$DEST"

cp "$DEST" "$REFERENCE"

# --------------------------------------------------
# 3. Missing source
# --------------------------------------------------

check "Reject missing source" \
    expect_failure "$TEST_DIR/missing.grib2" "$DEST" 2

# --------------------------------------------------
# 4. Empty source
# --------------------------------------------------

touch "$TEST_DIR/empty.grib2"

check "Reject empty source" \
    expect_failure "$TEST_DIR/empty.grib2" "$DEST" 2

# --------------------------------------------------
# 5. Incorrect inventory
# --------------------------------------------------

printf 'one record\n' > "$SOURCE"

check "Reject incorrect inventory" \
    expect_failure "$SOURCE" "$DEST" 2

check "Preserve COM after inventory failure" \
    cmp -s "$REFERENCE" "$DEST"

# Restore a valid two-record source.
printf 'candidate 1\ncandidate 2\n' > "$SOURCE"

# --------------------------------------------------
# 6. Simulate copy failure
# --------------------------------------------------

cp() {
    return 1
}

check "Reject copy failure" \
    expect_failure "$SOURCE" "$DEST" 2

unset -f cp

check "Preserve COM after copy failure" \
    cmp -s "$REFERENCE" "$DEST"

# --------------------------------------------------
# 7. Simulate byte comparison failure
# --------------------------------------------------

cmp() {
    return 1
}

check "Reject byte comparison failure" \
    expect_failure "$SOURCE" "$DEST" 2

unset -f cmp

check "Preserve COM after comparison failure" \
    cmp -s "$REFERENCE" "$DEST"

# --------------------------------------------------
# 8. Simulate rename failure
# --------------------------------------------------

mv() {
    return 1
}

check "Reject rename failure" \
    expect_failure "$SOURCE" "$DEST" 2

unset -f mv

check "Preserve COM after rename failure" \
    cmp -s "$REFERENCE" "$DEST"

# --------------------------------------------------
# 9. Failed first publication
# --------------------------------------------------

NEW_DEST="$TEST_DIR/com/new_product.grib2"

check "Reject invalid initial publication" \
    expect_failure "$SOURCE" "$NEW_DEST" 3

check "No final product after failed initial publication" \
    test ! -e "$NEW_DEST"

# --------------------------------------------------
# Additional defensive error-handling tests
# --------------------------------------------------

mktemp() {
    return 1
}

check "Reject mktemp failure" \
    expect_failure "$SOURCE" "$DEST" 2

unset -f mktemp

check "Preserve COM after mktemp failure" \
    cmp -s "$REFERENCE" "$DEST"

chmod() {
    return 1
}

check "Reject chmod failure" \
    expect_failure "$SOURCE" "$DEST" 2

unset -f chmod

check "Preserve COM after chmod failure" \
    cmp -s "$REFERENCE" "$DEST"

check "Reject identical source and destination" \
    expect_failure "$DEST" "$DEST" 2

check "Preserve identical source and destination" \
    cmp -s "$REFERENCE" "$DEST"

# --------------------------------------------------
# 10. Temporary-file cleanup
# --------------------------------------------------

check "No leftover temporary COM files" \
    no_temporary_files

echo
echo "===== Atomic publication test summary ====="

echo "PASS: $PASS"
echo "FAIL: $FAIL"

(( FAIL == 0 ))

echo "[PASS] Atomic publication tests"
