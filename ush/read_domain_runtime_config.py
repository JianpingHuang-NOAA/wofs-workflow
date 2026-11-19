"""Read WoFS scalar runtime settings without executing shell code."""

import re


_ASSIGNMENT = re.compile(
    r"(?:export ([A-Za-z_][A-Za-z0-9_]*)='([A-Za-z0-9_./:+-]+)'"
    r"|setenv ([A-Za-z_][A-Za-z0-9_]*) ([A-Za-z0-9_./:+-]+))"
)


def read_domain_config(path):
    values = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        match = _ASSIGNMENT.fullmatch(line)
        if not match:
            raise ValueError(f"{path}:{number}: invalid runtime assignment")
        bash_name, bash_value, legacy_name, legacy_value = match.groups()
        name = bash_name or legacy_name
        if name in values:
            raise ValueError(f"{path}:{number}: duplicate runtime variable {name}")
        values[name] = bash_value if bash_name else legacy_value

    return values
