import UIKit
import Flutter
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Flutter pluginleri kaydet
    GeneratedPluginRegistrant.register(with: self)

    // Güvenli şekilde FlutterViewController'ı al
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Flutter <-> iOS köprüsü: Wi‑Fi AP'ye otomatik katılmak için
    let wifiChannel = FlutterMethodChannel(
      name: "wifi_config",
      binaryMessenger: controller.binaryMessenger
    )

    wifiChannel.setMethodCallHandler { call, result in
      guard call.method == "joinAp" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let args = call.arguments as? [String: Any],
        let ssid = args["ssid"] as? String
      else {
        result(FlutterError(code: "WIFI_ARGS", message: "Eksik SSID", details: nil))
        return
      }

      let pass = (args["pass"] as? String) ?? ""
      let isWep = (args["isWep"] as? Bool) ?? false

      let config: NEHotspotConfiguration
      if pass.isEmpty {
        config = NEHotspotConfiguration(ssid: ssid)
      } else {
        config = NEHotspotConfiguration(ssid: ssid, passphrase: pass, isWEP: isWep)
      }
      // Yalnızca bir kez katıl, iOS otomatik olarak geri dönebilir
      config.joinOnce = true

      NEHotspotConfigurationManager.shared.apply(config) { error in
        if let e = error as NSError? {
          // iOS sabiti: NEHotspotConfigurationErrorDomain
          if e.domain == NEHotspotConfigurationErrorDomain,
             let code = NEHotspotConfigurationError(rawValue: e.code),
             code == .alreadyAssociated {
            result(true) // zaten bu SSID'ye bağlı
          } else {
            result(FlutterError(code: "WIFI_ERROR", message: e.localizedDescription, details: nil))
          }
        } else {
          result(true) // başarı
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
