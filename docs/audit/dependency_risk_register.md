# Dependency Risk Register

Son tarama kaynağı:
- `docs/audit/dependency-audit-latest.txt`
- komut: `./scripts/qa/dependency_audit.sh`

## Current Open Findings (infra/cdk transitive)

- Açık bulgu yok (`npm audit --audit-level=critical` sonucu: 0 vulnerability)
- CDK dependency baseline:
  - `aws-cdk-lib`: `^2.248.0`
  - `aws-cdk`: `^2.1117.0`

## Recently Closed

1. `minimatch` (high) via `aws-cdk-lib`  
2. `ajv` (moderate) via `aws-cdk-lib`  
3. `yaml` (moderate) via `aws-cdk-lib`  
4. `brace-expansion` (moderate) via `aws-cdk-lib`  

Kapatma yöntemi: CDK paket yükseltmesi + tekrar audit.

## Policy

- CI gate kritik (`critical`) açıkları fail eder.
- High/Moderate açıklar kayıt altına alınır ve release notlarında takip edilir.
- Üretim rollout öncesi high açıklar için risk kabulü veya yükseltme aksiyonu zorunludur.
