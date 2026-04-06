#!/usr/bin/env python3
from __future__ import annotations

import configparser
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "audit" / "sbom" / "latest-sbom.json"


def run_json(cmd: list[str], cwd: Path) -> dict:
    proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return {"_error": {"cmd": cmd, "code": proc.returncode, "stderr": proc.stderr.strip()}}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"_error": {"cmd": cmd, "code": proc.returncode, "stderr": "non-json-output"}}


def parse_platformio_ini(path: Path) -> dict:
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read(path, encoding="utf-8")

    envs: dict[str, dict] = {}
    for section in parser.sections():
        if not section.startswith("env:"):
            continue
        env_name = section.split("env:", 1)[1]
        lib_deps_raw = parser.get(section, "lib_deps", fallback="")
        build_flags_raw = parser.get(section, "build_flags", fallback="")
        envs[env_name] = {
            "lib_deps": [line.strip() for line in lib_deps_raw.splitlines() if line.strip()],
            "build_flags": [line.strip() for line in build_flags_raw.splitlines() if line.strip()],
        }
    return envs


def main() -> int:
    platformio_envs = parse_platformio_ini(ROOT / "platformio.ini")
    flutter_deps = run_json(["flutter", "pub", "deps", "--json"], ROOT / "app")
    npm_tree = run_json(["npm", "ls", "--json", "--all"], ROOT / "infra" / "cdk")

    sbom = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "project": "aac",
        "components": {
            "firmware": {
                "platformioEnvs": platformio_envs,
            },
            "mobileApp": {
                "flutterPubDeps": flutter_deps,
            },
            "cloud": {
                "npmDependencyTree": npm_tree,
            },
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(sbom, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[PASS] wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
