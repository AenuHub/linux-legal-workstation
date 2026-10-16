#!/usr/bin/env python3
"""Install manifest for Legal Workstation.

Tracks what the installer newly added (packages, services, paths, rc files) so
that `legal-workstation uninstall --all` can remove exactly those and never a
package the user already had.

Location: ${XDG_DATA_HOME:-$HOME/.local/share}/legal-workstation/manifest.json
"""

from __future__ import annotations

import datetime
import json
import os
import sys

SCHEMA_VERSION = 1
LIST_KEYS = ("packages_added", "services_enabled", "paths", "rc_files")


def manifest_path() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(base, "legal-workstation", "manifest.json")


def load() -> dict:
    try:
        with open(manifest_path(), encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def base_doc(data: dict) -> dict:
    data.setdefault("manifest_version", SCHEMA_VERSION)
    data.setdefault(
        "installed_at",
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    data.setdefault("os_family", os.environ.get("LW_OS_FAMILY", "unknown"))
    for key in LIST_KEYS:
        data.setdefault(key, [])
    return data


def save(data: dict) -> None:
    target = manifest_path()
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, target)


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: manifest.py <command> [args]", file=sys.stderr)
        return 2
    cmd, *args = argv

    if cmd == "init":
        save(base_doc(load()))

    elif cmd == "add-package":
        data = base_doc(load())
        for pkg in args:
            if pkg not in data["packages_added"]:
                data["packages_added"].append(pkg)
        save(data)

    elif cmd == "add-service":
        if len(args) != 3:
            print("add-service <unit> <was_enabled> <was_active>", file=sys.stderr)
            return 2
        unit, was_enabled, was_active = args
        data = base_doc(load())
        data["services_enabled"] = [
            s for s in data["services_enabled"] if s.get("unit") != unit
        ]
        data["services_enabled"].append(
            {
                "unit": unit,
                "was_enabled": was_enabled == "1",
                "was_active": was_active == "1",
            }
        )
        save(data)

    elif cmd == "add-path":
        data = base_doc(load())
        for item in args:
            if item not in data["paths"]:
                data["paths"].append(item)
        save(data)

    elif cmd == "add-rc":
        data = base_doc(load())
        for item in args:
            if item not in data["rc_files"]:
                data["rc_files"].append(item)
        save(data)

    elif cmd == "list-packages":
        for pkg in load().get("packages_added", []):
            print(pkg)

    elif cmd == "list-services":
        for svc in load().get("services_enabled", []):
            enabled = 1 if svc.get("was_enabled") else 0
            active = 1 if svc.get("was_active") else 0
            print(f"{svc.get('unit', '')}\t{enabled}\t{active}")

    elif cmd == "list-paths":
        for item in load().get("paths", []):
            print(item)

    elif cmd == "list-rc":
        for item in load().get("rc_files", []):
            print(item)

    elif cmd == "delete":
        try:
            os.remove(manifest_path())
        except FileNotFoundError:
            pass
        try:
            os.rmdir(os.path.dirname(manifest_path()))
        except OSError:
            pass

    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
