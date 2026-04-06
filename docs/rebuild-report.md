# Rebuild Report

## 1) AWS resources (by stack)

### AuthStack (Cognito)
- User Pool (email sign-in, password policy, optional MFA)
- App Client (public client for Hosted UI/OIDC)
- Hosted UI domain

### DataStack (DynamoDB)
- `aac_device_ownership` (PK deviceId, GSI by ownerUserId)
- `aac_device_state` (PK deviceId)
- `aac_user_devices` (PK userId, SK deviceId)

### IotStack (IoT Core)
- IoT device policy (X.509 cert based)
- IoT data endpoint discovery (Custom Resource)

### ApiStack (API Gateway + Lambda)
- HTTP API with JWT authorizer (Cognito)
- Lambdas: auth/ping, device-claim, device-unclaim, device-get, device-command, me-devices
- Throttling (burst/rate) and CORS

### ObservabilityStack
- CloudWatch alarms for API 5xx and Lambda errors
- Lambda log retention: 14 days (set in Lambda functions)

## 2) Outputs (IDs / endpoints)
Populated by CDK deployment and exported to `deploy/outputs.json` / `shared/config.json`:
- `AWS_REGION`
- `AWS_ACCOUNT_ID`
- `COGNITO_USER_POOL_ID`
- `COGNITO_CLIENT_ID`
- `COGNITO_DOMAIN`
- `COGNITO_REGION`
- `CLOUD_BASE_URL`
- `HTTP_API_ID`
- `IOT_DATA_ENDPOINT`
- `CLOUD_IOT_ENDPOINT`
- `IOT_POLICY_NAME`
- `DDB_DEVICE_OWNERSHIP_TABLE`
- `DDB_DEVICE_STATE_TABLE`
- `DDB_USER_DEVICES_TABLE`
- `DDB_DEVICE_OWNERSHIP_BY_OWNER_GSI`

## 3) Routes + auth matrix

| Method | Path | Auth | Lambda |
| --- | --- | --- | --- |
| POST | /auth/ping | optional | backend/lambdas/health/handler.ts |
| POST | /device/claim | required | backend/lambdas/device-claim/handler.ts |
| POST | /device/unclaim | required | backend/lambdas/device-unclaim/handler.ts |
| GET | /device/{deviceId} | required | backend/lambdas/device-get/handler.ts |
| POST | /device/{deviceId}/command | required | backend/lambdas/device-command/handler.ts |
| GET | /me/devices | required | backend/lambdas/me-devices/handler.ts |

## 4) IoT topics / policy matrix

