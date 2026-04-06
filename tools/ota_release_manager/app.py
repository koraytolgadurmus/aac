#!/usr/bin/env python3
"""
AAC OTA Release Manager (local desktop tool)

What it does:
- Select firmware .bin
- Compute SHA256
- Upload to S3
- Create OTA job (/device/{id6}/ota/job) or campaign (/ota/campaign)

No external Python dependency required (tkinter + stdlib).
Requires installed tools:
- aws cli
"""

from __future__ import annotations

import hashlib
import json
import os
import queue
import subprocess
import threading
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox
from tkinter.scrolledtext import ScrolledText

APP_TITLE = "AAC OTA Release Manager"
CONFIG_PATH = Path.home() / ".aac_release_manager.json"
PRESIGN_EXPIRES_SEC = 7 * 24 * 60 * 60


@dataclass
class ReleaseConfig:
    api_base: str = "https://3wl1he0yj3.execute-api.eu-central-1.amazonaws.com"
    jwt_token: str = ""
    cognito_region: str = "eu-central-1"
    cognito_user_pool_id: str = "eu-central-1_KuBlWrAt7"
    cognito_client_id: str = "3edajq3f7eu6sbrva8qsrnd0ep"
    cognito_username: str = ""
    aws_region: str = "eu-central-1"
    s3_bucket: str = ""
    firmware_path: str = ""
    version: str = ""
    min_version: str = ""
    product: str = "aac"
    hw_rev: str = "v1"
    board_rev: str = "esp32dev"
    fw_channel: str = "stable"
    mode: str = "device"  # device | campaign
    device_id: str = ""
    requires_user_approval: bool = True
    dry_run: bool = False
    force: bool = False
    strict_prod: bool = True
    prod_evidence_path: str = ""


class ReleaseManagerUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title(APP_TITLE)
        self.root.geometry("980x760")

        self.log_q: queue.Queue[str] = queue.Queue()

        cfg = self.load_config()

        self.api_base_var = tk.StringVar(value=cfg.api_base)
        self.jwt_var = tk.StringVar(value=cfg.jwt_token)
        self.cognito_region_var = tk.StringVar(value=cfg.cognito_region)
        self.cognito_user_pool_id_var = tk.StringVar(value=cfg.cognito_user_pool_id)
        self.cognito_client_id_var = tk.StringVar(value=cfg.cognito_client_id)
        self.cognito_username_var = tk.StringVar(value=cfg.cognito_username)
        self.cognito_password_var = tk.StringVar(value="")
        self.region_var = tk.StringVar(value=cfg.aws_region)
        self.bucket_var = tk.StringVar(value=cfg.s3_bucket)
        self.file_var = tk.StringVar(value=cfg.firmware_path)
        self.version_var = tk.StringVar(value=cfg.version)
        self.min_version_var = tk.StringVar(value=cfg.min_version)
        self.product_var = tk.StringVar(value=cfg.product)
        self.hw_rev_var = tk.StringVar(value=cfg.hw_rev)
        self.board_rev_var = tk.StringVar(value=cfg.board_rev)
        self.fw_channel_var = tk.StringVar(value=cfg.fw_channel)
        self.mode_var = tk.StringVar(value=cfg.mode)
        self.device_id_var = tk.StringVar(value=cfg.device_id)
        self.approval_var = tk.BooleanVar(value=cfg.requires_user_approval)
        self.dry_run_var = tk.BooleanVar(value=cfg.dry_run)
        self.force_var = tk.BooleanVar(value=cfg.force)
        self.strict_prod_var = tk.BooleanVar(value=cfg.strict_prod)
        self.prod_evidence_var = tk.StringVar(value=cfg.prod_evidence_path)

        self.build_ui()
        self.toggle_mode()
        self.poll_logs()

    def build_ui(self) -> None:
        pad = {"padx": 8, "pady": 6}

        top = tk.Frame(self.root)
        top.pack(fill="x", **pad)

        tk.Label(top, text="API Base URL").grid(row=0, column=0, sticky="w")
        tk.Entry(top, textvariable=self.api_base_var, width=72).grid(row=0, column=1, columnspan=3, sticky="we", **pad)

        tk.Label(top, text="JWT Token").grid(row=1, column=0, sticky="w")
        tk.Entry(top, textvariable=self.jwt_var, width=72, show="*").grid(row=1, column=1, columnspan=3, sticky="we", **pad)

        tk.Label(top, text="AWS Region").grid(row=2, column=0, sticky="w")
        tk.Entry(top, textvariable=self.region_var, width=22).grid(row=2, column=1, sticky="w", **pad)
        tk.Label(top, text="S3 Bucket (opsiyonel)").grid(row=2, column=2, sticky="w")
        tk.Entry(top, textvariable=self.bucket_var, width=30).grid(row=2, column=3, sticky="we", **pad)

        auth = tk.LabelFrame(self.root, text="Cognito Login (JWT Al)")
        auth.pack(fill="x", **pad)

        tk.Label(auth, text="Cognito Region").grid(row=0, column=0, sticky="w")
        tk.Entry(auth, textvariable=self.cognito_region_var, width=18).grid(row=0, column=1, sticky="w", **pad)
        tk.Label(auth, text="User Pool ID").grid(row=0, column=2, sticky="w")
        tk.Entry(auth, textvariable=self.cognito_user_pool_id_var, width=20).grid(row=0, column=3, sticky="w", **pad)
        tk.Label(auth, text="Client ID").grid(row=0, column=4, sticky="w")
        tk.Entry(auth, textvariable=self.cognito_client_id_var, width=26).grid(row=0, column=5, sticky="w", **pad)

        tk.Label(auth, text="E-posta / Username").grid(row=1, column=0, sticky="w")
        tk.Entry(auth, textvariable=self.cognito_username_var, width=32).grid(row=1, column=1, sticky="w", **pad)
        tk.Label(auth, text="Şifre").grid(row=1, column=2, sticky="w")
        tk.Entry(auth, textvariable=self.cognito_password_var, width=24, show="*").grid(row=1, column=3, sticky="w", **pad)
        tk.Button(auth, text="JWT Al", command=self.fetch_jwt).grid(row=1, column=4, sticky="w", **pad)

        fw = tk.LabelFrame(self.root, text="Firmware")
        fw.pack(fill="x", **pad)

        tk.Label(fw, text=".bin Dosyası").grid(row=0, column=0, sticky="w")
        tk.Entry(fw, textvariable=self.file_var, width=70).grid(row=0, column=1, sticky="we", **pad)
        tk.Button(fw, text="Seç", command=self.pick_firmware).grid(row=0, column=2, **pad)
        tk.Button(fw, text="Proje", command=self.pick_project).grid(row=0, column=3, **pad)

        tk.Label(fw, text="Version").grid(row=1, column=0, sticky="w")
        tk.Entry(fw, textvariable=self.version_var, width=18).grid(row=1, column=1, sticky="w", **pad)
        tk.Label(fw, text="Min Version (opsiyonel)").grid(row=1, column=2, sticky="w")
        tk.Entry(fw, textvariable=self.min_version_var, width=18).grid(row=1, column=3, sticky="w", **pad)

        target = tk.LabelFrame(self.root, text="Hedef")
        target.pack(fill="x", **pad)

        tk.Label(target, text="Product").grid(row=0, column=0, sticky="w")
        tk.Entry(target, textvariable=self.product_var, width=18).grid(row=0, column=1, sticky="w", **pad)
        tk.Label(target, text="HW Rev").grid(row=0, column=2, sticky="w")
        tk.Entry(target, textvariable=self.hw_rev_var, width=18).grid(row=0, column=3, sticky="w", **pad)

        tk.Label(target, text="Board Rev").grid(row=1, column=0, sticky="w")
        tk.Entry(target, textvariable=self.board_rev_var, width=18).grid(row=1, column=1, sticky="w", **pad)
        tk.Label(target, text="FW Channel").grid(row=1, column=2, sticky="w")
        tk.Entry(target, textvariable=self.fw_channel_var, width=18).grid(row=1, column=3, sticky="w", **pad)

        mode = tk.LabelFrame(self.root, text="Yayın Türü")
        mode.pack(fill="x", **pad)

        tk.Radiobutton(mode, text="Tek cihaz (/device/{id6}/ota/job)", variable=self.mode_var, value="device", command=self.toggle_mode).grid(row=0, column=0, sticky="w", **pad)
        tk.Radiobutton(mode, text="Campaign (/ota/campaign)", variable=self.mode_var, value="campaign", command=self.toggle_mode).grid(row=0, column=1, sticky="w", **pad)

        self.device_id_label = tk.Label(mode, text="Device ID (6 hane)")
        self.device_id_label.grid(row=1, column=0, sticky="w")
        self.device_id_entry = tk.Entry(mode, textvariable=self.device_id_var, width=18)
        self.device_id_entry.grid(row=1, column=1, sticky="w", **pad)

        flags = tk.Frame(self.root)
        flags.pack(fill="x", **pad)
        tk.Checkbutton(flags, text="requiresUserApproval", variable=self.approval_var).pack(side="left", padx=8)
        tk.Checkbutton(flags, text="dryRun", variable=self.dry_run_var).pack(side="left", padx=8)
        tk.Checkbutton(flags, text="force (sadece device)", variable=self.force_var).pack(side="left", padx=8)
        tk.Checkbutton(flags, text="strictProd", variable=self.strict_prod_var).pack(side="left", padx=8)

        prod = tk.LabelFrame(self.root, text="Production Evidence")
        prod.pack(fill="x", **pad)
        tk.Label(prod, text="Evidence JSON").grid(row=0, column=0, sticky="w")
        tk.Entry(prod, textvariable=self.prod_evidence_var, width=72).grid(row=0, column=1, sticky="we", **pad)
        tk.Button(prod, text="Seç", command=self.pick_prod_evidence).grid(row=0, column=2, **pad)

        actions = tk.Frame(self.root)
        actions.pack(fill="x", **pad)
        tk.Button(actions, text="Config Kaydet", command=self.save_current_config).pack(side="left", padx=8)
        tk.Button(actions, text="Yayınla", bg="#1e8e3e", fg="white", command=self.start_release).pack(side="right", padx=8)

        self.log_box = ScrolledText(self.root, height=20)
        self.log_box.pack(fill="both", expand=True, **pad)

    def log(self, msg: str) -> None:
        self.log_q.put(msg)

    def poll_logs(self) -> None:
        while True:
            try:
                msg = self.log_q.get_nowait()
            except queue.Empty:
                break
            self.log_box.insert(tk.END, msg + "\n")
            self.log_box.see(tk.END)
        self.root.after(120, self.poll_logs)

    def pick_firmware(self) -> None:
        f = filedialog.askopenfilename(
            title="Firmware .bin seç",
            filetypes=[("Binary", "*.bin"), ("All files", "*.*")],
        )
        if f:
            self.file_var.set(f)

    def pick_project(self) -> None:
        d = filedialog.askdirectory(title="AAC proje klasörünü seç")
        if not d:
            return
        resolved = self.resolve_firmware_path(d)
        if resolved:
            self.file_var.set(resolved)
            self.log(f"[PASS] Firmware bulundu: {resolved}")
        else:
            self.file_var.set(d)
            self.log("[WARN] Bu proje altında firmware.bin bulunamadı. Önce build almanız gerekebilir.")

    def pick_prod_evidence(self) -> None:
        f = filedialog.askopenfilename(
            title="Production evidence JSON seç",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if f:
            self.prod_evidence_var.set(f)

    @staticmethod
    def resolve_firmware_path(path: str) -> str:
        raw = (path or "").strip()
        if not raw:
            return ""
        p = Path(raw).expanduser()
        if p.is_file():
            return str(p)
        if not p.is_dir():
            return ""
        candidates = []
        preferred = p / ".pio" / "build" / "esp32dev" / "firmware.bin"
        if preferred.is_file():
            return str(preferred)
        for item in p.glob(".pio/build/*/firmware.bin"):
            if item.is_file():
                candidates.append(item)
        if not candidates:
            return ""
        candidates.sort(key=lambda item: item.stat().st_mtime, reverse=True)
        return str(candidates[0])

    @staticmethod
    def strict_prod_pio_env(board_rev: str) -> str:
        value = (board_rev or "").strip().lower()
        if value in {"esp32dev_board_legacy", "esp32dev-legacy", "legacy"}:
            return "esp32dev_board_legacy"
        if value in {"esp32dev_board_aux", "esp32dev-aux", "aux"}:
            return "esp32dev_board_aux"
        return ""

    def toggle_mode(self) -> None:
        is_device = self.mode_var.get() == "device"
        state = "normal" if is_device else "disabled"
        self.device_id_entry.configure(state=state)
        self.device_id_label.configure(state=state)

    def load_config(self) -> ReleaseConfig:
        if not CONFIG_PATH.exists():
            return ReleaseConfig()
        try:
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            return ReleaseConfig(**data)
        except Exception:
            return ReleaseConfig()

    def save_current_config(self) -> None:
        cfg = ReleaseConfig(
            api_base=self.api_base_var.get().strip(),
            jwt_token=self.jwt_var.get().strip(),
            cognito_region=self.cognito_region_var.get().strip(),
            cognito_user_pool_id=self.cognito_user_pool_id_var.get().strip(),
            cognito_client_id=self.cognito_client_id_var.get().strip(),
            cognito_username=self.cognito_username_var.get().strip(),
            aws_region=self.region_var.get().strip(),
            s3_bucket=self.bucket_var.get().strip(),
            firmware_path=self.file_var.get().strip(),
            version=self.version_var.get().strip(),
            min_version=self.min_version_var.get().strip(),
            product=self.product_var.get().strip(),
            hw_rev=self.hw_rev_var.get().strip(),
            board_rev=self.board_rev_var.get().strip(),
            fw_channel=self.fw_channel_var.get().strip(),
            mode=self.mode_var.get().strip(),
            device_id=self.device_id_var.get().strip(),
            requires_user_approval=self.approval_var.get(),
            dry_run=self.dry_run_var.get(),
            force=self.force_var.get(),
            strict_prod=self.strict_prod_var.get(),
            prod_evidence_path=self.prod_evidence_var.get().strip(),
        )
        CONFIG_PATH.write_text(json.dumps(cfg.__dict__, indent=2, ensure_ascii=False), encoding="utf-8")
        self.log(f"[PASS] Config saved: {CONFIG_PATH}")

    def validate(self) -> str | None:
        resolved_firmware = self.resolve_firmware_path(self.file_var.get().strip())
        if not self.file_var.get().strip():
            return "Firmware dosyası seçmelisin"
        if not resolved_firmware:
            return "Firmware dosyası bulunamadı"
        if resolved_firmware != self.file_var.get().strip():
            self.file_var.set(resolved_firmware)
        if not self.version_var.get().strip():
            return "Version zorunlu"
        if not self.jwt_var.get().strip():
            return "JWT token zorunlu"
        if not self.api_base_var.get().strip().startswith("http"):
            return "API Base URL geçersiz"
        if self.mode_var.get() == "device":
            d = self.device_id_var.get().strip()
            if not (len(d) == 6 and d.isdigit()):
                return "Device ID 6 hane numerik olmalı"
        fw_channel = self.fw_channel_var.get().strip().lower()
        strict_prod = self.strict_prod_var.get()
        dry_run = self.dry_run_var.get()
        evidence = self.prod_evidence_var.get().strip()
        if fw_channel == "stable" and not dry_run and not strict_prod:
            return "Stable release için strictProd zorunlu"
        if strict_prod and not evidence:
            return "strictProd için production evidence JSON zorunlu"
        if strict_prod and not self.strict_prod_pio_env(self.board_rev_var.get()):
            return "strictProd için boardRev legacy/aux profile ile eşleşmeli"
        if evidence:
            p = Path(evidence).expanduser()
            if not p.is_file():
                return "Production evidence dosyası bulunamadı"
        return None

    def start_release(self) -> None:
        err = self.validate()
        if err:
            messagebox.showerror(APP_TITLE, err)
            return

        self.save_current_config()
        t = threading.Thread(target=self.run_release, daemon=True)
        t.start()

    def fetch_jwt(self) -> None:
        region = self.cognito_region_var.get().strip()
        user_pool_id = self.cognito_user_pool_id_var.get().strip()
        client_id = self.cognito_client_id_var.get().strip()
        username = self.cognito_username_var.get().strip()
        password = self.cognito_password_var.get().strip()
        if not region or not user_pool_id or not client_id or not username or not password:
            messagebox.showerror(APP_TITLE, "Cognito region/userPoolId/clientId/username/password zorunlu")
            return
        threading.Thread(
            target=self._fetch_jwt_worker,
            args=(region, user_pool_id, client_id, username, password),
            daemon=True,
        ).start()

    def _fetch_jwt_worker(
        self,
        region: str,
        user_pool_id: str,
        client_id: str,
        username: str,
        password: str,
    ) -> None:
        try:
            self.log("[INFO] Cognito'dan JWT alınıyor...")
            token = ""
            try:
                out = self.run_cmd([
                    "aws",
                    "cognito-idp",
                    "initiate-auth",
                    "--region",
                    region,
                    "--client-id",
                    client_id,
                    "--auth-flow",
                    "USER_PASSWORD_AUTH",
                    "--auth-parameters",
                    f"USERNAME={username},PASSWORD={password}",
                ])
                parsed = json.loads(out)
                auth_result = parsed.get("AuthenticationResult", {})
                token = str(auth_result.get("IdToken", "")).strip()
            except subprocess.CalledProcessError as e:
                msg = (e.stderr or "").strip()
                # Common fallback: app client has USER_PASSWORD_AUTH disabled.
                if "USER_PASSWORD_AUTH flow not enabled" in msg:
                    self.log("[WARN] USER_PASSWORD_AUTH kapalı, ADMIN_USER_PASSWORD_AUTH deneniyor...")
                    out = self.run_cmd([
                        "aws",
                        "cognito-idp",
                        "admin-initiate-auth",
                        "--region",
                        region,
                        "--user-pool-id",
                        user_pool_id,
                        "--client-id",
                        client_id,
                        "--auth-flow",
                        "ADMIN_USER_PASSWORD_AUTH",
                        "--auth-parameters",
                        f"USERNAME={username},PASSWORD={password}",
                    ])
                    parsed = json.loads(out)
                    auth_result = parsed.get("AuthenticationResult", {})
                    token = str(auth_result.get("IdToken", "")).strip()
                else:
                    raise
            if not token:
                raise RuntimeError("IdToken alınamadı")

            def apply_token() -> None:
                self.jwt_var.set(token)
                self.cognito_password_var.set("")
                self.save_current_config()
                self.log("[PASS] JWT alındı ve alana yazıldı")
                messagebox.showinfo(APP_TITLE, "JWT başarıyla alındı")

            self.root.after(0, apply_token)
        except subprocess.CalledProcessError as e:
            msg = e.stderr.strip() if e.stderr else str(e)
            self.log(f"[FAIL] JWT alma hatası: {msg}")
            self.root.after(0, lambda: messagebox.showerror(APP_TITLE, msg))
        except Exception as e:
            self.log(f"[FAIL] JWT alma hatası: {e}")
            self.root.after(0, lambda: messagebox.showerror(APP_TITLE, str(e)))

    @staticmethod
    def run_cmd(cmd: list[str]) -> str:
        p = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return p.stdout.strip()

    @staticmethod
    def _http_post_json(endpoint: str, token: str, payload: dict, timeout: int = 60) -> tuple[int, str]:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            endpoint,
            data=data,
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, body

    @staticmethod
    def sha256_file(path: str) -> str:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()

    @staticmethod
    def presign_s3_object(bucket: str, key: str, region: str) -> str:
        return ReleaseManagerUI.run_cmd([
            "aws", "s3", "presign", f"s3://{bucket}/{key}",
            "--region", region,
            "--expires-in", str(PRESIGN_EXPIRES_SEC),
        ]).strip()

    def run_release(self) -> None:
        try:
            api_base = self.api_base_var.get().strip().rstrip("/")
            token = self.jwt_var.get().strip()
            region = self.region_var.get().strip() or "eu-central-1"
            firmware_path = self.resolve_firmware_path(self.file_var.get().strip())
            version = self.version_var.get().strip()
            min_version = self.min_version_var.get().strip()
            product = self.product_var.get().strip().lower()
            hw_rev = self.hw_rev_var.get().strip().lower()
            board_rev = self.board_rev_var.get().strip().lower()
            fw_channel = self.fw_channel_var.get().strip().lower()
            mode = self.mode_var.get().strip()
            device_id = self.device_id_var.get().strip()
            requires_user_approval = self.approval_var.get()
            dry_run = self.dry_run_var.get()
            force = self.force_var.get()
            strict_prod = self.strict_prod_var.get() or (fw_channel == "stable" and not dry_run)
            prod_evidence = self.prod_evidence_var.get().strip()

            if strict_prod:
                strict_env = self.strict_prod_pio_env(board_rev)
                self.log("[INFO] Strict production preflight çalıştırılıyor...")
                preflight_cmd = [
                    "bash",
                    str(Path(__file__).resolve().parents[2] / "scripts" / "aws" / "release-preflight.sh"),
                    "--with-firmware",
                    "--firmware-env",
                    strict_env,
                    "--strict-prod",
                    "--prod-evidence",
                    prod_evidence,
                ]
                self.run_cmd(preflight_cmd)
                self.log("[PASS] Strict production preflight tamam")

            self.log("[INFO] SHA256 hesaplanıyor...")
            sha256_hex = self.sha256_file(firmware_path)
            self.log(f"[PASS] sha256={sha256_hex}")

            bucket = self.bucket_var.get().strip()
            if not bucket:
                self.log("[INFO] AWS account alınıyor...")
                account = self.run_cmd([
                    "aws", "sts", "get-caller-identity",
                    "--query", "Account",
                    "--output", "text",
                ])
                bucket = f"aac-dev-ota-artifacts-{account}-{region}"

            key = f"firmware/{product}/{hw_rev}/{fw_channel}/{version}/firmware.bin"
            s3_uri = f"s3://{bucket}/{key}"

            self.log(f"[INFO] S3 upload: {s3_uri}")
            self.run_cmd([
                "aws", "s3", "cp", firmware_path, s3_uri,
                "--region", region,
            ])
            self.log("[PASS] S3 upload tamam")
            self.log(f"[INFO] Presigned URL oluşturuluyor ({PRESIGN_EXPIRES_SEC}s)")
            firmware_url = self.presign_s3_object(bucket, key, region)
            if not firmware_url.startswith("https://"):
                raise RuntimeError("Presigned URL üretilemedi")
            self.log("[PASS] Presigned URL hazır")

            payload = {
                "firmwareUrl": firmware_url,
                "sha256": sha256_hex,
                "version": version,
                "requiresUserApproval": requires_user_approval,
                "dryRun": dry_run,
                "target": {
                    "product": product,
                    "hwRev": hw_rev,
                    "boardRev": board_rev,
                    "fwChannel": fw_channel,
                },
            }
            if min_version:
                payload["minVersion"] = min_version

            if mode == "device":
                payload["force"] = force
                endpoint = f"{api_base}/device/{device_id}/ota/job"
                self.log(f"[INFO] OTA request: {endpoint}")
                status, body = self._http_post_json(endpoint, token, payload)
            else:
                endpoint = f"{api_base}/ota/campaign"
                self.log(f"[INFO] OTA request: {endpoint}")
                try:
                    status, body = self._http_post_json(endpoint, token, payload)
                except urllib.error.HTTPError as e:
                    body_text = e.read().decode("utf-8", errors="replace") if hasattr(e, "read") else ""
                    # Backward-compat: some deployed APIs don't expose /ota/campaign yet.
                    # If so, fallback to single-device route when Device ID is provided.
                    if e.code == 404 and "Not Found" in body_text and device_id and len(device_id) == 6 and device_id.isdigit():
                        self.log("[WARN] /ota/campaign route yok. Tek cihaz endpoint'ine fallback yapılıyor...")
                        device_payload = dict(payload)
                        device_payload["force"] = force
                        fallback_endpoint = f"{api_base}/device/{device_id}/ota/job"
                        self.log(f"[INFO] OTA request (fallback): {fallback_endpoint}")
                        status, body = self._http_post_json(fallback_endpoint, token, device_payload)
                    else:
                        raise

            self.log(f"[PASS] OTA request success HTTP {status}")
            self.log(body)
            self.log("[PASS] Release tamam")

        except subprocess.CalledProcessError as e:
            self.log("[FAIL] Komut hatası")
            if e.stdout:
                self.log(e.stdout.strip())
            if e.stderr:
                self.log(e.stderr.strip())
            messagebox.showerror(APP_TITLE, "Komut hatası. Log'u kontrol et.")
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace") if hasattr(e, "read") else ""
            self.log(f"[FAIL] HTTP {e.code}")
            if body:
                self.log(body)
            if e.code == 404 and "Not Found" in body:
                self.log("[HINT] API deployment bu route'u içermiyor olabilir. Campaign için backend'i yeni route'larla yeniden deploy et veya Tek cihaz modunu kullan.")
            messagebox.showerror(APP_TITLE, f"HTTP {e.code} hatası. Log'u kontrol et.")
        except Exception as e:
            self.log(f"[FAIL] {e}")
            messagebox.showerror(APP_TITLE, str(e))


def main() -> None:
    root = tk.Tk()
    ReleaseManagerUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
