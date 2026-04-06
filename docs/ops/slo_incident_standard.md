# SLO & Incident Standard

Bu doküman cloud + cihaz operasyonu için minimum SLO ve incident kurallarını tanımlar.

## SLI / SLO

1. API Availability (`/health`, `/me`)
- SLI: 2xx ratio
- SLO: aylık %99.9

2. Command Delivery (`/device/{id6}/cmd`)
- SLI: accepted command / total command
- SLO: 5 dakikalık pencerede %99

3. MQTT Connectivity
- SLI: connected device ratio
- SLO: 15 dakikalık pencerede %98

4. Claim Success
- SLI: successful claim / total claim attempt
- SLO: günlük %99

## Alert Thresholds

- API 5xx > %1 (5 dk): P1
- `claim_denied` anomali artışı (5 dk bazline x3): P1
- `cmd_rate_limited` > 100/5dk: P2
- MQTT disconnect spike > %10 device pool: P1

## Incident Process

1. Incident aç (`P1/P2/P3`)
2. Owner ata (on-call)
3. Mitigation: feature flag daraltma / rollback
4. Root cause + corrective action
5. Postmortem yayınla (24 saat içinde)

## Runbook Linkleri

- Release runbook: `docs/cloud/release_runbook.md`
- AWS side checklist: `docs/cloud/aws_side_checklist.md`
- Prod go-live checklist: `docs/production_go_live_checklist.md`