| Actor | Topic pattern | Publish | Subscribe |
| --- | --- | --- | --- |
| Device (X.509) | aac/{deviceId}/* | yes | yes |
| API Lambda | aac/{deviceId}/cmd | yes | no |
| App (HTTP API) | n/a | via API | via API |

## 5) Refactor / deletes
- Refactor: Flutter config now loads from `app/lib/config/app_env.dart` (generated output fallback).
- Added: CDK infra under `infra/` and new Lambda handlers under `backend/lambdas/`.
- Updated: `AWS_DEPLOYMENT.md` now points to generated config flow.
- Deleted: none.

## 6) TODOs
- Firmware MQTT topics migrated to `aac/{deviceId}/*`.
- Decide whether to keep the legacy IoT custom authorizer (cloud/iotDeviceAuthorizer.js) after migration.
- Deploy CDK stacks, export outputs, and regenerate `app/lib/config/generated_env.dart`.

## 7) Tree (-L 4)
Generated via python3 (filtered to omit .git/.cache/.pio/node_modules/build/.dart_tool/.idea).

```
aac
├── .vscode
│   ├── c_cpp_properties.json
│   ├── extensions.json
│   └── launch.json
├── app
│   ├── android
│   │   ├── .gradle
│   │   │   ├── 8.12
│   │   │   ├── buildOutputCleanup
│   │   │   ├── noVersion
│   │   │   ├── vcs-1
│   │   │   └── file-system.probe
│   │   ├── .kotlin
│   │   │   └── sessions
│   │   ├── app
│   │   │   ├── src
│   │   │   └── build.gradle.kts
│   │   ├── gradle
│   │   │   └── wrapper
│   │   ├── .DS_Store
│   │   ├── .gitignore
│   │   ├── app_android.iml
│   │   ├── build.gradle.kts
│   │   ├── gradle.properties
│   │   ├── gradlew
│   │   ├── gradlew.bat
│   │   ├── local.properties
│   │   └── settings.gradle.kts
│   ├── app
│   │   └── android
│   │       ├── app
│   │       └── .DS_Store
│   ├── assets
│   │   ├── i18n
│   │   ├── icons
│   │   │   ├── .DS_Store
│   │   │   ├── fan.svg
│   │   │   └── logo.png
│   │   ├── images
│   │   └── .DS_Store
│   ├── ios
│   │   ├── .symlinks
│   │   │   └── plugins
│   │   ├── Flutter
│   │   │   ├── ephemeral
│   │   │   ├── .DS_Store
│   │   │   ├── AppFrameworkInfo.plist
│   │   │   ├── Debug.xcconfig
│   │   │   ├── Flutter.podspec
│   │   │   ├── flutter_export_environment.sh
│   │   │   ├── Generated.xcconfig
│   │   │   └── Release.xcconfig
│   │   ├── Pods
│   │   │   ├── AppAuth
│   │   │   ├── Headers
│   │   │   ├── Local Podspecs
│   │   │   ├── Pods.xcodeproj
│   │   │   ├── Target Support Files
│   │   │   └── Manifest.lock
│   │   ├── Runner
│   │   │   ├── Assets.xcassets
│   │   │   ├── Base.lproj
│   │   │   ├── .DS_Store
│   │   │   ├── AppDelegate.swift
│   │   │   ├── GeneratedPluginRegistrant.h
│   │   │   ├── GeneratedPluginRegistrant.m
│   │   │   ├── Info.plist
│   │   │   ├── Runner-Bridging-Header.h
│   │   │   └── Runner.entitlements
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   └── project.pbxproj
│   │   ├── Runner.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   ├── xcuserdata
│   │   │   └── contents.xcworkspacedata
│   │   ├── RunnerTests
│   │   │   └── RunnerTests.swift
│   │   ├── .DS_Store
│   │   ├── .gitignore
│   │   ├── Podfile
│   │   └── Podfile.lock
│   ├── ios copy
│   │   ├── .symlinks
│   │   │   └── plugins
│   │   ├── Flutter
│   │   │   ├── ephemeral
│   │   │   ├── AppFrameworkInfo.plist
│   │   │   ├── Debug.xcconfig
│   │   │   ├── Flutter.podspec
│   │   │   ├── flutter_export_environment.sh
│   │   │   ├── Generated.xcconfig
│   │   │   └── Release.xcconfig
│   │   ├── Pods
│   │   │   ├── Headers
│   │   │   ├── Local Podspecs
│   │   │   ├── Pods.xcodeproj
│   │   │   ├── Target Support Files
│   │   │   ├── .DS_Store
│   │   │   └── Manifest.lock
│   │   ├── Runner
│   │   │   ├── Assets.xcassets
│   │   │   ├── Base.lproj
│   │   │   ├── AppDelegate.swift
│   │   │   ├── GeneratedPluginRegistrant.h
│   │   │   ├── GeneratedPluginRegistrant.m
│   │   │   ├── Info.plist
│   │   │   └── Runner-Bridging-Header.h
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   └── project.pbxproj
│   │   ├── Runner.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   ├── xcuserdata
│   │   │   └── contents.xcworkspacedata
│   │   ├── RunnerTests
│   │   │   └── RunnerTests.swift
│   │   ├── .DS_Store
│   │   ├── .gitignore
│   │   ├── Podfile
│   │   └── Podfile.lock
│   ├── ios2
│   │   ├── .symlinks
│   │   │   └── plugins
│   │   ├── Flutter
│   │   │   ├── ephemeral
│   │   │   ├── .DS_Store
│   │   │   ├── AppFrameworkInfo.plist
│   │   │   ├── Debug.xcconfig
│   │   │   ├── Flutter.podspec
│   │   │   ├── flutter_export_environment.sh
│   │   │   ├── Generated.xcconfig
│   │   │   ├── Profile.xcconfig
│   │   │   └── Release.xcconfig
│   │   ├── Pods
│   │   │   ├── GoogleDataTransport
│   │   │   ├── GoogleMLKit
│   │   │   ├── GoogleToolboxForMac
│   │   │   ├── GoogleUtilities
│   │   │   ├── GoogleUtilitiesComponents
│   │   │   ├── GTMSessionFetcher
│   │   │   ├── Headers
│   │   │   ├── Local Podspecs
│   │   │   ├── MLImage
│   │   │   ├── MLKitBarcodeScanning
│   │   │   ├── MLKitCommon
│   │   │   ├── MLKitVision
│   │   │   ├── nanopb
│   │   │   ├── Pods.xcodeproj
│   │   │   ├── PromisesObjC
│   │   │   ├── Target Support Files
│   │   │   └── Manifest.lock
│   │   ├── Runner
│   │   │   ├── Assets.xcassets
│   │   │   ├── Base.lproj
│   │   │   ├── .DS_Store
│   │   │   ├── AppDelegate.swift
│   │   │   ├── GeneratedPluginRegistrant.h
│   │   │   ├── GeneratedPluginRegistrant.m
│   │   │   ├── Info.plist
│   │   │   ├── Runner-Bridging-Header.h
│   │   │   └── Runner.entitlements
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   ├── project.pbxproj
│   │   │   ├── project.pbxproj.BACKUP_FINAL
│   │   │   ├── project.pbxproj.BACKUP_LDFLAGS
│   │   │   ├── project.pbxproj.bak
│   │   │   └── project.pbxproj.bak2
│   │   ├── Runner.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   ├── xcuserdata
│   │   │   └── contents.xcworkspacedata
│   │   ├── RunnerTests
│   │   │   └── RunnerTests.swift
│   │   ├── .DS_Store
│   │   ├── .gitignore
│   │   ├── Podfile
│   │   └── Podfile.lock
│   ├── lib
│   │   ├── config
│   │   │   ├── app_env.dart
│   │   │   └── generated_env.dart
│   │   ├── core
│   │   │   ├── api
│   │   │   ├── logic
│   │   │   ├── mqtt
│   │   │   └── net
│   │   ├── l10n
│   │   ├── models
│   │   ├── screens
│   │   ├── services
│   │   │   ├── .DS_Store
│   │   │   ├── cognito_oidc_auth.dart
│   │   │   ├── cognito_oidc_auth.dart.zip
│   │   │   ├── mdns_resolver.dart
│   │   │   ├── mdns_resolver.dart.zip
│   │   │   ├── mdns_resolver_io.dart
│   │   │   ├── mdns_resolver_io.dart.zip
│   │   │   ├── mdns_resolver_stub.dart
│   │   │   └── mdns_resolver_stub.dart.zip
│   │   ├── state
│   │   ├── utils
│   │   ├── .DS_Store
│   │   ├── main.dart
│   │   └── main.dart.zip
│   ├── linux
│   │   ├── flutter
│   │   │   ├── ephemeral
│   │   │   ├── CMakeLists.txt
│   │   │   ├── generated_plugin_registrant.cc
│   │   │   ├── generated_plugin_registrant.h
│   │   │   └── generated_plugins.cmake
│   │   ├── runner
│   │   │   ├── CMakeLists.txt
│   │   │   ├── main.cc
│   │   │   ├── my_application.cc
│   │   │   └── my_application.h
│   │   ├── .DS_Store
│   │   ├── .gitignore
│   │   └── CMakeLists.txt
│   ├── macos
│   │   ├── Flutter
│   │   │   ├── ephemeral
│   │   │   ├── Flutter-Debug.xcconfig
│   │   │   ├── Flutter-Release.xcconfig
│   │   │   └── GeneratedPluginRegistrant.swift
│   │   ├── Runner
│   │   │   ├── Assets.xcassets
│   │   │   ├── Base.lproj
│   │   │   ├── Configs
│   │   │   ├── AppDelegate.swift
│   │   │   ├── DebugProfile.entitlements
│   │   │   ├── Info.plist
│   │   │   ├── MainFlutterWindow.swift
│   │   │   └── Release.entitlements
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   └── project.pbxproj
│   │   ├── Runner.xcworkspace
│   │   │   ├── xcshareddata
│   │   │   └── contents.xcworkspacedata
│   │   ├── RunnerTests
│   │   │   └── RunnerTests.swift
│   │   ├── .DS_Store
│   │   ├── .gitignore
│   │   └── Podfile
│   ├── test
│   │   └── widget_test.dart
│   ├── web
│   │   ├── icons
│   │   │   ├── Icon-192.png
│   │   │   ├── Icon-512.png
│   │   │   ├── Icon-maskable-192.png
│   │   │   └── Icon-maskable-512.png
│   │   ├── favicon.png
│   │   ├── index.html
│   │   └── manifest.json
│   │   ├── windows
│   │   │   ├── flutter
│   │   │   ├── runner
│   │   │   ├── .DS_Store
│   │   │   ├── .gitignore
│   │   │   └── CMakeLists.txt
│   │   ├── .DS_Store
│   │   ├── .flutter-plugins-dependencies
│   │   ├── .gitignore
│   │   ├── .metadata
│   │   ├── AmazonRootCA1.pem
│   │   ├── analysis_options.yaml
│   │   ├── app.iml
│   │   ├── pubspec.lock
│   │   ├── pubspec.yaml
│   │   ├── pubspec.yaml.bak
│   │   ├── README.md
│   │   ├── run_with_cognito.sh
│   │   └── trust.json
├── backend
│   ├── lambdas
│   │   ├── common
│   │   │   ├── auth.ts
│   │   │   ├── ddb.ts
│   │   │   ├── env.ts
│   │   │   ├── logger.ts
│   │   │   ├── response.ts
│   │   │   └── validate.ts
│   │   ├── device-claim
│   │   │   └── handler.ts
│   │   ├── device-command
│   │   │   └── handler.ts
│   │   ├── device-get
│   │   │   └── handler.ts
│   │   ├── device-unclaim
│   │   │   └── handler.ts
│   │   ├── health
│   │   │   └── handler.ts
│   │   └── me-devices
│   │       └── handler.ts
│   ├── package.json
│   └── tsconfig.json
├── cloud
│   ├── claimDevice.js
│   ├── claimDevice.zip
│   ├── deploy.sh
│   ├── deviceStateGet.zip
│   ├── getDeviceState.js
│   ├── getDeviceState.zip
│   ├── index.js
│   ├── iotDeviceAuthorizer.js
│   ├── iotDeviceAuthorizer.zip
│   ├── issueMqttToken.js
│   ├── issueMqttToken.zip
│   ├── package-lock.json
│   ├── package.json
│   ├── README.md
│   ├── sendDeviceCommand.js
│   └── sendDeviceCommand.zip
├── deploy
├── docs
│   ├── api
│   │   └── routes.md
│   ├── audit
│   │   ├── aws-usage.md
│   │   └── config-standard.md
│   ├── data
│   │   └── ddb-schema.md
│   ├── deploy
│   │   └── how-config-flows.md
│   ├── iot
│   │   └── topics-and-policies.md
│   ├── esp32_secure_boot.md
│   └── oauth.md
├── include
│   └── README
├── infra
│   ├── bin
│   │   └── app.ts
│   ├── lib
│   │   └── stacks
│   │       ├── api-stack.ts
│   │       ├── auth-stack.ts
│   │       ├── data-stack.ts
│   │       ├── iot-stack.ts
│   │       └── observability-stack.ts
│   ├── scripts
│   │   └── export-outputs.ts
│   ├── cdk.json
│   ├── package.json
│   ├── README.md
│   └── tsconfig.json
├── lib
│   └── README
├── monitor
│   ├── __pycache__
│   │   ├── filter_esp32_autoreset.cpython-311.pyc
│   │   └── filter_esp32_autoreset.cpython-313.pyc
│   └── filter_esp32_autoreset.py
├── ota
│   ├── .DS_Store
│   ├── manifest_v1.json
│   ├── v1_1.0.1.bin
│   ├── v1_1.0.5.bin
│   └── v1_1.0.6.bin
├── scripts
│   ├── auto_pair_qr.py
│   ├── find_legacy_code.sh
│   ├── generate_flutter_env.js
│   ├── generate_pair_qr.py
│   ├── ota_sign.py
│   ├── README_OTA_SIGN.md
│   └── simple_pair_qr.py
├── shared
│   └── config.json
├── src
│   ├── bsec_config_iaq.h
│   ├── bsec_iaq_esphome.txt
│   ├── config.h
│   ├── config.h.zip
│   ├── main.cpp
│   └── main.cpp.zip
├── test
│   └── README
├── .DS_Store
├── .gitignore
├── AWS_DEPLOYMENT.md
├── compile_commands.json
├── generate_qr.py.save
├── partitions_ota.csv
├── platformio.ini
├── platformio.ini.zip
└── test_aws.sh
```
