#!/usr/bin/env python3
"""Expand an OBS_RADAR configuration into validated domain case YAML files."""

from pathlib import Path
import re
import subprocess
import sys
import yaml

output, *inputs = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
roots = set()
for path in inputs:
    shared = yaml.safe_load(path.read_text())
    domains = shared.pop("domains", None)
    if domains is None and "domain" in shared:
        cases = [shared]
    else:
        if {"domain", "stations", "radar_list"} & shared.keys():
            raise SystemExit("Set station information in DOMAIN_SETUP radar lists or per-domain entries")
        base = Path(shared["run_root"])
        if not base.is_absolute():
            raise SystemExit("Shared run_root must be absolute")

        cdate = shared["cdate"]
        if not isinstance(cdate, str) or not re.fullmatch(r"[0-9]{10}", cdate):
            raise SystemExit("cdate must be a quoted YYYYMMDDHH value")
        day = cdate[:8]
        setup_root = shared.pop("domain_setup_root", shared.get("publish_root"))
        if setup_root is None or not Path(setup_root).is_absolute():
            raise SystemExit("Set domain_setup_root or publish_root to the absolute versioned COM root")
        cycle = Path(setup_root) / f"wofs.{day}" / cdate[8:]
        if domains is None:
            domains = sorted(
                path.parent.name for path in cycle.glob(f"*/radars_{day}_*.sh")
                if path.name == f"radars_{day}_{path.parent.name}.sh" and path.is_file()
            )
        if isinstance(domains, list):
            if any(not isinstance(domain, str) for domain in domains):
                raise SystemExit("domains list must contain region names")
            if len(set(domains)) != len(domains):
                raise SystemExit("Duplicate region in domains list")
            domains = {domain: {} for domain in domains}
        if not isinstance(domains, dict) or not domains:
            raise SystemExit(f"No domains selected or discovered under {cycle}")

        base_configs = shared.pop("obs_base_configs", {})
        radar_lists = shared.pop("radar_lists", {})
        if not isinstance(base_configs, dict) or not isinstance(radar_lists, dict):
            raise SystemExit("obs_base_configs and radar_lists must be mappings")
        cases = []
        for domain, settings in domains.items():
            if not isinstance(domain, str) or not re.fullmatch(r"[A-Z0-9_]+", domain):
                raise SystemExit(f"Invalid domain: {domain}")
            if not isinstance(settings, dict):
                raise SystemExit(f"{domain}: expected a mapping of overrides")
            overrides = settings.keys() - {"stations", "radar_list", "obs_base_config", "nexrad_root"}
            if overrides:
                raise SystemExit(f"{domain}: unsupported domain keys: {sorted(overrides)}")
            radar_list = Path(settings.get("radar_list", radar_lists.get(domain, cycle / domain / f"radars_{day}_{domain}.sh")))
            if not radar_list.is_absolute() or not radar_list.is_file() or not radar_list.stat().st_size:
                raise SystemExit(f"{domain}: missing or invalid radar list: {radar_list}")
            geometry = cycle / domain / f"realtime.cfg.{day}.{domain}"
            if not geometry.is_file() or not geometry.stat().st_size:
                raise SystemExit(f"{domain}: missing or empty DOMAIN_SETUP geometry: {geometry}")
            result = subprocess.run(
                ["/bin/bash", "-ec", 'source "$1" >&2; printf "%s\\n" "${rad_name[@]}"', "bash", str(radar_list)],
                capture_output=True, text=True,
            )
            if result.returncode:
                raise SystemExit(f"{domain}: cannot load {radar_list}: {result.stderr.strip()}")
            stations = result.stdout.splitlines()
            if (not stations or len(set(stations)) != len(stations) or
                    any(not re.fullmatch(r"[A-Z][A-Z0-9]{3}", site) for site in stations)):
                raise SystemExit(f"{domain}: invalid rad_name array in {radar_list}")
            if "stations" in settings and settings["stations"] != stations:
                raise SystemExit(f"{domain}: stations override differs from {radar_list}")
            case = shared | settings | {
                "domain": domain, "run_root": str(base / domain),
                "radar_list": str(radar_list), "stations": stations,
                "domain_geometry": str(geometry),
            }
            if "obs_base_config" not in settings and domain in base_configs:
                case["obs_base_config"] = base_configs[domain]
            if case.get("obs_base_config"):
                case["obs_base_config"] = case["obs_base_config"].replace("{domain}", domain)
            cases.append(case)
    for case in cases:
        root = Path(case["run_root"])
        if not root.is_absolute() or root.exists() or root.is_symlink():
            raise SystemExit(f"run_root must be an unused absolute path: {root}")
        resolved = root.resolve()
        if resolved in roots:
            raise SystemExit(f"Duplicate run_root: {root}")
        roots.add(resolved)
        (output / f"{len(roots)}.yaml").write_text(yaml.safe_dump(case, sort_keys=False))
