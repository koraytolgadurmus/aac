#!/usr/bin/env python3
"""Compatibility wrapper for the OTA release manager UI.

Keeps legacy entrypoints working while the maintained implementation lives under
tools/ota_release_manager/app.py.
"""

from __future__ import annotations

import runpy
from pathlib import Path


def main() -> None:
    target = (
        Path(__file__).resolve().parents[2]
        / "tools"
        / "ota_release_manager"
        / "app.py"
    )
    runpy.run_path(str(target), run_name="__main__")


if __name__ == "__main__":
    main()
