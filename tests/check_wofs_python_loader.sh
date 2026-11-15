#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

export HOMEwofs="$ROOT"

# Usage:
#   check_wofs_python_loader.sh /path/to/venv/bin/python3
#
# Run on Ursa with the WoFS module environment available.

if [[ "$#" -ne 1 || "$1" != /* || ! -x "$1" ]]; then
    echo "Usage: $0 /absolute/path/to/venv/bin/python3" >&2
    exit 1
fi

PY="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
VENV="$(dirname "$(dirname "$PY")")"

mkdir -p "$ROOT/staging"

REPORT="$(mktemp -d "$ROOT/staging/python_loader_test.XXXXXXXX")"

echo "REPORT=$REPORT"

# Use an isolated repository structure for default-path tests.

FIXTURE="$REPORT/repository"

mkdir -p "$FIXTURE/versions"
mkdir -p "$FIXTURE/tests"
mkdir -p "$FIXTURE/sorc"

cp "$ROOT/versions/run.ver" "$FIXTURE/versions/"
cp "$ROOT/tests/check_wofs_python.sh" "$FIXTURE/tests/"
cp "$ROOT/sorc/requirements_wofs.txt" "$FIXTURE/sorc/"

source versions/run.ver

module purge
module use "$ROOT/modulefiles"
module load "$wofs_modulefile"

OLD_PY="$(command -v python3)"

[[ -x "$OLD_PY" ]]
[[ "$OLD_PY" != "$PY" ]]

PASS=0

run_test() {

    local NAME="$1"
    local EXPECTED="$2"
    local MESSAGE="$3"

    shift 3

    if ( "$@" ) > "$REPORT/${NAME}.log" 2>&1; then
        STATUS=0
    else
        STATUS=$?
    fi

    if [[ "$EXPECTED" == PASS && "$STATUS" -ne 0 ]]; then
        cat "$REPORT/${NAME}.log"
        return 1
    fi

    if [[ "$EXPECTED" == FAIL && "$STATUS" -eq 0 ]]; then
        echo "[FAIL] Unexpected success: $NAME"
        return 1
    fi

    grep -Fq "$MESSAGE" "$REPORT/${NAME}.log"

    echo "[PASS] $NAME"

    PASS=$((PASS + 1))
}

reset_settings() {

    unset WOFS_PYTHON IC_PREP_PYTHON WOFS_PYTHON_ENV
}

verify_runtime() {

    [[ "$WOFS_PYTHON" == "$PY" ]]
    [[ "$IC_PREP_PYTHON" == "$PY" ]]
    [[ "$PYTHONNOUSERSITE" == 1 ]]
    [[ -z "${PYTHONPATH+x}" ]]
    [[ -z "${PYTHONHOME+x}" ]]

    "$WOFS_PYTHON" -c \
        'import sys; assert sys.prefix != sys.base_prefix'
}

explicit_python() {

    reset_settings

    export WOFS_PYTHON="$PY"

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

legacy_python() {

    reset_settings

    export IC_PREP_PYTHON="$PY"

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

explicit_environment() {

    reset_settings

    export WOFS_PYTHON_ENV="$VENV"

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

matching_settings() {

    reset_settings

    export WOFS_PYTHON="$PY"
    export IC_PREP_PYTHON="$PY"
    export WOFS_PYTHON_ENV="$VENV"

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

conflicting_interpreters() {

    reset_settings

    export WOFS_PYTHON="$PY"
    export IC_PREP_PYTHON="$OLD_PY"

    source "$ROOT/ush/load_wofs_python.sh"
}

conflicting_environment() {

    reset_settings

    export WOFS_PYTHON="$OLD_PY"
    export WOFS_PYTHON_ENV="$VENV"

    source "$ROOT/ush/load_wofs_python.sh"
}

invalid_interpreter() {

    reset_settings

    export WOFS_PYTHON="$REPORT/nonexistent/python3"

    source "$ROOT/ush/load_wofs_python.sh"
}

relative_interpreter() {

    reset_settings

    export WOFS_PYTHON=python3

    source "$ROOT/ush/load_wofs_python.sh"
}

missing_default() {

    reset_settings

    export HOMEwofs="$FIXTURE"

    [[ ! -e "$FIXTURE/python_env" ]] || return 2

    source "$ROOT/ush/load_wofs_python.sh"
}

base_python() {

    reset_settings

    export WOFS_PYTHON="$(command -v python3)"

    source "$ROOT/ush/load_wofs_python.sh"
}

missing_homewofs() {

    reset_settings

    unset HOMEwofs

    source "$ROOT/ush/load_wofs_python.sh"
}

environment_isolation() {

    reset_settings

    export WOFS_PYTHON="$PY"
    export PYTHONNOUSERSITE=0
    export PYTHONPATH="$REPORT/nonexistent"
    export PYTHONHOME="$REPORT/nonexistent"

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

default_environment() {

    reset_settings

    export HOMEwofs="$FIXTURE"

    ln -s "$VENV" "$FIXTURE/python_env" || return 1

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    [[ "$WOFS_PYTHON" == "$FIXTURE/python_env/bin/python3" ]] \
        || return 1

    [[ "$IC_PREP_PYTHON" == "$WOFS_PYTHON" ]] || return 1

    "$WOFS_PYTHON" -c \
        'import sys; assert sys.prefix != sys.base_prefix'
}

repeated_initialization() {

    reset_settings

    export WOFS_PYTHON="$PY"

    source "$ROOT/ush/load_wofs_python.sh" || return 1
    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

canonical_directory() {

    reset_settings

    export WOFS_PYTHON="$VENV/bin/../bin/$(basename "$PY")"
    export IC_PREP_PYTHON="$PY"

    source "$ROOT/ush/load_wofs_python.sh" || return 1

    verify_runtime
}

failed_initialization() {

    reset_settings

    export WOFS_PYTHON="$REPORT/nonexistent/python3"

    if source "$ROOT/ush/load_wofs_python.sh"; then
        return 1
    fi

    [[ "$WOFS_PYTHON" == "$REPORT/nonexistent/python3" ]] \
        || return 1

    [[ -z "${IC_PREP_PYTHON+x}" ]] || return 1

    echo "[PASS] Failed initialization preserved settings"
}

echo "===== Phase P3 runtime loader tests ====="

OK="[PASS] Shared WoFS Python runtime initialized"

run_test explicit_python PASS "$OK" explicit_python

run_test legacy_python PASS "$OK" legacy_python

run_test explicit_environment PASS "$OK" explicit_environment

run_test matching_settings PASS "$OK" matching_settings

run_test conflicting_interpreters FAIL \
    "Conflicting Python settings" conflicting_interpreters

run_test conflicting_environment FAIL \
    "Conflicting Python settings" conflicting_environment

run_test invalid_interpreter FAIL \
    "Invalid Python interpreter" invalid_interpreter

run_test relative_interpreter FAIL \
    "must be an absolute path" relative_interpreter

run_test missing_default FAIL \
    "WoFS Python environment not found" missing_default

run_test base_python FAIL \
    "Virtual environment active" base_python

run_test missing_homewofs FAIL \
    "HOMEwofs is required" missing_homewofs

run_test environment_isolation PASS \
    "$OK" environment_isolation

echo
run_test default_environment PASS "$OK" default_environment

run_test repeated_initialization PASS "$OK" repeated_initialization

run_test canonical_directory PASS "$OK" canonical_directory

run_test failed_initialization PASS \
    "Failed initialization preserved settings" failed_initialization

echo
echo "===== Validate loader under BC_PREP modules ====="

(
    source versions/bc_prep.ver

    module purge
    module use "$ROOT/modulefiles"
    module load "$wofs_modulefile"

    explicit_python

    [[ "$wofs_component" == bc_prep ]]
    [[ "$wofs_modulefile" == ursa_bc_prep ]]

) > "$REPORT/bc_prep_loader.log" 2>&1

echo "[PASS] BC_PREP loader and component settings"

PASS=$((PASS + 1))

echo
echo "===== Final validation summary ====="

echo "PASS=$PASS"
echo "EXPECTED=17"
echo "REPORT=$REPORT"

[[ "$PASS" -eq 17 ]]

echo "[PASS] All seventeen WoFS Python loader checks"
