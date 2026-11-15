#!/bin/bash
#
# Initialize the shared WoFS v1.0 Python runtime.
#
# Source this file after loading the component modules.
#
# Interpreter selection:
#   1. WOFS_PYTHON
#   2. IC_PREP_PYTHON (legacy compatibility)
#   3. WOFS_PYTHON_ENV/bin/python3
#   4. ${HOMEwofs}/python_env/bin/python3
#
# Conflicting explicit settings are rejected.
# No fallback to the system Python is permitted.
#

_wofs_load_python() {

    local root
    local candidate=""
    local selected=""
    local origin=""
    local key
    local value
    local directory

    if [[ -z "${HOMEwofs:-}" ]]; then
        echo "[ERROR] HOMEwofs is required" >&2
        return 1
    fi

    root="$(cd "$HOMEwofs" && pwd -P)" || return 1

    if [[ ! -f "$root/versions/run.ver" || \
          ! -f "$root/tests/check_wofs_python.sh" ]]; then

        echo "[ERROR] Invalid HOMEwofs: $root" >&2
        return 1
    fi

    # Resolve explicit interpreter settings.
    for key in WOFS_PYTHON IC_PREP_PYTHON WOFS_PYTHON_ENV
    do
        value="${!key:-}"

        [[ -n "$value" ]] || continue

        if [[ "$value" != /* ]]; then
            echo "[ERROR] $key must be an absolute path" >&2
            return 1
        fi

        if [[ "$key" == WOFS_PYTHON_ENV ]]; then
            candidate="${value%/}/bin/python3"
        else
            candidate="$value"
        fi

        if [[ ! -f "$candidate" || ! -x "$candidate" ]]; then
            echo "[ERROR] Invalid Python interpreter from $key:" >&2
            echo "        $candidate" >&2
            return 1
        fi

        # Canonicalize the parent directory only.
        # Never resolve the interpreter symlink itself.
        directory="$(cd "$(dirname "$candidate")" && pwd -P)" \
            || return 1

        candidate="$directory/$(basename "$candidate")"

        if [[ -z "$selected" ]]; then
            selected="$candidate"
            origin="$key"

        elif [[ "$selected" != "$candidate" ]]; then
            echo "[ERROR] Conflicting Python settings:" >&2
            echo "        $origin=$selected" >&2
            echo "        $key=$candidate" >&2
            return 1
        fi
    done

    # Repository-local default environment.
    if [[ -z "$selected" ]]; then
        selected="$root/python_env/bin/python3"
        origin="repository default"
    fi

    if [[ ! -f "$selected" || ! -x "$selected" ]]; then

        echo "[ERROR] WoFS Python environment not found:" >&2
        echo "        $selected" >&2
        echo "Install using:" >&2
        echo "  bash $root/sorc/install_wofs_python.sh $root/python_env" >&2
        echo "Or configure WOFS_PYTHON or WOFS_PYTHON_ENV." >&2

        return 1
    fi

    # Validate before publishing interpreter settings.
    echo "===== Initialize WoFS Python runtime ====="
    echo "Selection source: $origin"
    echo "Interpreter     : $selected"

    if ! bash "$root/tests/check_wofs_python.sh" "$selected"; then
        echo "[ERROR] WoFS Python runtime validation failed" >&2
        return 1
    fi

    # Export the validated runtime to downstream processes.
    export PYTHONNOUSERSITE=1
    unset PYTHONPATH PYTHONHOME

    export WOFS_PYTHON="$selected"
    export IC_PREP_PYTHON="$selected"

    echo "[PASS] Shared WoFS Python runtime initialized"

    return 0
}

if _wofs_load_python; then
    unset -f _wofs_load_python
    return 0 2>/dev/null || exit 0
else
    unset -f _wofs_load_python
    return 1 2>/dev/null || exit 1
fi
