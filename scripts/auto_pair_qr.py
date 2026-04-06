#!/usr/bin/env python3
"""
Tek komutla:
- USB üzerinden bağlı ESP32'nin seri logundan mevcut kimlik bilgilerini okur,
- İsteğe bağlı olarak /api/admin/rotate_pair_token çağrısı yaparak yeni token alır,
- Pair token'ı QR koda çevirip PNG dosyası olarak kaydeder.

Gereken paketler (sanal ortamdayken bir kere kur):
    pip install pyserial requests "qrcode[pil]"

Örnek kullanım:
    python scripts/auto_pair_qr.py --output ~/Desktop/pair_token.png
    python scripts/auto_pair_qr.py --port /dev/cu.usbserial-0002 --no-rotate
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import time
from dataclasses import dataclass
from typing import Optional

try:
    import serial  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.exit("pyserial eksik. pip install pyserial komutunu çalıştırın.")

try:
    import requests  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.exit("requests eksik. pip install requests komutunu çalıştırın.")

try:
    import qrcode  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.exit('qrcode modülü eksik. pip install "qrcode[pil]" komutunu çalıştırın.')


AUTH_RE = re.compile(
    r"user=(?P<user>[0-9A-F]{32}).*?"
    r"pass=(?P<user_pass>[0-9A-F]{32}).*?"
    r"admin=(?P<admin>[0-9A-F]{32}).*?"
    r"adminPass=(?P<admin_pass>[0-9A-F]{32}).*?"
    r"pair=(?P<pair>[0-9A-F]{32})"
)
IP_RE = re.compile(r"STA:\s+CONNECTED\s+ip=(?P<ip>\d+\.\d+\.\d+\.\d+)")


@dataclass
class AuthInfo:
    user: str
    user_pass: str
    admin: str
    admin_pass: str
    pair_token: str
    ip: Optional[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ESP32 pair token’ını otomatik QR olarak üret.")
    parser.add_argument(
        "--port",
        default="/dev/cu.usbserial-0001",
        help="Seri port (varsayılan: /dev/cu.usbserial-0001).",
    )
    parser.add_argument(
        "--baud",
        type=int,
        default=115200,
        help="Baud rate (varsayılan: 115200).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=6.0,
        help="Seriden log toplama süresi (saniye).",
    )
    parser.add_argument(
        "--host",
        help="HTTP isteği için doğrudan host/IP. Belirtilmezse logdaki STA IP veya 192.168.4.1 kullanılır.",
    )
    parser.add_argument(
        "--https",
        action="store_true",
        help="HTTP yerine HTTPS kullan.",
    )
    parser.add_argument(
        "--no-rotate",
        action="store_true",
        help="/api/admin/rotate_pair_token çağrısı yapmaksızın logdaki mevcut token’ı kullan.",
    )
    parser.add_argument(
        "--output",
        default="pair_token.png",
        help="QR PNG dosya yolu (varsayılan: pair_token.png).",
    )
    return parser.parse_args()


def collect_serial(port: str, baud: int, timeout: float) -> list[str]:
    lines: list[str] = []
    end_ts = time.time() + timeout
    try:
        with serial.Serial(port, baudrate=baud, timeout=1) as ser:
            while time.time() < end_ts:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="ignore").strip()
                if line:
                    lines.append(line)
    except serial.SerialException as exc:
        raise SystemExit(f"[ERR] Seri porta erişilemedi: {exc}")
    return lines


def extract_auth(lines: list[str]) -> AuthInfo:
    auth = None
    ip = None
    for line in lines:
        if "[AUTH]" in line:
            match = AUTH_RE.search(line)
            if match:
                auth = match.groupdict()
        elif "STA: CONNECTED" in line:
            m_ip = IP_RE.search(line)
            if m_ip:
                ip = m_ip.group("ip")
    if not auth:
        raise SystemExit("[ERR] Seri logda [AUTH] satırı bulunamadı. Cihazı resetleyip tekrar deneyin.")
    return AuthInfo(
        user=auth["user"],
        user_pass=auth["user_pass"],
        admin=auth["admin"],
        admin_pass=auth["admin_pass"],
        pair_token=auth["pair"],
        ip=ip,
    )


def rotate_pair_token(host: str, https: bool, admin: str, admin_pass: str) -> Optional[str]:
    scheme = "https" if https else "http"
    url = f"{scheme}://{host}/api/admin/rotate_pair_token"
    headers = {"X-User": admin, "X-Pass": admin_pass}
    try:
        resp = requests.post(url, headers=headers, timeout=5)
    except requests.RequestException as exc:
        print(f"[WARN] Token yenileme isteği başarısız: {exc}")
        return None
    if resp.status_code != 200:
        print(f"[WARN] HTTP {resp.status_code} döndü: {resp.text}")
        return None
    try:
        payload = resp.json()
    except ValueError:
        print(f"[WARN] JSON parse edilemedi: {resp.text}")
        return None
    if not payload.get("ok"):
        print(f"[WARN] Cihaz hata döndürdü: {payload}")
        return None
    token = payload.get("pairToken")
    if isinstance(token, str) and len(token) == 32:
        print(f"[INFO] Token yenilendi. Yeni token: {token}")
        return token
    print(f"[WARN] Yanıtta pairToken alanı yok: {payload}")
    return None


def ensure_token(token: str) -> str:
    token = token.strip().upper()
    if len(token) != 32 or any(c not in "0123456789ABCDEF" for c in token):
        raise SystemExit(f"[ERR] Token formatı beklenmiyor: {token}")
    return token


def save_qr(token: str, output: str) -> pathlib.Path:
    image = qrcode.make(token)
    path = pathlib.Path(output).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def main() -> None:
    args = parse_args()

    print(f"[INFO] Seri port okunuyor: {args.port} @ {args.baud} baud (≈{args.timeout:.0f}s)")
    lines = collect_serial(args.port, args.baud, args.timeout)
    info = extract_auth(lines)

    print(f"[INFO] Kullanıcı token bulundu: {info.pair_token}")
    print(f"[INFO] Admin hesabı: {info.admin} / {info.admin_pass}")
    if info.ip:
        print(f"[INFO] STA IP: {info.ip}")

    token = info.pair_token
    if not args.no_rotate:
        host = args.host or info.ip or "192.168.4.1"
        print(f"[INFO] Token yenileme deneniyor: {host}")
        new_token = rotate_pair_token(host, args.https, info.admin, info.admin_pass)
        if new_token:
            token = new_token

    token = ensure_token(token)
    path = save_qr(token, args.output)
    print("[OK] QR üretildi.")
    print(f"     Token : {token}")
    print(f"     Dosya : {path}")
    print("Mobil uygulamada 'QR Tara' ile bu görseli okutun.")


if __name__ == "__main__":
    main()
