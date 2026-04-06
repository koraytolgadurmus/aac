# iOS Developer Certificate Trust Runbook

This issue is not fixable from Flutter/Dart code. It is device-signing state.

## Symptoms
- `IDELaunchCoreDevice Code: 0`
- `CoreDeviceError 10002`
- `Unable to launch ... invalid code signature / profile has not been explicitly trusted`

## Fix steps (device + Xcode)
1. On iPhone: `Settings -> General -> VPN & Device Management -> Developer App`.
2. Trust the developer certificate for the Apple ID used to sign the app.
3. On Mac/Xcode:
   - Open `Runner` target -> `Signing & Capabilities`.
   - Ensure correct Team is selected.
   - Ensure Bundle Identifier is unique for this team/device.
   - Enable `Automatically manage signing`.
4. Delete the app from iPhone and run again from Xcode.
5. If still failing:
   - Xcode: `Product -> Clean Build Folder`.
   - Delete DerivedData for the project.
   - Reconnect device and run again.

## Notes
- This is independent from MQTT/BLE/app runtime logic.
- Cannot be auto-approved by app code due iOS security model.
- `CoreBluetooth API MISUSE ... willRestoreState` warning seen in logs is from plugin lifecycle behavior; it is non-fatal and separate from signing/trust.
