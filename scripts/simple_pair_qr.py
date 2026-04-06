#!/usr/bin/env python3
"""
Very small helper to turn the current ArtAirCleaner pair token into a QR code.

Usage examples:
    python scripts/simple_pair_qr.py --token 15C96B46702C1BF25F27331FA8835891
    python scripts/simple_pair_qr.py --token 15C9... --out ~/Desktop/pair_token.png

Requires qrcode + pillow once:
    pip install "qrcode[pil]"
"""

from __future__ import annotations

import argparse
import pathlib
import sys

try:
    import qrcode  # type: ignore
except ImportError as exc:
    sys.exit("qrcode kütüphanesi eksik. pip install \"qrcode[pil]\" çalıştırın.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pair token için QR kod üret.")
    parser.add_argument(
        "--token",
        required=True,
        help="32 karakterlik büyük harf hex pair token (örn. 15C96B...5891).",
    )
    parser.add_argument(
        "--out",
        default="pair_token.png",
        help="PNG kaydedilecek dosya yolu (varsayılan: pair_token.png).",
    )
    return parser.parse_args()


def ensure_token(token: str) -> str:
    token = token.strip().upper()
    if len(token) != 32 or any(c not in "0123456789ABCDEF" for c in token):
        raise SystemExit("Token 32 karakterlik büyük harf HEX olmalıdır.")
    return token


def save_qr(token: str, out_path: str) -> pathlib.Path:
    image = qrcode.make(token)
    path = pathlib.Path(out_path).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def main() -> None:
    args = parse_args()
    token = ensure_token(args.token)
    path = save_qr(token, args.out)
    print(f"[OK] QR oluşturuldu: {path}")
    print("Uygulamada 'QR Tara' diyerek bu görseli okutabilirsiniz.")


if __name__ == "__main__":
    main()
