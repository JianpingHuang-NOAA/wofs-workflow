#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

HELPER="$ROOT/ush/lock_ic_prep.sh"

[[ -f "$HELPER" ]]

TEST_DIR=$(mktemp -d \
    "${TMPDIR:-/tmp}/ic_prep_locking.XXXXXXXX")

HOLDER_PID=""

cleanup()
{
    local status=$?

    trap - EXIT

    if [[ -n "$HOLDER_PID" ]]; then
        kill "$HOLDER_PID" 2>/dev/null || true
        wait "$HOLDER_PID" 2>/dev/null || true
    fi

    rm -rf -- "$TEST_DIR"

    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PASS=0
FAIL=0

check()
{
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

WORK1="$TEST_DIR/work1"
WORK2="$TEST_DIR/work2"

COM1="$TEST_DIR/com1"
COM2="$TEST_DIR/com2"

mkdir -p "$WORK1" "$WORK2" "$COM1" "$COM2"

OUT1="$COM1/wrfnat_mem0001.grib2"
OUT2="$COM2/wrfnat_mem0002.grib2"

WORK_LOCK="$WORK1/.ic_prep_work.lock"
COM_LOCK="$COM1/.wrfnat_mem0001.grib2.lock"

READY="$TEST_DIR/holder.ready"
RELEASE="$TEST_DIR/holder.release"

# Each worker uses a separate Bash process so that it
# does not inherit lock descriptors from another worker.

cat > "$TEST_DIR/worker.sh" <<'WORKER'
#!/usr/bin/env bash
set -euo pipefail

HELPER="$1"
WORK="$2"
OUTPUT="$3"
MODE="$4"

source "$HELPER"

initialize_ic_prep_locks "$WORK" "$OUTPUT"

case "$MODE" in
    success)
        release_ic_prep_locks
        exit 0
        ;;
    failure)
        exit 42
        ;;
    hold)
        READY="$5"
        RELEASE="$6"

        touch "$READY"

        for ((i=0; i<60; i++)); do
            if [[ -f "$RELEASE" ]]; then
                release_ic_prep_locks
                exit 0
            fi
            sleep 1
        done

        exit 1
        ;;
    *)
        exit 2
        ;;
esac
WORKER

run_worker()
{
    bash "$TEST_DIR/worker.sh" \
        "$HELPER" "$1" "$2" "${3:-success}" \
        > "$TEST_DIR/worker.log" 2>&1
}

expect_status()
{
    local expected="$1"
    shift

    local status=0

    "$@" || status=$?

    [[ "$status" == "$expected" ]]
}

wait_for_ready()
{
    for ((i=0; i<30; i++)); do
        [[ ! -f "$READY" ]] || return 0
        sleep 1
    done

    return 1
}

echo "===== Basic lock acquisition ====="

check "Initial dual-lock acquisition" \
    run_worker "$WORK1" "$OUT1"

check "Persistent working lock exists" \
    test -f "$WORK_LOCK"

check "Persistent COM lock exists" \
    test -f "$COM_LOCK"

WORK_INODE=$(stat -c '%d:%i' "$WORK_LOCK")
COM_INODE=$(stat -c '%d:%i' "$COM_LOCK")

echo
echo "===== Start independent lock holder ====="

bash "$TEST_DIR/worker.sh" \
    "$HELPER" "$WORK1" "$OUT1" hold \
    "$READY" "$RELEASE" \
    > "$TEST_DIR/holder.log" 2>&1 &

HOLDER_PID=$!

if ! wait_for_ready; then
    cat "$TEST_DIR/holder.log"
    echo "ERROR: Lock holder failed to initialize" >&2
    exit 1
fi

check "Lock holder acquired both resources" \
    test -f "$READY"

echo
echo "===== Concurrent execution tests ====="

check "Reject same work and same COM" \
    expect_status 75 run_worker "$WORK1" "$OUT1"

check "Reject same work and different COM" \
    expect_status 75 run_worker "$WORK1" "$OUT2"

check "Reject different work and same COM" \
    expect_status 75 run_worker "$WORK2" "$OUT1"

check "Allow independent work and COM" \
    run_worker "$WORK2" "$OUT2"

# This also verifies that the previous COM conflict
# did not leave WORK2 locked.

check "Release work lock after COM conflict" \
    run_worker "$WORK2" "$OUT2"

echo
echo "===== Release and reacquisition ====="

touch "$RELEASE"

check "Lock holder exits successfully" \
    wait "$HOLDER_PID"

HOLDER_PID=""

check "Reacquire both locks after release" \
    run_worker "$WORK1" "$OUT1"

check "Working lock inode preserved" \
    test "$(stat -c '%d:%i' "$WORK_LOCK")" \
         = "$WORK_INODE"

check "COM lock inode preserved" \
    test "$(stat -c '%d:%i' "$COM_LOCK")" \
         = "$COM_INODE"

echo
echo "===== Failure and automatic release ====="

check "Worker returns expected failure status" \
    expect_status 42 run_worker \
        "$WORK1" "$OUT1" failure

check "Locks released after failed process" \
    run_worker "$WORK1" "$OUT1"

echo
echo "===== Unsafe lock-file tests ====="

BAD_WORK="$TEST_DIR/bad_work"
BAD_COM="$TEST_DIR/bad_com"

mkdir -p "$BAD_WORK" "$BAD_COM"

BAD_OUT="$BAD_COM/wrfnat_bad.grib2"
BAD_WORK_LOCK="$BAD_WORK/.ic_prep_work.lock"
BAD_COM_LOCK="$BAD_COM/.wrfnat_bad.grib2.lock"

touch "$TEST_DIR/lock_target"

ln -s "$TEST_DIR/lock_target" "$BAD_WORK_LOCK"

check "Reject symbolic-link working lock" \
    expect_status 1 run_worker "$BAD_WORK" "$BAD_OUT"

rm -- "$BAD_WORK_LOCK"

ln "$TEST_DIR/lock_target" "$BAD_WORK_LOCK"

check "Reject hard-linked working lock" \
    expect_status 1 run_worker "$BAD_WORK" "$BAD_OUT"

rm -- "$BAD_WORK_LOCK"

ln -s "$TEST_DIR/lock_target" "$BAD_COM_LOCK"

check "Reject symbolic-link COM lock" \
    expect_status 1 run_worker "$BAD_WORK" "$BAD_OUT"

rm -- "$BAD_COM_LOCK"

ln "$TEST_DIR/lock_target" "$BAD_COM_LOCK"

check "Reject hard-linked COM lock" \
    expect_status 1 run_worker "$BAD_WORK" "$BAD_OUT"

rm -- "$BAD_COM_LOCK"

check "Acquire locks after unsafe COM rejection" \
    run_worker "$BAD_WORK" "$BAD_OUT"

echo
echo "===== Canonical directory aliases ====="

ln -s "$WORK1" "$TEST_DIR/work_alias"
ln -s "$COM1" "$TEST_DIR/com_alias"

check "Acquire locks through directory aliases" \
    run_worker "$TEST_DIR/work_alias" \
        "$TEST_DIR/com_alias/wrfnat_mem0001.grib2"

check "Alias preserves working lock identity" \
    test "$(stat -c '%d:%i' "$WORK_LOCK")" \
         = "$WORK_INODE"

check "Alias preserves COM lock identity" \
    test "$(stat -c '%d:%i' "$COM_LOCK")" \
         = "$COM_INODE"

echo
echo "===== IC_PREP locking test summary ====="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if (( FAIL != 0 )); then
    exit 1
fi

echo "[PASS] IC_PREP locking regression"
