# Branch Protection Standard

Bu repo için `main` branch minimum koruma standardı:

## Required Status Checks

- `quality-gate`
- `cloud-checks`

## Pull Request Rules

- En az 1 reviewer onayı
- Dismiss stale approvals: açık
- Require conversation resolution: açık
- Force push: kapalı
- Delete branch on merge: açık

## Admin Rules

- `enforce_admins`: açık
- Direct push: kapalı

## Ops Notu

CI içinde bu politikanın varlığı opsiyonel olarak doğrulanır:

- script: `scripts/qa/check_branch_protection.sh`
- workflow step: `Quality Gate / Branch protection policy check (optional)`

Bu check'in aktif çalışması için `GH_ADMIN_TOKEN` secret gerekir.

## Otomatik Uygulama

Policy'yi API ile uygulamak için:

```bash
GH_REPO=<owner/repo> GH_TOKEN=<admin-token> GH_BRANCH=main \
bash scripts/qa/apply_branch_protection.sh
```
