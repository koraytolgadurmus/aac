#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def read_text(path: str) -> str:
    return Path(path).expanduser().read_text(encoding="utf-8")


def detect_key_type(pem: str) -> str:
    if "BEGIN EC PRIVATE KEY" in pem:
      return "ec-p256" if "prime256v1" in inspect_private_key(pem) else "ec"
    if "BEGIN RSA PRIVATE KEY" in pem:
      return "rsa"
    if "BEGIN PRIVATE KEY" in pem:
      details = inspect_private_key(pem)
      if "ASN1 OID: prime256v1" in details:
        return "ec-p256"
      if "id-ecPublicKey" in details or "EC Private-Key" in details:
        return "ec"
    return "unknown"


def inspect_private_key(pem: str) -> str:
    proc = subprocess.run(
        ["openssl", "pkey", "-text", "-noout"],
        input=pem,
        text=True,
        capture_output=True,
        check=False,
    )
    return (proc.stdout or "") + (proc.stderr or "")


def parse_espefuse_summary(text: str) -> tuple[bool, str, bool, str]:
    normalized = text.lower()
    secure_boot = False
    flash_encryption = False
    secure_boot_version = "unknown"
    flash_mode = "unknown"

    if re.search(r"secure[_ ]boot.*?(enable|enabled|true|1|yes)", normalized):
        secure_boot = True
    if "secure boot v2" in normalized or "secure_boot_v2" in normalized:
        secure_boot = True
        secure_boot_version = "v2"
    elif "secure boot" in normalized:
        secure_boot_version = "v1-or-unknown"

    if re.search(r"flash[_ ]encryption.*?(enable|enabled|true|1|yes)", normalized):
        flash_encryption = True
    if re.search(r"flash_crypt_cnt\s*=\s*[1-9]", normalized):
        flash_encryption = True
    if "flash encryption mode" in normalized:
        m = re.search(r"flash encryption mode[^:\n]*[:=]\s*([a-z0-9_-]+)", normalized)
        if m:
            flash_mode = m.group(1)
    elif "release" in normalized and "flash encryption" in normalized:
        flash_mode = "release"

    return secure_boot, secure_boot_version, flash_encryption, flash_mode


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate production security evidence JSON")
    parser.add_argument("--espefuse-summary", required=True, help="Path to saved espefuse summary text")
    parser.add_argument("--device-key", required=True, help="Path to device private key PEM")
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--board-rev", required=True)
    parser.add_argument("--verified-by", required=True)
    parser.add_argument("--secure-boot-digest", default="SBV2_DIGEST_SLOT0")
    parser.add_argument("--notes", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    summary_text = read_text(args.espefuse_summary)
    key_text = read_text(args.device_key)
    key_type = detect_key_type(key_text)
    if key_type != "ec-p256":
        print(f"[FAIL] device key must be EC/P-256, got: {key_type}", file=sys.stderr)
        return 1

    secure_boot, secure_boot_version, flash_encryption, flash_mode = parse_espefuse_summary(summary_text)
    if not secure_boot:
        print("[FAIL] secure boot not detected in espefuse summary", file=sys.stderr)
        return 1
    if not flash_encryption:
        print("[FAIL] flash encryption not detected in espefuse summary", file=sys.stderr)
        return 1

    evidence = {
        "schemaVersion": 1,
        "deviceIdentity": {
            "deviceId": args.device_id,
            "boardRev": args.board_rev,
            "keyType": key_type,
        },
        "secureBoot": {
            "enabled": True,
            "version": "v2" if secure_boot_version == "v2" else secure_boot_version,
            "digest": args.secure_boot_digest,
        },
        "flashEncryption": {
            "enabled": True,
            "mode": flash_mode,
        },
        "evidence": {
            "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "verifiedBy": args.verified_by,
            "notes": args.notes,
            "source": str(Path(args.espefuse_summary).expanduser()),
        },
    }

    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[PASS] wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
