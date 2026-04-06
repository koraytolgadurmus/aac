# Config Standard (Single Source of Truth)

## Source of truth
- Canonical config file: `shared/config.json`.
- Generated runtime config: `deploy/outputs.json` (from CDK outputs) is transformed into `shared/config.json` and `app/lib/config/generated_env.dart`.
- Flutter consumes `app/lib/config/app_env.dart` which merges `--dart-define` overrides with the generated values.

## Schema (shared/config.json)

| Key | Description |
| --- | --- |
| AWS_REGION | Primary AWS region for all stacks/services. |
| AWS_ACCOUNT_ID | AWS account id (used for IoT policy ARNs). |
| COGNITO_REGION | Cognito region (usually same as AWS_REGION). |
| COGNITO_USER_POOL_ID | Cognito User Pool ID. |
| COGNITO_CLIENT_ID | Cognito App Client ID (public client). |
| COGNITO_DOMAIN | Cognito Hosted UI domain. |
| COGNITO_SCOPES | OIDC scopes used by Flutter. |
| COGNITO_IDENTITY_POOL_ID | Optional (only if Identity Pool is used). |
| CLOUD_BASE_URL | API Gateway invoke URL. |
| CLOUD_IOT_ENDPOINT | IoT Core MQTT endpoint hostname (ATS). |
| IOT_DATA_ENDPOINT | IoT data plane HTTPS endpoint hostname. |
| IOT_TOPIC_STATE | `aac/{id6}/state` topic pattern. |
| IOT_TOPIC_TELEMETRY | `aac/{id6}/telemetry` topic pattern. |
| IOT_TOPIC_SHADOW_UPDATE | `aac/{id6}/shadow/update` topic pattern. |
| IOT_TOPIC_CMD | `aac/{id6}/cmd` topic pattern. |
| IOT_TOPIC_EVT | `aac/{id6}/evt` topic pattern. |
| DDB_DEVICE_OWNERSHIP_TABLE | Ownership table name. |
| DDB_DEVICE_STATE_TABLE | Device state table name. |
| DDB_USER_DEVICES_TABLE | User-to-device table name. |

## Old -> new mapping

| Old location | Old name | New key |
| --- | --- | --- |
| app/lib/main.dart | kCloudBaseUrl | CLOUD_BASE_URL |
| app/lib/main.dart | kCloudIotEndpoint | CLOUD_IOT_ENDPOINT |
| app/lib/main.dart | kCognitoRegion | COGNITO_REGION |
| app/lib/main.dart | kCognitoUserPoolId | COGNITO_USER_POOL_ID |
| app/lib/main.dart | kCognitoClientId | COGNITO_CLIENT_ID |
| app/lib/main.dart | kCognitoDomain | COGNITO_DOMAIN |
| app/lib/main.dart | kCognitoScopesCsv | COGNITO_SCOPES |
| AWS_DEPLOYMENT.md | COGNITO_* + CLOUD_BASE_URL | shared/config.json equivalents |
| test_aws.sh | BASE_URL | CLOUD_BASE_URL |
| cloud/*.js | AWS_IOT_REGION | AWS_REGION |
| cloud/*.js | IOT_DATA_ENDPOINT / AWS_IOT_DATA_ENDPOINT | IOT_DATA_ENDPOINT |
| cloud/*.js | DEVICE_OWNERSHIP_TABLE | DDB_DEVICE_OWNERSHIP_TABLE |
| cloud/*.js | DEVICE_STATE_TABLE | DDB_DEVICE_STATE_TABLE |

## Flutter mapping
- `app/lib/config/app_env.dart` reads `--dart-define` keys listed above; falls back to `app/lib/config/generated_env.dart`.
- `app/lib/config/generated_env.dart` is generated from CDK outputs and should never contain hardcoded production values in source control.

## Notes
- Only one name is used per config field to avoid drift; legacy aliases should be removed once migration is complete.
- IoT topic names are standardized to the new `aac/{id6}/*` pattern (firmware aligned).
