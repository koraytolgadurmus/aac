# GitHub Security Standard

Bu repoda minimum GitHub güvenlik standardı:

## Branch Protection

- `main` için PR zorunlu
- En az 1 onay
- Required checks:
  - `quality-gate`
  - `cloud-checks`
- Conversation resolution: açık
- Force push: kapalı
- Delete protection: açık

## Ownership

- CODEOWNERS zorunlu: `.github/CODEOWNERS`
- Kritik alanlarda sahiplik açıkça tanımlı olmalı.

## Secret Hygiene

- Repository'de private key/cert commit edilmez.
- Lokal tarama scripti: `scripts/aws/secret-scan.sh`
- CI içinde quality-gate adımı olarak çalışır.

## Verification

- Repo readiness: `scripts/qa/github_readiness.sh`
- Branch policy doğrulama: `scripts/qa/check_branch_protection.sh`
