#!/usr/bin/env python3
"""
Generate a QR code for the ArtAirCleaner mobile app by rotating/fetching the
current pairing token from the ESP32 firmware and saving it as an image.

Usage:
    python scripts/generate_pair_qr.py --host 192.168.4.1 \
        --user <admin_user> --password <admin_pass> --output pair_token.png

Requirements:
    pip install requests qrcode[pil]

The script calls `/api/admin/rotate_pair_token` which returns a fresh pairing
token while keeping it active on the device, then encodes that token as a QR
image that the mobile app can scan during onboarding.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
from typing import Optional

try:
    import requests
except ImportError as exc:  # pragma: no cover - guidance for missing dep
    sys.exit("Missing dependency: install requests (pip install requests).")

try:
    import qrcode
except ImportError as exc:  # pragma: no cover - guidance for missing dep
    sys.exit("Missing dependency: install qrcode (pip install qrcode[pil]).")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch the current ArtAirCleaner pairing token and create a QR image."
    )
    parser.add_argument(
        "--host",
        required=True,
        help="Device host or IP (e.g. 192.168.4.1 or artair-ABCDEF.local)",
    )
    parser.add_argument(
        "--user",
        required=True,
        help="Admin username (header X-User).",
    )
    parser.add_argument(
        "--password",
        required=True,
        help="Admin password (header X-Pass).",
    )
    parser.add_argument(
        "--output",
        help="Output PNG path. Defaults to pair_token_<last4>.png next to this script.",
    )
    parser.add_argument(
        "--https",
        action="store_true",
        help="Use HTTPS instead of HTTP when talking to the device.",
    )
    return parser.parse_args()


def rotate_pair_token(
    base_url: str, user: str, password: str
) -> tuple[str, Optional[str]]:
    """Call /api/admin/rotate_pair_token and return (token, device_id)."""
    url = f"{base_url}/api/admin/rotate_pair_token"
    headers = {"X-User": user, "X-Pass": password}
    try:
        response = requests.post(url, headers=headers, timeout=5)
    except requests.RequestException as exc:
        raise SystemExit(f"[ERR] Request failed: {exc}") from exc

    if response.status_code != 200:
        raise SystemExit(
            f"[ERR] Device responded with HTTP {response.status_code}: {response.text}"
        )

    try:
        payload = response.json()
    except ValueError as exc:
        raise SystemExit(f"[ERR] Invalid JSON response: {response.text}") from exc

    if not payload.get("ok"):
        raise SystemExit(f"[ERR] Device returned error: {payload}")

    token = payload.get("pairToken")
    if not token or not isinstance(token, str):
        raise SystemExit(f"[ERR] pairToken missing in response: {payload}")

    device_id = payload.get("deviceId")
    return token, device_id


def validate_token(token: str) -> None:
    if len(token) != 32 or any(c not in "0123456789ABCDEF" for c in token):
        raise SystemExit(
            "[ERR] Token has unexpected format. Expected 32 uppercase hex characters."
        )


def resolve_output_path(token: str, supplied: Optional[str]) -> pathlib.Path:
    if supplied:
        return pathlib.Path(supplied).expanduser().resolve()

    suffix = token[-4:]
    default_name = f"pair_token_{suffix}.png"
    return pathlib.Path(__file__).resolve().parent / default_name


def generate_qr(token: str, output: pathlib.Path) -> None:
    image = qrcode.make(token)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)


def main() -> None:
    args = parse_args()
    protocol = "https" if args.https else "http"
    base_url = f"{protocol}://{args.host}"

    token, device_id = rotate_pair_token(base_url, args.user, args.password)
    validate_token(token)
    output = resolve_output_path(token, args.output)
    generate_qr(token, output)

    print("[OK] Pairing token fetched and QR generated.")
    print(f"      Token : {token}")
    if device_id:
        print(f"      Device: {device_id}")
    print(f"      Saved : {output}")
    print("Scan this QR with the ArtAirCleaner mobile app to pair the device.")


if __name__ == "__main__":
    main()
