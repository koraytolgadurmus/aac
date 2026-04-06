#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git_commit(root: Path) -> str:
    proc = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(root), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return "unknown"
    return proc.stdout.strip() or "unknown"


def maybe_sign(att_path: Path, key_path: Path) -> str:
    sig_path = att_path.with_suffix(".sig")
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path), "-out", str(sig_path), str(att_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "openssl signing failed")
    sig_b64 = base64.b64encode(sig_path.read_bytes()).decode("ascii")
    sig_path.unlink(missing_ok=True)
    return sig_b64


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate release attestation")
    parser.add_argument("--firmware-bin", required=True, help="Path to firmware .bin")
    parser.add_argument("--firmware-env", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--board-rev", required=True)
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--signing-key", default="", help="Optional PEM private key for signature")
    args = parser.parse_args()

    firmware = Path(args.firmware_bin).expanduser().resolve()
    if not firmware.exists():
        raise SystemExit(f"[FAIL] firmware not found: {firmware}")

    root = Path(__file__).resolve().parents[2]
    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    attestation: dict = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "project": "aac",
        "build": {
            "firmwareEnv": args.firmware_env,
            "version": args.version,
            "boardRev": args.board_rev,
            "gitCommit": git_commit(root),
        },
        "artifacts": [
            {
                "path": str(firmware),
                "sha256": sha256_file(firmware),
                "sizeBytes": firmware.stat().st_size,
            }
        ],
    }

    output.write_text(json.dumps(attestation, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if args.signing_key:
        key = Path(args.signing_key).expanduser().resolve()
        if not key.exists():
            raise SystemExit(f"[FAIL] signing key not found: {key}")
        signature = maybe_sign(output, key)
        signed_payload = json.loads(output.read_text(encoding="utf-8"))
        signed_payload["signature"] = {"algorithm": "RSA/ECDSA-SHA256", "encoding": "base64", "value": signature}
        output.write_text(json.dumps(signed_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"[PASS] wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
