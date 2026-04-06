# AAC Cloud CDK (Minimum Stack)

Bu modül, cloud tarafını kodla yönetmek için minimum bir CDK başlangıç seti sağlar.

## Kapsam

- Cognito User Pool + App Client + Hosted UI domain
- HTTP API (API Gateway v2) + JWT Authorizer
- `scripts/aws/aac-cloud-api.js` Lambda deploy
- DynamoDB tabloları:
  - ownership
  - state
  - user_devices
  - invites
  - cmd_idempotency
  - audit
  - rate_limit
- IoT policy'ler:
  - claim cert policy (yalnız provisioning topicleri)
  - thing policy (yalnız kendi id6 topic/shadow/jobs)
- Fleet provisioning template
- OTA artifact S3 bucket

## Kullanım

```bash
cd infra/cdk
npm install
npm run synth
```

Deploy:

```bash
cd infra/cdk
npm run deploy -- \
  --context stage=dev \
  --parameters IotDataEndpoint=<your-iot-data-endpoint> \
  --parameters ProvisioningRoleArn=arn:aws:iam::<account-id>:role/<fleet-provisioning-role>
```

## Notlar

- `CognitoCallbackUrls` ve `CognitoSignoutUrls` parametreleri default olarak
  `com.koray.artaircleaner://callback` içerir.
- Lambda env'leri backend kodundaki feature flag ve tablo isimleriyle eşlenmiştir.
- Removal policy prod güvenliği için `RETAIN` olarak ayarlanmıştır.
