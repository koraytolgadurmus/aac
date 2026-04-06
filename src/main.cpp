#include <Arduino.h>

// =============================================================
// Feature switches
// =============================================================
// These can be overridden from PlatformIO build flags.
// =============================================================

#ifndef ENABLE_WAQI
#define ENABLE_WAQI 1
#endif


// Local-only build compatibility stubs
#if !ENABLE_WAQI
static inline void pollWaqiIfDue(uint32_t) {}
#endif

static const char* g_loopPhase = nullptr;
static bool g_lastFilterAlert = false;
static uint32_t g_mqttConnectedAtMs = 0;

#include <WiFi.h>
#include <FS.h>
#include <SPIFFS.h>

#if ENABLE_WAQI
#include <WiFiClientSecure.h>
#endif

#if ENABLE_WAQI
#include <HTTPClient.h>
#endif
#if !ENABLE_WAQI
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#endif

#include <Update.h>

#include <PubSubClient.h>

#include <Preferences.h>
Preferences prefs;
#include <ArduinoJson.h>
#include <WebServer.h>

// Production build flag'i
#ifndef PRODUCTION_BUILD
#define PRODUCTION_BUILD 0
#endif

// Log flag'leri - Manufacturing için her zaman aktif (ama sadece 2 defa log'lanacak)
// Production build'de de log'lar gözüksün (güvenlik için sadece 2 defa)
#ifndef LOG_AP_PASS
#define LOG_AP_PASS 0
#endif
#ifndef LOG_FACTORY_QR
#define LOG_FACTORY_QR 0
#endif
// SECURITY: Secret-bearing logs must remain disabled in production.
#ifndef ALLOW_SECRET_LOGS
#define ALLOW_SECRET_LOGS 0
#endif

#include <ESPmDNS.h>
#include <NimBLEDevice.h>
#include <esp_bt.h>
#include "esp_wifi.h"
#include "esp_system.h"
#include "esp_mac.h"
#include "esp_coexist.h"
#include "esp_random.h"

#if defined(ARDUINO_ARCH_ESP32)
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#endif

#if defined(ARDUINO_ARCH_ESP32)
#include <esp_arduino_version.h>
#include "mbedtls/md.h"
#include "mbedtls/sha256.h"
#include "mbedtls/base64.h"
#include "mbedtls/error.h"
#include "mbedtls/ecp.h"
#include "mbedtls/ecdsa.h"
#include "mbedtls/pk.h"
#include "mbedtls/x509_csr.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/gcm.h"
#include "driver/i2s.h"
#endif

#include <ctype.h>
#include <math.h>
#include <algorithm>
#include <memory>
#include <string.h>

#ifndef ENABLE_LOCAL_CONTROL
#define ENABLE_LOCAL_CONTROL 1
#endif
#ifndef ENABLE_HTTP_CMD
#define ENABLE_HTTP_CMD 1
#endif
#ifndef ENABLE_BLE_CMD
#define ENABLE_BLE_CMD 1
#endif
#ifndef DISABLE_CLASSIC_BT_A2DP
#define DISABLE_CLASSIC_BT_A2DP 1
#endif
#ifndef ENABLE_TCP_CMD
#if PRODUCTION_BUILD
#define ENABLE_TCP_CMD 0
#else
#define ENABLE_TCP_CMD 1
#endif
#endif
#ifndef ENABLE_CLOUD
#define ENABLE_CLOUD 0
#endif
#ifndef ENABLE_PERF_DIAG
#define ENABLE_PERF_DIAG 0
#endif
#ifndef ENABLE_RAW_MQTT_LOG
#define ENABLE_RAW_MQTT_LOG 0
#endif
#ifndef OTA_LOCAL_REQUIRE_STRONG_AUTH
#define OTA_LOCAL_REQUIRE_STRONG_AUTH 1
#endif
#ifndef OTA_LOCAL_REQUIRE_SHA256
#define OTA_LOCAL_REQUIRE_SHA256 1
#endif
#ifndef OTA_LOCAL_MIN_INTERVAL_MS
#define OTA_LOCAL_MIN_INTERVAL_MS 120000UL
#endif
#ifndef FW_VERSION
#define FW_VERSION "1.0.3"
#endif
#ifndef SCHEMA_VERSION
#define SCHEMA_VERSION 1
#endif
#ifndef DEVICE_PRODUCT
#define DEVICE_PRODUCT "aac"  // e.g. aac, doa
#endif
#ifndef DEVICE_HW_REV
#define DEVICE_HW_REV "v1"
#endif
#ifndef DEVICE_BOARD_REV
#define DEVICE_BOARD_REV "esp32dev"
#endif
#ifndef DEVICE_FW_CHANNEL
#define DEVICE_FW_CHANNEL "stable"
#endif
#ifndef WIFI_FORCE_NO_SLEEP
#define WIFI_FORCE_NO_SLEEP 1
#endif
#ifndef WIFI_NO_SLEEP_ALLOW_BLE_DEINIT
#define WIFI_NO_SLEEP_ALLOW_BLE_DEINIT 1
#endif
#ifndef WIFI_NO_SLEEP_TEST_MS
#define WIFI_NO_SLEEP_TEST_MS 120000UL
#endif
#ifndef HTTP_DIAG_LOG
#define HTTP_DIAG_LOG 0
#endif
// ---- Forward declarations (local-safe) ----
enum class CmdSource : uint8_t { UNKNOWN = 0, BLE = 1, HTTP = 2, TCP = 3, MQTT = 4 };
static bool equalsIgnoreCaseStr(const String& a, const String& b);
static bool verifyEcdsaP256SignatureOverBytes(const String& pubKeyB64,
                                             const uint8_t* msg,
                                             size_t msgLen,
                                             const String& sigB64);
static void fillStatusJsonMinDoc(JsonDocument& doc);
static String buildStatusJsonMin();
static inline const String& getDeviceId6();
#if defined(ARDUINO_ARCH_ESP32)
static bool ensureSpiffsReady();
static bool ensureSpiffsReadyLogged(const char* context);
#endif

#if ENABLE_PERF_DIAG
static uint32_t perfLargestBlock8Bit() {
#if defined(ARDUINO_ARCH_ESP32)
  return heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
#else
  return 0;
#endif
}

static uint32_t perfLargestBlock32Bit() {
#if defined(ARDUINO_ARCH_ESP32)
  return heap_caps_get_largest_free_block(MALLOC_CAP_32BIT);
#else
  return 0;
#endif
}

static uint32_t perfInternalFree8Bit() {
#if defined(ARDUINO_ARCH_ESP32)
  return heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
#else
  return 0;
#endif
}

static uint32_t perfTaskStackHighWaterBytes() {
#if defined(ARDUINO_ARCH_ESP32)
  return (uint32_t)uxTaskGetStackHighWaterMark(nullptr) * sizeof(StackType_t);
#else
  return 0;
#endif
}

struct PerfThrottleEntry {
  char tag[32];
  uint32_t lastMs;
};

static bool shouldLogPerfTag(const char* tag, uint32_t minIntervalMs) {
  if (!tag || !*tag || minIntervalMs == 0) return true;
  static PerfThrottleEntry entries[24] = {};
  const uint32_t now = millis();
  int freeSlot = -1;
  for (size_t i = 0; i < (sizeof(entries) / sizeof(entries[0])); ++i) {
    if (entries[i].tag[0] == '\0') {
      if (freeSlot < 0) freeSlot = (int)i;
      continue;
    }
    if (strncmp(entries[i].tag, tag, sizeof(entries[i].tag)) == 0) {
      if ((uint32_t)(now - entries[i].lastMs) < minIntervalMs) return false;
      entries[i].lastMs = now;
      return true;
    }
  }
  if (freeSlot < 0) freeSlot = 0;
  strncpy(entries[freeSlot].tag, tag, sizeof(entries[freeSlot].tag) - 1);
  entries[freeSlot].tag[sizeof(entries[freeSlot].tag) - 1] = '\0';
  entries[freeSlot].lastMs = now;
  return true;
}

static void logPerfSnapshot(const char* tag) {
  Serial.printf(
      "[PERF][%s] free=%u min=%u max=%u largest8=%u largest32=%u internal8=%u cpuMHz=%u stackHW=%u\n",
      tag ? tag : "-",
      ESP.getFreeHeap(),
      ESP.getMinFreeHeap(),
      ESP.getMaxAllocHeap(),
      perfLargestBlock8Bit(),
      perfLargestBlock32Bit(),
      perfInternalFree8Bit(),
      ESP.getCpuFreqMHz(),
      perfTaskStackHighWaterBytes());
}

class ScopedPerfLog {
 public:
  explicit ScopedPerfLog(const char* tag, uint32_t minIntervalMs = 0)
      : tag_(tag ? tag : "-"),
        startUs_(micros()),
        enabled_(shouldLogPerfTag(tag_, minIntervalMs)) {
    if (enabled_) logPerfSnapshot(tag_);
  }

  ~ScopedPerfLog() {
    if (!enabled_) return;
    const uint32_t elapsedUs = (uint32_t)(micros() - startUs_);
    Serial.printf("[PERF][%s] elapsed_us=%u\n", tag_, elapsedUs);
    logPerfSnapshot(tag_);
  }

 private:
  const char* tag_;
  uint32_t startUs_;
  bool enabled_;
};
#else
static uint32_t perfLargestBlock8Bit() { return 0; }
static uint32_t perfLargestBlock32Bit() { return 0; }
static uint32_t perfInternalFree8Bit() { return 0; }
static uint32_t perfTaskStackHighWaterBytes() { return 0; }
static void logPerfSnapshot(const char*) {}
class ScopedPerfLog {
 public:
  explicit ScopedPerfLog(const char*, uint32_t = 0) {}
};
#endif
static bool handleIncomingControlJson(JsonDocument& doc,
                                      CmdSource src,
                                      const char* srcName,
                                      bool skipAck,
                                      bool* acceptedOut);
static void onMqttMessage(char* topic, uint8_t* payload, unsigned int length);
static bool loadRootCa(String& out);
static void kickNtpSyncIfNeeded(const char* reason, bool force = false);
static void pollNtpSync(uint32_t nowMs);
static String deviceProductSlug();
static String deviceBrandName();
static String deviceApSsidForId6(const String& id6);
static String deviceBleNameForId6(const String& id6);
static String deviceMdnsHostForId6(const String& id6);
static String deviceMdnsFqdnForId6(const String& id6);

#if ENABLE_WAQI
// HTTP client used for WAQI HTTPS calls.
static WiFiClientSecure g_httpNet;
static bool httpBegin(HTTPClient& http, const String& url);
static void httpStop(HTTPClient& http);
#endif
// --- Optional developer overrides (config.h) ---
// If a local config.h exists, it may define TEST_EMAIL / TEST_ACCESS_TOKEN / TEST_REFRESH.
// We include it conditionally so builds work even without the file.
#if defined(__has_include)
#  if __has_include("config.h")
#    include "config.h"
#  endif
#endif

// NOTE: AP password is derived from device secret (with deterministic secure fallback).
#define ENABLE_BLE 1   // BLE yeniden etkin (gecikmeli güvenli başlatma)
#define SAFE_AP   1   // 1 = AP'nin daima görünür kalmasına odaklı watchdog
#include <Wire.h>
#include <SensirionI2CSen5x.h>
#include <Adafruit_BME680.h>
#include <Adafruit_NeoPixel.h>
#include <DHT.h>
#include <time.h>
#include <sys/time.h>
#include "driver/ledc.h"
#include <bsec2.h>
#include "bsec_config_iaq.h"

#define SAFE_BOOT 0  // 0 = normal operation (enable sensors & planner)


static constexpr time_t kMinValidEpoch = 1700000000L; // ~2023-11-14

static inline bool isTimeValid() {
  return time(nullptr) >= kMinValidEpoch;
}

static constexpr uint32_t NTP_RETRY_MS = 15000UL;
static uint32_t g_lastNtpKickMs = 0;
static bool g_ntpKickStarted = false;
static bool g_ntpAcquiredLogged = false;

/*
 * External declaration for the ESP32 task watchdog reset helper.
 * Declared outside functions so MSVC/GCC treat it as a declaration, not a linkage statement.
 */
#if defined(ARDUINO_ARCH_ESP32)
extern "C" void esp_task_wdt_reset(void);
#endif

// Yield helper for long operations (large JSON / crypto) to avoid WDT/timeouts.
static inline void aacYieldLongOp() {
  // Let WiFi/BLE stacks run.
  delay(0);
  yield();
#if defined(ARDUINO_ARCH_ESP32)
  // If task watchdog is enabled in this build, keep it happy.
  // (esp_task_wdt_reset is available in ESP-IDF; include is optional in Arduino builds.)
  esp_task_wdt_reset();
#endif
}

/* =================== Cloud (Remote) =================== */
#ifndef CLOUD_TOPIC_PREFIX
#define CLOUD_TOPIC_PREFIX "aac"
#endif

struct CloudRuntime {
  bool enabled = false;
  bool linked = false;
  String email;
  String iotEndpoint;
  bool streamActive = false;
  bool mqttConnected = false;
  uint16_t mqttPort = 8883;
  String mqttState;
  int mqttStateCode = 0;
  // cloud state machine info
  uint8_t stateCode = 0;
  String stateReason;
  uint32_t stateSinceMs = 0;
};

enum class CloudState : uint8_t {
  OFF = 0,
  SETUP_REQUIRED = 1,
  PROVISIONING = 2,
  LINKED = 3,
  CONNECTED = 4,
  DEGRADED = 5,
};

static const char* cloudStateToString(CloudState state) {
  switch (state) {
    case CloudState::OFF:
      return "DISABLED";
    case CloudState::SETUP_REQUIRED:
      return "SETUP_REQUIRED";
    case CloudState::PROVISIONING:
      return "PROVISIONING";
    case CloudState::LINKED:
      return "LINKED";
    case CloudState::CONNECTED:
      return "CONNECTED";
    case CloudState::DEGRADED:
      return "DEGRADED";
    default:
      return "UNKNOWN";
  }
}

static String normalizeCloudReason(const char* reason) {
  if (!reason || !reason[0]) return "";
  String r = String(reason);
  r.trim();
  r.toLowerCase();
  if (r == "cloudinit") return "cloud_init";
  if (r == "user disabled") return "user_disabled";
  if (r == "no endpoint") return "no_endpoint";
  if (r == "no wifi") return "no_wifi";
  if (r == "fs fail") return "fs_fail";
  if (r == "needs provisioning") return "needs_provisioning";
  if (r == "tls config") return "tls_config";
  if (r == "no root ca") return "no_root_ca";
  if (r == "tls fail") return "tls_fail";
  if (r == "tls ready") return "tls_ready";
  if (r == "no time") return "no_time";
  if (r == "mqtt connected") return "mqtt_connected";
  if (r == "mqtt connect fail") return "mqtt_connect_fail";
  if (r == "mqtt loop") return "mqtt_loop";
  // Fallback: stabilize free text to snake_case.
  String out;
  out.reserve(r.length());
  bool prevUnderscore = false;
  for (size_t i = 0; i < r.length(); ++i) {
    const char c = r.charAt(i);
    const bool isAlnum =
        (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9');
    if (isAlnum) {
      out += c;
      prevUnderscore = false;
    } else if (!prevUnderscore) {
      out += '_';
      prevUnderscore = true;
    }
  }
  while (out.endsWith("_")) out.remove(out.length() - 1);
  return out;
}

static CloudState g_cloudState = CloudState::OFF;
static CloudRuntime g_cloud;
static String g_cloudEndpointOverride;

static bool isPlaceholderCloudEndpoint(const String& endpointRaw) {
  String endpoint = endpointRaw;
  endpoint.trim();
  endpoint.toLowerCase();
  return endpoint.length() == 0 || endpoint == "your_aws_iot_endpoint";
}

static String normalizeCloudEndpoint(String endpointRaw) {
  endpointRaw.trim();
  if (endpointRaw.startsWith("https://")) endpointRaw.remove(0, 8);
  if (endpointRaw.startsWith("mqtts://")) endpointRaw.remove(0, 8);
  const int slashIdx = endpointRaw.indexOf('/');
  if (slashIdx >= 0) endpointRaw = endpointRaw.substring(0, slashIdx);
  endpointRaw.trim();
  // Accept host or host:port; keep host part for PubSubClient setServer(host, port).
  const int colonIdx = endpointRaw.lastIndexOf(':');
  if (colonIdx > 0) {
    bool portOnly = true;
    for (int i = colonIdx + 1; i < endpointRaw.length(); ++i) {
      if (!isDigit((unsigned char)endpointRaw.charAt(i))) {
        portOnly = false;
        break;
      }
    }
    if (portOnly) endpointRaw = endpointRaw.substring(0, colonIdx);
  }
  endpointRaw.trim();
  return endpointRaw;
}

static String effectiveCloudEndpoint() {
  String endpoint = normalizeCloudEndpoint(g_cloudEndpointOverride);
  if (!isPlaceholderCloudEndpoint(endpoint)) return endpoint;
  endpoint = normalizeCloudEndpoint(String(AWS_IOT_ENDPOINT));
  return endpoint;
}

static void setCloudState(CloudState next, const char* reason = nullptr) {
  const bool changed = (g_cloudState != next);
  String reasonNorm;
  bool hasReason = false;
  bool reasonChanged = false;
  if (reason && reason[0]) {
    hasReason = true;
    reasonNorm = normalizeCloudReason(reason);
    reasonChanged = (reasonNorm != g_cloud.stateReason);
  }
  if (!changed && !reasonChanged) return;
  g_cloudState = next;
  if (changed) {
    g_cloud.stateSinceMs = millis();
  }
  g_cloud.stateCode = static_cast<uint8_t>(next);
  g_cloud.mqttState = cloudStateToString(next);
  g_cloud.mqttStateCode = static_cast<int>(next);
  if (hasReason) {
    g_cloud.stateReason = reasonNorm;
    Serial.printf("[CLOUD] state -> %s (%s)\n",
                  g_cloud.mqttState.c_str(),
                  reasonNorm.c_str());
  } else if (changed) {
    g_cloud.stateReason = "";
  }
}

static WiFiClientSecure g_mqttNet;
static PubSubClient g_mqtt(g_mqttNet);
static String g_mqttServerHost;
static uint32_t g_mqttLastAttemptMs = 0;
static const uint32_t MQTT_RECONNECT_MS = 5000;
static const uint32_t MQTT_RECONNECT_MAX_MS = 60000;
static uint32_t g_mqttBackoffMs = MQTT_RECONNECT_MS;
static uint8_t g_mqttTlsFailStreak = 0;
static uint8_t g_mqttConnectFailStreak = 0;
static uint32_t g_mqttLastRecoveryMs = 0;
static uint32_t g_mqttLastRestartMs = 0;
static const uint8_t MQTT_TLS_RELOAD_THRESHOLD = 3;
static const uint8_t MQTT_TLS_RESTART_THRESHOLD = 12;
static const uint8_t MQTT_TLS_WIFI_RECOVER_THRESHOLD = 8;
static const uint8_t MQTT_CONNECT_RELOAD_THRESHOLD = 6;
static const uint32_t MQTT_RECOVERY_COOLDOWN_MS = 20000;
static const uint32_t MQTT_RESTART_COOLDOWN_MS = 600000;
static const uint32_t MQTT_WIFI_RECOVERY_COOLDOWN_MS = 120000;
static uint32_t g_mqttLastWifiRecoverMs = 0;
static const uint32_t PROV_RETRY_MS = 5000;
static const uint32_t PROV_RETRY_MAX_MS = 60000;
static uint32_t g_provLastAttemptMs = 0;
static uint32_t g_provBackoffMs = PROV_RETRY_MS;
static const uint32_t TLSCFG_RETRY_MS = 5000;
static const uint32_t TLSCFG_RETRY_MAX_MS = 60000;
static uint32_t g_tlsCfgLastAttemptMs = 0;
static uint32_t g_tlsCfgBackoffMs = TLSCFG_RETRY_MS;
static uint32_t g_cloudLastPubMs = 0;
static bool g_cloudDirty = true;
static const uint32_t CLOUD_PUB_INTERVAL_MS = 10000;
static uint32_t g_lastDesiredDebugPingMs = 0;
static uint64_t g_lastDesiredDebugClientTsMs = 0;
static uint64_t g_lastDesiredDebugLogClientTsMs = 0;
static uint32_t g_lastDesiredDebugLogAtMs = 0;
static bool g_provisioned = false;
static bool g_provisioningInProgress = false;
static bool g_tlsConfigured = false;
static bool g_cloudUserEnabled = false;
static bool g_claimDeletePending = false;
static uint32_t g_nextDeviceCertValidationMs = 0;
static uint8_t g_deviceCertInvalidStreak = 0;
// Re-provision trigger latency was too long (60s * 3 ~= 3 min).
// Keep a small debounce for transient FS hiccups but recover much faster
// when device cert/key are genuinely missing.
static const uint32_t DEVICE_CERT_VALIDATION_INTERVAL_MS = 15000;
static const uint8_t DEVICE_CERT_INVALID_STREAK_MAX = 2;

// Provisioning state
static bool g_provCertOk = false;
static bool g_provCertFail = false;
static bool g_provThingOk = false;
static bool g_provThingFail = false;
static String g_newCertPem;
static String g_newPrivKey;
static String g_newCertId;
static String g_certOwnershipToken;
static String g_provErr;

#ifndef AWS_IOT_ENDPOINT
#define AWS_IOT_ENDPOINT "YOUR_AWS_IOT_ENDPOINT"
#endif
#ifndef AWS_IOT_PORT
#define AWS_IOT_PORT 8883
#endif
#ifndef AWS_IOT_ROOT_CA_PEM
#define AWS_IOT_ROOT_CA_PEM ""
#endif
#ifndef AWS_IOT_CLAIM_CERT_PEM
#define AWS_IOT_CLAIM_CERT_PEM ""
#endif
#ifndef AWS_IOT_CLAIM_PRIVATE_KEY_PEM
#define AWS_IOT_CLAIM_PRIVATE_KEY_PEM ""
#endif
#ifndef AWS_IOT_DEVICE_CERT_PEM
#define AWS_IOT_DEVICE_CERT_PEM ""
#endif
#ifndef AWS_IOT_PRIVATE_KEY_PEM
#define AWS_IOT_PRIVATE_KEY_PEM ""
#endif

#ifndef PROVISIONING_TEMPLATE_NAME
#define PROVISIONING_TEMPLATE_NAME ""
#endif
#ifndef FORCE_PROVISIONING
#define FORCE_PROVISIONING 0
#endif

static const char* kRootCaPath = "/AmazonRootCA1.pem";
static const char* kClaimCertPath = "/claim_cert.pem";
static const char* kClaimKeyPath = "/claim_private.key";
static const char* kDeviceCertPath = "/device_cert.pem";
static const char* kDeviceKeyPath = "/device_private.key";

// Keep TLS material alive for the lifetime of the connection.
static String g_tlsRootCaOwned;
static String g_tlsCertOwned;
static String g_tlsKeyOwned;
static const char* g_tlsRootCa = nullptr;
static const char* g_tlsCert = nullptr;
static const char* g_tlsKey = nullptr;

static void applyTlsCommon() {
  // WiFiClientSecure expects seconds (not milliseconds).
  // 10s was still too aggressive during claim/provisioning on noisy WLANs.
  g_mqttNet.setTimeout(20);
  g_mqttNet.setHandshakeTimeout(20);
}

static void ensureMqttServerConfigured(const String& endpoint) {
  if (endpoint.isEmpty()) return;
  if (g_mqttServerHost != endpoint) {
    g_mqttServerHost = endpoint;
    // PubSubClient keeps raw host pointer internally; keep backing storage alive.
    g_mqtt.setServer(g_mqttServerHost.c_str(), AWS_IOT_PORT);
    Serial.printf("[MQTT] server host set=%s\n", g_mqttServerHost.c_str());
  }
}

static void ensureMqttPacketBuffer(size_t bytes) {
  const bool ok = g_mqtt.setBufferSize(bytes);
  Serial.printf("[MQTT] buffer size request=%u ok=%d\n",
                (unsigned)bytes,
                ok ? 1 : 0);
}

static void recoverMqttTransport(const char* reason, bool requestTlsReload) {
  const uint32_t nowMs = millis();
  if ((uint32_t)(nowMs - g_mqttLastRecoveryMs) < MQTT_RECOVERY_COOLDOWN_MS) {
    return;
  }
  g_mqttLastRecoveryMs = nowMs;
  Serial.printf("[MQTT][RECOVERY] reason=%s tlsReload=%d freeHeap=%u minFree=%u\n",
                reason ? reason : "-",
                requestTlsReload ? 1 : 0,
                (unsigned)ESP.getFreeHeap(),
                (unsigned)ESP.getMinFreeHeap());
  if (g_mqtt.connected()) {
    g_mqtt.disconnect();
  }
  if (g_mqttNet.connected()) {
    g_mqttNet.stop();
  }
  delay(40);
  if (requestTlsReload) {
    g_tlsConfigured = false;
    g_tlsCfgLastAttemptMs = 0;
    g_tlsCfgBackoffMs = TLSCFG_RETRY_MS;
    setCloudState(CloudState::SETUP_REQUIRED, "tls reload");
  }
}

static void recoverWifiTransportForMqtt(const char* reason) {
  const uint32_t nowMs = millis();
  if ((uint32_t)(nowMs - g_mqttLastWifiRecoverMs) < MQTT_WIFI_RECOVERY_COOLDOWN_MS) {
    return;
  }
  g_mqttLastWifiRecoverMs = nowMs;

  const wl_status_t sta = WiFi.status();
  const wifi_mode_t mode = WiFi.getMode();
  const bool keepAp = (mode == WIFI_AP || mode == WIFI_AP_STA);
  Serial.printf("[MQTT][RECOVERY] wifi reconnect reason=%s sta=%d mode=%d keepAp=%d\n",
                reason ? reason : "-",
                (int)sta,
                (int)mode,
                keepAp ? 1 : 0);

  // Keep SoftAP availability if it was already active, but force STA re-association.
  WiFi.mode(keepAp ? WIFI_AP_STA : WIFI_STA);
  if (sta == WL_CONNECTED) {
    WiFi.disconnect(false, false);
    delay(80);
  }
  WiFi.reconnect();
}

static inline String cloudTopicCmd() {
  return String(CLOUD_TOPIC_PREFIX) + "/" + getDeviceId6() + "/cmd";
}
static inline String cloudTopicState() {
  return String(CLOUD_TOPIC_PREFIX) + "/" + getDeviceId6() + "/state";
}
static inline String cloudThingNamePrimary();
static inline String cloudTopicShadow() {
  return String(CLOUD_TOPIC_PREFIX) + "/" + getDeviceId6() + "/shadow";
}

static inline String cloudThingNamePrimary() {
  return deviceProductSlug() + String("-") + getDeviceId6();
}
static inline String cloudThingNameLegacy() {
  return String(getDeviceId6());
}
static inline String cloudMqttClientId() {
  return cloudThingNamePrimary();
}
static inline String claimMqttClientId() {
  return String("claim-") + getDeviceId6();
}
static inline String cloudTopicShadowDeltaForThing(const String& thingName) {
  return String("$aws/things/") + thingName + "/shadow/update/delta";
}
static inline bool isShadowDeltaTopic(const String& topic) {
  return topic.endsWith("/shadow/update/delta");
}
static inline String jobsTopicNotifyNextForThing(const String& thingName) {
  return String("$aws/things/") + thingName + "/jobs/notify-next";
}
static inline String jobsTopicGetNextForThing(const String& thingName) {
  return String("$aws/things/") + thingName + "/jobs/$next/get";
}
static inline String jobsTopicGetNextAcceptedForThing(const String& thingName) {
  return String("$aws/things/") + thingName + "/jobs/$next/get/accepted";
}
static inline String jobsTopicUpdateForThing(const String& thingName, const String& jobId) {
  return String("$aws/things/") + thingName + "/jobs/" + jobId + "/update";
}
static inline bool isJobsNotifyNextTopic(const String& topic) {
  return topic.endsWith("/jobs/notify-next");
}
static inline bool isJobsGetNextAcceptedTopic(const String& topic) {
  return topic.endsWith("/jobs/$next/get/accepted");
}
static String extractThingNameFromJobsTopic(const String& topic) {
  const String prefix = "$aws/things/";
  const int p = topic.indexOf(prefix);
  if (p != 0) return String();
  const int start = prefix.length();
  const int end = topic.indexOf("/jobs/", start);
  if (end <= start) return String();
  return topic.substring(start, end);
}

static bool isHex64String(const String& s) {
  if (s.length() != 64) return false;
  for (size_t i = 0; i < 64; ++i) {
    const char c = s.charAt(i);
    const bool isDigit = (c >= '0' && c <= '9');
    const bool isHexLower = (c >= 'a' && c <= 'f');
    const bool isHexUpper = (c >= 'A' && c <= 'F');
    if (!isDigit && !isHexLower && !isHexUpper) return false;
  }
  return true;
}

static String toLowerAscii(const String& in) {
  String out = in;
  for (size_t i = 0; i < out.length(); ++i) {
    const char c = out.charAt(i);
    if (c >= 'A' && c <= 'Z') {
      out.setCharAt(i, static_cast<char>(c - 'A' + 'a'));
    }
  }
  return out;
}

static int parseSemverCore(const String& raw, int out[4]) {
  if (!out) return 0;
  for (int i = 0; i < 4; ++i) out[i] = 0;
  String s = raw;
  s.trim();
  if (!s.length()) return 0;
  const int dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);
  const int plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);

  int idx = 0;
  int start = 0;
  while (idx < 4 && start <= (int)s.length()) {
    int dot = s.indexOf('.', start);
    String token;
    if (dot < 0) {
      token = s.substring(start);
      start = s.length() + 1;
    } else {
      token = s.substring(start, dot);
      start = dot + 1;
    }
    token.trim();
    if (!token.length()) return 0;
    for (size_t i = 0; i < token.length(); ++i) {
      if (!isDigit(token[i])) return 0;
    }
    out[idx++] = token.toInt();
    if (dot < 0) break;
  }
  return idx;
}

static int compareSemver(const String& aRaw, const String& bRaw) {
  int a[4] = {0, 0, 0, 0};
  int b[4] = {0, 0, 0, 0};
  const int na = parseSemverCore(aRaw, a);
  const int nb = parseSemverCore(bRaw, b);
  if (na == 0 || nb == 0) return 0;  // fail-open for legacy/non-semver strings
  for (int i = 0; i < 4; ++i) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return 0;
}

struct PendingOtaJob {
  String thingName;
  String jobId;
  String firmwareUrl;
  String expectedSha256;
  String targetVersion;
};

struct OtaStatusInfo {
  String phase;
  String reason;
  String targetVersion;
  String jobId;
  uint32_t updatedAtMs = 0;
};

static PendingOtaJob g_pendingOtaJob;
static bool g_pendingOtaApproveRequested = false;
static bool g_pendingOtaRejectRequested = false;
static OtaStatusInfo g_lastOtaStatus;

static void setLastOtaStatus(const char* phase,
                             const char* reason,
                             const String& jobId = String(),
                             const String& targetVersion = String()) {
  g_lastOtaStatus.phase = phase ? String(phase) : String();
  g_lastOtaStatus.reason = reason ? String(reason) : String();
  g_lastOtaStatus.jobId = jobId;
  g_lastOtaStatus.targetVersion = targetVersion;
  g_lastOtaStatus.updatedAtMs = millis();

  prefs.begin("aac", false);
  prefs.putString("ota_phase", g_lastOtaStatus.phase);
  prefs.putString("ota_reason", g_lastOtaStatus.reason);
  prefs.putString("ota_job_id", g_lastOtaStatus.jobId);
  prefs.putString("ota_target_ver", g_lastOtaStatus.targetVersion);
  prefs.putUInt("ota_updated_ms", g_lastOtaStatus.updatedAtMs);
  prefs.end();
}

static void appendLastOtaStatus(JsonObject ota) {
  if (!g_lastOtaStatus.phase.length()) return;
  ota["lastStatus"] = g_lastOtaStatus.phase;
  if (g_lastOtaStatus.reason.length()) ota["lastReason"] = g_lastOtaStatus.reason;
  if (g_lastOtaStatus.targetVersion.length()) ota["lastTargetVersion"] = g_lastOtaStatus.targetVersion;
  if (g_lastOtaStatus.jobId.length()) ota["lastJobId"] = g_lastOtaStatus.jobId;
  if (g_lastOtaStatus.updatedAtMs > 0) ota["lastUpdatedMs"] = g_lastOtaStatus.updatedAtMs;
}


static bool isSemverParseable(const String& raw) {
  int parts[4] = {0, 0, 0, 0};
  return parseSemverCore(raw, parts) > 0;
}

static bool parseBoolLoose(const String& raw, bool fallbackValue = false) {
  String s = raw;
  s.trim();
  s.toLowerCase();
  if (!s.length()) return fallbackValue;
  if (s == "1" || s == "true" || s == "yes" || s == "on") return true;
  if (s == "0" || s == "false" || s == "no" || s == "off") return false;
  return fallbackValue;
}

static bool hasPendingOtaJob() {
  return g_pendingOtaJob.jobId.length() &&
         g_pendingOtaJob.thingName.length() &&
         g_pendingOtaJob.firmwareUrl.length() &&
         g_pendingOtaJob.expectedSha256.length() &&
         g_pendingOtaJob.targetVersion.length();
}

static void clearPendingOtaJob() {
  g_pendingOtaJob.thingName = "";
  g_pendingOtaJob.jobId = "";
  g_pendingOtaJob.firmwareUrl = "";
  g_pendingOtaJob.expectedSha256 = "";
  g_pendingOtaJob.targetVersion = "";
  g_pendingOtaApproveRequested = false;
  g_pendingOtaRejectRequested = false;
}

static void setPendingOtaJob(const String& thingName,
                             const String& jobId,
                             const String& firmwareUrl,
                             const String& expectedSha256,
                             const String& version) {
  g_pendingOtaJob.thingName = thingName;
  g_pendingOtaJob.jobId = jobId;
  g_pendingOtaJob.firmwareUrl = firmwareUrl;
  g_pendingOtaJob.expectedSha256 = expectedSha256;
  g_pendingOtaJob.targetVersion = version;
  g_pendingOtaApproveRequested = false;
  g_pendingOtaRejectRequested = false;
}

static bool publishJobExecutionStatus(const String& thingName,
                                      const String& jobId,
                                      const char* status,
                                      const char* reason,
                                      const String& detailA = String(),
                                      const String& detailB = String()) {
  if (!thingName.length() || !jobId.length() || !status || !reason) return false;
  const String updTopic = jobsTopicUpdateForThing(thingName, jobId);
  JsonDocument updDoc;
  JsonObject upd = updDoc.to<JsonObject>();
  upd["status"] = status;
  JsonObject details = upd["statusDetails"].to<JsonObject>();
  details["reason"] = reason;
  if (detailA.length()) details["detailA"] = detailA;
  if (detailB.length()) details["detailB"] = detailB;
  String payload;
  serializeJson(updDoc, payload);
  const bool ok = g_mqtt.publish(updTopic.c_str(), payload.c_str(), false);
  Serial.printf("[JOBS] update status=%s ok=%d topic=%s\n",
                status, ok ? 1 : 0, updTopic.c_str());
  return ok;
}

static bool performOtaFromUrl(const String& firmwareUrl,
                              const String& expectedShaHexLower,
                              String& outError,
                              String& outShaHex,
                              size_t& outBytes) {
  outError = "";
  outShaHex = "";
  outBytes = 0;
  if (WiFi.status() != WL_CONNECTED) {
    outError = "no_wifi";
    return false;
  }
  if (!firmwareUrl.startsWith("https://")) {
    outError = "url_must_be_https";
    return false;
  }
  if (!isHex64String(expectedShaHexLower)) {
    outError = "bad_sha256";
    return false;
  }
  String rootCa;
  if (g_tlsRootCa && *g_tlsRootCa) {
    rootCa = g_tlsRootCa;
  }
  if (!rootCa.length()) {
    if (!loadRootCa(rootCa)) {
      outError = "missing_root_ca";
      return false;
    }
  }

  WiFiClientSecure otaNet;
  // WiFiClientSecure timeout units are seconds.
  otaNet.setTimeout(15);
  otaNet.setHandshakeTimeout(15);
  otaNet.setCACert(rootCa.c_str());
  HTTPClient http;
  if (!http.begin(otaNet, firmwareUrl)) {
    outError = "http_begin_failed";
    return false;
  }
  http.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
  const int code = http.GET();
  if (code != HTTP_CODE_OK) {
    outError = String("http_") + String(code);
    http.end();
    otaNet.stop();
    return false;
  }

  const int contentLength = http.getSize();
  if (!Update.begin(contentLength > 0 ? (size_t)contentLength : UPDATE_SIZE_UNKNOWN)) {
    outError = String("update_begin_") + String((int)Update.getError());
    http.end();
    otaNet.stop();
    return false;
  }

  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  if (mbedtls_sha256_starts_ret(&sha, 0) != 0) {
    Update.abort();
    mbedtls_sha256_free(&sha);
    http.end();
    otaNet.stop();
    outError = "sha_init_failed";
    return false;
  }

  WiFiClient* stream = http.getStreamPtr();
  int remaining = contentLength;
  uint8_t buf[1024];
  while (http.connected() && (remaining > 0 || remaining == -1)) {
    const size_t avail = stream->available();
    if (avail == 0) {
      delay(1);
      continue;
    }
    const size_t toRead = (avail > sizeof(buf)) ? sizeof(buf) : avail;
    const int n = stream->readBytes(reinterpret_cast<char*>(buf), toRead);
    if (n <= 0) continue;
    if (Update.write(buf, static_cast<size_t>(n)) != static_cast<size_t>(n)) {
      mbedtls_sha256_free(&sha);
      Update.abort();
      http.end();
      otaNet.stop();
      outError = String("update_write_") + String((int)Update.getError());
      return false;
    }
    if (mbedtls_sha256_update_ret(&sha, buf, static_cast<size_t>(n)) != 0) {
      mbedtls_sha256_free(&sha);
      Update.abort();
      http.end();
      otaNet.stop();
      outError = "sha_update_failed";
      return false;
    }
    outBytes += static_cast<size_t>(n);
    if (remaining > 0) remaining -= n;
  }

  uint8_t digest[32] = {0};
  if (mbedtls_sha256_finish_ret(&sha, digest) != 0) {
    mbedtls_sha256_free(&sha);
    Update.abort();
    http.end();
    otaNet.stop();
    outError = "sha_finish_failed";
    return false;
  }
  mbedtls_sha256_free(&sha);
  outShaHex = "";
  outShaHex.reserve(64);
  static const char* kHex = "0123456789abcdef";
  for (size_t i = 0; i < 32; ++i) {
    outShaHex += kHex[(digest[i] >> 4) & 0x0F];
    outShaHex += kHex[digest[i] & 0x0F];
  }
  if (toLowerAscii(outShaHex) != toLowerAscii(expectedShaHexLower)) {
    Update.abort();
    http.end();
    otaNet.stop();
    outError = "sha256_mismatch";
    return false;
  }

  if (!Update.end(true)) {
    outError = String("update_end_") + String((int)Update.getError());
    http.end();
    otaNet.stop();
    return false;
  }
  if (!Update.isFinished()) {
    outError = "update_not_finished";
    http.end();
    otaNet.stop();
    return false;
  }
  http.end();
  otaNet.stop();
  return true;
}

static inline String provCreateAcceptedTopic() {
  return String("$aws/certificates/create-from-csr/json/accepted");
}
static inline String provCreateRejectedTopic() {
  return String("$aws/certificates/create-from-csr/json/rejected");
}
static inline String provisioningTemplateName() {
  String configured = String(PROVISIONING_TEMPLATE_NAME);
  configured.trim();
  if (configured.length() > 0) return configured;
  return deviceProductSlug() + String("-provisioning-template");
}
static inline String provProvisionTopic() {
  return String("$aws/provisioning-templates/") +
         provisioningTemplateName() + "/provision/json";
}
static inline String provProvisionAcceptedTopic() {
  return String("$aws/provisioning-templates/") +
         provisioningTemplateName() + "/provision/json/accepted";
}
static inline String provProvisionRejectedTopic() {
  return String("$aws/provisioning-templates/") +
         provisioningTemplateName() + "/provision/json/rejected";
}

static int mbedtlsHardwareRng(void* ctx, unsigned char* out, size_t len) {
  (void)ctx;
  if (!out || len == 0) return 0;
  esp_fill_random(out, len);
  return 0;
}

static bool generateEcDeviceKeyAndCsr(String& outKeyPem, String& outCsrPem) {
#if defined(ARDUINO_ARCH_ESP32)
  outKeyPem = "";
  outCsrPem = "";

  mbedtls_pk_context pk;
  mbedtls_x509write_csr req;
  mbedtls_pk_init(&pk);
  mbedtls_x509write_csr_init(&req);

  bool ok = false;
  std::unique_ptr<unsigned char[]> keyPem(new unsigned char[2048]());
  std::unique_ptr<unsigned char[]> csrPem(new unsigned char[2048]());
  const mbedtls_pk_info_t* pkInfo = mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY);
  if (pkInfo && keyPem && csrPem &&
      mbedtls_pk_setup(&pk, pkInfo) == 0 &&
      mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1,
                          mbedtls_pk_ec(pk),
                          mbedtlsHardwareRng,
                          nullptr) == 0 &&
      mbedtls_pk_write_key_pem(&pk, keyPem.get(), 2048) == 0) {
    mbedtls_x509write_csr_set_md_alg(&req, MBEDTLS_MD_SHA256);
    mbedtls_x509write_csr_set_key(&req, &pk);
    const String subject = String("CN=") + cloudThingNamePrimary() + ",O=" + deviceBrandName();
    if (mbedtls_x509write_csr_set_subject_name(&req, subject.c_str()) == 0 &&
        mbedtls_x509write_csr_pem(&req,
                                  csrPem.get(),
                                  2048,
                                  mbedtlsHardwareRng,
                                  nullptr) == 0) {
      outKeyPem = String(reinterpret_cast<const char*>(keyPem.get()));
      outCsrPem = String(reinterpret_cast<const char*>(csrPem.get()));
      ok = outKeyPem.indexOf("BEGIN") >= 0 &&
           outKeyPem.indexOf("END") >= 0 &&
           outCsrPem.indexOf("BEGIN CERTIFICATE REQUEST") >= 0 &&
           outCsrPem.indexOf("END CERTIFICATE REQUEST") >= 0;
    }
  }

  mbedtls_x509write_csr_free(&req);
  mbedtls_pk_free(&pk);
  return ok;
#else
  (void)outKeyPem;
  (void)outCsrPem;
  return false;
#endif
}

static bool spiffsReadString(const char* path, String& out) {
  if (!ensureSpiffsReady()) return false;
  if (!SPIFFS.exists(path)) return false;
  File f = SPIFFS.open(path, "r");
  if (!f) return false;
  out = f.readString();
  f.close();
  return out.length() > 0;
}

static size_t spiffsFileSize(const char* path) {
  if (!ensureSpiffsReady()) return 0;
  if (!SPIFFS.exists(path)) return 0;
  File f = SPIFFS.open(path, "r");
  if (!f) return 0;
  size_t n = f.size();
  f.close();
  return n;
}

static void logCertFileStatus() {
  const size_t rootSz = spiffsFileSize(kRootCaPath);
  const size_t devCertSz = spiffsFileSize(kDeviceCertPath);
  const size_t devKeySz = spiffsFileSize(kDeviceKeyPath);
  const size_t claimCertSz = spiffsFileSize(kClaimCertPath);
  const size_t claimKeySz = spiffsFileSize(kClaimKeyPath);
  Serial.printf("[TLS] files rootCA=%u deviceCert=%u deviceKey=%u claimCert=%u claimKey=%u\n",
                (unsigned)rootSz, (unsigned)devCertSz, (unsigned)devKeySz,
                (unsigned)claimCertSz, (unsigned)claimKeySz);
}

static bool pemLooksValid(const String& s) {
  if (s.length() < 64) return false;
  const bool hasBegin = s.indexOf("BEGIN") >= 0;
  const bool hasEnd = s.indexOf("END") >= 0;
  return hasBegin && hasEnd;
}

static bool spiffsFileContainsToken(const char* path, const char* token) {
  if (!ensureSpiffsReady()) return false;
  if (!path || !token) return false;
  File f = SPIFFS.open(path, "r");
  if (!f) return false;
  const size_t needleLen = strlen(token);
  if (needleLen == 0) {
    f.close();
    return false;
  }
  String window;
  window.reserve(needleLen + 4);
  bool found = false;
  while (f.available()) {
    const char c = (char)f.read();
    window += c;
    if (window.length() > needleLen) {
      window.remove(0, window.length() - needleLen);
    }
    if (window.equals(token)) {
      found = true;
      break;
    }
  }
  f.close();
  return found;
}

static bool deviceCertsValid() {
  const size_t certSz = spiffsFileSize(kDeviceCertPath);
  const size_t keySz = spiffsFileSize(kDeviceKeyPath);
  if (certSz < 256 || keySz < 256) return false;
  const bool certBegin = spiffsFileContainsToken(kDeviceCertPath, "-----BEGIN CERTIFICATE-----");
  const bool certEnd = spiffsFileContainsToken(kDeviceCertPath, "-----END CERTIFICATE-----");
  const bool keyBeginRsa = spiffsFileContainsToken(kDeviceKeyPath, "-----BEGIN RSA PRIVATE KEY-----");
  const bool keyEndRsa = spiffsFileContainsToken(kDeviceKeyPath, "-----END RSA PRIVATE KEY-----");
  const bool keyBeginPkcs8 = spiffsFileContainsToken(kDeviceKeyPath, "-----BEGIN PRIVATE KEY-----");
  const bool keyEndPkcs8 = spiffsFileContainsToken(kDeviceKeyPath, "-----END PRIVATE KEY-----");
  const bool keyBeginEc = spiffsFileContainsToken(kDeviceKeyPath, "-----BEGIN EC PRIVATE KEY-----");
  const bool keyEndEc = spiffsFileContainsToken(kDeviceKeyPath, "-----END EC PRIVATE KEY-----");
  const bool certOk = certBegin && certEnd;
  const bool keyOk = (keyBeginRsa && keyEndRsa) ||
                     (keyBeginPkcs8 && keyEndPkcs8) ||
                     (keyBeginEc && keyEndEc);
  return certOk && keyOk;
}

static bool deviceKeyLooksEc() {
  const bool keyBeginPkcs8 = spiffsFileContainsToken(kDeviceKeyPath, "-----BEGIN PRIVATE KEY-----");
  const bool keyEndPkcs8 = spiffsFileContainsToken(kDeviceKeyPath, "-----END PRIVATE KEY-----");
  const bool keyBeginEc = spiffsFileContainsToken(kDeviceKeyPath, "-----BEGIN EC PRIVATE KEY-----");
  const bool keyEndEc = spiffsFileContainsToken(kDeviceKeyPath, "-----END EC PRIVATE KEY-----");
  const bool keyBeginRsa = spiffsFileContainsToken(kDeviceKeyPath, "-----BEGIN RSA PRIVATE KEY-----");
  const bool keyEndRsa = spiffsFileContainsToken(kDeviceKeyPath, "-----END RSA PRIVATE KEY-----");
  if (keyBeginRsa && keyEndRsa) return false;
  return (keyBeginEc && keyEndEc) || (keyBeginPkcs8 && keyEndPkcs8);
}

static bool deviceCertsEcReady() {
  return deviceCertsValid() && deviceKeyLooksEc();
}

static bool inlineDeviceCertsValid() {
  const bool certInline = AWS_IOT_DEVICE_CERT_PEM[0] &&
                          strcmp(AWS_IOT_DEVICE_CERT_PEM, "YOUR_AWS_IOT_DEVICE_CERT_PEM") != 0 &&
                          strstr(AWS_IOT_DEVICE_CERT_PEM, "-----BEGIN ") != nullptr;
  const bool keyInline = AWS_IOT_PRIVATE_KEY_PEM[0] &&
                         strcmp(AWS_IOT_PRIVATE_KEY_PEM, "YOUR_AWS_IOT_PRIVATE_KEY_PEM") != 0 &&
                         strstr(AWS_IOT_PRIVATE_KEY_PEM, "-----BEGIN ") != nullptr;
  return certInline && keyInline;
}

static void logPemInfo(const char* label, const char* s) {
  if (!s || !*s) {
    Serial.printf("[TLS] %s len=0\n", label);
    return;
  }
  const int len = (int)strlen(s);
  const uint8_t* p = reinterpret_cast<const uint8_t*>(s);
  Serial.printf("[TLS] %s len=%d head=%02X %02X %02X %02X %02X %02X %02X %02X tail=%02X %02X %02X %02X %02X %02X %02X %02X\n",
                label, len,
                p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7],
                p[len - 8], p[len - 7], p[len - 6], p[len - 5],
                p[len - 4], p[len - 3], p[len - 2], p[len - 1]);
  const bool hasBegin = strstr(s, "BEGIN") != nullptr;
  const bool hasEnd = strstr(s, "END") != nullptr;
  Serial.printf("[TLS] %s hasBegin=%d hasEnd=%d\n", label, hasBegin ? 1 : 0, hasEnd ? 1 : 0);
}

static bool pemLiteralIsUsable(const char* pem, const char* placeholder) {
  if (!pem || !*pem) return false;
  if (placeholder && strcmp(pem, placeholder) == 0) return false;
  return strstr(pem, "-----BEGIN ") != nullptr;
}

static bool pemLooksRsaPrivateKey(const char* pem) {
  if (!pem) return false;
  return strstr(pem, "BEGIN RSA PRIVATE KEY") != nullptr;
}

static void resetTlsMaterial() {
  g_tlsRootCaOwned = "";
  g_tlsCertOwned = "";
  g_tlsKeyOwned = "";
  g_tlsRootCa = nullptr;
  g_tlsCert = nullptr;
  g_tlsKey = nullptr;
}

static bool spiffsWriteString(const char* path, const String& data) {
  if (!ensureSpiffsReadyLogged("spiffs_write")) return false;
  File f = SPIFFS.open(path, "w");
  if (!f) return false;
  size_t n = f.print(data);
  f.close();
  return n == data.length();
}

static void spiffsRemoveIfExists(const char* path) {
  if (!ensureSpiffsReadyLogged("spiffs_remove")) return;
  if (SPIFFS.exists(path)) {
    SPIFFS.remove(path);
  }
}

static bool loadRootCa(String& out) {
  String inlinePem = String(AWS_IOT_ROOT_CA_PEM);
  if (inlinePem.length() > 0 && inlinePem != "YOUR_AWS_IOT_ROOT_CA_PEM") {
    out = inlinePem;
    return true;
  }
  return spiffsReadString(kRootCaPath, out);
}

static bool loadClaimCert(String& out) {
  String inlinePem = String(AWS_IOT_CLAIM_CERT_PEM);
  if (inlinePem.length() > 0 && inlinePem != "YOUR_AWS_IOT_CLAIM_CERT_PEM") {
    out = inlinePem;
    return true;
  }
  return spiffsReadString(kClaimCertPath, out);
}

static bool loadClaimKey(String& out) {
  String inlinePem = String(AWS_IOT_CLAIM_PRIVATE_KEY_PEM);
  if (inlinePem.length() > 0 && inlinePem != "YOUR_AWS_IOT_CLAIM_PRIVATE_KEY_PEM") {
    out = inlinePem;
    return true;
  }
  return spiffsReadString(kClaimKeyPath, out);
}

static bool loadDeviceCertPem(const char* certPath, String& out) {
  if (spiffsReadString(certPath, out)) return true;
  String inlinePem = String(AWS_IOT_DEVICE_CERT_PEM);
  if (inlinePem.length() > 0 && inlinePem != "YOUR_AWS_IOT_DEVICE_CERT_PEM") {
    out = inlinePem;
    return true;
  }
  return false;
}

static bool loadDeviceKeyPem(const char* keyPath, String& out) {
  if (spiffsReadString(keyPath, out)) return true;
  String inlinePem = String(AWS_IOT_PRIVATE_KEY_PEM);
  if (inlinePem.length() > 0 && inlinePem != "YOUR_AWS_IOT_PRIVATE_KEY_PEM") {
    out = inlinePem;
    return true;
  }
  return false;
}

static bool configureTlsFromFiles(const char* certPath, const char* keyPath) {
  resetTlsMaterial();

  if (pemLiteralIsUsable(AWS_IOT_ROOT_CA_PEM, "YOUR_AWS_IOT_ROOT_CA_PEM")) {
    g_tlsRootCa = AWS_IOT_ROOT_CA_PEM;
  } else if (loadRootCa(g_tlsRootCaOwned)) {
    g_tlsRootCa = g_tlsRootCaOwned.c_str();
  } else {
    Serial.println("[MQTT] Root CA missing");
    return false;
  }

  if (spiffsReadString(certPath, g_tlsCertOwned)) {
    g_tlsCert = g_tlsCertOwned.c_str();
  } else if (pemLiteralIsUsable(AWS_IOT_DEVICE_CERT_PEM, "YOUR_AWS_IOT_DEVICE_CERT_PEM")) {
    g_tlsCert = AWS_IOT_DEVICE_CERT_PEM;
  }

  if (spiffsReadString(keyPath, g_tlsKeyOwned)) {
    g_tlsKey = g_tlsKeyOwned.c_str();
  } else if (pemLiteralIsUsable(AWS_IOT_PRIVATE_KEY_PEM, "YOUR_AWS_IOT_PRIVATE_KEY_PEM")) {
    g_tlsKey = AWS_IOT_PRIVATE_KEY_PEM;
  }

  if (!g_tlsCert || !g_tlsKey) {
    Serial.println("[MQTT] Device cert/key missing");
    resetTlsMaterial();
    return false;
  }
  Serial.println("[MQTT] TLS mode=DEVICE");
  logPemInfo("rootCA", g_tlsRootCa);
  logPemInfo("deviceCert", g_tlsCert);
  logPemInfo("deviceKey", g_tlsKey);
  Serial.printf("[TLS] source root=%s cert=%s key=%s\n",
                g_tlsRootCaOwned.length() ? "spiffs" : "inline",
                g_tlsCertOwned.length() ? "spiffs" : "inline",
                g_tlsKeyOwned.length() ? "spiffs" : "inline");
  if (pemLooksRsaPrivateKey(g_tlsKey)) {
    Serial.println("[TLS][WARN] RSA private key detected; ESP32 heap pressure may break MQTT TLS. Prefer EC/P-256 key.");
  }
  applyTlsCommon();
  g_mqttNet.setCACert(g_tlsRootCa);
  g_mqttNet.setCertificate(g_tlsCert);
  g_mqttNet.setPrivateKey(g_tlsKey);
  return true;
}

static bool configureTlsFromClaim() {
  resetTlsMaterial();

  if (pemLiteralIsUsable(AWS_IOT_ROOT_CA_PEM, "YOUR_AWS_IOT_ROOT_CA_PEM")) {
    g_tlsRootCa = AWS_IOT_ROOT_CA_PEM;
  } else if (loadRootCa(g_tlsRootCaOwned)) {
    g_tlsRootCa = g_tlsRootCaOwned.c_str();
  } else {
    Serial.println("[MQTT] Root CA missing");
    return false;
  }

  if (spiffsReadString(kClaimCertPath, g_tlsCertOwned)) {
    g_tlsCert = g_tlsCertOwned.c_str();
  } else if (pemLiteralIsUsable(AWS_IOT_CLAIM_CERT_PEM, "YOUR_AWS_IOT_CLAIM_CERT_PEM")) {
    g_tlsCert = AWS_IOT_CLAIM_CERT_PEM;
  }

  if (spiffsReadString(kClaimKeyPath, g_tlsKeyOwned)) {
    g_tlsKey = g_tlsKeyOwned.c_str();
  } else if (pemLiteralIsUsable(AWS_IOT_CLAIM_PRIVATE_KEY_PEM, "YOUR_AWS_IOT_CLAIM_PRIVATE_KEY_PEM")) {
    g_tlsKey = AWS_IOT_CLAIM_PRIVATE_KEY_PEM;
  }

  if (!g_tlsCert || !g_tlsKey) {
    Serial.println("[MQTT] Claim cert/key missing");
    Serial.println("[PROV] using claim cert: no");
    resetTlsMaterial();
    return false;
  }
  Serial.println("[PROV] using claim cert: yes");
  Serial.println("[MQTT] TLS mode=CLAIM");
  Serial.printf("[MQTT] Claim TLS: ca=%u cert=%u key=%u\n",
                (unsigned)strlen(g_tlsRootCa),
                (unsigned)strlen(g_tlsCert),
                (unsigned)strlen(g_tlsKey));
  logPemInfo("rootCA", g_tlsRootCa);
  logPemInfo("claimCert", g_tlsCert);
  logPemInfo("claimKey", g_tlsKey);
  Serial.printf("[TLS] source root=%s cert=%s key=%s\n",
                g_tlsRootCaOwned.length() ? "spiffs" : "inline",
                g_tlsCertOwned.length() ? "spiffs" : "inline",
                g_tlsKeyOwned.length() ? "spiffs" : "inline");
  if (pemLooksRsaPrivateKey(g_tlsKey)) {
    Serial.println("[TLS][WARN] RSA private key detected; ESP32 heap pressure may break MQTT TLS. Prefer EC/P-256 key.");
  }
  applyTlsCommon();
  g_mqttNet.setCACert(g_tlsRootCa);
  g_mqttNet.setCertificate(g_tlsCert);
  g_mqttNet.setPrivateKey(g_tlsKey);
  return true;
}

static String buildShadowReportedJson() {
  JsonDocument report;
  fillStatusJsonMinDoc(report);
  JsonDocument doc;
  JsonObject state = doc["state"].to<JsonObject>();
  state["reported"] = report.as<JsonVariant>();
  String out;
  serializeJson(doc, out);
  return out;
}

static void cloudPublishState() {
  if (g_provisioningInProgress) return;
  if (!g_cloud.mqttConnected || !g_mqtt.connected()) return;
  const String stateTopic = cloudTopicState();
  const String state = buildStatusJsonMin();
  Serial.printf("[MQTT] publish -> %s len=%u\n",
                stateTopic.c_str(), (unsigned)state.length());
  bool okState = g_mqtt.publish(stateTopic.c_str(), state.c_str(), true);
  if (!okState) {
    Serial.printf("[MQTT] publish fail state=%d topic=%s\n",
                  g_mqtt.state(), stateTopic.c_str());
    return;
  }
  const String shadowTopic = cloudTopicShadow();
  const String shadow = buildShadowReportedJson();
  Serial.printf("[MQTT] publish -> %s len=%u\n",
                shadowTopic.c_str(), (unsigned)shadow.length());
  // Publish to the legacy custom shadow topic used by the backend ingest rule.
  // Do not publish to AWS reserved shadow topics from the device here.
  bool okShadow = g_mqtt.publish(shadowTopic.c_str(), shadow.c_str(), false);
  if (!okShadow) {
    Serial.printf("[MQTT] publish fail state=%d topic=%s\n",
                  g_mqtt.state(), shadowTopic.c_str());
  }
  g_cloudDirty = false;
  g_cloudLastPubMs = millis();
}

static bool provisionIfNeeded() {
  ScopedPerfLog perfScope("provision_if_needed");
  const String endpoint = effectiveCloudEndpoint();
  if (isPlaceholderCloudEndpoint(endpoint)) {
    Serial.println("[PROV] enter provisionIfNeeded() reason=no_endpoint");
    return false;
  }
  const bool forceProv = (FORCE_PROVISIONING != 0);
  if (forceProv) {
    Serial.println("[PROV] FORCE_PROVISIONING=1");
  }
  if (g_provisioned) {
    Serial.println("[PROV] enter provisionIfNeeded() reason=already_provisioned");
    return true;
  }
  if (g_provisioningInProgress) {
    Serial.println("[PROV] enter provisionIfNeeded() reason=provisioning_in_progress");
    return false;
  }
  const uint32_t nowMs = millis();
  if (nowMs - g_provLastAttemptMs < g_provBackoffMs) {
    return false;
  }
  g_provLastAttemptMs = nowMs;
  if (!g_cloud.enabled) {
    Serial.println("[PROV] enter provisionIfNeeded() reason=cloud_disabled");
    return false;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[PROV] enter provisionIfNeeded() reason=no_wifi");
    return false;
  }

  if (!ensureSpiffsReadyLogged("provision")) {
    Serial.println("[PROV] enter provisionIfNeeded() reason=spiffs_mount_failed");
    return false;
  }
  logCertFileStatus();
  const bool hasClaimCert = SPIFFS.exists(kClaimCertPath) && SPIFFS.exists(kClaimKeyPath);
  Serial.printf("[PROV] usingClaim=%d paths: %s %s %s\n",
                hasClaimCert ? 1 : 0,
                kClaimCertPath,
                kClaimKeyPath,
                kRootCaPath);
  Serial.println("[PROV] using claim cert: yes");
  if (!configureTlsFromClaim()) {
    Serial.println("[PROV] Claim TLS config failed -> using claim cert: no");
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }

  if (g_mqtt.connected()) {
    g_mqtt.disconnect();
  }
  if (g_mqttNet.connected()) {
    g_mqttNet.stop();
  }
  ensureMqttPacketBuffer(8192);

  g_provisioningInProgress = true;
  g_provCertOk = g_provCertFail = g_provThingOk = g_provThingFail = false;
  g_newCertPem = "";
  g_newPrivKey = "";
  g_newCertId = "";
  g_certOwnershipToken = "";
  g_provErr = "";

  g_mqtt.setCallback(onMqttMessage);
  Serial.println("[MQTT] callback registered");
  ensureMqttServerConfigured(endpoint);
  const String clientId = claimMqttClientId();
  Serial.printf("[PROV] connect clientId=%s\n", clientId.c_str());
  IPAddress ip;
  if (WiFi.hostByName(endpoint.c_str(), ip)) {
    Serial.printf("[PROV] DNS %s -> %s\n", endpoint.c_str(), ip.toString().c_str());
  } else {
    Serial.printf("[PROV] DNS failed for %s\n", endpoint.c_str());
  }

  // Do TLS handshake explicitly to get clearer errors before MQTT CONNECT.
  logPerfSnapshot("prov_before_tls_connect");
  uint32_t tlsStartUs = micros();
  bool tlsConnected = g_mqttNet.connect(endpoint.c_str(), AWS_IOT_PORT);
  if (!tlsConnected) {
    char errBuf[128] = {0};
    g_mqttNet.stop();
    delay(150);
    tlsStartUs = micros();
    tlsConnected = g_mqttNet.connect(endpoint.c_str(), AWS_IOT_PORT);
    if (!tlsConnected) {
      const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
      Serial.printf("[PROV] tls connect elapsed_us=%u\n", (uint32_t)(micros() - tlsStartUs));
      Serial.printf("[PROV] tls connect failed err=%d (%s)\n", tlsErr, errBuf);
      logPerfSnapshot("prov_after_tls_connect_fail");
      g_provisioningInProgress = false;
      g_mqttNet.stop();
      recoverWifiTransportForMqtt("prov_tls_connect_fail");
      g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
      return false;
    }
  }
  Serial.printf("[PROV] tls connect elapsed_us=%u\n", (uint32_t)(micros() - tlsStartUs));
  Serial.printf("[PROV] tls connected net.connected=%d\n", g_mqttNet.connected() ? 1 : 0);
  logPerfSnapshot("prov_after_tls_connect_ok");

  g_mqtt.setSocketTimeout(30);
  g_mqtt.setKeepAlive(30);

  logPerfSnapshot("prov_before_mqtt_connect");
  const uint32_t mqttStartUs = micros();
  if (!g_mqtt.connect(clientId.c_str())) {
    Serial.printf("[PROV] mqtt connect failed state=%d net.connected=%d\n",
                  g_mqtt.state(), g_mqttNet.connected() ? 1 : 0);
    Serial.printf("[PROV] mqtt connect elapsed_us=%u\n", (uint32_t)(micros() - mqttStartUs));
    char errBuf[128] = {0};
    const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
    if (tlsErr != 0) {
      Serial.printf("[PROV] tls lastError after mqtt=%d (%s)\n", tlsErr, errBuf);
    }
    logPerfSnapshot("prov_after_mqtt_connect_fail");
    g_provisioningInProgress = false;
    g_mqttNet.stop();
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }
  Serial.printf("[PROV] mqtt connect elapsed_us=%u\n", (uint32_t)(micros() - mqttStartUs));
  logPerfSnapshot("prov_after_mqtt_connect_ok");

  bool subAccepted = g_mqtt.subscribe(provCreateAcceptedTopic().c_str());
  Serial.printf("[PROV] subscribe ok: %s -> %d\n", provCreateAcceptedTopic().c_str(), subAccepted ? 1 : 0);
  bool subRejected = g_mqtt.subscribe(provCreateRejectedTopic().c_str());
  Serial.printf("[PROV] subscribe ok: %s -> %d\n", provCreateRejectedTopic().c_str(), subRejected ? 1 : 0);
  bool subProvisionAccept = g_mqtt.subscribe(provProvisionAcceptedTopic().c_str());
  Serial.printf("[PROV] subscribe ok: %s -> %d\n", provProvisionAcceptedTopic().c_str(), subProvisionAccept ? 1 : 0);
  bool subProvisionReject = g_mqtt.subscribe(provProvisionRejectedTopic().c_str());
  Serial.printf("[PROV] subscribe ok: %s -> %d\n", provProvisionRejectedTopic().c_str(), subProvisionReject ? 1 : 0);

  Serial.println("[PROV] subscribed to provisioning topics");
  String csrPem;
  if (!generateEcDeviceKeyAndCsr(g_newPrivKey, csrPem)) {
    Serial.println("[PROV] EC key/CSR generation failed");
    g_mqtt.disconnect();
    g_provisioningInProgress = false;
    g_mqttNet.stop();
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }
  JsonDocument createReq;
  createReq["certificateSigningRequest"] = csrPem;
  String createPayload;
  serializeJson(createReq, createPayload);
  const String createTopic = "$aws/certificates/create-from-csr/json";
  bool pubCertCreate = g_mqtt.publish(createTopic.c_str(), createPayload.c_str(), false);
  Serial.printf("[PROV] publish: %s csrLen=%u ok=%d\n",
                createTopic.c_str(),
                (unsigned)csrPem.length(),
                pubCertCreate ? 1 : 0);
  if (!pubCertCreate) {
    Serial.printf("[PROV] publish failed topic=%s state=%d\n",
                  createTopic.c_str(), g_mqtt.state());
    if (!g_mqtt.connected()) {
      Serial.println("[PROV] reconnecting claim MQTT after CSR publish failure");
      g_mqttNet.stop();
      delay(100);
      if (g_mqtt.connect(clientId.c_str())) {
        const bool subAcceptedRetry = g_mqtt.subscribe(provCreateAcceptedTopic().c_str());
        const bool subRejectedRetry = g_mqtt.subscribe(provCreateRejectedTopic().c_str());
        const bool subProvisionAcceptRetry = g_mqtt.subscribe(provProvisionAcceptedTopic().c_str());
        const bool subProvisionRejectRetry = g_mqtt.subscribe(provProvisionRejectedTopic().c_str());
        Serial.printf("[PROV] retry subscribe createAccepted=%d createRejected=%d provAccepted=%d provRejected=%d\n",
                      subAcceptedRetry ? 1 : 0,
                      subRejectedRetry ? 1 : 0,
                      subProvisionAcceptRetry ? 1 : 0,
                      subProvisionRejectRetry ? 1 : 0);
        pubCertCreate = g_mqtt.publish(createTopic.c_str(), createPayload.c_str(), false);
        Serial.printf("[PROV] retry publish: %s csrLen=%u ok=%d state=%d\n",
                      createTopic.c_str(),
                      (unsigned)csrPem.length(),
                      pubCertCreate ? 1 : 0,
                      g_mqtt.state());
      } else {
        Serial.printf("[PROV] retry connect failed state=%d\n", g_mqtt.state());
      }
    }
  }
  const uint32_t t0 = millis();
  while (!g_provCertOk && !g_provCertFail && (millis() - t0) < 15000) {
    g_mqtt.loop();
    delay(10);
  }
  if (!g_provCertOk) {
    char errBuf[128] = {0};
    const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
    Serial.printf("[PROV] cert create failed: %s state=%d tlsErr=%d (%s) time=%lu\n",
                  g_provErr.c_str(), g_mqtt.state(), tlsErr, errBuf, millis());
    g_mqtt.disconnect();
    g_provisioningInProgress = false;
    g_mqttNet.stop();
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }

  if (g_certOwnershipToken.isEmpty()) {
    Serial.println("[PROV] missing certificateOwnershipToken");
    g_mqtt.disconnect();
    g_provisioningInProgress = false;
    g_mqttNet.stop();
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }
  String payload =
      String("{\"certificateOwnershipToken\":\"") + g_certOwnershipToken +
      String("\",\"parameters\":{\"SerialNumber\":\"") + getDeviceId6() + "\"}}";
  bool pubProvision = g_mqtt.publish(provProvisionTopic().c_str(), payload.c_str(), false);
  Serial.printf("[PROV] publish: %s params={SerialNumber:%s} ok=%d\n",
                provProvisionTopic().c_str(), getDeviceId6().c_str(), pubProvision ? 1 : 0);
  if (!pubProvision) {
    Serial.printf("[PROV] publish failed topic=%s state=%d\n",
                  provProvisionTopic().c_str(), g_mqtt.state());
  }
  Serial.printf("[PROV] provision request SerialNumber=%s\n", getDeviceId6().c_str());
  const uint32_t t1 = millis();
  while (!g_provThingOk && !g_provThingFail && (millis() - t1) < 15000) {
    g_mqtt.loop();
    delay(10);
  }
  if (!g_provThingOk) {
    char errBuf[128] = {0};
    const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
    Serial.printf("[PROV] provision failed: %s state=%d tlsErr=%d (%s) time=%lu\n",
                  g_provErr.c_str(), g_mqtt.state(), tlsErr, errBuf, millis());
    g_mqtt.disconnect();
    g_provisioningInProgress = false;
    g_mqttNet.stop();
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }

  if (!spiffsWriteString(kDeviceCertPath, g_newCertPem) ||
      !spiffsWriteString(kDeviceKeyPath, g_newPrivKey)) {
    Serial.println("[PROV] write device cert/key failed");
    g_mqtt.disconnect();
    g_provisioningInProgress = false;
    g_mqttNet.stop();
    g_provBackoffMs = min(PROV_RETRY_MAX_MS, g_provBackoffMs * 2);
    return false;
  }

  prefs.begin("aac", false);
  prefs.putBool("provOk", true);
  prefs.end();

  g_provisioned = true;
  g_tlsConfigured = false;
  g_provBackoffMs = PROV_RETRY_MS;
  g_claimDeletePending = true;
  g_provisioningInProgress = false;
  g_deviceCertInvalidStreak = 0;
  g_nextDeviceCertValidationMs = millis() + DEVICE_CERT_VALIDATION_INTERVAL_MS;
  Serial.printf("[PROV] wrote device cert=%s key=%s; deleting claim cert/key; reconnecting with device cert\n",
                kDeviceCertPath, kDeviceKeyPath);
  Serial.println("[PROV] success -> reconnect with device cert");
  g_mqtt.disconnect();
  return true;
}

static void onMqttMessage(char* topic, uint8_t* payload, unsigned int length) {
#if ENABLE_RAW_MQTT_LOG
  Serial.println("[RAW MQTT] rx");
  Serial.print("[RAW MQTT] topic=");
  Serial.println(topic ? topic : "");
  Serial.print("[RAW MQTT] len=");
  Serial.println(length);
  String rawMsg;
  rawMsg.reserve(length + 1);
  for (unsigned int i = 0; i < length; ++i) {
    rawMsg += (char)payload[i];
  }
  Serial.print("[RAW MQTT] str=");
  Serial.println(rawMsg);
  Serial.print("[RAW MQTT] hex=");
  const unsigned int maxDump = (length < 64) ? length : 64;
  for (unsigned int i = 0; i < maxDump; ++i) {
    if (payload[i] < 16) Serial.print("0");
    Serial.print(payload[i], HEX);
    Serial.print(" ");
  }
  Serial.println();
#endif

  const String t = String(topic ? topic : "");
  if (g_provisioningInProgress) {
    if (length == 0 || length > 8192) return;
    Serial.printf("[PROV] rx topic=%s len=%u\n", t.c_str(), (unsigned)length);
    String body;
    body.reserve(length + 1);
    for (unsigned int i = 0; i < length; ++i) body += (char)payload[i];
    JsonDocument doc;
    if (deserializeJson(doc, body)) {
      Serial.println("[PROV] JSON parse failed");
      return;
    }
    if (t == provCreateAcceptedTopic()) {
      g_newCertPem = doc["certificatePem"] | "";
      g_newCertId = doc["certificateId"] | "";
      g_certOwnershipToken = doc["certificateOwnershipToken"] | "";
      Serial.printf("[PROV] create/accepted received: certId=%s tokenLen=%u\n",
                    g_newCertId.c_str(),
                    (unsigned)g_certOwnershipToken.length());
      g_provCertOk = !g_newCertPem.isEmpty() && !g_newPrivKey.isEmpty() &&
                     !g_certOwnershipToken.isEmpty();
      return;
    }
    if (t == provCreateRejectedTopic()) {
      g_provCertFail = true;
      g_provErr = doc["errorMessage"] | "create_rejected";
      const int previewLen = min(200, (int)body.length());
      String preview = body.substring(0, previewLen);
      if (body.length() > previewLen) preview += "...";
      Serial.printf("[PROV] create/rejected received: err=%s payload=%s\n",
                    g_provErr.c_str(), preview.c_str());
      return;
    }
    if (t == provProvisionAcceptedTopic()) {
      g_provThingOk = true;
      const String thingName = doc["thingName"] | "";
      Serial.printf("[PROV] provision/accepted received: thingName=%s certId=%s\n",
                    thingName.c_str(),
                    g_newCertId.c_str());
      return;
    }
    if (t == provProvisionRejectedTopic()) {
      g_provThingFail = true;
      g_provErr = doc["errorMessage"] | "provision_rejected";
      const int previewLen = min(200, (int)body.length());
      String preview = body.substring(0, previewLen);
      if (body.length() > previewLen) preview += "...";
      Serial.printf("[PROV] provision/rejected received: err=%s payload=%s\n",
                    g_provErr.c_str(), preview.c_str());
      return;
    }
  }
  const bool isCmdTopic = t.endsWith("/cmd");
  const bool isDeltaTopic = isShadowDeltaTopic(t);
  const bool isJobsNotifyNext = isJobsNotifyNextTopic(t);
  const bool isJobsGetAccepted = isJobsGetNextAcceptedTopic(t);
  if (isJobsNotifyNext) {
    const String thingName = extractThingNameFromJobsTopic(t);
    if (!thingName.length()) {
      Serial.println("[JOBS] notify-next: invalid topic");
      return;
    }
    const String getTopic = jobsTopicGetNextForThing(thingName);
    const bool ok = g_mqtt.publish(getTopic.c_str(), "{}", false);
    Serial.printf("[JOBS] request $next thing=%s ok=%d topic=%s\n",
                  thingName.c_str(), ok ? 1 : 0, getTopic.c_str());
    return;
  }
  if (isJobsGetAccepted) {
    if (length == 0 || length > 8192) {
      Serial.printf("[JOBS] drop payload size=%u\n", (unsigned)length);
      return;
    }
    String body;
    body.reserve(length + 1);
    for (unsigned int i = 0; i < length; ++i) body += (char)payload[i];
    JsonDocument doc;
    if (deserializeJson(doc, body)) {
      Serial.println("[JOBS] JSON parse failed");
      return;
    }
    JsonObjectConst exec = doc["execution"].as<JsonObjectConst>();
    if (exec.isNull()) {
      Serial.println("[JOBS] no pending execution");
      return;
    }
    const String jobId = String(exec["jobId"] | "");
    if (!jobId.length()) {
      Serial.println("[JOBS] missing jobId");
      return;
    }
    JsonObjectConst jobDoc = exec["jobDocument"].as<JsonObjectConst>();
    const String op = String(jobDoc["operation"] | "");
    JsonObjectConst fw = jobDoc["firmware"].as<JsonObjectConst>();
    const String url = String(fw["url"] | "");
    const String sha = toLowerAscii(String(fw["sha256"] | ""));
    const String version = String(fw["version"] | "");
    const String minVersion = String(fw["minVersion"] | fw["min_version"] | "");
    JsonVariantConst requiresApprovalRaw = fw["requiresUserApproval"];
    if (requiresApprovalRaw.isNull()) {
      requiresApprovalRaw = jobDoc["requiresUserApproval"];
    }
    bool requiresUserApproval = true;
    if (requiresApprovalRaw.is<bool>()) {
      requiresUserApproval = requiresApprovalRaw.as<bool>();
    } else if (requiresApprovalRaw.is<int>()) {
      requiresUserApproval = requiresApprovalRaw.as<int>() != 0;
    } else if (requiresApprovalRaw.is<const char*>()) {
      requiresUserApproval =
          parseBoolLoose(String(requiresApprovalRaw.as<const char*>()), true);
    }
    JsonObjectConst target = fw["target"].as<JsonObjectConst>();
    if (target.isNull()) target = jobDoc["target"].as<JsonObjectConst>();
    const String targetProduct = toLowerAscii(String(target["product"] | target["deviceProduct"] | ""));
    const String targetHwRev = toLowerAscii(String(target["hwRev"] | target["hardwareRev"] | ""));
    const String targetBoardRev = toLowerAscii(String(target["boardRev"] | target["board"] | ""));
    const String targetChannel = toLowerAscii(String(target["fwChannel"] | target["channel"] | ""));
    const String thingName = extractThingNameFromJobsTopic(t);
    if (op == "OTA" && url.length() && sha.length() && version.length()) {
      const String localProduct = toLowerAscii(String(DEVICE_PRODUCT));
      const String localHwRev = toLowerAscii(String(DEVICE_HW_REV));
      const String localBoardRev = toLowerAscii(String(DEVICE_BOARD_REV));
      const String localChannel = toLowerAscii(String(DEVICE_FW_CHANNEL));
      if (targetProduct.length() && targetProduct != localProduct) {
        (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "target_product_mismatch",
                                        targetProduct, localProduct);
        Serial.printf("[JOBS] ota REJECT target_product_mismatch want=%s have=%s\n",
                      targetProduct.c_str(), localProduct.c_str());
        return;
      }
      if (targetHwRev.length() && targetHwRev != localHwRev) {
        (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "target_hw_mismatch",
                                        targetHwRev, localHwRev);
        Serial.printf("[JOBS] ota REJECT target_hw_mismatch want=%s have=%s\n",
                      targetHwRev.c_str(), localHwRev.c_str());
        return;
      }
      if (targetBoardRev.length() && targetBoardRev != localBoardRev) {
        (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "target_board_mismatch",
                                        targetBoardRev, localBoardRev);
        Serial.printf("[JOBS] ota REJECT target_board_mismatch want=%s have=%s\n",
                      targetBoardRev.c_str(), localBoardRev.c_str());
        return;
      }
      if (targetChannel.length() && targetChannel != localChannel) {
        (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "target_channel_mismatch",
                                        targetChannel, localChannel);
        Serial.printf("[JOBS] ota REJECT target_channel_mismatch want=%s have=%s\n",
                      targetChannel.c_str(), localChannel.c_str());
        return;
      }
      if (minVersion.length() && compareSemver(String(FW_VERSION), minVersion) < 0) {
        (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "min_version_not_met",
                                        minVersion, String(FW_VERSION));
        Serial.printf("[JOBS] ota REJECT min_version_not_met min=%s fw=%s\n",
                      minVersion.c_str(), FW_VERSION);
        return;
      }
      const bool semverComparable =
          isSemverParseable(String(FW_VERSION)) && isSemverParseable(version);
      if (semverComparable && compareSemver(String(FW_VERSION), version) >= 0) {
        (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "version_not_newer",
                                        version, String(FW_VERSION));
        Serial.printf("[JOBS] ota REJECT version_not_newer target=%s fw=%s\n",
                      version.c_str(), FW_VERSION);
        return;
      }
      if (requiresUserApproval) {
        setPendingOtaJob(thingName, jobId, url, sha, version);
        setLastOtaStatus("waiting_approval", "waiting_user_approval", jobId, version);
        (void)publishJobExecutionStatus(thingName, jobId, "IN_PROGRESS", "waiting_user_approval",
                                        version, String(FW_VERSION));
        Serial.printf("[JOBS] ota pending user approval jobId=%s version=%s\n",
                      jobId.c_str(), version.c_str());
        g_cloudDirty = true;
        return;
      }
      setLastOtaStatus("starting", "ota_started", jobId, version);
      (void)publishJobExecutionStatus(thingName, jobId, "IN_PROGRESS", "ota_started",
                                      version, url.substring(0, 96));
      String err;
      String actualSha;
      size_t bytesWritten = 0;
      const bool okOta = performOtaFromUrl(url, sha, err, actualSha, bytesWritten);
      if (!okOta) {
        setLastOtaStatus("failed", err.c_str(), jobId, version);
        (void)publishJobExecutionStatus(thingName, jobId, "FAILED", err.c_str(),
                                        actualSha.substring(0, 64), String((unsigned)bytesWritten));
        Serial.printf("[JOBS] ota FAILED jobId=%s reason=%s bytes=%u\n",
                      jobId.c_str(), err.c_str(), (unsigned)bytesWritten);
        return;
      }
      setLastOtaStatus("succeeded", "ota_applied", jobId, version);
      (void)publishJobExecutionStatus(thingName, jobId, "SUCCEEDED", "ota_applied",
                                      version, actualSha.substring(0, 64));
      Serial.printf("[JOBS] ota SUCCEEDED jobId=%s version=%s bytes=%u\n",
                    jobId.c_str(), version.c_str(), (unsigned)bytesWritten);
      delay(500);
      ESP.restart();
    } else {
      (void)publishJobExecutionStatus(thingName, jobId, "REJECTED", "unsupported_job_document");
      Serial.printf("[JOBS] reject jobId=%s\n", jobId.c_str());
    }
    return;
  }
  if (!isCmdTopic && !isDeltaTopic) {
    return;
  }
  if (length == 0 || length > 4096) {
    Serial.printf("[MQTT] drop payload size=%u\n", (unsigned)length);
    return;
  }
  String body;
  body.reserve(length + 1);
  for (unsigned int i = 0; i < length; ++i) {
    body += (char)payload[i];
  }
  JsonDocument doc;
  if (deserializeJson(doc, body)) {
    Serial.println("[MQTT] JSON parse failed");
    return;
  }
  if (body.indexOf("\"rgb\"") >= 0 || body.indexOf("\"rgbOn\"") >= 0 ||
      body.indexOf("\"rgbBrightness\"") >= 0 || body.indexOf("\"r\"") >= 0 ||
      body.indexOf("\"g\"") >= 0 || body.indexOf("\"b\"") >= 0) {
    const int previewLen = min(320, (int)body.length());
    String preview = body.substring(0, previewLen);
    if (body.length() > previewLen) preview += "...";
    Serial.printf("[CMD][MQTT] payload=%s\n", preview.c_str());
  }
  if (isDeltaTopic) {
    JsonVariantConst state = doc["state"];
    if (!state.is<JsonObjectConst>()) {
      Serial.println("[SHADOW] delta payload missing state object");
      return;
    }
    JsonDocument deltaDoc;
    deltaDoc.set(state);
    (void)handleIncomingControlJson(deltaDoc, CmdSource::MQTT, "SHADOW_DELTA", false, nullptr);
    return;
  }
  (void)handleIncomingControlJson(doc, CmdSource::MQTT, "MQTT", false, nullptr);
}

static void cloudInit() {
  const String endpoint = effectiveCloudEndpoint();
  g_cloud.enabled = (ENABLE_CLOUD != 0) && g_cloudUserEnabled;
  g_cloud.linked = false;
  g_cloud.email = "";
  g_cloud.iotEndpoint = endpoint;
  g_cloud.streamActive = false;
  g_cloud.mqttConnected = false;
  g_cloud.mqttPort = AWS_IOT_PORT;
  setCloudState(
    g_cloud.enabled ? CloudState::SETUP_REQUIRED : CloudState::OFF,
    "cloudInit");
  ensureMqttServerConfigured(endpoint);
  g_mqtt.setCallback(onMqttMessage);
  Serial.println("[MQTT] callback registered");
  ensureMqttPacketBuffer(4096);
  g_mqtt.setSocketTimeout(10);
  g_mqtt.setKeepAlive(45);
  if (ensureSpiffsReady()) {
    logCertFileStatus();
  } else {
    Serial.println("[TLS] SPIFFS mount failed (cloudInit)");
  }
}

#if ENABLE_IR_RX_DEBUG
static inline uint16_t irPendingEdgeCount();
#endif

static inline void cloudLoop(uint32_t) {
  static bool s_mqttCmdSubscribed = false;
  static bool s_mqttShadowSubscribed = false;
  static bool s_mqttJobsSubscribed = false;
  static bool s_mqttWasConnected = false;
  const String endpoint = effectiveCloudEndpoint();
  ensureMqttServerConfigured(endpoint);
  g_cloud.iotEndpoint = endpoint;
  g_cloud.enabled = (ENABLE_CLOUD != 0) && g_cloudUserEnabled;
  if (!g_cloud.enabled) {
    if (g_mqtt.connected()) g_mqtt.disconnect();
    g_cloud.mqttConnected = false;
    g_cloud.linked = false;
    s_mqttCmdSubscribed = false;
    s_mqttShadowSubscribed = false;
    s_mqttJobsSubscribed = false;
    s_mqttWasConnected = false;
    g_mqttBackoffMs = MQTT_RECONNECT_MS;
    g_mqttTlsFailStreak = 0;
    g_mqttConnectFailStreak = 0;
    setCloudState(CloudState::OFF, "user disabled");
    return;
  }
  if (isPlaceholderCloudEndpoint(endpoint)) {
    setCloudState(CloudState::DEGRADED, "no endpoint");
    return;
  }

  if (WiFi.status() != WL_CONNECTED) {
    g_cloud.mqttConnected = false;
    setCloudState(CloudState::DEGRADED, "no wifi");
    if (g_mqtt.connected()) g_mqtt.disconnect();
    if (s_mqttWasConnected) {
      Serial.printf("[MQTT] disconnected state=%d\n", g_mqtt.state());
      char errBuf[128] = {0};
      const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
      if (tlsErr != 0) {
        Serial.printf("[MQTT] tls lastError=%d (%s)\n", tlsErr, errBuf);
      }
      s_mqttWasConnected = false;
    }
    s_mqttCmdSubscribed = false;
    s_mqttShadowSubscribed = false;
    s_mqttJobsSubscribed = false;
    g_mqttBackoffMs = MQTT_RECONNECT_MS;
    g_mqttTlsFailStreak = 0;
    g_mqttConnectFailStreak = 0;
    return;
  }

  const bool forceProv = (FORCE_PROVISIONING != 0);
  const bool hasInlineDeviceCerts = inlineDeviceCertsValid();
  if (forceProv) {
    g_provisioned = false;
    g_tlsConfigured = false;
    g_deviceCertInvalidStreak = 0;
    g_nextDeviceCertValidationMs = 0;
  } else if (g_provisioned) {
    if (!ensureSpiffsReadyLogged("cloudLoop:validate")) {
      g_cloud.mqttState = "FS_FAIL";
      g_cloud.mqttStateCode = 11;
      setCloudState(CloudState::DEGRADED, "fs fail");
      return;
    }
    const uint32_t nowMs = millis();
    if ((int32_t)(nowMs - g_nextDeviceCertValidationMs) >= 0) {
      g_nextDeviceCertValidationMs = nowMs + DEVICE_CERT_VALIDATION_INTERVAL_MS;
      const bool certsOk = hasInlineDeviceCerts ? true : deviceCertsEcReady();
      if (certsOk) {
        g_deviceCertInvalidStreak = 0;
      } else {
        if (g_deviceCertInvalidStreak < 255) {
          g_deviceCertInvalidStreak++;
        }
        Serial.printf("[PROV] device cert/key validation failed (%u/%u)\n",
                      (unsigned)g_deviceCertInvalidStreak,
                      (unsigned)DEVICE_CERT_INVALID_STREAK_MAX);
        if (g_deviceCertInvalidStreak >= DEVICE_CERT_INVALID_STREAK_MAX) {
          Serial.println("[PROV] device cert/key invalid, missing, or non-EC -> re-provision");
          g_provisioned = false;
          g_tlsConfigured = false;
          g_deviceCertInvalidStreak = 0;
          g_nextDeviceCertValidationMs = 0;
          spiffsRemoveIfExists(kDeviceCertPath);
          spiffsRemoveIfExists(kDeviceKeyPath);
        }
      }
    }
  }

  if (!g_provisioned) {
    if (ensureSpiffsReady() && deviceCertsEcReady()) {
      Serial.println("[PROV] found valid EC device cert/key on disk -> skip claim provisioning");
      g_provisioned = true;
      g_tlsConfigured = false;
      g_provBackoffMs = PROV_RETRY_MS;
      g_deviceCertInvalidStreak = 0;
      g_nextDeviceCertValidationMs = millis() + DEVICE_CERT_VALIDATION_INTERVAL_MS;
    } else if (ensureSpiffsReady() && deviceCertsValid()) {
      Serial.println("[PROV] found legacy non-EC device key -> forcing re-provision");
      spiffsRemoveIfExists(kDeviceCertPath);
      spiffsRemoveIfExists(kDeviceKeyPath);
      g_provisioned = false;
      g_tlsConfigured = false;
      g_provBackoffMs = PROV_RETRY_MS;
      g_deviceCertInvalidStreak = 0;
      g_nextDeviceCertValidationMs = 0;
    } else if (hasInlineDeviceCerts) {
      Serial.println("[PROV] using inline device cert/key -> skip claim provisioning");
      g_provisioned = true;
      g_tlsConfigured = false;
      g_provBackoffMs = PROV_RETRY_MS;
      g_deviceCertInvalidStreak = 0;
      g_nextDeviceCertValidationMs = millis() + DEVICE_CERT_VALIDATION_INTERVAL_MS;
    }
  }

  if (!g_provisioned) {
    provisionIfNeeded();
    setCloudState(CloudState::PROVISIONING, "needs provisioning");
    return;
  }

  if (!g_tlsConfigured) {
    setCloudState(CloudState::SETUP_REQUIRED, "tls config");
    const uint32_t nowMs = millis();
    if (nowMs - g_tlsCfgLastAttemptMs < g_tlsCfgBackoffMs) {
      return;
    }
    g_tlsCfgLastAttemptMs = nowMs;
    if (!ensureSpiffsReadyLogged("cloudLoop:tls_config")) {
      setCloudState(CloudState::DEGRADED, "fs fail");
      g_tlsCfgBackoffMs = min(TLSCFG_RETRY_MAX_MS, g_tlsCfgBackoffMs * 2);
      return;
    }
    String rootCa;
    if (!loadRootCa(rootCa)) {
      setCloudState(CloudState::DEGRADED, "no root ca");
      g_tlsCfgBackoffMs = min(TLSCFG_RETRY_MAX_MS, g_tlsCfgBackoffMs * 2);
      return;
    }
    if (!configureTlsFromFiles(kDeviceCertPath, kDeviceKeyPath)) {
      setCloudState(CloudState::DEGRADED, "tls fail");
      g_tlsCfgBackoffMs = min(TLSCFG_RETRY_MAX_MS, g_tlsCfgBackoffMs * 2);
      return;
    }
    g_tlsCfgBackoffMs = TLSCFG_RETRY_MS;
    g_tlsConfigured = true;
    g_mqtt.setSocketTimeout(10);
    g_mqtt.setKeepAlive(45);
    g_cloud.linked = true;
    setCloudState(CloudState::LINKED, "tls ready");
  }

  if (!g_mqtt.connected()) {
    if (s_mqttWasConnected) {
      Serial.printf("[MQTT] disconnected state=%d\n", g_mqtt.state());
      char errBuf[128] = {0};
      const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
      if (tlsErr != 0) {
        Serial.printf("[MQTT] tls lastError=%d (%s)\n", tlsErr, errBuf);
      }
      s_mqttWasConnected = false;
    }
    s_mqttCmdSubscribed = false;
    s_mqttShadowSubscribed = false;
    s_mqttJobsSubscribed = false;
#if ENABLE_IR_RX_DEBUG
    // If IR edges are queued, prioritize draining them before a potentially
    // blocking TLS/MQTT connect attempt.
    if (irPendingEdgeCount() >= 24U) {
      return;
    }
#endif
    const uint32_t nowMs = millis();
    if (nowMs - g_mqttLastAttemptMs < g_mqttBackoffMs) {
      return;
    }
    g_mqttLastAttemptMs = nowMs;
    if (g_mqtt.connected()) {
      g_mqtt.disconnect();
      delay(50);
    }
    if (g_mqttNet.connected()) {
      g_mqttNet.stop();
      delay(50);
    }
    const String clientId = cloudMqttClientId();
    Serial.printf("[MQTT] connect clientId=%s\n", clientId.c_str());
    logPerfSnapshot("mqtt_before_connect");

    // 1) Time gate (AWS TLS için kritik)
    if (!isTimeValid()) {
      g_cloud.mqttConnected = false;
      g_cloud.mqttState = "NO_TIME";
      g_cloud.mqttStateCode = 13;
      setCloudState(CloudState::DEGRADED, "no time");
      Serial.printf("[MQTT] NO_TIME epoch=%ld\n", (long)time(nullptr));
      kickNtpSyncIfNeeded("mqtt-no-time", false);
      g_mqttBackoffMs = min(MQTT_RECONNECT_MAX_MS, g_mqttBackoffMs * 2);
      g_mqttConnectFailStreak = min<uint8_t>(255, (uint8_t)(g_mqttConnectFailStreak + 1));
      return;
    }

    // 2) Explicit TLS preflight. Provisioning path already does this and
    // produces clearer failure modes than letting PubSubClient open the socket.
    const uint32_t tlsStartUs = micros();
    if (!g_mqttNet.connect(endpoint.c_str(), AWS_IOT_PORT)) {
      logPerfSnapshot("mqtt_after_tls_preflight_fail");
      g_cloud.mqttConnected = false;
      g_cloud.mqttState = "CONNECT_FAIL";
      g_cloud.mqttStateCode = -2;
      setCloudState(CloudState::DEGRADED, "mqtt connect fail");
      g_mqttBackoffMs = min(MQTT_RECONNECT_MAX_MS, g_mqttBackoffMs * 2);
      g_mqttTlsFailStreak = min<uint8_t>(255, (uint8_t)(g_mqttTlsFailStreak + 1));
      g_mqttConnectFailStreak = min<uint8_t>(255, (uint8_t)(g_mqttConnectFailStreak + 1));
      char errBuf[128] = {0};
      const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
      logPerfSnapshot("mqtt_tls_preflight_fail_detail");
      Serial.printf("[MQTT] tls preflight elapsed_us=%u\n",
                    (uint32_t)(micros() - tlsStartUs));
      if (errBuf[0] != '\0') {
        Serial.printf("[MQTT] tls preflight failed err=%d (%s)\n", tlsErr, errBuf);
      } else {
        Serial.printf("[MQTT] tls preflight failed err=%d\n", tlsErr);
      }
      if (g_mqttTlsFailStreak >= MQTT_TLS_RELOAD_THRESHOLD) {
        recoverMqttTransport("tls_preflight_fail", true);
      }
      if (g_mqttTlsFailStreak >= MQTT_TLS_WIFI_RECOVER_THRESHOLD) {
        recoverWifiTransportForMqtt("tls_preflight_fail");
      }
      if (g_mqttTlsFailStreak >= MQTT_TLS_RESTART_THRESHOLD &&
          (uint32_t)(nowMs - g_mqttLastRestartMs) > MQTT_RESTART_COOLDOWN_MS) {
        g_mqttLastRestartMs = nowMs;
        Serial.println("[MQTT][RECOVERY] restart after repeated TLS preflight failures");
        delay(200);
        ESP.restart();
      }
      g_mqttNet.stop();
      return;
    }
    Serial.printf("[MQTT] tls preflight elapsed_us=%u\n",
                  (uint32_t)(micros() - tlsStartUs));

    // 3) MQTT CONNECT + net/state log
    const uint32_t mqttConnectStartUs = micros();
    bool ok = g_mqtt.connect(clientId.c_str());
    Serial.printf("[MQTT] connect elapsed_us=%u\n", (uint32_t)(micros() - mqttConnectStartUs));
    Serial.printf("[MQTT] connect ok=%d state=%d net.connected=%d\n",
                  ok ? 1 : 0, g_mqtt.state(), g_mqttNet.connected() ? 1 : 0);

    if (ok) {
      logPerfSnapshot("mqtt_after_connect_ok");
      g_mqttTlsFailStreak = 0;
      g_mqttConnectFailStreak = 0;
      g_cloud.mqttConnected = true;
#if ENABLE_WAQI
      g_mqttConnectedAtMs = millis();
#endif
      g_cloud.mqttState = "CONNECTED";
      g_cloud.mqttStateCode = 0;
      setCloudState(CloudState::CONNECTED, "mqtt connected");
      if (!s_mqttWasConnected) {
        Serial.println("[MQTT] connected (stable)");
        s_mqttWasConnected = true;
      }
      if (!s_mqttCmdSubscribed) {
        bool subOk = g_mqtt.subscribe(cloudTopicCmd().c_str());
        Serial.printf("[MQTT] subscribe cmd ok=%d topic=%s\n",
                      subOk ? 1 : 0, cloudTopicCmd().c_str());
        s_mqttCmdSubscribed = subOk;
      }
      if (!s_mqttShadowSubscribed) {
        const String deltaPrimary = cloudTopicShadowDeltaForThing(cloudThingNamePrimary());
        const String deltaLegacy = cloudTopicShadowDeltaForThing(cloudThingNameLegacy());
        bool subPrimary = g_mqtt.subscribe(deltaPrimary.c_str());
        bool subLegacy = true;
        if (deltaLegacy != deltaPrimary) {
          subLegacy = g_mqtt.subscribe(deltaLegacy.c_str());
        }
        Serial.printf("[MQTT] subscribe shadow delta primary ok=%d topic=%s\n",
                      subPrimary ? 1 : 0, deltaPrimary.c_str());
        if (deltaLegacy != deltaPrimary) {
          Serial.printf("[MQTT] subscribe shadow delta legacy ok=%d topic=%s\n",
                        subLegacy ? 1 : 0, deltaLegacy.c_str());
        }
        s_mqttShadowSubscribed = subPrimary || subLegacy;
      }
      if (!s_mqttJobsSubscribed) {
        const String things[2] = { cloudThingNamePrimary(), cloudThingNameLegacy() };
        bool anyOk = false;
        for (int i = 0; i < 2; ++i) {
          if (i == 1 && things[1] == things[0]) continue;
          const String notifyTopic = jobsTopicNotifyNextForThing(things[i]);
          const String getAcceptedTopic = jobsTopicGetNextAcceptedForThing(things[i]);
          const bool okNotify = g_mqtt.subscribe(notifyTopic.c_str());
          const bool okGetAccepted = g_mqtt.subscribe(getAcceptedTopic.c_str());
          Serial.printf("[JOBS] subscribe notify ok=%d topic=%s\n",
                        okNotify ? 1 : 0, notifyTopic.c_str());
          Serial.printf("[JOBS] subscribe get/accepted ok=%d topic=%s\n",
                        okGetAccepted ? 1 : 0, getAcceptedTopic.c_str());
          const String getTopic = jobsTopicGetNextForThing(things[i]);
          const bool okGet = g_mqtt.publish(getTopic.c_str(), "{}", false);
          Serial.printf("[JOBS] request $next ok=%d topic=%s\n",
                        okGet ? 1 : 0, getTopic.c_str());
          anyOk = anyOk || okNotify || okGetAccepted;
        }
        s_mqttJobsSubscribed = anyOk;
      }
      if (g_claimDeletePending) {
        Serial.println("[PROV] deleting claim cert/key after device connect");
        spiffsRemoveIfExists(kClaimCertPath);
        spiffsRemoveIfExists(kClaimKeyPath);
        g_claimDeletePending = false;
      }
      g_mqtt.loop();
      g_mqttBackoffMs = MQTT_RECONNECT_MS;
    } else {
      logPerfSnapshot("mqtt_after_connect_fail");
      g_mqttConnectFailStreak = min<uint8_t>(255, (uint8_t)(g_mqttConnectFailStreak + 1));
      g_cloud.mqttConnected = false;
#if ENABLE_WAQI
      g_mqttConnectedAtMs = 0;
#endif
      g_cloud.mqttState = "CONNECT_FAIL";
      g_cloud.mqttStateCode = g_mqtt.state();
      setCloudState(CloudState::DEGRADED, "mqtt connect fail");
      g_mqttBackoffMs = min(MQTT_RECONNECT_MAX_MS, g_mqttBackoffMs * 2);

      char errBuf[128] = {0};
      const int tlsErr = g_mqttNet.lastError(errBuf, sizeof(errBuf));
      if (errBuf[0] != '\0') {
        Serial.printf("[MQTT] tls lastError=%d (%s)\n", tlsErr, errBuf);
      } else {
        Serial.printf("[MQTT] tls lastError=%d\n", tlsErr);
      }
      if (g_mqttConnectFailStreak >= MQTT_CONNECT_RELOAD_THRESHOLD) {
        recoverMqttTransport("mqtt_connect_fail", true);
      }
      g_mqttNet.stop();
    }
    return;
  }

  g_cloud.mqttConnected = true;
#if ENABLE_WAQI
  if (g_mqttConnectedAtMs == 0) g_mqttConnectedAtMs = millis();
#endif
  g_cloud.mqttState = "CONNECTED";
  g_cloud.mqttStateCode = 0;
  setCloudState(CloudState::CONNECTED, "mqtt loop");
  if (!s_mqttWasConnected) {
    Serial.println("[MQTT] connected (stable)");
    s_mqttWasConnected = true;
  }
  if (!s_mqttCmdSubscribed) {
    bool subOk = g_mqtt.subscribe(cloudTopicCmd().c_str());
    Serial.printf("[MQTT] subscribe cmd ok=%d topic=%s\n",
                  subOk ? 1 : 0, cloudTopicCmd().c_str());
    s_mqttCmdSubscribed = subOk;
  }
  if (!s_mqttShadowSubscribed) {
    const String deltaPrimary = cloudTopicShadowDeltaForThing(cloudThingNamePrimary());
    const String deltaLegacy = cloudTopicShadowDeltaForThing(cloudThingNameLegacy());
    bool subPrimary = g_mqtt.subscribe(deltaPrimary.c_str());
    bool subLegacy = true;
    if (deltaLegacy != deltaPrimary) {
      subLegacy = g_mqtt.subscribe(deltaLegacy.c_str());
    }
    Serial.printf("[MQTT] subscribe shadow delta primary ok=%d topic=%s\n",
                  subPrimary ? 1 : 0, deltaPrimary.c_str());
    if (deltaLegacy != deltaPrimary) {
      Serial.printf("[MQTT] subscribe shadow delta legacy ok=%d topic=%s\n",
                    subLegacy ? 1 : 0, deltaLegacy.c_str());
    }
    s_mqttShadowSubscribed = subPrimary || subLegacy;
  }
  if (!s_mqttJobsSubscribed) {
    const String things[2] = { cloudThingNamePrimary(), cloudThingNameLegacy() };
    bool anyOk = false;
    for (int i = 0; i < 2; ++i) {
      if (i == 1 && things[1] == things[0]) continue;
      const String notifyTopic = jobsTopicNotifyNextForThing(things[i]);
      const String getAcceptedTopic = jobsTopicGetNextAcceptedForThing(things[i]);
      const bool okNotify = g_mqtt.subscribe(notifyTopic.c_str());
      const bool okGetAccepted = g_mqtt.subscribe(getAcceptedTopic.c_str());
      Serial.printf("[JOBS] subscribe notify ok=%d topic=%s\n",
                    okNotify ? 1 : 0, notifyTopic.c_str());
      Serial.printf("[JOBS] subscribe get/accepted ok=%d topic=%s\n",
                    okGetAccepted ? 1 : 0, getAcceptedTopic.c_str());
      const String getTopic = jobsTopicGetNextForThing(things[i]);
      const bool okGet = g_mqtt.publish(getTopic.c_str(), "{}", false);
      Serial.printf("[JOBS] request $next ok=%d topic=%s\n",
                    okGet ? 1 : 0, getTopic.c_str());
      anyOk = anyOk || okNotify || okGetAccepted;
    }
    s_mqttJobsSubscribed = anyOk;
  }
  g_mqtt.loop();
  const uint32_t nowMs = millis();
  if (g_cloudDirty || (nowMs - g_cloudLastPubMs) >= CLOUD_PUB_INTERVAL_MS) {
    cloudPublishState();
  }
}

#if ENABLE_WAQI
/* =================== WAQI (World Air Quality Index) =================== */
// ESP32'nin dış ortam (şehir) hava kalitesini çekmesi için WAQI entegrasyonu.
// SECURITY: WAQI_API_TOKEN config.h içinde tanımlanmalı (gitignore'da olmalı).
// Eğer config.h'de tanımlı değilse, bu default değer kullanılır (güvenlik riski!).
#ifndef WAQI_API_TOKEN
// SECURITY: Do not ship a default token in firmware.
// Define WAQI_API_TOKEN in config.h (gitignored) or via build flags.
#define WAQI_API_TOKEN ""
#warning "WAQI_API_TOKEN is not set; WAQI fetching will be disabled."
#endif

// WAQI HTTPS root CA must be provided via config.h.
// If empty, WAQI fetch will be skipped for security.
#ifndef WAQI_ROOT_CA_PEM
static const char WAQI_ROOT_CA_PEM_DEFAULT[] PROGMEM = R"EOF(-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)EOF";
#define WAQI_ROOT_CA_PEM WAQI_ROOT_CA_PEM_DEFAULT
#endif

// Varsayılan koordinatlar (örn. Ankara). Mobil uygulama /api/cmd üzerinden
// "waqi" nesnesi ile bu değerleri güncelleyebilir.
#ifndef WAQI_LAT_DEFAULT
#define WAQI_LAT_DEFAULT 39.93
#endif
#ifndef WAQI_LON_DEFAULT
#define WAQI_LON_DEFAULT 32.86
#endif

#endif // ENABLE_WAQI
// =================== Device identity (canonical) ===================
// Canonical deviceId used across APIs: "<id6>" (digits only).
static String g_id6; // e.g. "926499"

static String shortChipId();

static inline String normalizeDeviceId6(const String& any) {
  String v = any;
  v.trim();
  if (v.length() != 6) return String();
  for (size_t i = 0; i < v.length(); ++i) {
    if (!isDigit(v[i])) return String();
  }
  return v;
}

static inline void setDeviceIdentity(const String& id6) {
  String normalized = normalizeDeviceId6(id6);
  if (normalized.isEmpty()) {
    normalized = normalizeDeviceId6(shortChipId());
  }
  g_id6 = normalized;
}

static inline const String& getDeviceId6() {
  if (g_id6.isEmpty()) setDeviceIdentity(shortChipId());
  return g_id6;
}

static inline String canonicalDeviceId() {
  return normalizeDeviceId6(getDeviceId6());
}

static String _titleCaseWords(const String& raw) {
  String out;
  bool nextUpper = true;
  for (size_t i = 0; i < raw.length(); ++i) {
    char c = raw[i];
    if (c == '_' || c == '-' || c == ' ') {
      if (out.length() > 0 && out[out.length() - 1] != ' ') out += ' ';
      nextUpper = true;
      continue;
    }
    if (nextUpper && isalpha((unsigned char)c)) {
      out += (char)toupper((unsigned char)c);
      nextUpper = false;
    } else {
      out += (char)tolower((unsigned char)c);
      nextUpper = false;
    }
  }
  out.trim();
  return out;
}

static String deviceProductSlug() {
  String p = String(DEVICE_PRODUCT);
  p.trim();
  p.toLowerCase();
  if (p == "artaircleaner" || p == "art_air_cleaner" || p == "art-air-cleaner" || p == "artair") {
    p = "aac";
  }
  if (p != "aac" && p != "doa" && p != "boom") {
    p = "aac";
  }
  return p;
}

static String deviceBrandName() {
  const String code = deviceProductSlug();
  if (code == "doa") return String("Doa");
  if (code == "boom") return String("Boom");
  return String("ArtAirCleaner");
}

static String deviceApSsidForId6(const String& id6) {
  return deviceBrandName() + String("_AP_") + id6;
}

static String deviceBleNameForId6(const String& id6) {
  return deviceBrandName() + String("_BT_") + id6;
}

static String deviceMdnsHostForId6(const String& id6) {
  const String product = deviceProductSlug();
  const String mdnsSlug = (product == "aac") ? String("artair") : product;
  return mdnsSlug + String("-") + id6;
}

static String deviceMdnsFqdnForId6(const String& id6) {
  return deviceMdnsHostForId6(id6) + String(".local");
}

static const char* SVC_UUID   = "12345678-1234-1234-1234-1234567890aa";
static const char* CH_PROV    = "12345678-1234-1234-1234-1234567890a1"; // WRITE: {ssid,pass}
static const char* CH_INFO    = "12345678-1234-1234-1234-1234567890a2"; // READ/NOTIFY: status
static const char* CH_CMD     = "12345678-1234-1234-1234-1234567890a3"; // WRITE: command


/* =================== SoftAP =================== */
static const IPAddress AP_IP(192,168,4,1), AP_GW(192,168,4,1), AP_MASK(255,255,255,0);
static String g_apSsid;
static String g_apPass;

/* =================== Pins =================== */
// Relays
// New board mapping (from schematic):
//   LIGHT (220V) -> POWER_LED_EN (IO19, mechanical relay)
//   ION/CLEAN -> PUMP_EN (IO13)
//   AUTO_HUM / WATER -> ATOM_EN (IO32)
//   MAIN -> not used on this board variant
#ifndef PIN_RLY_MAIN_GPIO
#define PIN_RLY_MAIN_GPIO 255
#endif
#ifndef PIN_RLY_LIGHT_GPIO
#define PIN_RLY_LIGHT_GPIO 19
#endif
#ifndef PIN_RLY_ION_GPIO
#define PIN_RLY_ION_GPIO 13
#endif
#ifndef PIN_RLY_WATER_GPIO
#define PIN_RLY_WATER_GPIO 32 // ATOM_EN
#endif

// Product-specific water output override (Doa can map watering to atomizer socket).
#ifndef PIN_DOA_WATER_GPIO
#define PIN_DOA_WATER_GPIO PIN_RLY_WATER_GPIO
#endif
#ifndef PIN_ADDR_LED_DATA_GPIO
#define PIN_ADDR_LED_DATA_GPIO 4
#endif
static const uint8_t PIN_ADDR_LED_DATA = PIN_ADDR_LED_DATA_GPIO; // ADDR_LED (IO4 on board A)
#ifndef LIGHT_RELAY_INVERT
#define LIGHT_RELAY_INVERT 1
#endif
#ifndef ION_RELAY_INVERT
#define ION_RELAY_INVERT 1
#endif
#ifndef WATER_RELAY_INVERT
#define WATER_RELAY_INVERT 1
#endif
#ifndef DOA_WATER_RELAY_INVERT
#define DOA_WATER_RELAY_INVERT 0
#endif
#ifndef AAC_WATER_REQUIRES_MASTER
#define AAC_WATER_REQUIRES_MASTER 1
#endif
#ifndef DOA_WATER_REQUIRES_MASTER
#define DOA_WATER_REQUIRES_MASTER 0
#endif

// Fan PWM + Tach
#ifdef PIN_FAN_PWM
#define PIN_FAN_PWM_GPIO PIN_FAN_PWM
#endif
#ifdef PIN_FAN_TACH
#define PIN_FAN_TACH_GPIO PIN_FAN_TACH
#endif
#ifndef PIN_FAN_PWM_GPIO
#define PIN_FAN_PWM_GPIO 23
#endif
#ifndef PIN_FAN_TACH_GPIO
#define PIN_FAN_TACH_GPIO 12
#endif
#ifndef FAN_PWM_MIRROR_ALT_GPIO
#define FAN_PWM_MIRROR_ALT_GPIO 5
#endif
#ifndef FAN_PWM_MIRROR_ALT_ENABLE
#define FAN_PWM_MIRROR_ALT_ENABLE 1
#endif
#ifndef FAN_PWM_MIRROR_ALT_INVERT
#define FAN_PWM_MIRROR_ALT_INVERT 1
#endif
#ifndef PIN_FAN_AUX_EN_GPIO
#define PIN_FAN_AUX_EN_GPIO 255
#endif
#ifndef FAN_TACH_EDGE
// Buffered tach output (U9 -> RPM_OUT_BUF) is best sampled on a single edge.
#define FAN_TACH_EDGE FALLING
#endif
#ifndef FAN_TACH_PPR
// Buffered tach output measures closest to the common 2 pulses/rev behavior.
#define FAN_TACH_PPR 2
#endif
#ifndef FAN_TACH_EDGE_FACTOR
#define FAN_TACH_EDGE_FACTOR 1
#endif
#ifndef FAN_RPM_SAMPLE_WINDOW_MS
#define FAN_RPM_SAMPLE_WINDOW_MS 2000U
#endif
#ifndef FAN_RPM_ZERO_HOLD_WINDOWS
#define FAN_RPM_ZERO_HOLD_WINDOWS 2U
#endif
#ifndef FAN_TACH_USE_PULLUP
#define FAN_TACH_USE_PULLUP 1
#endif
#ifndef FAN_AUX_EN_ACTIVE_HIGH
#define FAN_AUX_EN_ACTIVE_HIGH 1
#endif
#ifndef ENABLE_IR_RX_DEBUG
#define ENABLE_IR_RX_DEBUG 0
#endif
#ifndef ENABLE_IR_DANGEROUS_COMBOS
// Safety default:
// Disable hidden IR combo sequences that can open recovery/factory-reset.
// They were too easy to trigger accidentally with normal remote usage.
#define ENABLE_IR_DANGEROUS_COMBOS 0
#endif
#ifndef ENABLE_IR_SOFT_RECOVERY_COMBO
// Keep soft recovery combo available by default so users can re-open pairing
// without enabling full dangerous combo set.
#define ENABLE_IR_SOFT_RECOVERY_COMBO 1
#endif
#ifndef ENABLE_IR_FACTORY_RESET_COMBO
// Factory reset via IR should stay off unless explicitly enabled.
#define ENABLE_IR_FACTORY_RESET_COMBO ENABLE_IR_DANGEROUS_COMBOS
#endif
#ifndef AUTH_HTTP_DEBUG
#define AUTH_HTTP_DEBUG 0
#endif
#ifndef FAN_DEBUG_LOG
#define FAN_DEBUG_LOG 0
#endif
#ifndef TACH_PIN12_DEBUG_LOG
#define TACH_PIN12_DEBUG_LOG 0
#endif
#ifndef CMD_LOG_UNCHANGED
#define CMD_LOG_UNCHANGED 0
#endif
#ifndef WIFI_EVENT_DEBUG
#define WIFI_EVENT_DEBUG 0
#endif
#ifndef WIFI_INFO_LOG
#define WIFI_INFO_LOG 0
#endif
#ifndef SEN55_DEBUG_LOG
#define SEN55_DEBUG_LOG 0
#endif
#ifndef BME688_DEBUG_LOG
#define BME688_DEBUG_LOG 0
#endif
#ifndef I2C_SCAN_LOG
#define I2C_SCAN_LOG 0
#endif
#ifndef BSEC_INFO_LOG
#define BSEC_INFO_LOG 0
#endif
#ifndef BSEC_RUNTIME_STATUS_LOG
#define BSEC_RUNTIME_STATUS_LOG 0
#endif
#ifndef QR_DEBUG_LOG
#define QR_DEBUG_LOG 0
#endif
#if PRODUCTION_BUILD
#if (LOG_AP_PASS || LOG_FACTORY_QR || QR_DEBUG_LOG || ALLOW_SECRET_LOGS)
#error "Production build cannot enable secret-bearing logs."
#endif
#endif
#ifndef BLE_OWNER_AUTH_GRACE_MS
#define BLE_OWNER_AUTH_GRACE_MS 180000UL
#endif
#ifndef BLE_NOTIFY_DEBUG
#define BLE_NOTIFY_DEBUG 0
#endif
#ifndef PIN_IR_RX_GPIO
// New board schematic: RMT_DATA_BUF -> IO35
#define PIN_IR_RX_GPIO 35
#endif
#ifndef IR_CODE_POWER_TOGGLE
#define IR_CODE_POWER_TOGGLE 0xBA45FF00UL
#endif
#ifndef IR_CODE_FRAME_LIGHT_TOGGLE
#define IR_CODE_FRAME_LIGHT_TOGGLE 0xB847FF00UL
#endif
#ifndef IR_CODE_FAN_MODE_UP
#define IR_CODE_FAN_MODE_UP 0xF609FF00UL
#endif
#ifndef IR_CODE_FAN_MODE_DOWN
#define IR_CODE_FAN_MODE_DOWN 0xF807FF00UL
#endif
#ifndef IR_CODE_ION_TOGGLE
#define IR_CODE_ION_TOGGLE 0xBF40FF00UL
#endif
#ifndef IR_CODE_AUTO_HUM_TOGGLE
#define IR_CODE_AUTO_HUM_TOGGLE 0xE619FF00UL
#endif
#ifndef IR_FACTORY_RESET_STEP_TIMEOUT_MS
#define IR_FACTORY_RESET_STEP_TIMEOUT_MS 6000UL
#endif
#ifndef IR_SOFT_RECOVERY_STEP_TIMEOUT_MS
#define IR_SOFT_RECOVERY_STEP_TIMEOUT_MS 4000UL
#endif
#ifndef SOFT_RECOVERY_WINDOW_MS
#define SOFT_RECOVERY_WINDOW_MS 120000UL
#endif
#ifndef UNOWNED_BOOT_PAIRING_WINDOW_MS
// Unowned cihazda ilk kurulum için daha geniş BLE pairing süresi.
// IR combo recovery kapalıyken kullanıcıya yeterli zaman verir.
#define UNOWNED_BOOT_PAIRING_WINDOW_MS 600000UL
#endif
#ifndef USE_ADDR_LED_PROTOCOL
#define USE_ADDR_LED_PROTOCOL 1
#endif
#ifndef ADDR_LED_COLOR_ORDER
#define ADDR_LED_COLOR_ORDER NEO_BRG
#endif
#ifndef ADDR_LED_SIGNAL_SPEED
#define ADDR_LED_SIGNAL_SPEED NEO_KHZ800
#endif
#ifndef FRAME_LED_COUNT
#define FRAME_LED_COUNT 24
#endif
#ifndef FAN_MODE_SHOW_DURATION_MS
#define FAN_MODE_SHOW_DURATION_MS 2800UL
#endif
#ifndef FAN_MODE_SHOW_START_LEVEL
#define FAN_MODE_SHOW_START_LEVEL 0U
#endif
#ifndef CLEAN_SNAKE_SHOW_DURATION_MS
#define CLEAN_SNAKE_SHOW_DURATION_MS 4000UL
#endif
#ifndef CLEAN_SNAKE_STEP_MS
#define CLEAN_SNAKE_STEP_MS 55UL
#endif
#ifndef CLEAN_SNAKE_TAIL_PIXELS
#define CLEAN_SNAKE_TAIL_PIXELS 7U
#endif
#ifndef BOOT_FORCE_OUTPUTS_OFF
#define BOOT_FORCE_OUTPUTS_OFF 1
#endif
static const uint8_t PIN_FAN_PWM   = PIN_FAN_PWM_GPIO;
static const uint8_t PIN_FAN_TACH  = PIN_FAN_TACH_GPIO;
static const uint8_t PIN_FAN_AUX_EN = PIN_FAN_AUX_EN_GPIO;
static const uint8_t PIN_FAN_PWM_ALT = FAN_PWM_MIRROR_ALT_GPIO;
static const uint8_t PIN_IR_RX = PIN_IR_RX_GPIO;

// RGB
static const uint8_t PIN_RGB_R     = 18;
static const uint8_t PIN_RGB_G     = 14;
static const uint8_t PIN_RGB_B     = 16;

// I2C bus pins can be overridden per board from platformio.ini.
#ifndef PIN_I2C_SDA_GPIO
#define PIN_I2C_SDA_GPIO 21
#endif
#ifndef PIN_I2C_SCL_GPIO
#define PIN_I2C_SCL_GPIO 22
#endif
static const uint8_t PIN_I2C_SDA   = PIN_I2C_SDA_GPIO;
static const uint8_t PIN_I2C_SCL   = PIN_I2C_SCL_GPIO;
#ifndef I2C_BUS_HZ
#define I2C_BUS_HZ 100000
#endif
#ifndef SEN55_I2C_ADDR
#define SEN55_I2C_ADDR 0x69
#endif
// Legacy analog sensors are disabled - these pins are no longer used but kept for compilation
// These functions may still be called but sensors are not connected
static const uint8_t PIN_GP2Y_LED  = 4;   // unused (legacy sensor disabled)
static const uint8_t PIN_GP2Y_AO   = 39;  // unused (legacy sensor disabled)
static const uint8_t PIN_MQ4_AO    = 34;  // unused (legacy sensor disabled)
static const uint8_t PIN_MQ135_AO  = 35;  // unused (legacy sensor disabled)
static const uint8_t PIN_DHT       = 17;  // DHT11 (kept if present)
#define DHTTYPE DHT11

#if USE_ADDR_LED_PROTOCOL
static Adafruit_NeoPixel g_framePixels(
    FRAME_LED_COUNT,
    PIN_ADDR_LED_DATA,
    ADDR_LED_COLOR_ORDER + ADDR_LED_SIGNAL_SPEED
);
static bool g_frameSolidCacheValid = false;
static uint8_t g_frameSolidLastR = 255;
static uint8_t g_frameSolidLastG = 255;
static uint8_t g_frameSolidLastB = 255;
#endif

static void initI2C() {
  static bool done = false;
  if (done) return;
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(I2C_BUS_HZ);
#if I2C_SCAN_LOG
  Serial.printf("[I2C] begin(SDA=%u, SCL=%u) @%luHz\n",
                (unsigned)PIN_I2C_SDA,
                (unsigned)PIN_I2C_SCL,
                (unsigned long)I2C_BUS_HZ);
#endif
  done = true;
}

// Buzzer
static const uint8_t PIN_BUZZER    = 2;
#ifndef ENABLE_I2S_BEEP
#define ENABLE_I2S_BEEP 1
#endif
#ifndef I2S_BEEP_BCLK_PIN
#define I2S_BEEP_BCLK_PIN 26
#endif
#ifndef I2S_BEEP_LRCK_PIN
#define I2S_BEEP_LRCK_PIN 25
#endif
#ifndef I2S_BEEP_DOUT_PIN
#define I2S_BEEP_DOUT_PIN 27
#endif
#ifndef I2S_BEEP_SAMPLE_RATE
#define I2S_BEEP_SAMPLE_RATE 44100
#endif
#ifndef I2S_BEEP_AMPLITUDE
#define I2S_BEEP_AMPLITUDE 1200
#endif
#ifndef I2S_WAV_VOLUME_PERCENT
#define I2S_WAV_VOLUME_PERCENT 45
#endif
#ifndef ENABLE_IR_VOICE_PROMPTS
#define ENABLE_IR_VOICE_PROMPTS 1
#endif
#ifndef IR_VOICE_POWER_ON
#define IR_VOICE_POWER_ON "/on.wav"
#endif
#ifndef IR_VOICE_POWER_OFF
#define IR_VOICE_POWER_OFF "/off.wav"
#endif
#ifndef IR_VOICE_LIGHT_ON
#define IR_VOICE_LIGHT_ON "/light_on.wav"
#endif
#ifndef IR_VOICE_LIGHT_OFF
#define IR_VOICE_LIGHT_OFF "/light_off.wav"
#endif
#ifndef IR_VOICE_ION_ON
#define IR_VOICE_ION_ON "/ion_on.wav"
#endif
#ifndef IR_VOICE_ION_OFF
#define IR_VOICE_ION_OFF "/ion_off.wav"
#endif
#ifndef IR_VOICE_HUM_ON
#define IR_VOICE_HUM_ON "/humidity_on.wav"
#endif
#ifndef IR_VOICE_HUM_OFF
#define IR_VOICE_HUM_OFF "/humidity_off.wav"
#endif
#ifndef IR_VOICE_FAN_SLEEP
#define IR_VOICE_FAN_SLEEP "/silent_mod_on.wav"
#endif
#ifndef IR_VOICE_FAN_MED
#define IR_VOICE_FAN_MED "/medium_mod_on.wav"
#endif
#ifndef IR_VOICE_FAN_TURBO
#define IR_VOICE_FAN_TURBO "/turbo_mod_on.wav"
#endif
#ifndef IR_VOICE_FAN_AUTO
#define IR_VOICE_FAN_AUTO "/auto_mod_on.wav"
#endif
#ifndef ENABLE_IR_KEY_BEEP
#define ENABLE_IR_KEY_BEEP 1
#endif
#ifndef BUZZER_USE_TONE
#define BUZZER_USE_TONE 0
#endif
#ifndef BUZZER_FREQ_HZ
#define BUZZER_FREQ_HZ 3000
#endif
#ifndef BUZZER_BEEP_MS
#define BUZZER_BEEP_MS 90
#endif
static uint32_t g_buzzerOffAtMs = 0;
static bool g_i2sBeepReady = false;

struct WavInfo {
  uint32_t sampleRate = 0;
  uint16_t channels = 0;
  uint16_t bitsPerSample = 0;
  uint32_t dataOffset = 0;
  uint32_t dataSize = 0;
};

static bool g_spiffsReady = false;
static bool g_spiffsMountAttempted = false;
static bool g_spiffsMountFailed = false;

#if defined(ARDUINO_ARCH_ESP32)
static bool ensureSpiffsReady() {
  if (g_spiffsReady) return true;
  if (g_spiffsMountAttempted) return false;
  g_spiffsMountAttempted = true;
  if (!SPIFFS.begin(false)) {
    // First mount can fail on fresh/corrupted FS after partition/layout changes.
    // Try one-time format+mount recovery so provisioning/cloud can proceed.
    Serial.println("[TLS] SPIFFS mount failed, attempting format+mount");
    if (!SPIFFS.begin(true)) {
      g_spiffsMountFailed = true;
      return false;
    }
    Serial.println("[TLS] SPIFFS format+mount recovery succeeded");
  }
  g_spiffsReady = true;
  g_spiffsMountFailed = false;
  return true;
}

static bool ensureSpiffsReadyLogged(const char* context) {
  if (ensureSpiffsReady()) return true;
  if (context && *context) {
    Serial.printf("[TLS] SPIFFS mount failed without format (%s)\n", context);
  } else {
    Serial.println("[TLS] SPIFFS mount failed without format");
  }
  return false;
}

static uint16_t rd16(const uint8_t* p) {
  return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t rd32(const uint8_t* p) {
  return (uint32_t)p[0] |
         ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static bool parseWavHeader(File& f, WavInfo& out) {
  uint8_t h[12];
  if (f.read(h, sizeof(h)) != (int)sizeof(h)) return false;
  if (memcmp(h, "RIFF", 4) != 0 || memcmp(h + 8, "WAVE", 4) != 0) return false;

  bool haveFmt = false;
  bool haveData = false;
  while (f.available()) {
    uint8_t ch[8];
    if (f.read(ch, sizeof(ch)) != (int)sizeof(ch)) break;
    const uint32_t sz = rd32(ch + 4);
    const uint32_t nextPos = (uint32_t)f.position() + sz + (sz & 1U);

    if (memcmp(ch, "fmt ", 4) == 0) {
      uint8_t fmt[40];
      const uint32_t toRead = (sz > sizeof(fmt)) ? sizeof(fmt) : sz;
      if (f.read(fmt, toRead) != (int)toRead) return false;
      if (toRead < 16) return false;
      const uint16_t audioFmt = rd16(fmt + 0);
      out.channels = rd16(fmt + 2);
      out.sampleRate = rd32(fmt + 4);
      out.bitsPerSample = rd16(fmt + 14);
      if (audioFmt != 1) return false; // PCM
      haveFmt = true;
    } else if (memcmp(ch, "data", 4) == 0) {
      out.dataOffset = (uint32_t)f.position();
      out.dataSize = sz;
      haveData = true;
    }
    f.seek(nextPos, SeekSet);
    if (haveFmt && haveData) break;
  }
  if (!haveFmt || !haveData) return false;
  if ((out.channels != 1 && out.channels != 2) || out.bitsPerSample != 16) return false;
  if (out.sampleRate < 8000 || out.sampleRate > 48000) return false;
  return true;
}

static bool initI2sBeepIfNeeded() {
#if ENABLE_I2S_BEEP
  if (g_i2sBeepReady) return true;

  const i2s_config_t cfg = {
      .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
      .sample_rate = I2S_BEEP_SAMPLE_RATE,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
      .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
      .communication_format = I2S_COMM_FORMAT_STAND_I2S,
      .intr_alloc_flags = 0,
      .dma_buf_count = 4,
      .dma_buf_len = 256,
      .use_apll = false,
      .tx_desc_auto_clear = true,
      .fixed_mclk = 0
  };
  const i2s_pin_config_t pins = {
      .bck_io_num = I2S_BEEP_BCLK_PIN,
      .ws_io_num = I2S_BEEP_LRCK_PIN,
      .data_out_num = I2S_BEEP_DOUT_PIN,
      .data_in_num = I2S_PIN_NO_CHANGE
  };
  if (i2s_driver_install(I2S_NUM_0, &cfg, 0, NULL) != ESP_OK) return false;
  if (i2s_set_pin(I2S_NUM_0, &pins) != ESP_OK) return false;
  if (i2s_set_clk(I2S_NUM_0, I2S_BEEP_SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_STEREO) != ESP_OK) return false;
  i2s_zero_dma_buffer(I2S_NUM_0);
  g_i2sBeepReady = true;
  return true;
#else
  return false;
#endif
}

static bool playI2sBeep(uint16_t freqHz, uint16_t durMs, int16_t amp) {
#if ENABLE_I2S_BEEP
  if (!initI2sBeepIfNeeded()) return false;
  i2s_set_clk(I2S_NUM_0, I2S_BEEP_SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_STEREO);
  if (freqHz < 50 || durMs == 0) return false;
  if (amp < 200) amp = 200;
  if (amp > 16000) amp = 16000;

  const uint32_t sr = I2S_BEEP_SAMPLE_RATE;
  uint32_t framesLeft = ((uint32_t)durMs * sr) / 1000U;
  if (framesLeft == 0) framesLeft = 1;
  static int16_t pcm[256 * 2]; // stereo interleaved
  const float step = (float)freqHz / (float)sr;
  float phase = 0.0f;

  while (framesLeft > 0) {
    const uint32_t n = (framesLeft > 256U) ? 256U : framesLeft;
    for (uint32_t i = 0; i < n; ++i) {
      const int16_t s = (phase < 0.5f) ? amp : (int16_t)-amp;
      pcm[i * 2] = s;
      pcm[i * 2 + 1] = s;
      phase += step;
      if (phase >= 1.0f) phase -= 1.0f;
    }
    size_t written = 0;
    i2s_write(I2S_NUM_0, pcm, n * 2U * sizeof(int16_t), &written, portMAX_DELAY);
    framesLeft -= n;
  }
  i2s_zero_dma_buffer(I2S_NUM_0);
  return true;
#else
  (void)freqHz; (void)durMs; (void)amp;
  return false;
#endif
}

static bool playWavI2s(const char* path) {
#if ENABLE_I2S_BEEP
  if (!path || !*path) return false;
  if (!ensureSpiffsReady()) return false;
  if (!initI2sBeepIfNeeded()) return false;
  if (!SPIFFS.exists(path)) return false;

  File f = SPIFFS.open(path, "r");
  if (!f) return false;
  WavInfo w;
  if (!parseWavHeader(f, w)) {
    f.close();
    return false;
  }
  f.seek(w.dataOffset, SeekSet);
  i2s_set_clk(I2S_NUM_0, w.sampleRate, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_STEREO);
  int wavVolPct = I2S_WAV_VOLUME_PERCENT;
  if (wavVolPct < 0) wavVolPct = 0;
  if (wavVolPct > 100) wavVolPct = 100;

  uint8_t inBuf[1024];
  int16_t outStereo[1024];
  uint32_t remain = w.dataSize;
  while (remain > 0) {
    const uint32_t want = (remain > sizeof(inBuf)) ? (uint32_t)sizeof(inBuf) : remain;
    const int got = f.read(inBuf, want);
    if (got <= 0) break;
    remain -= (uint32_t)got;
    size_t written = 0;
    if (w.channels == 2) {
      const int samples = got / 2;
      for (int i = 0; i < samples; ++i) {
        int32_t s = (int16_t)rd16(inBuf + i * 2);
        s = (s * wavVolPct) / 100;
        outStereo[i] = (int16_t)s;
      }
      i2s_write(I2S_NUM_0, outStereo, (size_t)samples * sizeof(int16_t), &written, portMAX_DELAY);
    } else {
      const int samples = got / 2;
      for (int i = 0; i < samples; ++i) {
        int32_t s = (int16_t)rd16(inBuf + i * 2);
        s = (s * wavVolPct) / 100;
        outStereo[i * 2] = (int16_t)s;
        outStereo[i * 2 + 1] = (int16_t)s;
      }
      i2s_write(I2S_NUM_0, outStereo, (size_t)samples * 2U * sizeof(int16_t), &written, portMAX_DELAY);
    }
  }
  f.close();
  i2s_zero_dma_buffer(I2S_NUM_0);
  i2s_set_clk(I2S_NUM_0, I2S_BEEP_SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_STEREO);
  return true;
#else
  (void)path;
  return false;
#endif
}
#endif

static inline void triggerIrKeyBeep(uint32_t nowMs) {
#if ENABLE_IR_KEY_BEEP
#if defined(ARDUINO_ARCH_ESP32)
  if (playI2sBeep((uint16_t)BUZZER_FREQ_HZ, (uint16_t)BUZZER_BEEP_MS, (int16_t)I2S_BEEP_AMPLITUDE)) {
    return;
  }
#endif
#if BUZZER_USE_TONE
  tone(PIN_BUZZER, BUZZER_FREQ_HZ, BUZZER_BEEP_MS);
  g_buzzerOffAtMs = 0;
#else
  g_buzzerOffAtMs = nowMs + (uint32_t)BUZZER_BEEP_MS;
  digitalWrite(PIN_BUZZER, HIGH);
#endif
#else
  (void)nowMs;
#endif
}

static const char* resolveVoicePath(const char* primary, const char* fallback = nullptr) {
#if ENABLE_IR_VOICE_PROMPTS
  if (ensureSpiffsReady()) {
    if (primary && *primary && SPIFFS.exists(primary)) return primary;
    if (fallback && *fallback && SPIFFS.exists(fallback)) return fallback;
  }
#else
  (void)primary;
  (void)fallback;
#endif
  return nullptr;
}

static inline void serviceBuzzer(uint32_t nowMs) {
#if ENABLE_IR_KEY_BEEP
  if (g_buzzerOffAtMs != 0 && (int32_t)(nowMs - g_buzzerOffAtMs) >= 0) {
    digitalWrite(PIN_BUZZER, LOW);
    g_buzzerOffAtMs = 0;
  }
#else
  (void)nowMs;
#endif
}

/* =================== Config =================== */
#ifndef RELAY_ACTIVE_LOW
#define RELAY_ACTIVE_LOW 1
#endif
#ifndef FAN_PWM_INVERT
#define FAN_PWM_INVERT 0
#endif
static const bool     FAN_PWM_INVERTED = (FAN_PWM_INVERT != 0);
static bool           AP_ONLY = false;
struct RelayRoutingConfig {
  uint8_t pinMain;
  uint8_t pinLight;
  uint8_t pinIon;
  uint8_t pinWater;
  bool invertLight;
  bool invertIon;
  bool invertWater;
  bool activeLow;
  bool waterRequiresMaster;
  const char* waterLabel;
};
static RelayRoutingConfig g_relayCfg = {
  PIN_RLY_MAIN_GPIO,
  PIN_RLY_LIGHT_GPIO,
  PIN_RLY_ION_GPIO,
  PIN_RLY_WATER_GPIO,
  (LIGHT_RELAY_INVERT != 0),
  (ION_RELAY_INVERT != 0),
  (WATER_RELAY_INVERT != 0),
  (RELAY_ACTIVE_LOW != 0),
  (AAC_WATER_REQUIRES_MASTER != 0),
  "WATER",
};
static void initRelayRoutingConfig() {
  const String product = deviceProductSlug();
  g_relayCfg.pinMain = PIN_RLY_MAIN_GPIO;
  g_relayCfg.pinLight = PIN_RLY_LIGHT_GPIO;
  g_relayCfg.pinIon = PIN_RLY_ION_GPIO;
  g_relayCfg.pinWater = PIN_RLY_WATER_GPIO;
  g_relayCfg.invertLight = (LIGHT_RELAY_INVERT != 0);
  g_relayCfg.invertIon = (ION_RELAY_INVERT != 0);
  g_relayCfg.invertWater = (WATER_RELAY_INVERT != 0);
  g_relayCfg.activeLow = (RELAY_ACTIVE_LOW != 0);
  g_relayCfg.waterRequiresMaster = (AAC_WATER_REQUIRES_MASTER != 0);
  g_relayCfg.waterLabel = "WATER";
  if (product == "doa") {
    g_relayCfg.pinWater = PIN_DOA_WATER_GPIO;
    g_relayCfg.invertWater = (DOA_WATER_RELAY_INVERT != 0);
    g_relayCfg.waterRequiresMaster = (DOA_WATER_REQUIRES_MASTER != 0);
    g_relayCfg.waterLabel = "ATOM";
  }
  Serial.printf(
      "[RELAYCFG] product=%s main=%u light=%u ion=%u %s=%u invert(light=%d ion=%d water=%d) activeLow=%d waterNeedsMaster=%d\n",
      product.c_str(),
      (unsigned)g_relayCfg.pinMain,
      (unsigned)g_relayCfg.pinLight,
      (unsigned)g_relayCfg.pinIon,
      g_relayCfg.waterLabel,
      (unsigned)g_relayCfg.pinWater,
      g_relayCfg.invertLight ? 1 : 0,
      g_relayCfg.invertIon ? 1 : 0,
      g_relayCfg.invertWater ? 1 : 0,
      g_relayCfg.activeLow ? 1 : 0,
      g_relayCfg.waterRequiresMaster ? 1 : 0);
}
// GP2Y10 config
static const bool GP2Y_LED_ACTIVE_HIGH = false;
static const bool GP2Y_LED_ALWAYS_ON   = false;
inline void gp2y_led_on()  { digitalWrite(PIN_GP2Y_LED, GP2Y_LED_ACTIVE_HIGH ? HIGH : LOW); }
inline void gp2y_led_off() { digitalWrite(PIN_GP2Y_LED, GP2Y_LED_ACTIVE_HIGH ? LOW  : HIGH); }

// Optional user button (long-press = pairing/join window, very long = factory reset)
// Donanımınıza göre config.h içinde PIN_BTN override edebilirsiniz.
#ifndef PIN_BTN
#define PIN_BTN 0
#endif
static const uint32_t BTN_PAIR_MS  = 3000;   // 3s -> pairing/join window
static const uint32_t BTN_RESET_MS = 12000;  // 12s -> factory reset

// LEDC
static const uint8_t  CH_FAN = 0;
static const uint8_t  CH_FAN_ALT = 4;
static const uint8_t  CH_R   = 1;
static const uint8_t  CH_G   = 2;
static const uint8_t  CH_B   = 3;
#ifndef PWM_FREQ_FAN
// Default to 1kHz for broader compatibility with transistor/MOSFET fan stages.
// 4-wire PC fan drivers can override this to 25kHz via build flags.
#define PWM_FREQ_FAN 1000
#endif
static const uint32_t PWM_FREQ_LED = 1000;
static const uint8_t  PWM_RES_BITS = 10;
inline uint32_t dutyMax() { return (1U << PWM_RES_BITS) - 1U; }

// ADC
static const float   ADC_VREF = 3.3f;
static const int     ADC_MAX  = 4095;

/* =================== State =================== */
enum FanMode { FAN_SLEEP, FAN_LOW, FAN_MED, FAN_HIGH, FAN_TURBO, FAN_AUTO };

static const char* fanModeToStr(FanMode mode) {
  switch (mode) {
    case FAN_SLEEP: return "sleep";
    case FAN_LOW:   return "low";
    case FAN_MED:   return "med";
    case FAN_HIGH:  return "high";
    case FAN_TURBO: return "turbo";
    case FAN_AUTO:  return "auto";
    default:        return "unknown";
  }
}

static uint8_t fanModeToLevel(FanMode mode) {
  switch (mode) {
    case FAN_SLEEP: return 0;
    case FAN_LOW:   return 1;
    case FAN_MED:   return 2;
    case FAN_HIGH:  return 3;
    case FAN_TURBO: return 4;
    case FAN_AUTO:  return 5;
    default:        return 0;
  }
}

static const char* airQualityLevelFromScore(int score) {
  if (score >= 80) return "good";
  if (score >= 50) return "moderate";
  return "bad";
}

static float aqiFromPm25(float c) {
  if (isnan(c) || c <= 0.0f) return NAN;
  // EPA AQI breakpoints for PM2.5 (µg/m3, 24h)
  const float bp[][4] = {
    {0.0f,   12.0f,  0.0f,  50.0f},
    {12.1f,  35.4f,  51.0f, 100.0f},
    {35.5f,  55.4f,  101.0f,150.0f},
    {55.5f,  150.4f,151.0f,200.0f},
    {150.5f, 250.4f,201.0f,300.0f},
    {250.5f, 500.4f,301.0f,500.0f},
  };
  for (size_t i = 0; i < 6; ++i) {
    if (c <= bp[i][1]) {
      const float cLow = bp[i][0], cHigh = bp[i][1];
      const float iLow = bp[i][2], iHigh = bp[i][3];
      return ((iHigh - iLow) / (cHigh - cLow)) * (c - cLow) + iLow;
    }
  }
  return 500.0f;
}

static float aqiFromPm10(float c) {
  if (isnan(c) || c <= 0.0f) return NAN;
  // EPA AQI breakpoints for PM10 (µg/m3, 24h)
  const float bp[][4] = {
    {0.0f,   54.0f,  0.0f,  50.0f},
    {55.0f,  154.0f, 51.0f, 100.0f},
    {155.0f, 254.0f, 101.0f,150.0f},
    {255.0f, 354.0f, 151.0f,200.0f},
    {355.0f, 424.0f, 201.0f,300.0f},
    {425.0f, 604.0f, 301.0f,500.0f},
  };
  for (size_t i = 0; i < 6; ++i) {
    if (c <= bp[i][1]) {
      const float cLow = bp[i][0], cHigh = bp[i][1];
      const float iLow = bp[i][2], iHigh = bp[i][3];
      return ((iHigh - iLow) / (cHigh - cLow)) * (c - cLow) + iLow;
    }
  }
  return 500.0f;
}
struct AppState {
  bool     masterOn = true;
  bool     lightOn  = false;
  bool     cleanOn  = false;
  bool     ionOn    = false;
  FanMode  mode     = FAN_LOW;
  uint8_t  fanPercent = 35;
  bool     autoHumEnabled = false;
  uint8_t  autoHumTarget  = 55; // 30..70

  // RGB
  uint8_t  r=0,g=0,b=0;
  bool     rgbOn = false;
  uint8_t  rgbBrightness = 100; // 0..100

  // Sensors
  // Simplified sensor set: using SEN55 via I2C for PM, T, RH, VOC/NOx
  float    pm_v   = 0.0f; // generic PM metric placeholder (mapped from SEN55)
  // MQ sensors removed
  float    tempC  = 0.0f; // from SEN55/DHT fallback
  float    humPct = 0.0f; // from SEN55/DHT fallback
  // Raw DHT11 fallback (ayrı alanlarda da tutalım)
  float    dhtTempC = NAN;
  float    dhtHumPct = NAN;
  float    vocIndex = NAN;
  float    noxIndex = NAN;
  // Detailed PM concentrations (µg/m3)
  float    pm1_0 = NAN;
  float    pm2_5 = NAN;
  float    pm4_0 = NAN;
  float    pm10_0 = NAN;
  // BME688 (AI pipeline) classic readings – kept separate so UI'de ayrıştırılabilir
  float    aiTempC     = NAN;
  float    aiHumPct    = NAN;
  float    aiPressure  = NAN;   // hPa
  float    aiGasKOhm   = NAN;   // kΩ
  float    aiIaq       = NAN;   // BSEC static IAQ
  float    aiCo2Eq     = NAN;   // BSEC CO2 equivalent
  float    aiBVocEq    = NAN;   // BSEC breath VOC equivalent

  // Safety/alerts

  // Calibration & filter
  uint16_t calibRPM[9] = {0};
  bool     filterAlert  = false;
} app;

enum class FanAutoReason : uint8_t {
  HEALTH = 0,
  ODOR_CLEANUP = 1,
};

static float g_healthSeverity = 0.0f;
static float g_odorBoostSeverity = 0.0f;
static float g_controlSeverity = 0.0f;
static FanAutoReason g_fanAutoReason = FanAutoReason::HEALTH;
static uint32_t g_odorBoostUntilMs = 0;
static float g_prevVocIndexForOdor = NAN;
static float g_prevAiIaqForOdor = NAN;
static float g_prevAiBVocEqForOdor = NAN;

static bool     g_fanModeShowActive = false;
static uint32_t g_fanModeShowStartMs = 0;
static uint8_t  g_fanModeShowR = 0;
static uint8_t  g_fanModeShowG = 0;
static uint8_t  g_fanModeShowB = 0;
static bool     g_cleanSnakeShowActive = false;
static uint32_t g_cleanSnakeShowStartMs = 0;
static bool     g_autoSnakeShowActive = false;
static uint32_t g_autoSnakeShowStartMs = 0;

void applyRgb();
static void startCleanSnakeShow(uint32_t nowMs);
static void updateCleanSnakeShow(uint32_t nowMs);
static void startAutoSnakeShow(uint32_t nowMs);
static void updateAutoSnakeShow(uint32_t nowMs);

// Forward declaration (helper is implemented later in the file)
static bool updateFloatIfChanged(float& target, float value, float epsilon);

/* =================== In‑memory sensor history =================== */
struct HistorySample {
  uint32_t tsSec;       // unix epoch seconds (approximate)
  int16_t  pm25_x10;    // pm2_5 * 10
  int16_t  tempC_x10;   // tempC * 10
  int16_t  humPct_x10;  // humPct * 10
  int16_t  voc_x10;     // vocIndex * 10
  int16_t  nox_x10;     // noxIndex * 10
  int16_t  aiTempC_x10; // aiTempC * 10
  int16_t  aiHum_x10;   // aiHumPct * 10
  int16_t  aiPress_x10; // aiPressure * 10 (hPa)
  int16_t  aiGas_x10;   // aiGasKOhm * 10
  uint16_t rpm;
};

// Short‑term history: ~25 saat, 10 dakikada 1 örnek
static constexpr uint32_t HISTORY_SAMPLE_INTERVAL_MS = 600000;   // 600s (10 min)
static constexpr uint16_t HISTORY_CAPACITY           = 150;      // 150 * 10 min = 25 saat
extern volatile uint32_t g_lastRPM;
static HistorySample g_history[HISTORY_CAPACITY];
static uint16_t      g_historyCount = 0;
static uint16_t      g_historyHead  = 0; // next index to write
static uint32_t      g_lastHistorySampleMs = 0;

// Daily aggregated history persisted in NVS (flash).
struct DailySample {
  uint32_t dayStart;   // epoch seconds for local midnight
  float    pm2_5;
  float    tempC;
  float    humPct;
  float    vocIndex;
  float    noxIndex;
  float    aiTempC;
  float    aiHumPct;
  float    aiPressure;
  float    aiGasKOhm;
  uint16_t rpm;
};

static constexpr uint8_t DAILY_HISTORY_CAPACITY = 32; // last 32 days
static DailySample g_daily[DAILY_HISTORY_CAPACITY];
static uint8_t     g_dailyCount = 0;
static uint8_t     g_dailyHead  = 0; // next index to write
static int         g_lastDailyKey = -1;


#if ENABLE_WAQI
// Dış ortam (şehir) snapshot'ı – WAQI'den çekilen son değerler.
struct CitySnapshot {
  bool   hasData      = false;
  String name;
  String description;
  float  tempC        = NAN;
  float  humPct       = NAN;
  float  windKph      = NAN;
  float  aqiScore     = NAN; // 0..500 indeks veya 0..100 skor, sadece UI için
  float  pm2_5        = NAN;
};

// WAQI konfigürasyonu (lat/lon + görünen ad)
struct WaqiConfig {
  double lat;
  double lon;
  String name;   // "Ankara, TR" gibi
  bool   valid;
};

static CitySnapshot g_city;
static WaqiConfig   g_waqiConfig {WAQI_LAT_DEFAULT, WAQI_LON_DEFAULT, String(""), true};
static bool g_forceWaqiFetch = true;
#endif // ENABLE_WAQI



// WAQI'den belirli aralıklarla dış ortam verisi çek.
#if ENABLE_WAQI
static void pollWaqiIfDue(uint32_t nowMs) {
  ScopedPerfLog perfScope("waqi_poll", 10000);
  static uint32_t lastFetchMs = 0;
  const uint32_t intervalMs = 30UL * 60UL * 1000UL; // 30 dakika
  const uint32_t retryMs    = 5UL * 60UL * 1000UL;  // hata durumunda 5 dakikada bir dene
  constexpr uint32_t kWaqiIoTimeoutMs = 7000UL;

  uint32_t sinceLast = nowMs - lastFetchMs;
  if (!g_forceWaqiFetch && lastFetchMs != 0) {
    if (g_city.hasData) {
      if (sinceLast < intervalMs) return;
    } else {
      if (sinceLast < retryMs) return;
    }
  }

  if (strlen(WAQI_API_TOKEN) == 0) {
    // Token yoksa erken çık.
    return;
  }
  if (!g_waqiConfig.valid) {
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }
  // WAQI fetch should not depend on MQTT/cloud session.
  // Local-only mode still needs external city air-quality refresh.
  lastFetchMs    = nowMs;
  g_forceWaqiFetch = false;

  double lat = g_waqiConfig.lat;
  double lon = g_waqiConfig.lon;

  Serial.printf("[WAQI] fetch for lat=%.4f lon=%.4f\n", lat, lon);

  if (!isTimeValid()) {
    // NTP zamanı yoksa TLS doğrulaması başarısız olabilir; WAQI'yi geciktirmek yerine
    // bu fetch için doğrulamayı gevşet.
    Serial.println("[WAQI] time invalid; using insecure TLS for this fetch");
    g_httpNet.setInsecure();
  } else if (strlen(WAQI_ROOT_CA_PEM) == 0) {
    Serial.println("[WAQI] Root CA missing; WAQI_ROOT_CA_PEM empty (cannot set CACert)");
  } else {
    g_httpNet.setCACert(WAQI_ROOT_CA_PEM);
  }
  // WiFiClientSecure timeout units are seconds.
  const uint32_t waqiIoTimeoutSec = std::max<uint32_t>(1UL, kWaqiIoTimeoutMs / 1000UL);
  g_httpNet.setTimeout(waqiIoTimeoutSec);
  g_httpNet.setHandshakeTimeout(waqiIoTimeoutSec);
  HTTPClient http;

  String url = String("https://api.waqi.info/feed/geo:")
      + String(lat, 6) + ";" + String(lon, 6)
      + "/?token=" + WAQI_API_TOKEN;

  if (!httpBegin(http, url)) {
    Serial.println("[WAQI] HTTP begin failed");
    return;
  }
  http.setTimeout((uint16_t)kWaqiIoTimeoutMs);
  http.setReuse(false);

  logPerfSnapshot("waqi_before_http_get");
  int code = http.GET();
  Serial.printf("[WAQI] HTTP GET code=%d\n", code);
  logPerfSnapshot("waqi_after_http_get");
  if (code >= 200 && code < 300) {
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, http.getStream());
    if (err) {
      Serial.printf("[WAQI] JSON error: %s\n", err.c_str());
    } else {
      const char* status = doc["status"] | "";
      if (strcmp(status, "ok") == 0) {
        JsonObject data = doc["data"].as<JsonObject>();
        if (!data.isNull()) {
          float aqiIdx = data["aqi"] | NAN; // 0..500
          JsonObject city = data["city"].as<JsonObject>();
          JsonObject iaqi = data["iaqi"].as<JsonObject>();

          const char* name = city["name"] | "";

          float pm25   = NAN;
          float temp   = NAN;
          float hum    = NAN;
          float windMs = NAN;

          if (!iaqi.isNull()) {
            JsonObject pm25Obj = iaqi["pm25"].as<JsonObject>();
            if (!pm25Obj.isNull()) pm25 = pm25Obj["v"] | NAN;
            JsonObject tObj = iaqi["t"].as<JsonObject>();
            if (!tObj.isNull()) temp = tObj["v"] | NAN;
            JsonObject hObj = iaqi["h"].as<JsonObject>();
            if (!hObj.isNull()) hum = hObj["v"] | NAN;
            JsonObject wObj = iaqi["w"].as<JsonObject>();
            if (!wObj.isNull()) windMs = wObj["v"] | NAN;
          }

          float windKph = isnan(windMs) ? NAN : (windMs * 3.6f);

          g_city.hasData     = true;
          g_city.name        = String(name);
          g_city.description = String("WAQI");
          g_city.tempC       = temp;
          g_city.humPct      = hum;
          g_city.windKph     = windKph;
          g_city.pm2_5       = pm25;
          g_city.aqiScore    = aqiIdx;
        }
      } else {
        Serial.printf("[WAQI] status=%s\n", status);
      }
    }
  } else {
    Serial.printf("[WAQI] HTTP error: %d (%s)\n", code, http.errorToString(code).c_str());
  }
  httpStop(http);
}
#endif // ENABLE_WAQI


static void dailyHistoryMaybePush(time_t nowEpoch);

static void historyPushSample(uint32_t nowMs) {
  if (nowMs - g_lastHistorySampleMs < HISTORY_SAMPLE_INTERVAL_MS) return;
  g_lastHistorySampleMs = nowMs;

  time_t nowEpoch = time(nullptr);
  HistorySample& s = g_history[g_historyHead];
  s.tsSec      = (nowEpoch > 0) ? (uint32_t)nowEpoch : (nowMs / 1000);
  auto q10 = [](float v) -> int16_t {
    if (isnan(v)) return 0;
    float scaled = v * 10.0f;
    if (scaled > 32767.0f) scaled = 32767.0f;
    if (scaled < -32768.0f) scaled = -32768.0f;
    return (int16_t)lrintf(scaled);
  };
  s.pm25_x10   = q10(app.pm2_5);
  s.tempC_x10  = q10(app.tempC);
  s.humPct_x10 = q10(app.humPct);
  s.voc_x10    = q10(app.vocIndex);
  s.nox_x10    = q10(app.noxIndex);
  s.aiTempC_x10= q10(app.aiTempC);
  s.aiHum_x10  = q10(app.aiHumPct);
  s.aiPress_x10= q10(app.aiPressure);
  s.aiGas_x10  = q10(app.aiGasKOhm);
  s.rpm        = (uint16_t)g_lastRPM;

  g_historyHead = (g_historyHead + 1) % HISTORY_CAPACITY;
  if (g_historyCount < HISTORY_CAPACITY) g_historyCount++;

  if (nowEpoch > 0) {
    dailyHistoryMaybePush(nowEpoch);
  }
}

static void dailyHistoryMaybePush(time_t nowEpoch) {
  if (nowEpoch <= 0) return;
  struct tm tmNow;
  memset(&tmNow, 0, sizeof(tmNow));
  localtime_r(&nowEpoch, &tmNow);
  // Derive a simple day key that is stable across reboots
  int dayKey = (tmNow.tm_year + 1900) * 10000 +
               (tmNow.tm_mon + 1) * 100 +
               tmNow.tm_mday;
  if (dayKey == g_lastDailyKey) return;

  // Compute local midnight epoch
  time_t midnight = nowEpoch -
      (tmNow.tm_hour * 3600 + tmNow.tm_min * 60 + tmNow.tm_sec);

  DailySample& d = g_daily[g_dailyHead];
  d.dayStart  = (uint32_t)midnight;
  d.pm2_5     = app.pm2_5;
  d.tempC     = app.tempC;
  d.humPct    = app.humPct;
  d.vocIndex  = app.vocIndex;
  d.noxIndex  = app.noxIndex;
  d.aiTempC   = app.aiTempC;
  d.aiHumPct  = app.aiHumPct;
  d.aiPressure= app.aiPressure;
  d.aiGasKOhm = app.aiGasKOhm;
  d.rpm       = (uint16_t)g_lastRPM;

  g_dailyHead = (g_dailyHead + 1) % DAILY_HISTORY_CAPACITY;
  if (g_dailyCount < DAILY_HISTORY_CAPACITY) g_dailyCount++;
  g_lastDailyKey = dayKey;

  // Persist to NVS so that daily history survives reboots.
  Preferences p;
  p.begin("aac", false);
  // Linearize ring buffer oldest->newest
  DailySample linear[DAILY_HISTORY_CAPACITY];
  uint8_t count = g_dailyCount;
  for (uint8_t i = 0; i < count; ++i) {
    uint8_t idx =
        (g_dailyHead + DAILY_HISTORY_CAPACITY - count + i) % DAILY_HISTORY_CAPACITY;
    linear[i] = g_daily[idx];
  }
  p.putUChar("dailyCount", count);
  if (count > 0) {
    p.putBytes("histDaily", linear, sizeof(DailySample) * count);
  }
  p.end();
}
//#if 0 // CLOUD REMOVED (local-only stabilization)
// ... unchanged context ...
// ========== Owner / Invite / Security (NVS-backed) ==========
// NOTE: İlk etapta sadece temel depolama iskeletini ekliyoruz; owner
// claim / invite / QR akışları sonraki adımlarda bu alanları kullanacak.
static String  g_ownerHash;          // NVS: owner_hash
static String  g_usersJson;          // NVS: users_json (whitelist + roller)
// Cloud shadow ACL sync version (eventual revokes when device was offline).
// NVS: acl_v (uint32)
static uint32_t g_shadowAclVersion = 0;
static uint8_t g_deviceSecret[32] = {0}; // NVS: device_secret (32 bayt rastgele)
static bool    g_deviceSecretLoaded = false;

// ===== Secure Owner Claim (BLE-only) =====
// UNOWNED: owner_exists=false -> only CLAIM/AUTH allowed, Wi-Fi kept passive.
// OWNED: owner_exists=true -> BLE commands require successful AUTH.
static bool   g_ownerExists = false;          // NVS: owner_exists
static String g_ownerPubKeyB64;               // NVS: owner_pubkey (base64, 65 bytes uncompressed P-256)
static inline bool isOwned() {
  return g_ownerExists;
}

static void setOwned(bool newOwned, const char* reason) {
  static bool inited = false;
  static bool owned = false;
  if (!inited) {
    owned = g_ownerExists;
    inited = true;
  }
  if (owned != newOwned) {
    Serial.printf("[OWNER] owned change %d -> %d reason=%s\n",
                  owned ? 1 : 0,
                  newOwned ? 1 : 0,
                  reason ? reason : "-");
    owned = newOwned;
    // Reflect ownership transition quickly to cloud/shadow payloads.
    g_cloudDirty = true;
  } else {
    Serial.printf("[OWNER] owned unchanged=%d reason=%s\n",
                  owned ? 1 : 0,
                  reason ? reason : "-");
  }
  g_ownerExists = owned;
}
static String g_setupUser;                    // NVS: setup_user (factory QR)
static String g_setupPassHashHex;             // NVS: setup_pass_hash (sha256 hex of pass)
static String g_setupPassEncB64;              // NVS: setup_pass_enc (encrypted 16B secret, base64)
static bool   g_setupPassJustGenerated = false;
static String g_pairToken;
static bool   g_pairTokenTrusted = false;
static uint32_t g_pairTokenTrustedIp = 0;

static bool hexToBytes16(const String& hex, uint8_t out[16]) {
  if (hex.length() != 32) return false;
  for (int i = 0; i < 16; ++i) {
    char c1 = hex[i * 2];
    char c2 = hex[i * 2 + 1];
    auto nyb = [](char c) -> int {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
      if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
      return -1;
    };
    int n1 = nyb(c1), n2 = nyb(c2);
    if (n1 < 0 || n2 < 0) return false;
    out[i] = (uint8_t)((n1 << 4) | n2);
  }
  return true;
}

static void handlePendingOtaDecision() {
  if (!hasPendingOtaJob()) return;

  if (g_pendingOtaRejectRequested) {
    g_pendingOtaRejectRequested = false;
    setLastOtaStatus("rejected",
                     "user_declined",
                     g_pendingOtaJob.jobId,
                     g_pendingOtaJob.targetVersion);
    (void)publishJobExecutionStatus(g_pendingOtaJob.thingName,
                                    g_pendingOtaJob.jobId,
                                    "REJECTED",
                                    "user_declined",
                                    g_pendingOtaJob.targetVersion,
                                    String(FW_VERSION));
    Serial.printf("[JOBS] ota REJECTED by user jobId=%s version=%s\n",
                  g_pendingOtaJob.jobId.c_str(),
                  g_pendingOtaJob.targetVersion.c_str());
    clearPendingOtaJob();
    g_cloudDirty = true;
    return;
  }

  if (!g_pendingOtaApproveRequested) return;
  g_pendingOtaApproveRequested = false;

  setLastOtaStatus("starting",
                   "ota_started",
                   g_pendingOtaJob.jobId,
                   g_pendingOtaJob.targetVersion);
  (void)publishJobExecutionStatus(g_pendingOtaJob.thingName,
                                  g_pendingOtaJob.jobId,
                                  "IN_PROGRESS",
                                  "ota_started",
                                  g_pendingOtaJob.targetVersion,
                                  g_pendingOtaJob.firmwareUrl.substring(0, 96));
  String err;
  String actualSha;
  size_t bytesWritten = 0;
  const bool okOta = performOtaFromUrl(g_pendingOtaJob.firmwareUrl,
                                       g_pendingOtaJob.expectedSha256,
                                       err,
                                       actualSha,
                                       bytesWritten);
  if (!okOta) {
    setLastOtaStatus("failed",
                     err.c_str(),
                     g_pendingOtaJob.jobId,
                     g_pendingOtaJob.targetVersion);
    (void)publishJobExecutionStatus(g_pendingOtaJob.thingName,
                                    g_pendingOtaJob.jobId,
                                    "FAILED",
                                    err.c_str(),
                                    actualSha.substring(0, 64),
                                    String((unsigned)bytesWritten));
    Serial.printf("[JOBS] ota FAILED after user approval jobId=%s reason=%s bytes=%u\n",
                  g_pendingOtaJob.jobId.c_str(),
                  err.c_str(),
                  (unsigned)bytesWritten);
    // Keep the OTA metadata so the app/web UI can offer a retry without
    // requiring a brand-new job to be created immediately.
    g_cloudDirty = true;
    return;
  }

  setLastOtaStatus("succeeded",
                   "ota_applied",
                   g_pendingOtaJob.jobId,
                   g_pendingOtaJob.targetVersion);
  (void)publishJobExecutionStatus(g_pendingOtaJob.thingName,
                                  g_pendingOtaJob.jobId,
                                  "SUCCEEDED",
                                  "ota_applied",
                                  g_pendingOtaJob.targetVersion,
                                  actualSha.substring(0, 64));
  Serial.printf("[JOBS] ota SUCCEEDED after user approval jobId=%s version=%s bytes=%u\n",
                g_pendingOtaJob.jobId.c_str(),
                g_pendingOtaJob.targetVersion.c_str(),
                (unsigned)bytesWritten);
  clearPendingOtaJob();
  g_cloudDirty = true;
  delay(500);
  ESP.restart();
}

static bool hexToBytes(const String& hex, std::vector<uint8_t>& out) {
  out.clear();
  const int len = hex.length();
  if (len == 0 || (len % 2) != 0) return false;
  out.reserve((size_t)len / 2);
  auto nyb = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
  };
  for (int i = 0; i < len; i += 2) {
    const int n1 = nyb(hex[i]);
    const int n2 = nyb(hex[i + 1]);
    if (n1 < 0 || n2 < 0) return false;
    out.push_back((uint8_t)((n1 << 4) | n2));
  }
  return true;
}

static String bytes16ToHex(const uint8_t in[16]) {
  String hex;
  hex.reserve(32);
  for (int i = 0; i < 16; ++i) {
    char buf[3];
    snprintf(buf, sizeof(buf), "%02X", in[i]);
    hex += buf;
  }
  return hex;
}

static bool deriveSetupKeystream(uint8_t out32[32]) {
  if (!g_deviceSecretLoaded) return false;
#if defined(ARDUINO_ARCH_ESP32)
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  if (mbedtls_sha256_update_ret(&ctx, g_deviceSecret, sizeof(g_deviceSecret)) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  const char* tag = "SETUPPASS|v1";
  if (mbedtls_sha256_update_ret(&ctx, (const uint8_t*)tag, strlen(tag)) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  if (mbedtls_sha256_finish_ret(&ctx, out32) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  mbedtls_sha256_free(&ctx);
  return true;
#else
  (void)out32;
  return false;
#endif
}

// Forward declarations (base64 helpers are defined later in this file)
static String base64Encode(const uint8_t* data, size_t len);
static bool base64Decode(const String& b64, std::vector<uint8_t>& out);
static String sha256HexOfBytes(const uint8_t* data, size_t len);

static bool encryptSetupSecret16(const uint8_t plain16[16], String& outB64) {
  uint8_t ks[32];
  if (!deriveSetupKeystream(ks)) return false;
  uint8_t enc[16];
  for (int i = 0; i < 16; ++i) enc[i] = plain16[i] ^ ks[i];
  outB64 = base64Encode(enc, sizeof(enc));
  return outB64.length() > 0;
}

static bool decryptSetupSecret16(const String& encB64, uint8_t outPlain16[16]) {
  std::vector<uint8_t> enc;
  if (!base64Decode(encB64, enc) || enc.size() != 16) return false;
  uint8_t ks[32];
  if (!deriveSetupKeystream(ks)) return false;
  for (int i = 0; i < 16; ++i) outPlain16[i] = enc[i] ^ ks[i];
  return true;
}

// ✅ WiFi şifre encryption için key derivation
static bool deriveWifiEncryptionKey(uint8_t out32[32]) {
  if (!g_deviceSecretLoaded) return false;
#if defined(ARDUINO_ARCH_ESP32)
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  if (mbedtls_sha256_update_ret(&ctx, g_deviceSecret, sizeof(g_deviceSecret)) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  const char* tag = "WIFI_ENCRYPT|v1";
  if (mbedtls_sha256_update_ret(&ctx, (const uint8_t*)tag, strlen(tag)) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  String id6 = shortChipId();
  if (mbedtls_sha256_update_ret(&ctx, (const uint8_t*)id6.c_str(), id6.length()) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  if (mbedtls_sha256_finish_ret(&ctx, out32) != 0) {
    mbedtls_sha256_free(&ctx);
    return false;
  }
  mbedtls_sha256_free(&ctx);
  return true;
#else
  (void)out32;
  return false;
#endif
}

static bool deriveBleKeypairFromPairToken(
    const String& pairTokenHex,
    mbedtls_ecp_keypair* outKeypair,
    uint8_t outPub65[65]) {
  if (!outKeypair || !outPub65) return false;
  std::vector<uint8_t> tokenBytes;
  if (!hexToBytes(pairTokenHex, tokenBytes) || tokenBytes.empty()) return false;
#if defined(ARDUINO_ARCH_ESP32)
  uint8_t seed[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  const bool ok =
      (mbedtls_sha256_starts_ret(&ctx, 0) == 0) &&
      (mbedtls_sha256_update_ret(&ctx, tokenBytes.data(), tokenBytes.size()) == 0) &&
      (mbedtls_sha256_finish_ret(&ctx, seed) == 0);
  mbedtls_sha256_free(&ctx);
  if (!ok) return false;

  mbedtls_ecp_keypair_init(outKeypair);
  if (mbedtls_ecp_group_load(&outKeypair->grp, MBEDTLS_ECP_DP_SECP256R1) != 0) {
    mbedtls_ecp_keypair_free(outKeypair);
    return false;
  }

  mbedtls_mpi seedMpi;
  mbedtls_mpi_init(&seedMpi);
  bool derivedOk = false;
  if (mbedtls_mpi_read_binary(&seedMpi, seed, sizeof(seed)) == 0 &&
      mbedtls_mpi_mod_mpi(&outKeypair->d, &seedMpi, &outKeypair->grp.N) == 0) {
    if (mbedtls_mpi_cmp_int(&outKeypair->d, 0) == 0) {
      mbedtls_mpi_lset(&outKeypair->d, 1);
    }
    if (mbedtls_ecp_mul(&outKeypair->grp,
                        &outKeypair->Q,
                        &outKeypair->d,
                        &outKeypair->grp.G,
                        NULL,
                        NULL) == 0) {
      outPub65[0] = 0x04;
      if (mbedtls_mpi_write_binary(&outKeypair->Q.X, outPub65 + 1, 32) == 0 &&
          mbedtls_mpi_write_binary(&outKeypair->Q.Y, outPub65 + 33, 32) == 0) {
        derivedOk = true;
      }
    }
  }
  mbedtls_mpi_free(&seedMpi);
  if (!derivedOk) {
    mbedtls_ecp_keypair_free(outKeypair);
    return false;
  }
  return true;
#else
  (void)pairTokenHex;
  return false;
#endif
}

// ✅ WiFi şifresini AES-256-GCM ile şifrele
static bool encryptWifiPassword(const String& plain, String& outB64) {
  if (plain.length() == 0) return false;
#if defined(ARDUINO_ARCH_ESP32)
  uint8_t key[32];
  if (!deriveWifiEncryptionKey(key)) return false;
  
  // IV (12 bytes for GCM)
  uint8_t iv[12];
  esp_fill_random(iv, 12);
  
  // Plaintext
  const size_t plainLen = plain.length();
  if (plainLen > 64) return false; // Max WiFi password length
  const uint8_t* plainBytes = (const uint8_t*)plain.c_str();
  
  // Ciphertext (same length as plaintext for GCM)
  uint8_t* cipher = (uint8_t*)malloc(plainLen);
  if (!cipher) return false;
  uint8_t tag[16];
  
  mbedtls_gcm_context ctx;
  mbedtls_gcm_init(&ctx);
  
  bool ok = false;
  if (mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, 32 * 8) == 0 &&
      mbedtls_gcm_crypt_and_tag(&ctx, MBEDTLS_GCM_ENCRYPT,
                                 plainLen, iv, 12, NULL, 0,
                                 plainBytes, cipher, 16, tag) == 0) {
    // Format: base64(iv(12) + ciphertext + tag(16))
    size_t totalLen = 12 + plainLen + 16;
    uint8_t* combined = (uint8_t*)malloc(totalLen);
    if (combined) {
      memcpy(combined, iv, 12);
      memcpy(combined + 12, cipher, plainLen);
      memcpy(combined + 12 + plainLen, tag, 16);
      outB64 = base64Encode(combined, totalLen);
      free(combined);
      ok = (outB64.length() > 0);
    }
  }
  
  free(cipher);
  mbedtls_gcm_free(&ctx);
  return ok;
#else
  (void)plain; (void)outB64;
  return false;
#endif
}

// ✅ WiFi şifresini AES-256-GCM ile deşifrele
static bool decryptWifiPassword(const String& encB64, String& outPlain) {
  if (encB64.length() == 0) return false;
#if defined(ARDUINO_ARCH_ESP32)
  std::vector<uint8_t> combined;
  if (!base64Decode(encB64, combined) || combined.size() < 28) return false; // min: 12 IV + 0 data + 16 tag
  
  uint8_t key[32];
  if (!deriveWifiEncryptionKey(key)) return false;
  
  // Extract IV, ciphertext, tag
  uint8_t iv[12];
  memcpy(iv, combined.data(), 12);
  size_t cipherLen = combined.size() - 12 - 16;
  if (cipherLen == 0 || cipherLen > 256) return false; // Max WiFi password length
  uint8_t tag[16];
  memcpy(tag, combined.data() + 12 + cipherLen, 16);
  
  uint8_t* plain = (uint8_t*)malloc(cipherLen + 1); // +1 for null terminator
  if (!plain) return false;
  plain[cipherLen] = 0; // Null terminator
  
  mbedtls_gcm_context ctx;
  mbedtls_gcm_init(&ctx);
  
  bool ok = false;
  if (mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, 32 * 8) == 0 &&
      mbedtls_gcm_auth_decrypt(&ctx, cipherLen, iv, 12, NULL, 0,
                               tag, 16, combined.data() + 12, plain) == 0) {
    outPlain = String((char*)plain);
    ok = true;
  }
  
  free(plain);
  mbedtls_gcm_free(&ctx);
  return ok;
#else
  (void)encB64; (void)outPlain;
  return false;
#endif
}
static bool   g_bleAuthed = false;            // session flag (clears on disconnect)
static String g_bleNonceB64;                  // current session nonce (base64)
static uint16_t g_bleConnHandle = BLE_HS_CONN_HANDLE_NONE;
static uint32_t g_bleAuthDeadlineMs = 0;      // if non-zero, disconnect when now >= deadline and not authed
static uint32_t g_bleOwnerAuthGraceUntilMs = 0;
static uint32_t g_bleConnectedAtMs = 0;
static uint32_t g_blePolicyHoldUntilMs = 0;   // keep BLE ON while a session/command is active
static uint32_t g_bleCloudReadySinceMs = 0;   // require post-cloud grace before disabling BLE
static bool   g_bleApStartPending = false;    // run startAP outside BLE callback

static CmdSource g_lastCmdSource = CmdSource::UNKNOWN;

// Defaults (can be overridden from config.h if desired)
#ifndef FACTORY_SETUP_USER
#define FACTORY_SETUP_USER "AAC"
#endif
#ifndef FACTORY_SETUP_PASS
#define FACTORY_SETUP_PASS ""
#endif

static bool equalsIgnoreCaseStr(const String& a, const String& b) {
  if (a.length() != b.length()) return false;
  for (size_t i = 0; i < a.length(); ++i) {
    if (tolower((unsigned char)a[i]) != tolower((unsigned char)b[i])) return false;
  }
  return true;
}

static String sha256HexOfString(const String& s) {
#if defined(ARDUINO_ARCH_ESP32)
  uint8_t out[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_update_ret(&ctx, (const uint8_t*)s.c_str(), (size_t)s.length()) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_finish_ret(&ctx, out) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  mbedtls_sha256_free(&ctx);
  String hex;
  hex.reserve(64);
  for (size_t i = 0; i < sizeof(out); ++i) {
    char buf[3];
    snprintf(buf, sizeof(buf), "%02x", out[i]);
    hex += buf;
  }
  return hex;
#else
  return String();
#endif
}

static String sha256Fp8HexOfString(const String& s) {
  const String hex = sha256HexOfString(s);
  if (hex.length() >= 16) return hex.substring(0, 16);
  return hex;
}

static bool hasPemHeader(const String& s, const char* header) {
  return s.indexOf(header) >= 0;
}

static bool isLikelyCertPem(const String& s) {
  return hasPemHeader(s, "BEGIN CERTIFICATE") && hasPemHeader(s, "END CERTIFICATE");
}

static bool isLikelyKeyPem(const String& s) {
  return (hasPemHeader(s, "BEGIN PRIVATE KEY") && hasPemHeader(s, "END PRIVATE KEY")) ||
         (hasPemHeader(s, "BEGIN RSA PRIVATE KEY") && hasPemHeader(s, "END RSA PRIVATE KEY")) ||
         (hasPemHeader(s, "BEGIN EC PRIVATE KEY") && hasPemHeader(s, "END EC PRIVATE KEY"));
}

#if 1  // always include base64 helpers (used by BLE/local security too)

static String base64Encode(const uint8_t* data, size_t len) {
#if defined(ARDUINO_ARCH_ESP32)
  size_t outLen = 0;
  // First call to get size
  mbedtls_base64_encode(nullptr, 0, &outLen, data, len);
  String out;
  out.reserve(outLen + 1);
  std::unique_ptr<uint8_t[]> buf(new uint8_t[outLen + 1]);
  if (mbedtls_base64_encode(buf.get(), outLen + 1, &outLen, data, len) != 0) return String();
  buf.get()[outLen] = 0;
  out = (const char*)buf.get();
  out.trim();
  return out;
#else
  (void)data; (void)len;
  return String();
#endif
}

static bool base64Decode(const String& b64, std::vector<uint8_t>& out) {
#if defined(ARDUINO_ARCH_ESP32)
  out.clear();
  String s = b64;
  s.trim();
  if (!s.length()) return false;

  // Normalize base64:
  // - strip any non-base64 characters (some transports may inject stray bytes)
  // - accept URL-safe variants by mapping '-'->'+' and '_'->'/'
  String clean;
  clean.reserve(s.length());
  for (size_t i = 0; i < (size_t)s.length(); ++i) {
    char ch = s[i];
    if (ch == '-') ch = '+';
    if (ch == '_') ch = '/';
    const bool ok =
        (ch >= 'A' && ch <= 'Z') ||
        (ch >= 'a' && ch <= 'z') ||
        (ch >= '0' && ch <= '9') ||
        (ch == '+') || (ch == '/') || (ch == '=');
    if (ok) clean += ch;
  }
  if (clean.length() != s.length()) {
    Serial.printf("[B64] normalized input len=%u -> %u\n", (unsigned)s.length(), (unsigned)clean.length());
  }
  s = clean;
  s.trim();
  if (!s.length()) return false;

  auto decodePortable = [](const String& in, std::vector<uint8_t>& outBytes) -> bool {
    auto val = [](uint8_t c) -> int {
      if (c >= 'A' && c <= 'Z') return (int)(c - 'A');
      if (c >= 'a' && c <= 'z') return (int)(c - 'a') + 26;
      if (c >= '0' && c <= '9') return (int)(c - '0') + 52;
      if (c == '+') return 62;
      if (c == '/') return 63;
      return -1;
    };

    outBytes.clear();
    int quartet[4] = {0, 0, 0, 0};
    int q = 0;
    int pad = 0;

    for (size_t i = 0; i < (size_t)in.length(); ++i) {
      const uint8_t c = (uint8_t)in[i];
      if (c == '=') {
        quartet[q++] = 0;
        pad++;
      } else {
        const int v = val(c);
        if (v < 0) return false;
        quartet[q++] = v;
      }

      if (q == 4) {
        const uint32_t triple =
            ((uint32_t)quartet[0] << 18) |
            ((uint32_t)quartet[1] << 12) |
            ((uint32_t)quartet[2] << 6) |
            (uint32_t)quartet[3];
        outBytes.push_back((uint8_t)((triple >> 16) & 0xFF));
        if (pad < 2) outBytes.push_back((uint8_t)((triple >> 8) & 0xFF));
        if (pad < 1) outBytes.push_back((uint8_t)(triple & 0xFF));
        q = 0;
        pad = 0;
      }
    }
    return q == 0;
  };

  size_t olen = 0;
  // First call to get size
  int r0 = mbedtls_base64_decode(nullptr, 0, &olen, (const uint8_t*)s.c_str(), s.length());
  if (r0 < 0 && r0 != MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL) {
    Serial.printf("[B64] decode size failed ret=%d len=%u\n", r0, (unsigned)s.length());
    // Fallback: portable decoder (some builds return INVALID_CHARACTER unexpectedly)
    if (decodePortable(s, out)) {
      Serial.printf("[B64] fallback portable decode OK len=%u\n", (unsigned)out.size());
      return true;
    }
    return false;
  }
  out.resize(olen);
  int r1 = mbedtls_base64_decode(out.data(), out.size(), &olen, (const uint8_t*)s.c_str(), s.length());
  if (r1 != 0) {
    Serial.printf("[B64] decode failed ret=%d len=%u\n", r1, (unsigned)s.length());
    out.clear();
    if (decodePortable(s, out)) {
      Serial.printf("[B64] fallback portable decode OK len=%u\n", (unsigned)out.size());
      return true;
    }
    return false;
  }
  out.resize(olen);
  return true;
#else
  (void)b64; (void)out;
  return false;
#endif
}

#endif // base64 helpers
static String makeNonceB64() {
  uint8_t raw[16];
  for (size_t i = 0; i < sizeof(raw); ++i) raw[i] = (uint8_t)(esp_random() & 0xFF);
  return base64Encode(raw, sizeof(raw));
}

static String bytesToHex(const uint8_t* data, size_t len) {
  static const char* kHex = "0123456789abcdef";
  String out;
  out.reserve(len * 2);
  for (size_t i = 0; i < len; ++i) {
    out += kHex[(data[i] >> 4) & 0xF];
    out += kHex[data[i] & 0xF];
  }
  return out;
}

// BLE session authorization role
enum class BleRole : uint8_t { NONE = 0, SETUP = 1, GUEST = 2, USER = 3, OWNER = 4 };

static inline const char* roleToStr(BleRole r) {
  switch (r) {
    case BleRole::OWNER: return "OWNER";
    case BleRole::USER: return "USER";
    case BleRole::GUEST: return "GUEST";
    case BleRole::SETUP: return "SETUP";
    default: return "NONE";
  }
}

static inline BleRole roleFromStr(const char* role) {
  if (!role || !*role) return BleRole::USER;
  if (equalsIgnoreCaseStr(String(role), "OWNER")) return BleRole::OWNER;
  if (equalsIgnoreCaseStr(String(role), "GUEST")) return BleRole::GUEST;
  if (equalsIgnoreCaseStr(String(role), "SETUP")) return BleRole::SETUP;
  if (equalsIgnoreCaseStr(String(role), "NONE")) return BleRole::NONE;
  return BleRole::USER;
}
static bool loadUsersArray(JsonDocument& doc, JsonArray& outArr);
static inline bool pairingWindowActive(uint32_t nowMs);
static inline bool ownerRotateWindowActive(uint32_t nowMs);

#ifndef BLE_AUTH_DEBUG_STATIC_KEY
#define BLE_AUTH_DEBUG_STATIC_KEY 0
#endif
static const char* kBleAuthDebugPubKeyB64 =
    "BNj61d6GfJrUA+dFQEqdaCAnRrkhme/X112gd3lVtaGJH5Wy0TusECd6TdxpE9hubJuXu6tPlufIab/AyscWwp0=";

static bool verifyEcdsaP256Signature(const String& pubKeyB64,
                                     const uint8_t* msgBytes,
                                     size_t msgLen,
                                     const String& sigB64) {
#if defined(ARDUINO_ARCH_ESP32)
  std::vector<uint8_t> pub, sig;
  if (!base64Decode(pubKeyB64, pub) || pub.size() != 65) return false; // 0x04 || X(32) || Y(32)
  if (!base64Decode(sigB64, sig)) return false;
  if (!msgBytes || msgLen == 0) return false;

  uint8_t hash[32];
  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  if (mbedtls_sha256_starts_ret(&sha, 0) != 0 ||
      mbedtls_sha256_update_ret(&sha, msgBytes, msgLen) != 0 ||
      mbedtls_sha256_finish_ret(&sha, hash) != 0) {
    mbedtls_sha256_free(&sha);
    return false;
  }
  mbedtls_sha256_free(&sha);

  mbedtls_ecp_group grp;
  mbedtls_ecp_point Q;
  mbedtls_mpi r, s;
  mbedtls_ecp_group_init(&grp);
  mbedtls_ecp_point_init(&Q);
  mbedtls_mpi_init(&r);
  mbedtls_mpi_init(&s);

  bool ok = false;
  if (mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_SECP256R1) == 0 &&
      mbedtls_ecp_point_read_binary(&grp, &Q, pub.data(), pub.size()) == 0) {
    if (sig.size() == 64) {
      if (mbedtls_mpi_read_binary(&r, sig.data(), 32) == 0 &&
          mbedtls_mpi_read_binary(&s, sig.data() + 32, 32) == 0) {
        const int vr = mbedtls_ecdsa_verify(&grp, hash, sizeof(hash), &Q, &r, &s);
        ok = (vr == 0);
      }
    } else {
      mbedtls_ecdsa_context ctx;
      mbedtls_ecdsa_init(&ctx);
      if (mbedtls_ecp_group_load(&ctx.grp, MBEDTLS_ECP_DP_SECP256R1) == 0 &&
          mbedtls_ecp_point_read_binary(&ctx.grp, &ctx.Q, pub.data(), pub.size()) == 0) {
        const int vr = mbedtls_ecdsa_read_signature(
            &ctx,
            hash,
            sizeof(hash),
            sig.data(),
            sig.size());
        ok = (vr == 0);
      }
      mbedtls_ecdsa_free(&ctx);
    }
  }

  mbedtls_mpi_free(&s);
  mbedtls_mpi_free(&r);
  mbedtls_ecp_point_free(&Q);
  mbedtls_ecp_group_free(&grp);
  return ok;
#else
  (void)pubKeyB64; (void)msgBytes; (void)msgLen; (void)sigB64;
  return false;
#endif
}

// Compatibility wrapper: some modules call the "OverBytes" name.
// Keep a single implementation to avoid duplicate symbols.
static bool verifyEcdsaP256SignatureOverBytes(const String& pubKeyB64,
                                             const uint8_t* msg,
                                             size_t msgLen,
                                             const String& sigB64) {
  return verifyEcdsaP256Signature(pubKeyB64, msg, msgLen, sigB64);
}

static void logBleAuthPubKeyDebug(const String& pubKeyB64) {
  std::vector<uint8_t> pub;
  size_t pubLen = 0;
  String fp;
  if (base64Decode(pubKeyB64, pub)) {
    pubLen = pub.size();
    const String hex = sha256HexOfBytes(pub.data(), pub.size());
    if (hex.length() >= 16) {
      fp = hex.substring(0, 16);
    } else {
      fp = hex;
    }
  }
  Serial.printf("[AUTH][BLE] pubKeyLen=%u\n", (unsigned)pubLen);
  Serial.printf("[AUTH][BLE] pubKeyFp=%s\n", fp.length() ? fp.c_str() : "");
}

static String sha256HexFromPubKeyB64(const String& pubKeyB64) {
  std::vector<uint8_t> pub;
  if (!base64Decode(pubKeyB64, pub)) return String();
  return sha256HexOfBytes(pub.data(), pub.size());
}

static String extractUserIdHashFromDoc(const JsonDocument& doc) {
  const char* id =
      doc["userIdHash"] | doc["user_id_hash"] | doc["userId"] | doc["uid"] | "";
  if (id && id[0]) return String(id);
  const char* pub =
      doc["user_pubkey"] | doc["userPubKey"] | doc["pubkey"] | doc["pubKey"] | "";
  if (pub && pub[0]) {
    return sha256HexFromPubKeyB64(String(pub));
  }
  return String();
}

static BleRole roleFromUserIdHash(const String& userIdHash, String& outUserIdHash) {
  static String s_lastRoleMissHash;
  outUserIdHash.clear();
  if (!userIdHash.length()) return BleRole::NONE;
  const String ownerHash = sha256HexFromPubKeyB64(g_ownerPubKeyB64);
  if (ownerHash.length() && ownerHash.equalsIgnoreCase(userIdHash)) {
    outUserIdHash = ownerHash;
    return BleRole::OWNER;
  }
  // Fallback for cloud-only ownership paths where owner pubkey is not present
  // on device yet, but owner hash is known (legacy/cloud ACL sync).
  if (g_ownerHash.length() && g_ownerHash.equalsIgnoreCase(userIdHash)) {
    outUserIdHash = g_ownerHash;
    return BleRole::OWNER;
  }
  if (!g_usersJson.length()) {
    if (!s_lastRoleMissHash.equalsIgnoreCase(userIdHash)) {
      s_lastRoleMissHash = userIdHash;
      Serial.printf("[ROLE] userIdHash not found (usersJson empty) idHash=%s ownerHashLen=%u\n",
                    userIdHash.c_str(),
                    (unsigned)ownerHash.length());
    }
    return BleRole::NONE;
  }
  JsonDocument usersDoc;
  DeserializationError err = deserializeJson(usersDoc, g_usersJson);
  if (err || !usersDoc.is<JsonArray>()) {
    if (!s_lastRoleMissHash.equalsIgnoreCase(userIdHash)) {
      s_lastRoleMissHash = userIdHash;
      const String head = g_usersJson.substring(0, 160);
      Serial.printf("[ROLE] userIdHash not found (usersJson parse fail) idHash=%s err=%d usersJsonLen=%u head=%s\n",
                    userIdHash.c_str(),
                    (int)err.code(),
                    (unsigned)g_usersJson.length(),
                    head.c_str());
    }
    return BleRole::NONE;
  }
  JsonArray arr = usersDoc.as<JsonArray>();
  for (JsonVariant v : arr) {
    if (!v.is<JsonObject>()) continue;
    JsonObject o = v.as<JsonObject>();
    const char* id = o["id"] | o["userIdHash"] | "";
    if (id && *id && userIdHash.equalsIgnoreCase(String(id))) {
      const char* roleStr = o["role"] | "USER";
      BleRole r = roleFromStr(roleStr);
      if (r == BleRole::OWNER) r = BleRole::USER;
      outUserIdHash = String(id);
      return r;
    }
  }
  if (!s_lastRoleMissHash.equalsIgnoreCase(userIdHash)) {
    s_lastRoleMissHash = userIdHash;
    const String head = g_usersJson.substring(0, 160);
    Serial.printf("[ROLE] userIdHash not found (usersJson no match) idHash=%s ownerHashLen=%u users=%u head=%s\n",
                  userIdHash.c_str(),
                  (unsigned)ownerHash.length(),
                  (unsigned)arr.size(),
                  head.c_str());
  }
  return BleRole::NONE;
}

static bool verifyAnyTrustedSignature(const uint8_t* msgBytes,
                                      size_t msgLen,
                                      const String& sigB64,
                                      BleRole& outRole,
                                      String& outUserIdHash) {
  outRole = BleRole::NONE;
  outUserIdHash.clear();

#if BLE_AUTH_DEBUG_STATIC_KEY
  logBleAuthPubKeyDebug(String(kBleAuthDebugPubKeyB64));
  if (verifyEcdsaP256Signature(String(kBleAuthDebugPubKeyB64), msgBytes, msgLen, sigB64)) {
    outRole = BleRole::OWNER;
    return true;
  }
#endif

  // Owner key always wins.
  if (g_ownerPubKeyB64.length()) {
    logBleAuthPubKeyDebug(g_ownerPubKeyB64);
    if (verifyEcdsaP256Signature(g_ownerPubKeyB64, msgBytes, msgLen, sigB64)) {
      outRole = BleRole::OWNER;
      return true;
    }
  }

  // Users list (invited phones) may also authenticate.
  if (!g_usersJson.length()) return false;

  JsonDocument doc;
  JsonArray arr;
  loadUsersArray(doc, arr);
  for (JsonVariant v : arr) {
    JsonObject o = v.as<JsonObject>();
    const char* pub = o["pubkey"] | o["pubKey"] | "";
    if (!pub || !pub[0]) continue;
    logBleAuthPubKeyDebug(String(pub));
    if (verifyEcdsaP256Signature(String(pub), msgBytes, msgLen, sigB64)) {
      const char* id = o["id"] | o["userIdHash"] | "";
      const char* roleStr = o["role"] | "USER";
      outUserIdHash = id ? String(id) : String();
      BleRole r = roleFromStr(roleStr);
      // Do not allow promoting to OWNER via users_json.
      if (r == BleRole::OWNER || r == BleRole::SETUP || r == BleRole::NONE) {
        r = BleRole::USER;
      }
      outRole = r;
      return true;
    }
  }
  return false;
}

static bool verifySetupUserPass(const char* user, const char* pass) {
  if (!user || !user[0] || !pass || !pass[0]) return false;
  const String userStr = String(user);
  const String passStr = String(pass);

  if (equalsIgnoreCaseStr(userStr, g_setupUser)) {
    const String h = sha256HexOfString(passStr);
    if (!h.length()) return false;
    if (equalsIgnoreCaseStr(h, g_setupPassHashHex)) return true;
  }

  // IR-first QR-less recovery fallback:
  // Accept legacy deterministic setup credentials only while a physical-presence
  // recovery window is active.
  const uint32_t nowMs = millis();
  const bool recoveryWindow =
      pairingWindowActive(nowMs) || ownerRotateWindowActive(nowMs);
  if (recoveryWindow && equalsIgnoreCaseStr(userStr, String(FACTORY_SETUP_USER))) {
    const String legacyPass = String("aac") + shortChipId();
    if (passStr.equalsIgnoreCase(legacyPass)) {
      Serial.println("[AUTH] setup credentials accepted via legacy fallback");
      return true;
    }
  }

  return false;
}

// Brute-force protection for factory setup credentials (AUTH_SETUP / CLAIM_REQUEST).
static uint8_t  g_setupAuthFailCount = 0;
static uint32_t g_setupAuthLockUntilMs = 0;
static constexpr uint8_t  SETUP_AUTH_MAX_FAILS = 5;
static constexpr uint32_t SETUP_AUTH_LOCK_MS = 120000UL; // 2 min

static bool setupAuthLocked(uint32_t nowMs, uint32_t* outRetryMs = nullptr) {
  if (outRetryMs) *outRetryMs = 0;
  if (g_setupAuthLockUntilMs == 0) return false;
  if ((int32_t)(g_setupAuthLockUntilMs - nowMs) <= 0) {
    g_setupAuthLockUntilMs = 0;
    g_setupAuthFailCount = 0;
    return false;
  }
  if (outRetryMs) *outRetryMs = g_setupAuthLockUntilMs - nowMs;
  return true;
}

static void noteSetupAuthFailure(uint32_t nowMs) {
  if (g_setupAuthLockUntilMs != 0 && (int32_t)(g_setupAuthLockUntilMs - nowMs) > 0) {
    return;
  }
  if (g_setupAuthFailCount < 255) g_setupAuthFailCount++;
  if (g_setupAuthFailCount >= SETUP_AUTH_MAX_FAILS) {
    g_setupAuthLockUntilMs = nowMs + SETUP_AUTH_LOCK_MS;
    g_setupAuthFailCount = 0;
    Serial.printf("[AUTH] setup credentials locked for %lus\n",
                  (unsigned long)(SETUP_AUTH_LOCK_MS / 1000UL));
  }
}

static void noteSetupAuthSuccess() {
  g_setupAuthFailCount = 0;
  g_setupAuthLockUntilMs = 0;
}

static bool    g_setupDone          = false; // NVS: setup_done
// Aktif davet/join penceresi (RAM, persist edilmez)
static String   g_joinInviteId;
static String   g_joinRole;
static uint32_t g_joinUntilMs = 0;
// SoftAP oturumu için kısa ömürlü session token (X-Session-Token)
static String   g_apSessionToken;
static String   g_apSessionNonce;
static uint32_t g_apSessionUntilMs = 0;
static bool     g_apSessionBound = false;
static uint32_t g_apSessionBindIp = 0;
static uint32_t g_apSessionBindUa = 0;
static bool     g_apSessionOpenedWithQr = false; // trusted auth ile açıldı mı?
static bool     g_localControlReady = false;     // STA LAN uzerinden app session basariyla acildi mi?
static constexpr uint32_t AP_GRACE_MS = 180000; // 3 min SoftAP grace after STA connects
static uint32_t g_apGraceUntilMs = 0;
static uint32_t g_apStopDueMs = 0;
// Owner recovery: physical-presence window to allow rotating owner via factory QR.
static uint32_t g_ownerRotateUntilMs = 0;
// Son üretilen davet (ephemeral, sadece durum JSON'u üzerinden app'e iletilir)
static String   g_lastInviteJson;
// BLE eşleşme/pairing penceresi (sadece belirli zamanlarda reklam yap)
static bool     g_pairingWindowActive = false;
static uint32_t g_pairingWindowUntilMs = 0;
static BleRole  g_bleRole = BleRole::NONE;
static String   g_bleUserIdHash; // for USER role (sha256(pubkey) hex)
// HTTP-auth session role (set per-request by authorizeRequest)
static BleRole  g_httpRole = BleRole::NONE;
static String   g_httpUserIdHash;
enum class HttpAuthMode : uint8_t { NONE = 0, PAIR_TOKEN = 1, SESSION = 2, SIGNATURE = 3 };
static HttpAuthMode g_httpAuthMode = HttpAuthMode::NONE;
// MQTT-auth role (resolved from userIdHash per MQTT command)
static BleRole  g_mqttRole = BleRole::NONE;

static inline BleRole effectiveRole(BleRole r) {
  return (r == BleRole::SETUP) ? BleRole::OWNER : r;
}

static inline bool pairingWindowActive(uint32_t nowMs) {
  if (!g_pairingWindowActive || g_pairingWindowUntilMs == 0) return false;
  if ((int32_t)(g_pairingWindowUntilMs - nowMs) <= 0) {
    g_pairingWindowActive = false;
    g_pairingWindowUntilMs = 0;
    return false;
  }
  return true;
}

static void openPairingWindow(uint32_t ttlMs) {
  if (ttlMs == 0) return;
  uint32_t nowMs = millis();
  g_pairingWindowActive  = true;
  g_pairingWindowUntilMs = nowMs + ttlMs;
  Serial.printf("[BLE] pairing window opened ttlMs=%u\n", (unsigned)ttlMs);
}

static inline bool ownerRotateWindowActive(uint32_t nowMs) {
  if (g_ownerRotateUntilMs == 0) return false;
  if ((int32_t)(g_ownerRotateUntilMs - nowMs) <= 0) {
    g_ownerRotateUntilMs = 0;
    return false;
  }
  return true;
}

static inline uint32_t remainingWindowMs(uint32_t untilMs, uint32_t nowMs) {
  if (untilMs == 0) return 0;
  const int32_t diff = (int32_t)(untilMs - nowMs);
  return (diff > 0) ? (uint32_t)diff : 0;
}

static uint32_t softRecoveryRemainingMs(uint32_t nowMs) {
  uint32_t remainMs = 0;
  if (pairingWindowActive(nowMs)) {
    const uint32_t pairingRemain = remainingWindowMs(g_pairingWindowUntilMs, nowMs);
    if (pairingRemain > remainMs) remainMs = pairingRemain;
  }
  if (ownerRotateWindowActive(nowMs)) {
    const uint32_t ownerRemain = remainingWindowMs(g_ownerRotateUntilMs, nowMs);
    if (ownerRemain > remainMs) remainMs = ownerRemain;
  }
  const uint32_t apRemain = remainingWindowMs(g_apSessionUntilMs, nowMs);
  if (apRemain > remainMs) remainMs = apRemain;
  return remainMs;
}

static void openOwnerRotateWindow(uint32_t ttlMs) {
  if (ttlMs == 0) return;
  uint32_t nowMs = millis();
  g_ownerRotateUntilMs = nowMs + ttlMs;
  Serial.printf("[OWNER] rotate window opened ttlMs=%u\n", (unsigned)ttlMs);
}

static void closeTransientOnboardingState() {
  g_pairingWindowActive = false;
  g_pairingWindowUntilMs = 0;
  g_ownerRotateUntilMs = 0;
  g_apSessionUntilMs = 0;
  g_apSessionOpenedWithQr = false;
  g_apSessionBound = false;
  g_apSessionBindIp = 0;
  g_apSessionBindUa = 0;
  g_apSessionToken = "";
  g_apSessionNonce = "";
}

// Basit HMAC-SHA256 helper'ı: device_secret ile invite imzasını doğrulamak için kullanılır.
static bool computeHmacSha256(const uint8_t* key,
                              size_t keyLen,
                              const uint8_t* data,
                              size_t dataLen,
                              uint8_t out[32]) {
#if defined(ARDUINO_ARCH_ESP32)
  mbedtls_md_context_t ctx;
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!info) return false;
  mbedtls_md_init(&ctx);
  if (mbedtls_md_setup(&ctx, info, 1) != 0) {
    mbedtls_md_free(&ctx);
    return false;
  }
  if (mbedtls_md_hmac_starts(&ctx, key, keyLen) != 0 ||
      mbedtls_md_hmac_update(&ctx, data, dataLen) != 0 ||
      mbedtls_md_hmac_finish(&ctx, out) != 0) {
    mbedtls_md_free(&ctx);
    return false;
  }
  mbedtls_md_free(&ctx);
  return true;
#else
  (void)key; (void)keyLen; (void)data; (void)dataLen; (void)out;
  return false;
#endif
}

static String computeOwnerHash(const String& ownerId) {
  uint8_t out[32];
  if (!g_deviceSecretLoaded) {
    Serial.println("[OWNER] computeOwnerHash: device_secret not loaded");
    return String();
  }
  // Deterministic, low-dependency hash:
  // SHA256(device_secret || "OWNER|" || ownerId)
#if defined(ARDUINO_ARCH_ESP32)
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_update_ret(&ctx, g_deviceSecret, sizeof(g_deviceSecret)) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  const char* prefix = "OWNER|";
  if (mbedtls_sha256_update_ret(&ctx, (const uint8_t*)prefix, strlen(prefix)) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_update_ret(&ctx, (const uint8_t*)ownerId.c_str(), (size_t)ownerId.length()) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_finish_ret(&ctx, out) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  mbedtls_sha256_free(&ctx);
#else
  return String();
#endif
  String macHex;
  macHex.reserve(64);
  for (size_t i = 0; i < sizeof(out); ++i) {
    char buf[3];
    snprintf(buf, sizeof(buf), "%02x", out[i]);
    macHex += buf;
  }
  return macHex;
}

static String shortChipId(); // forward
// Full, stable device id derived from ESP32 eFuse MAC (12 hex chars, lowercase).
// Diagnostics only; canonical deviceId is numeric id6.
static String fullChipId12() {
  uint64_t mac = ESP.getEfuseMac();
  char out[13];
  snprintf(out, sizeof(out),
           "%02x%02x%02x%02x%02x%02x",
           (uint8_t)(mac >> 40),
           (uint8_t)(mac >> 32),
           (uint8_t)(mac >> 24),
           (uint8_t)(mac >> 16),
           (uint8_t)(mac >> 8),
           (uint8_t)(mac));
  return String(out);
}

static String sha256HexOfBytes(const uint8_t* data, size_t len) {
#if defined(ARDUINO_ARCH_ESP32)
  uint8_t out[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_update_ret(&ctx, data, len) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  if (mbedtls_sha256_finish_ret(&ctx, out) != 0) {
    mbedtls_sha256_free(&ctx);
    return String();
  }
  mbedtls_sha256_free(&ctx);
  String hex;
  hex.reserve(64);
  for (size_t i = 0; i < sizeof(out); ++i) {
    char buf[3];
    snprintf(buf, sizeof(buf), "%02x", out[i]);
    hex += buf;
  }
  return hex;
#else
  (void)data; (void)len;
  return String();
#endif
}

static bool computeSha256Bytes(const uint8_t* data, size_t len, uint8_t out32[32]) {
#if defined(ARDUINO_ARCH_ESP32)
  if (!data || !out32) return false;
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  bool ok = (mbedtls_sha256_starts_ret(&ctx, 0) == 0) &&
            (mbedtls_sha256_update_ret(&ctx, data, len) == 0) &&
            (mbedtls_sha256_finish_ret(&ctx, out32) == 0);
  mbedtls_sha256_free(&ctx);
  return ok;
#else
  (void)data; (void)len; (void)out32;
  return false;
#endif
}

static bool loadUsersArray(JsonDocument& doc, JsonArray& outArr) {
  if (g_usersJson.length()) {
    DeserializationError err = deserializeJson(doc, g_usersJson);
    if (!err && doc.is<JsonArray>()) {
      outArr = doc.as<JsonArray>();
      return true;
    }
  }
  outArr = doc.to<JsonArray>();
  return true;
}

static bool verifyInviteSignature(JsonObjectConst invite) {
  // ArduinoJson: avoid `| nullptr` (can bind to std::nullptr_t overload and always return null)
  const char* sig = invite["sig"] | "";
  const char* devId = invite["deviceId"] | "";
  const char* inviteId = invite["inviteId"] | "";
  const char* roleRaw = invite["role"] | "USER";
  BleRole roleEnum = roleFromStr(roleRaw);
  const char* role = (roleEnum == BleRole::GUEST) ? "GUEST" : "USER";
  int exp = invite["exp"] | 0;
  const char* sigOwner = invite["sig_owner"] | invite["sigOwner"] | "";
  Serial.printf("[JOIN] verify invite inviteId=%s devId=%s roleRaw=%s role=%s exp=%d sigLen=%u sigOwnerLen=%u ownerPubKeyLen=%u\n",
                inviteId, devId, roleRaw, role, exp,
                (unsigned)strlen(sig), (unsigned)strlen(sigOwner),
                (unsigned)g_ownerPubKeyB64.length());
  if (!sig[0] || !devId[0] || !inviteId[0]) {
    Serial.println("[JOIN] invite missing required fields");
    return false;
  }

  // Cihaz kimliği uyuşmalı (id6 digits only).
  const String id6    = getDeviceId6();
  const String devIdStr = String(devId);
  // Normalize/canonicalize device id for signature verification.
  const String canonicalDevId = id6;
  const String inviteId6 = normalizeDeviceId6(devIdStr);

  if (inviteId6.isEmpty() || inviteId6 != canonicalDevId) {
    Serial.printf("[JOIN] deviceId mismatch invite='%s' local_short='%s' canonical='%s'\n",
                  devId, id6.c_str(), canonicalDevId.c_str());
    return false;
  }
  Serial.printf("[JOIN] invite deviceId ok inviteId6=%s canonical=%s\n",
                inviteId6.c_str(), canonicalDevId.c_str());

  // Süre sonu kontrolü: sistem saati geçerliyse exp'e göre doğrula
  time_t nowEpoch = time(nullptr);
  if (exp > 0 && nowEpoch >= kMinValidEpoch && nowEpoch > (time_t)exp) {
    Serial.printf("[JOIN] invite expired exp=%d now=%ld\n", exp, (long)nowEpoch);
    return false;
  }

  // Canonical string: deviceId|inviteId|role|exp
  String canon = canonicalDevId;
  canon += '|';
  canon += inviteId;
  canon += '|';
  canon += role;
  canon += '|';
  canon += String(exp);

  uint8_t mac[32];
  if (!g_deviceSecretLoaded) {
    Serial.println("[JOIN] device_secret not loaded; cannot verify invite");
    return false;
  }
  if (!computeHmacSha256(g_deviceSecret,
                         sizeof(g_deviceSecret),
                         (const uint8_t*)canon.c_str(),
                         (size_t)canon.length(),
                         mac)) {
    Serial.println("[JOIN] HMAC computation failed");
    return false;
  }

  // HMAC'i hex stringe çevir
  String macHex;
  macHex.reserve(64);
  for (size_t i = 0; i < sizeof(mac); ++i) {
    char buf[3];
    snprintf(buf, sizeof(buf), "%02x", mac[i]);
    macHex += buf;
  }

  String sigStr = String(sig);
  sigStr.trim();
  if (!sigStr.equalsIgnoreCase(macHex)) {
    Serial.println("[JOIN] invite signature mismatch");
    return false;
  }

  // If an owner public key exists, require owner-signed invite as well.
  if (g_ownerPubKeyB64.length() > 0) {
    if (!sigOwner[0]) {
      Serial.println("[JOIN] invite missing owner signature");
      return false;
    }
    if (!verifyEcdsaP256SignatureOverBytes(
            g_ownerPubKeyB64,
            (const uint8_t*)canon.c_str(),
            canon.length(),
            String(sigOwner))) {
      Serial.println("[JOIN] owner invite signature mismatch");
      return false;
    }
  }

  Serial.println("[JOIN] invite signature ok");
  return true;
}

static bool handleJoinInvite(JsonObjectConst invite, String& outUserIdHash) {
  outUserIdHash = String();
  uint32_t nowMs = millis();
  bool joinActive = (g_joinUntilMs != 0) &&
                    ((int32_t)(g_joinUntilMs - nowMs) > 0);
  Serial.printf("[JOIN] handleJoinInvite active=%d now=%u joinUntil=%u\n",
                joinActive ? 1 : 0, (unsigned)nowMs, (unsigned)g_joinUntilMs);
  if (!joinActive) {
    return false;
  }
  const char* inviteId = invite["inviteId"] | "";
  if (!inviteId[0]) {
    Serial.println("[JOIN] inviteId missing in JOIN payload");
    return false;
  }
  if (!g_joinInviteId.equalsIgnoreCase(String(inviteId))) {
    Serial.printf("[JOIN] inviteId mismatch payload='%s' active='%s'\n",
                  inviteId, g_joinInviteId.c_str());
    return false;
  }
  Serial.printf("[JOIN] inviteId ok=%s\n", inviteId);
  if (!verifyInviteSignature(invite)) {
    Serial.println("[JOIN] invite signature verification failed");
    return false;
  }

  const char* role = invite["role"] | "USER";
  // New schema: joiner can include their public key (base64 Q65) so that
  // future BLE sessions can authenticate via signature without re-scanning QR.
  // We bind the user identity to sha256(pubkeyBytes) to avoid spoofable IDs.
  const char* pubB64 = invite["user_pubkey"] | invite["userPubKey"] | "";
  String pubKeyB64 = String(pubB64);
  pubKeyB64.trim();
  if (pubKeyB64.length()) {
    std::vector<uint8_t> decoded;
    decoded.resize(80);
    size_t outLen = 0;
    int ret = mbedtls_base64_decode(decoded.data(), decoded.size(), &outLen,
                                    (const unsigned char*)pubKeyB64.c_str(),
                                    pubKeyB64.length());
    if (ret == 0 && outLen == 65) {
      outUserIdHash = sha256HexOfBytes(decoded.data(), outLen);
    } else {
      Serial.printf("[JOIN] invalid user_pubkey (b64len=%u ret=%d out=%u)\n",
                    (unsigned)pubKeyB64.length(), ret, (unsigned)outLen);
    }
  }
  // Legacy fallback: allow caller-provided idHash if pubkey isn't provided.
  if (!outUserIdHash.length()) {
    const char* idHash = invite["userIdHash"] | "";
    if (!idHash[0]) idHash = invite["sig"] | "";
    if (!idHash[0]) idHash = inviteId;
    outUserIdHash = String(idHash);
  }

  // users_json: [{ "id":"<sha256(pubkey)>", "role":"USER", "pubkey":"<b64Q65>" }, ...]
  JsonDocument doc;
  JsonArray arr;
  loadUsersArray(doc, arr);

  bool found = false;
  for (JsonVariant v : arr) {
    JsonObject o = v.as<JsonObject>();
    const char* existing = o["id"] | o["userIdHash"] | "";
    if (existing && outUserIdHash.equalsIgnoreCase(String(existing))) {
      o["id"]   = outUserIdHash;
      o["role"] = role;
      if (pubKeyB64.length()) o["pubkey"] = pubKeyB64;
      found = true;
      break;
    }
  }
  if (!found) {
    JsonObject o = arr.add<JsonObject>();
    o["id"]   = outUserIdHash;
    o["role"] = role;
    if (pubKeyB64.length()) o["pubkey"] = pubKeyB64;
  }

  String out;
  serializeJson(arr, out);
  g_usersJson = out;
  // Bu helper, applyControlDocument bağlamında çağrılıyor; şimdilik sadece
  // RAM'deki users_json'u güncelliyoruz ve log yazıyoruz.
  Serial.printf("[JOIN] user added idHash=%s role=%s\n",
                outUserIdHash.c_str(),
                role);
  // Single-use: başarılı join sonrası pencereyi kapat.
  g_joinInviteId.clear();
  g_joinRole.clear();
  g_joinUntilMs = 0;
  return true;
}

static void savePrefs();
static void applyRelays();
static void setFanPercent(uint8_t pct);
static uint8_t modeToPercent(FanMode m);
static void handleIrNecCommand(uint32_t necCode);


/* =================== Planner =================== */
#define MAX_PLANS 12
struct PlanItem {
  bool     enabled;
  uint16_t startMin;   // [0..1439]
  uint16_t endMin;
  uint8_t  mode;       // 0..5
  uint8_t  fanPercent; // when mode != AUTO
  bool     lightOn;
  bool     ionOn;
  bool     rgbOn;
};
PlanItem g_plans[MAX_PLANS];
// Initialize plan array to safe defaults (disabled) to avoid uninitialized memory
void initPlans() {
  for (uint8_t i = 0; i < MAX_PLANS; ++i) {
    g_plans[i].enabled = false;
    g_plans[i].startMin = 0;
    g_plans[i].endMin = 0;
    g_plans[i].mode = 1; // default to LOW
    g_plans[i].fanPercent = 35;
    g_plans[i].lightOn = false;
    g_plans[i].ionOn = false;
    g_plans[i].rgbOn = false;
  }
}
uint8_t  g_planCount = 0;

// Timezone (no NTP here; phone can set epoch via /api/cmd if needed)
static char g_tz[64] = "EET-2EEST,M3.5.0/3,M10.5.0/4";
static inline bool timeInRange(uint16_t s, uint16_t e, uint16_t nowMin) {
  if (s == e) return false;
  if (s < e) return (nowMin >= s && nowMin < e);
  return (nowMin >= s || nowMin < e); // overnight window
}

/* =================== Tachometer =================== */
volatile uint32_t tachPulses = 0;
volatile uint32_t lastPulseMicros = 0;
volatile uint32_t g_lastRPM = 0;
static uint32_t g_rpmFiltered = 0;
static uint8_t g_rpmZeroWindows = 0;

void IRAM_ATTR onTach() {
  uint32_t now = micros();
  if (now - lastPulseMicros > 200) { // ~5kHz debounce
    tachPulses++;
    lastPulseMicros = now;
  }
}

uint32_t calcRPM(uint32_t pulses, uint32_t ms, uint8_t pulsesPerRev = 2) {
  float revs = (float)pulses / pulsesPerRev;
  float minutes = (float)ms / 60000.0f;
  return (uint32_t)(revs / minutes);
}

/* =================== IR Receiver Debug =================== */
#if ENABLE_IR_RX_DEBUG
struct IrEdgeSample {
  uint16_t durUs;
  uint8_t level;
};

static volatile IrEdgeSample g_irEdgeBuf[256];
static volatile uint16_t g_irEdgeHead = 0;
static volatile uint16_t g_irEdgeTail = 0;
static volatile uint32_t g_irLastEdgeUs = 0;
static volatile uint8_t g_irLastLevel = 1;

static bool approxUs(uint16_t v, uint16_t target, uint16_t tol) {
  return (v >= (uint16_t)(target - tol) && v <= (uint16_t)(target + tol));
}

void IRAM_ATTR onIrRxEdge() {
  const uint32_t nowUs = micros();
  uint32_t d = nowUs - g_irLastEdgeUs;
  if (d > 65000UL) d = 65000UL;

  const uint16_t next = (uint16_t)((g_irEdgeHead + 1U) & 0xFFU);
  if (next != g_irEdgeTail) {
    g_irEdgeBuf[g_irEdgeHead].durUs = (uint16_t)d;
    g_irEdgeBuf[g_irEdgeHead].level = g_irLastLevel;
    g_irEdgeHead = next;
  }

  g_irLastLevel = (uint8_t)digitalRead(PIN_IR_RX);
  g_irLastEdgeUs = nowUs;
}

static bool decodeNec32FromSamples(const IrEdgeSample* s, uint16_t n, uint32_t& outCode) {
  // We expect low/high durations from an active-low demodulated IR receiver.
  for (uint16_t i = 0; i + 66 < n; ++i) {
    if (s[i].level != 0 || s[i + 1].level != 1) continue;
    if (!approxUs(s[i].durUs, 9000, 2200)) continue;
    if (!approxUs(s[i + 1].durUs, 4500, 1200)) continue;

    uint32_t code = 0;
    bool ok = true;
    uint16_t k = (uint16_t)(i + 2);
    for (uint8_t bit = 0; bit < 32; ++bit) {
      if (k + 1 >= n) { ok = false; break; }
      if (s[k].level != 0 || s[k + 1].level != 1) { ok = false; break; }
      if (!approxUs(s[k].durUs, 560, 260)) { ok = false; break; }

      const uint16_t hi = s[k + 1].durUs;
      if (approxUs(hi, 560, 260)) {
        // bit 0
      } else if (approxUs(hi, 1690, 450)) {
        code |= (1UL << bit);
      } else {
        ok = false;
        break;
      }
      k = (uint16_t)(k + 2);
    }
    if (ok) {
      outCode = code;
      return true;
    }
  }
  return false;
}

static bool decodeNecRepeatFromSamples(const IrEdgeSample* s, uint16_t n) {
  for (uint16_t i = 0; i + 3 < n; ++i) {
    if (s[i].level != 0 || s[i + 1].level != 1 || s[i + 2].level != 0) continue;
    if (!approxUs(s[i].durUs, 9000, 2200)) continue;
    if (!approxUs(s[i + 1].durUs, 2250, 900)) continue;
    if (!approxUs(s[i + 2].durUs, 560, 260)) continue;
    return true;
  }
  return false;
}

static inline uint16_t irPendingEdgeCount() {
  uint16_t count = 0;
  noInterrupts();
  const uint16_t head = g_irEdgeHead;
  const uint16_t tail = g_irEdgeTail;
  interrupts();
  if (head >= tail) {
    count = (uint16_t)(head - tail);
  } else {
    count = (uint16_t)(256U - tail + head);
  }
  return count;
}

static void processIrRxDebug() {
  static IrEdgeSample frame[192];
  static uint16_t frameLen = 0;
  static uint32_t lastFrameMs = 0;
  static uint32_t lastNecCode = 0;
  static uint32_t lastBudgetWarnMs = 0;
  // Bound per-loop IR work so noisy RX input cannot starve cloud/WiFi/BLE tasks.
  constexpr uint16_t kMaxSamplesPerCall = 96;
  uint16_t processed = 0;

  while (processed < kMaxSamplesPerCall) {
    IrEdgeSample x{};
    bool has = false;
    noInterrupts();
    if (g_irEdgeTail != g_irEdgeHead) {
      x.durUs = g_irEdgeBuf[g_irEdgeTail].durUs;
      x.level = g_irEdgeBuf[g_irEdgeTail].level;
      g_irEdgeTail = (uint16_t)((g_irEdgeTail + 1U) & 0xFFU);
      has = true;
    }
    interrupts();
    if (!has) break;
    processed++;

    // Large idle high/low gap => frame boundary.
    if (x.durUs >= 8000 && frameLen > 0) {
      uint32_t nec = 0;
      const bool necOk = decodeNec32FromSamples(frame, frameLen, nec);
      if (necOk) {
        lastNecCode = nec;
        handleIrNecCommand(nec);
      } else if (lastNecCode != 0 && decodeNecRepeatFromSamples(frame, frameLen)) {
        handleIrNecCommand(lastNecCode);
      }
      frameLen = 0;
      lastFrameMs = millis();
    }

    if (frameLen < (uint16_t)(sizeof(frame) / sizeof(frame[0]))) {
      frame[frameLen++] = x;
    } else {
      frameLen = 0;
    }
  }

  if (processed >= kMaxSamplesPerCall) {
    const uint32_t nowMs = millis();
    if ((uint32_t)(nowMs - lastBudgetWarnMs) >= 2000UL) {
      lastBudgetWarnMs = nowMs;
      Serial.printf("[IR] sample budget hit (%u), deferring remaining edges\n",
                    (unsigned)kMaxSamplesPerCall);
    }
    // Keep scheduler/network stacks responsive under sustained IR edge load.
    aacYieldLongOp();
  }

  // Flush pending frame if line stayed idle.
  if (frameLen > 0 && (millis() - lastFrameMs) > 150) {
    uint32_t nec = 0;
    const bool necOk = decodeNec32FromSamples(frame, frameLen, nec);
    if (necOk) {
      lastNecCode = nec;
      handleIrNecCommand(nec);
    } else if (lastNecCode != 0 && decodeNecRepeatFromSamples(frame, frameLen)) {
      handleIrNecCommand(lastNecCode);
    }
    frameLen = 0;
    lastFrameMs = millis();
  }
}
#endif

// --- Early-time BT Classic memory release (must be called before Wi-Fi init) ---
static void bleReleaseClassicEarlyOnce() {
#if ENABLE_BLE
  static bool done = false;
  if (done) return;
#if DISABLE_CLASSIC_BT_A2DP
  esp_bt_controller_status_t st = esp_bt_controller_get_status();
  // Only release when controller is IDLE; safest point on IDF v5/Arduino 3.x
  if (st == ESP_BT_CONTROLLER_STATUS_IDLE) {
    esp_err_t rel = esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT);
    Serial.printf("[BLE] classic BT disabled (A2DP off), release=%d\n", (int)rel);
  } else {
    Serial.printf("[BLE] classic BT release skipped (controller status=%d)\n", (int)st);
  }
#else
  Serial.println("[BLE] classic BT release disabled by config");
#endif
  done = true;
#endif
}

/* =================== BLE/HTTP/TCP =================== */
// Forward declaration for status JSON builder used before its definition
String buildStatusJson();
static String buildStatusJsonMin();
static String buildBleStatusJson();
static char* ensureMqttStateBuf(size_t cap);
static size_t buildStatusJsonToBuffer(char* buf, size_t cap, bool minimal);
#if ENABLE_BLE
void bleCoreInit();            // Initialize NimBLE stack, server, service, chars (NO advertising)
void bleStartAdvertising();    // Start advertising only (assumes core init done)
#endif
static NimBLEServer*         g_bleServer = nullptr;
static NimBLECharacteristic* g_chProv    = nullptr;
static NimBLECharacteristic* g_chInfo    = nullptr;
static NimBLECharacteristic* g_chCmd     = nullptr;

static String g_bleName; // holds full BLE name for logging (since NimBLEDevice::getDeviceName() not available in this core)

static void bleNotifyJson(const String& payload); // forward (used by deferred notify helper)

// Extra diagnostics for iOS/Android disconnect reasons.
// Uses NimBLE custom GAP handler to log connect/disconnect codes.
#if ENABLE_BLE
static const char* bleDiscReasonText(int reason) {
  // NimBLE may wrap HCI reason as 0x200 + hci_code.
  int hci = reason;
  if (hci >= 0x200) hci -= 0x200;
  switch (hci) {
    case 0x08: return "conn_timeout";
    case 0x13: return "remote_user_terminated";
    case 0x16: return "local_host_terminated";
    case 0x22: return "ll_response_timeout";
    case 0x3B: return "unacceptable_conn_params";
    default: return "unknown";
  }
}

static int bleGapLogHandler(ble_gap_event* event, void* arg) {
  (void)arg;
  if (!event) return 0;
  switch (event->type) {
    case BLE_GAP_EVENT_CONNECT: {
      Serial.printf("[BLE][GAP] CONNECT status=%d handle=%u\n",
                    event->connect.status,
                    (unsigned)event->connect.conn_handle);
      break;
    }
    case BLE_GAP_EVENT_DISCONNECT: {
      const int reason = event->disconnect.reason;
      int hci = reason;
      if (hci >= 0x200) hci -= 0x200;
      Serial.printf("[BLE][GAP] DISCONNECT reason=%d (0x%X hci=0x%X %s) handle=%u authed=%d\n",
                    event->disconnect.reason,
                    (unsigned)reason,
                    (unsigned)hci,
                    bleDiscReasonText(reason),
                    (unsigned)event->disconnect.conn.conn_handle,
                    g_bleAuthed ? 1 : 0);
      break;
    }
    default:
      break;
  }
  return 0;
}
#endif

// Some iOS stacks are sensitive to notifications sent directly inside NimBLE
// callbacks. Defer select notifications (e.g., auth responses) to the main loop.
#if ENABLE_BLE
static String   g_bleDeferredNotify;
static uint32_t g_bleDeferredNotifyAtMs = 0;
static void bleScheduleNotify(const String& payload, uint32_t delayMs = 60) {
  g_bleDeferredNotify = payload;
  g_bleDeferredNotifyAtMs = millis() + delayMs;
}
static void bleProcessDeferredNotify(uint32_t nowMs) {
  if (!g_bleDeferredNotify.length()) return;
  if ((int32_t)(nowMs - g_bleDeferredNotifyAtMs) < 0) return;
  // Only attempt if someone is subscribed; otherwise drop.
  if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
    bleNotifyJson(g_bleDeferredNotify);
  }
  g_bleDeferredNotify.clear();
  g_bleDeferredNotifyAtMs = 0;
}

// AUTH (signature verification) is computationally heavy (mbedtls) and must not
// run inside NimBLE host callbacks (nimble_host task stack is small). We capture
// the request in the callback and verify it in the main loop.
static portMUX_TYPE g_bleAuthMux = portMUX_INITIALIZER_UNLOCKED;
static volatile bool g_bleAuthPending = false;
static volatile uint16_t g_bleAuthPendingConnHandle = BLE_HS_CONN_HANDLE_NONE;
static char g_bleAuthPendingNonceB64[48] = {0}; // base64(16B)=24
static char g_bleAuthPendingSigB64[128] = {0};  // base64(64B)=88
static volatile bool g_bleClaimPending = false;
static char g_bleClaimPendingJson[1024] = {0};

static void bleQueueAuthVerify(const char* nonceB64, const char* sigB64) {
  if (!nonceB64 || !sigB64) return;
  portENTER_CRITICAL(&g_bleAuthMux);
  strlcpy(g_bleAuthPendingNonceB64, nonceB64, sizeof(g_bleAuthPendingNonceB64));
  strlcpy(g_bleAuthPendingSigB64, sigB64, sizeof(g_bleAuthPendingSigB64));
  g_bleAuthPendingConnHandle = g_bleConnHandle;
  g_bleAuthPending = true;
  portEXIT_CRITICAL(&g_bleAuthMux);
}

static bool bleDequeueAuthVerify(uint16_t& outConnHandle, char outNonceB64[48], char outSigB64[128]) {
  bool had = false;
  portENTER_CRITICAL(&g_bleAuthMux);
  if (g_bleAuthPending) {
    outConnHandle = g_bleAuthPendingConnHandle;
    strlcpy(outNonceB64, g_bleAuthPendingNonceB64, 48);
    strlcpy(outSigB64, g_bleAuthPendingSigB64, 128);
    g_bleAuthPending = false;
    g_bleAuthPendingConnHandle = BLE_HS_CONN_HANDLE_NONE;
    g_bleAuthPendingNonceB64[0] = '\0';
    g_bleAuthPendingSigB64[0] = '\0';
    had = true;
  }
  portEXIT_CRITICAL(&g_bleAuthMux);
  return had;
}

static void bleQueueClaimRequest(const char* jsonPayload) {
  if (!jsonPayload || !jsonPayload[0]) return;
  portENTER_CRITICAL(&g_bleAuthMux);
  strlcpy(g_bleClaimPendingJson, jsonPayload, sizeof(g_bleClaimPendingJson));
  g_bleClaimPending = true;
  portEXIT_CRITICAL(&g_bleAuthMux);
}

static bool bleDequeueClaimRequest(char outJson[1024]) {
  bool had = false;
  portENTER_CRITICAL(&g_bleAuthMux);
  if (g_bleClaimPending) {
    strlcpy(outJson, g_bleClaimPendingJson, 1024);
    g_bleClaimPending = false;
    g_bleClaimPendingJson[0] = '\0';
    had = true;
  }
  portEXIT_CRITICAL(&g_bleAuthMux);
  return had;
}

static void bleProcessAuthPending(uint32_t nowMs) {
  (void)nowMs;
  uint16_t connHandle = BLE_HS_CONN_HANDLE_NONE;
  char nonceB64[48];
  char sigB64[128];
  if (!bleDequeueAuthVerify(connHandle, nonceB64, sigB64)) return;

  // Request is tied to the current connection.
  if (connHandle == BLE_HS_CONN_HANDLE_NONE || connHandle != g_bleConnHandle) return;

  // Prevent replay: require nonce to match the most recent GET_NONCE for this session.
  if (!g_bleNonceB64.length() || strcmp(nonceB64, g_bleNonceB64.c_str()) != 0) {
    bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"nonce_mismatch\"}}"));
    if (g_ownerExists && g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
      g_bleServer->disconnect(g_bleConnHandle);
    }
    return;
  }

  const String deviceId = getDeviceId6();
  const String message = String("AAC1|") + deviceId + "|" + String(nonceB64);
  Serial.printf("[AUTH][BLE] nonceLen=%u deviceId=%s\n",
                (unsigned)strlen(nonceB64),
                deviceId.c_str());
  const String sigStr(sigB64);
  const String msgHashHex = sha256HexOfBytes(
      reinterpret_cast<const uint8_t*>(message.c_str()),
      message.length());
  const String msgHashFp = msgHashHex.length() >= 16
      ? msgHashHex.substring(0, 16)
      : msgHashHex;
  Serial.printf("[AUTH][BLE] msgHashFp=%s\n", msgHashFp.c_str());
  std::vector<uint8_t> sigBytes;
  size_t sigLen = 0;
  if (base64Decode(sigStr, sigBytes)) {
    sigLen = sigBytes.size();
  }
  Serial.printf("[AUTH][BLE] sigLen=%u\n", (unsigned)sigLen);
  Serial.printf("[AUTH][BLE] sigFormat=%s\n", (sigLen == 64) ? "RAW64" : "DER");
  const bool ownedNow = isOwned() || g_ownerPubKeyB64.length();
  BleRole role = BleRole::NONE;
  String userId;
  bool ok = false;

  if (ownedNow) {
    // Owned devices: AUTH must verify against owner/user keys (NOT pairToken).
    ok = verifyAnyTrustedSignature(
        reinterpret_cast<const uint8_t*>(message.c_str()),
        message.length(),
        String(sigB64),
        role,
        userId);
  } else {
    // Unowned devices: allow pairToken-derived AUTH (legacy) as a bridge.
    if (g_pairToken.isEmpty()) {
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"missing_pairToken\"}}"));
      if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
        g_bleServer->disconnect(g_bleConnHandle);
      }
      return;
    }
    Serial.printf("[AUTH][BLE] tokenHexLen=%u\n", (unsigned)g_pairToken.length());
    std::vector<uint8_t> tokenBytes;
    const bool tokenOk = hexToBytes(g_pairToken, tokenBytes);
    Serial.printf("[AUTH][BLE] tokenBytesLen=%u\n", (unsigned)tokenBytes.size());
    if (!tokenOk || tokenBytes.empty()) {
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"key_derivation_failed\"}}"));
      if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
        g_bleServer->disconnect(g_bleConnHandle);
      }
      return;
    }

    mbedtls_ecp_keypair kp;
    uint8_t pub65[65];
    if (!deriveBleKeypairFromPairToken(g_pairToken, &kp, pub65)) {
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"key_derivation_failed\"}}"));
      if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
        g_bleServer->disconnect(g_bleConnHandle);
      }
      return;
    }
    const String pubHashHex = sha256HexOfBytes(pub65, sizeof(pub65));
    const String pubKeyFp = pubHashHex.length() >= 16
        ? pubHashHex.substring(0, 16)
        : pubHashHex;
    Serial.printf("[AUTH][BLE] pubKeyLen=%u\n", (unsigned)sizeof(pub65));
    Serial.printf("[AUTH][BLE] pubKeyFp=%s\n", pubKeyFp.c_str());

    const String pubB64 = base64Encode(pub65, sizeof(pub65));
    ok = verifyEcdsaP256Signature(
        pubB64,
        reinterpret_cast<const uint8_t*>(message.c_str()),
        message.length(),
        String(sigB64));
    mbedtls_ecp_keypair_free(&kp);
    role = ok ? BleRole::OWNER : BleRole::NONE;
  }

  g_bleAuthed = ok;
  g_bleRole = ok ? role : BleRole::NONE;
  g_bleUserIdHash = ok ? userId : String();
  if (ok) {
    g_bleAuthDeadlineMs = 0;
    if (effectiveRole(g_bleRole) == BleRole::OWNER) {
      g_bleOwnerAuthGraceUntilMs = millis() + BLE_OWNER_AUTH_GRACE_MS;
    }
  }

  if (ok) {
    JsonDocument out;
    out["auth"]["ok"] = true;
    out["auth"]["role"] = roleToStr(effectiveRole(g_bleRole));
    out["auth"]["deviceId"] = canonicalDeviceId();
    out["auth"]["id6"] = shortChipId();
    const uint32_t nowMsAuth = millis();
    if (!isOwned() || ownerRotateWindowActive(nowMsAuth) || g_bleAuthed) {
      out["auth"]["pairToken"] = g_pairToken;
    }
    if (g_bleRole != BleRole::OWNER && g_bleUserIdHash.length()) {
      out["auth"]["userIdHash"] = g_bleUserIdHash;
    }
    String resp;
    serializeJson(out, resp);
    bleScheduleNotify(resp);
  } else {
    bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"invalid_signature\"}}"));
    // Owned devices should not allow fallback to AUTH_SETUP; drop the link.
    if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
      g_bleServer->disconnect(g_bleConnHandle);
    }
  }
}

static void bleProcessClaimPending(uint32_t nowMs) {
  (void)nowMs;
  char claimJson[1024];
  if (!bleDequeueClaimRequest(claimJson)) return;
  JsonDocument claimDoc;
  if (deserializeJson(claimDoc, claimJson)) {
    Serial.println("[BLE][CLAIM] pending payload parse failed");
    bleScheduleNotify(String("{\"claim\":{\"ok\":false,\"err\":\"invalid_payload\"}}"));
    return;
  }
  g_lastCmdSource = CmdSource::BLE;
  const bool changed = handleIncomingControlJson(claimDoc, CmdSource::BLE, "BLE", false, nullptr);
  bleScheduleNotify(buildBleStatusJson(), 80);
  if (changed) savePrefs();
  g_lastCmdSource = CmdSource::UNKNOWN;
}
#else
static void bleScheduleNotify(const String&, uint32_t = 0) {}
static void bleProcessDeferredNotify(uint32_t) {}
static void bleProcessAuthPending(uint32_t) {}
static void bleProcessClaimPending(uint32_t) {}
#endif

static void bleNotifyJson(const String& payload) {
#if ENABLE_BLE
  if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
#if BLE_NOTIFY_DEBUG
    const size_t previewLen = payload.length() > 120 ? 120 : payload.length();
    Serial.printf("[BLE][NOTIFY] %.*s%s\n",
                  (int)previewLen,
                  payload.c_str(),
                  payload.length() > previewLen ? "..." : "");
#endif
    // iOS tarafında notify payload'ı MTU'yu aşarsa paket "split" edilmeden kesilebiliyor.
    // Bu yüzden payload'ı küçük parçalara bölüp ardışık notify olarak gönderiyoruz.
    const size_t kMaxChunk = 180; // güvenli MTU (ATT overhead dahil)
    if (payload.length() <= kMaxChunk) {
      g_chInfo->setValue(payload);
      g_chInfo->notify(true);
    } else {
      for (size_t off = 0; off < payload.length(); off += kMaxChunk) {
        const String part = payload.substring(off, std::min(off + kMaxChunk, payload.length()));
        g_chInfo->setValue(part);
        g_chInfo->notify(true);
        delay(20); // BLE stack'e nefes ver (iOS/Android daha stabil)
      }
    }
  } else {
#if BLE_NOTIFY_DEBUG
    Serial.println("[BLE][NOTIFY] skipped (no subscribers)");
#endif
  }
#else
  (void)payload;
#endif
}

// BLE tarafında UI'nin canlı kalması için periyodik (kompakt) durum bildirimi.
// iOS tarafında notify akışı bazen "yalnızca olay olduğunda" kaldığı için,
// bağlı abone varken kısa aralıklarla status yayınlıyoruz.
static uint32_t g_bleLastStatusMs = 0;
static void bleMaybeNotifyStatusPeriodic(uint32_t nowMs) {
#if ENABLE_BLE
  if (!g_chInfo || g_chInfo->getSubscribedCount() == 0) return;
  // Keep status notifications conservative; iOS may terminate connections
  // if the peripheral pushes large/chunked notifications too early.
  // Only start periodic status AFTER AUTH, and wait a short grace period
  // after connect before the first big status publish.
  if (!g_bleAuthed) return;
  if (g_bleConnectedAtMs != 0 && (nowMs - g_bleConnectedAtMs) < 2000UL) return;
  const uint32_t kPeriodMs = 4000UL;
  if (g_bleLastStatusMs != 0 && (nowMs - g_bleLastStatusMs) < kPeriodMs) return;
  g_bleLastStatusMs = nowMs;
  // Kompakt BLE status JSON'u
  bleNotifyJson(buildBleStatusJson());
#else
  (void)nowMs;
#endif
}

static bool equalsIgnoreCase(const char* a, const char* b) {
  if (!a || !b) return false;
  while (*a && *b) {
    if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
      return false;
    }
    ++a;
    ++b;
  }
  return *a == *b;
}

static bool bleHasSecureBondedPeer() {
#if ENABLE_BLE
  if (!g_bleServer) return false;
  std::vector<uint16_t> peers = g_bleServer->getPeerDevices();
  for (size_t i = 0; i < peers.size(); ++i) {
    NimBLEConnInfo info = g_bleServer->getPeerIDInfo(peers[i]);
    if (info.isBonded() && info.isEncrypted()) {
      return true;
    }
  }
#endif
  return false;
}

void startAP();
static String deriveApPass(const String& id6);
static String chipCode4();

#if ENABLE_BLE
#if ENABLE_BLE_CMD
static String buildBleStatusJson(); // forward
static bool handleBleCommandJson(const JsonDocument& doc) {
  ScopedPerfLog perfScope("ble_cmd_json");
  bool requestWifiScan = false;
  bool requestApCredentials = false;
  // ArduinoJson: avoid `| nullptr` (can bind to std::nullptr_t overload and always return null)
  const char* scanVal = doc["scan"] | "";
  const char* wifiVal = doc["wifi"] | "";
  const char* cmdVal  = doc["cmd"]  | "";
  const char* getVal  = doc["get"]  | "";
  const char* typeVal = doc["type"] | "";

  if (equalsIgnoreCase(scanVal, "wifi")) requestWifiScan = true;
  if (equalsIgnoreCase(wifiVal, "scan")) requestWifiScan = true;
  if (equalsIgnoreCase(cmdVal, "scan_wifi")) requestWifiScan = true;
  if (doc["scan_wifi"].is<bool>() && doc["scan_wifi"].as<bool>()) requestWifiScan = true;
  if (equalsIgnoreCase(cmdVal, "get_ap_credentials")) requestApCredentials = true;
  if (equalsIgnoreCase(getVal, "ap_credentials")) requestApCredentials = true;
  if (doc["ap_credentials"].is<bool>() && doc["ap_credentials"].as<bool>()) requestApCredentials = true;

  const bool isSetMtls =
      equalsIgnoreCase(cmdVal, "set_mtls") || equalsIgnoreCase(typeVal, "set_mtls");

  JsonVariantConst wifiVar = doc["wifi"];
  if (!wifiVar.isNull() && wifiVar.is<JsonObjectConst>()) {
    JsonObjectConst wifiObj = wifiVar.as<JsonObjectConst>();
    if (wifiObj["scan"].is<bool>() && wifiObj["scan"].as<bool>()) requestWifiScan = true;
    const char* nestedScan = wifiObj["scan"] | "";
    if (equalsIgnoreCase(nestedScan, "wifi")) requestWifiScan = true;
  }

  if (requestWifiScan) {
    if (g_ownerExists && effectiveRole(g_bleRole) != BleRole::OWNER) {
      Serial.println("[BLE][CMD] Wi-Fi scan rejected (insufficient role)");
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
      return true;
    }
    Serial.println("[BLE][CMD] Wi-Fi scan requested via BLE");
    logPerfSnapshot("ble_scan_request");

    wifi_mode_t currentMode = WIFI_MODE_NULL;
    if (esp_wifi_get_mode(&currentMode) != ESP_OK) {
      currentMode = WIFI_MODE_NULL;
    }
    if (currentMode == WIFI_MODE_NULL) {
      Serial.println("[BLE][CMD] Wi-Fi mode is NULL, starting AP before scan");
      logPerfSnapshot("ble_scan_before_start_ap");
      startAP();
      logPerfSnapshot("ble_scan_after_start_ap");
      currentMode = WIFI_MODE_AP;
    }

    bool switchedToApSta = false;
    if (!AP_ONLY && currentMode == WIFI_MODE_AP) {
      Serial.println("[BLE][CMD] enabling STA interface for scan (AP+STA)");
      logPerfSnapshot("ble_scan_before_apsta");
      WiFi.mode(WIFI_AP_STA);
      // Ensure AP settings persist after mode switch
      WiFi.softAPConfig(AP_IP, AP_GW, AP_MASK);
      WiFi.softAP(g_apSsid.c_str(), g_apPass.c_str(), 1 /*channel*/, 0 /*hidden*/, 4 /*maxconn*/);
      logPerfSnapshot("ble_scan_after_apsta");
      switchedToApSta = true;
    }

    JsonDocument resp;
    JsonObject root = resp.to<JsonObject>();
    JsonArray aps = root["aps"].to<JsonArray>();
    bool ok = true;
    int count = 0;

    if (!AP_ONLY) {
      logPerfSnapshot("ble_scan_before_scanNetworks");
      int n = WiFi.scanNetworks(false, true);
      Serial.printf("[BLE][CMD] Wi-Fi scanNetworks -> %d\n", n);
      logPerfSnapshot("ble_scan_after_scanNetworks");
      if (n == WIFI_SCAN_FAILED || n == WIFI_SCAN_RUNNING) {
        Serial.println("[BLE][CMD] scan in progress or failed, retrying...");
        logPerfSnapshot("ble_scan_before_retry_delete");
        WiFi.scanDelete();
        logPerfSnapshot("ble_scan_after_retry_delete");
        delay(200);
        logPerfSnapshot("ble_scan_before_retry_scanNetworks");
        n = WiFi.scanNetworks(false, true);
        Serial.printf("[BLE][CMD] Wi-Fi scanNetworks retry -> %d\n", n);
        logPerfSnapshot("ble_scan_after_retry_scanNetworks");
      }
      if (n > 0) {
        count = n;
        for (int i = 0; i < n; ++i) {
          JsonObject o = aps.add<JsonObject>();
          o["ssid"]   = WiFi.SSID(i);
          o["rssi"]   = WiFi.RSSI(i);
          o["ch"]     = WiFi.channel(i);
          o["secure"] = (WiFi.encryptionType(i) != WIFI_AUTH_OPEN);
        }
      } else if (n == 0) {
        count = 0;
      } else {
        ok = false;
        root["err"] = n;
      }
      if (ok) {
        Serial.printf("[BLE][CMD] Wi-Fi scan completed, count=%d\n", count);
      } else {
        Serial.printf("[BLE][CMD] Wi-Fi scan failed, err=%d\n", root["err"].is<int>() ? root["err"].as<int>() : -999);
      }
      logPerfSnapshot("ble_scan_before_scanDelete");
      WiFi.scanDelete();
      logPerfSnapshot("ble_scan_after_scanDelete");
    } else {
      ok = false;
      root["err"] = "ap_only";
      Serial.println("[BLE][CMD] Wi-Fi scan skipped (AP_ONLY)");
    }

    if (switchedToApSta) {
      Serial.println("[BLE][CMD] scan complete, keeping AP+STA active for responsiveness");
    }

    root["ok"] = ok;
    root["count"] = count;
    root["source"] = "ble";
    root["ts_ms"] = (uint32_t)millis();

    String out;
    serializeJson(root, out);
    Serial.printf("[BLE][CMD] notifying scan result (%u bytes)\n", (unsigned)out.length());
    logPerfSnapshot("ble_scan_before_notify");
    bleNotifyJson(out);
    logPerfSnapshot("ble_scan_after_notify");
    return true;
  }

  if (requestApCredentials) {
    if (!g_bleAuthed) {
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"not_authenticated\"}}"));
      return true;
    }
    if (g_ownerExists && effectiveRole(g_bleRole) != BleRole::OWNER) {
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
      return true;
    }

    // Keep BLE command path lightweight: reply first, then ensure AP is up.
    // Starting AP can be relatively heavy and may destabilize short BLE sessions on iOS.
    if (g_apSsid.isEmpty()) {
      g_apSsid = deviceApSsidForId6(shortChipId());
    }
    if (g_apPass.isEmpty()) {
      g_apPass = deriveApPass(shortChipId());
    }

    JsonDocument resp;
    JsonObject ap = resp["apCredentials"].to<JsonObject>();
    ap["ok"] = true;
    ap["ssid"] = g_apSsid;
    ap["pass"] = g_apPass;
    ap["source"] = "ble";
    ap["ts_ms"] = (uint32_t)millis();

    String out;
    serializeJson(resp, out);
    bleNotifyJson(out);

    // Defer AP start to main loop to avoid heavy Wi-Fi mode operations inside
    // NimBLE callback context (can cause iOS-side disconnects on write).
    g_bleApStartPending = true;
    return true;
  }

  if (equalsIgnoreCase(getVal, "status") ||
      (doc["status"].is<bool>() && doc["status"].as<bool>())) {
    // BLE için kompakt status JSON'u kullan (sensör + temel state).
    String s = buildBleStatusJson();
    bleNotifyJson(s);
    return true;
  }

  return false;
}
#else
static bool handleBleCommandJson(const JsonDocument&) {
  return false;
}
#endif
#endif // ENABLE_BLE

#if ENABLE_BLE
static bool     g_bleCoreInitDone = false; // NimBLEDevice/init + server/service hazır mı
static bool     g_bleAdvStarted   = false; // Advertising başladı mı
static uint32_t g_bleAdvAt        = 0;     // Advertising başlatma zamanı (ms)
static bool     g_bleForceOff = false;     // BLE runtime policy: true => BLE off
static bool     g_bleDesiredOn = true;     // BLE policy wants radio on
static bool     g_bleBootWindowActive = false; // No-sleep hybrid: allow BLE briefly at boot
static uint32_t g_bleBootUntilMs = 0;
#endif
static bool     g_noSleepTestActive = false;   // No-sleep test penceresi aktif mi
static uint32_t g_noSleepTestUntilMs = 0;      // No-sleep test bitiş zamanı
static uint32_t g_lastSleepBlockLogMs = 0;     // Spam log koruması
static bool     g_wifiSleepDisabledOnce = false;
static bool     g_wifiSleepBlockLogged = false;
static bool     g_wifiBleModemSleepActive = false;
static uint32_t g_lastSleepEnforcedLogMs = 0;
static bool     g_mdnsStarted = false;
static constexpr uint32_t CONNECT_STABLE_MS = 60000; // WiFi+MQTT stabil süre
static constexpr uint32_t BUTTON_POLL_MAX_GAP_MS = 750;          // loop stall'lerinde sahte long-press'i engelle
static uint32_t g_connStableSinceMs = 0;
static constexpr uint32_t BLE_BOOT_WINDOW_MS = 120000; // BLE açık kalma süresi (no-sleep modunda)
static constexpr uint32_t RECOVERY_TRANSPORT_GRACE_MS = 60000UL; // Primary baglanti yoksa 60 sn sonra recovery ac
static constexpr uint32_t WIFI_RETRY_INTERVAL_MS = 15000UL;      // STA retry araligi
static uint32_t g_recoveryDeferSinceMs = 0;
static uint32_t g_lastStaRetryMs = 0;
static bool     g_recoverySuppressed = false;
static bool     g_postResetOpenRecoveryAtBoot = false;
static bool     g_factoryResetPending = false;
static uint32_t g_factoryResetDueMs = 0;

#if ENABLE_TCP_CMD
WiFiServer g_cmdServer(7777);
WiFiClient g_cmdClient;
static bool g_tcpCmdStarted = false;
#endif

WebServer g_http(80);
static bool g_httpStarted = false;

static inline void applyWifiPowerSave();
static inline void enableWifiBleModemSleep();
static inline void disableWifiSleepOnce(const char* reason);
static inline void disableWifiSleepSilent();
static inline bool tryDisableWifiSleep(const char* reason, bool log);
void setupHttp();
static void startMdnsIfNeeded();
static void kickNtpSyncIfNeeded(const char* reason, bool force);
static void pollNtpSync(uint32_t nowMs);
static inline void updateConnectivityStability(uint32_t nowMs);
static inline bool isCloudStable(uint32_t nowMs);
static void onWiFiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
  switch (event) {
    case ARDUINO_EVENT_WIFI_AP_START:
    case ARDUINO_EVENT_WIFI_STA_START:
      // ESP-IDF requires modem sleep to be enabled when Wi‑Fi and Bluetooth are both enabled.
      // Apply the power-save policy after the Wi‑Fi driver has started.
      applyWifiPowerSave();
      break;
    case ARDUINO_EVENT_WIFI_AP_STACONNECTED:
      Serial.printf("[WiFi][AP] STA connected: %02X:%02X:%02X:%02X:%02X:%02X, AID=%d\n",
                    info.wifi_ap_staconnected.mac[0], info.wifi_ap_staconnected.mac[1], info.wifi_ap_staconnected.mac[2],
                    info.wifi_ap_staconnected.mac[3], info.wifi_ap_staconnected.mac[4], info.wifi_ap_staconnected.mac[5],
                    info.wifi_ap_staconnected.aid);
      break;
    case ARDUINO_EVENT_WIFI_AP_STADISCONNECTED:
      Serial.printf("[WiFi][AP] STA disconnected: %02X:%02X:%02X:%02X:%02X:%02X, AID=%d\n",
                    info.wifi_ap_stadisconnected.mac[0], info.wifi_ap_stadisconnected.mac[1], info.wifi_ap_stadisconnected.mac[2],
                    info.wifi_ap_stadisconnected.mac[3], info.wifi_ap_stadisconnected.mac[4], info.wifi_ap_stadisconnected.mac[5],
                    info.wifi_ap_stadisconnected.aid);
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      Serial.printf("[WiFi][STA] disconnected, reason=%d\n", (int)info.wifi_sta_disconnected.reason);
      g_localControlReady = false;
      if (g_mdnsStarted) {
        MDNS.end();
        g_mdnsStarted = false;
      }
      if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
        bleNotifyJson(buildBleStatusJson());
      }
      break;
    case ARDUINO_EVENT_WIFI_STA_CONNECTED:
      Serial.println("[WiFi][STA] connected");
      // Reset reconnect backoff once the link is back.
      disableWifiSleepOnce("sta-connected");
      if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
        bleNotifyJson(buildBleStatusJson());
      }
      break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP: {
      IPAddress ip = WiFi.localIP();
      Serial.printf("[WiFi][STA] got IP: %s\n", ip.toString().c_str());
      logPerfSnapshot("wifi_sta_got_ip");
      // Reset reconnect backoff once we have an IP.
      g_apGraceUntilMs = millis() + AP_GRACE_MS;
      g_apStopDueMs = millis() + 60000UL;
      Serial.printf("[WiFi][AP] grace window started: %u ms\n", (unsigned)AP_GRACE_MS);
      disableWifiSleepOnce("sta-got-ip");
      startMdnsIfNeeded();
      kickNtpSyncIfNeeded("sta-got-ip", true);
      if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
        // 1) Hızlı, küçük JSON ile IP'yi hemen bildir
        String host = deviceMdnsHostForId6(shortChipId());
        String msg = String("{\"wifi\":{\"sta_ok\":true,\"ip\":\"") + ip.toString() +
                     String("\",\"host\":\"") + host + String(".local\"}}");
        g_chInfo->setValue(msg);
        g_chInfo->notify(true);
        // 2) Ardından tam durum JSON'unu gönder (mobil tarafı güncel kalsın)
        bleNotifyJson(buildBleStatusJson());
      }
      break;
    }
    default: break;
  }
}

static void kickNtpSyncIfNeeded(const char* reason, bool force) {
  if (WiFi.status() != WL_CONNECTED) return;
  const uint32_t nowMs = millis();
  if (!force && (uint32_t)(nowMs - g_lastNtpKickMs) < NTP_RETRY_MS) return;
  g_lastNtpKickMs = nowMs;
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  if (!g_ntpKickStarted || force) {
    Serial.printf("[NTP] sync requested (%s)\n", reason ? reason : "-");
  }
  g_ntpKickStarted = true;
}

static void pollNtpSync(uint32_t nowMs) {
  if (WiFi.status() != WL_CONNECTED) return;
  if (isTimeValid()) {
    if (!g_ntpAcquiredLogged) {
      Serial.println("[NTP] time acquired");
      g_ntpAcquiredLogged = true;
    }
    return;
  }
  if ((uint32_t)(nowMs - g_lastNtpKickMs) >= NTP_RETRY_MS) {
    kickNtpSyncIfNeeded("periodic", false);
  }
}

static String g_savedSsid, g_savedPass;
static bool   g_haveCreds = false;
// Persist Wi‑Fi credentials (used by BLE/HTTP provisioning)
static void saveCreds(const char* ssid, const char* pass) {
  ScopedPerfLog perfScope("wifi_save_creds");
  logPerfSnapshot("wifi_save_creds_start");
  g_savedSsid = ssid ? String(ssid) : String();
  g_savedPass = pass ? String(pass) : String();
  g_haveCreds = (g_savedSsid.length() && g_savedPass.length());

  // ✅ WiFi şifresini şifrele
  String encryptedPass;
  bool encryptOk = false;
  if (g_savedPass.length() > 0) {
    encryptOk = encryptWifiPassword(g_savedPass, encryptedPass);
  }

  // Store to NVS
  prefs.begin("aac", false);
  prefs.putString("wifi_ssid", g_savedSsid);
  if (encryptOk && encryptedPass.length() > 0) {
    // Şifrelenmiş şifreyi kaydet
    prefs.putString("wifi_pass_enc", encryptedPass);
    prefs.remove("wifi_pass"); // Eski plain text'i sil
  } else {
    // Encryption başarısız olursa fallback (migration için)
    prefs.putString("wifi_pass", g_savedPass);
    prefs.remove("wifi_pass_enc");
  }
  prefs.end();

  Serial.printf("[WiFi][PROV] saved credentials (ssidLen=%u, passLen=%u, encrypted=%s)\n",
              (unsigned)g_savedSsid.length(), (unsigned)g_savedPass.length(),
              encryptOk ? "yes" : "no");
  logPerfSnapshot("wifi_save_creds_done");
}

static inline void setCORS() {
  const String origin = g_http.header("Origin");
  const String host = g_http.header("Host");
  String allowedOrigin;
#if PRODUCTION_BUILD
  if (!origin.isEmpty()) {
    const int schemeSep = origin.indexOf("://");
    const int hostStart = (schemeSep >= 0) ? (schemeSep + 3) : 0;
    int hostEnd = origin.indexOf('/', hostStart);
    if (hostEnd < 0) hostEnd = origin.length();
    const String originHost = origin.substring(hostStart, hostEnd);
    if (!originHost.isEmpty() &&
        (originHost.equalsIgnoreCase(host) ||
         originHost.equalsIgnoreCase("192.168.4.1") ||
         originHost.equalsIgnoreCase("192.168.4.1:80") ||
         originHost.endsWith(".local") ||
         originHost.endsWith(".local:80"))) {
      allowedOrigin = origin;
    }
  }
#else
  allowedOrigin = origin.isEmpty() ? String("*") : origin;
#endif
  if (!allowedOrigin.isEmpty()) {
    g_http.sendHeader("Access-Control-Allow-Origin", allowedOrigin);
    if (allowedOrigin != "*") g_http.sendHeader("Vary", "Origin");
  }
  g_http.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  g_http.sendHeader(
      "Access-Control-Allow-Headers",
      "Content-Type, Authorization, X-Session-Token, X-Session-Nonce, X-Auth-Nonce, X-Auth-Sig, X-QR-Token, X-FW-SHA256");
  g_http.sendHeader("Connection", "close");
}

static String shortChipId();
static String deriveApPass(const String& id6);

// Wi‑Fi güç modu:
// ESP-IDF, Wi‑Fi + Bluetooth aynı anda aktifken WIFI_PS_NONE kullanımına
// izin vermiyor; aksi halde "Should enable WiFi modem sleep..." assert
// ile cihaz yeniden başlıyor. Bu yüzden:
//   - BLE açıkken: zorunlu olarak WIFI_PS_MIN_MODEM kullanıyoruz.
//   - BLE kapalıyken: tam performans için WIFI_PS_NONE.
// Modem-sleep, CPU/HTTP'yi durdurmuyor; sadece RF 'beklerken' kısa
// aralıklarla uyuyor. Uzun süre sonra bağlantı sorunu görürsek, sebebi
// büyük ihtimalle burası değil; o zaman ayrı bir watchdog/yeniden bağlanma
// mantığına bakarız.
static inline void applyWifiPowerSave() {
#if WIFI_FORCE_NO_SLEEP
  // Hybrid policy: allow BLE briefly at boot, then force no-sleep with BLE off.
  const uint32_t nowMs = millis();
#if ENABLE_BLE
  if (g_bleBootWindowActive && (int32_t)(nowMs - g_bleBootUntilMs) < 0) {
    enableWifiBleModemSleep();
    return;
  }
  g_bleBootWindowActive = false;
#endif
  // If Wi-Fi is NOT connected, keep BLE on for provisioning and allow modem sleep.
  if (WiFi.status() != WL_CONNECTED) {
#if ENABLE_BLE
    if (!g_recoverySuppressed) {
      g_bleForceOff = false;
      g_bleDesiredOn = true;
    }
#endif
    enableWifiBleModemSleep();
    return;
  }
  g_bleForceOff = true;
  g_bleDesiredOn = false;
  disableWifiSleepOnce("force");
  return;
#endif
  if (g_noSleepTestActive) {
#if ENABLE_BLE
    // If BLE is desired/active, keep modem sleep to satisfy BLE coex.
    if (g_bleDesiredOn || esp_bt_controller_get_status() != ESP_BT_CONTROLLER_STATUS_IDLE) {
      enableWifiBleModemSleep();
      return;
    }
#endif
    disableWifiSleepOnce("power-save");
    return;
  }
  g_wifiSleepDisabledOnce = false;
  enableWifiBleModemSleep();
}

static inline void enableWifiBleModemSleep() {
#if defined(ARDUINO_ARCH_ESP32)
  WiFi.setSleep(true);
  if (WiFi.getMode() != WIFI_MODE_NULL) {
    esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
  }
  // Log only on state transition + sparse heartbeat.
  const uint32_t nowMs = millis();
  if (!g_wifiBleModemSleepActive) {
#if WIFI_INFO_LOG
    Serial.println("[WiFi] sleep enforced (BLE coex)");
#endif
    g_wifiBleModemSleepActive = true;
    g_lastSleepEnforcedLogMs = nowMs;
  } else if ((nowMs - g_lastSleepEnforcedLogMs) > 60000UL) {
#if WIFI_INFO_LOG
    Serial.println("[WiFi] sleep enforced (BLE coex) [keepalive]");
#endif
    g_lastSleepEnforcedLogMs = nowMs;
  }
#endif
}

static inline void disableWifiSleepOnce(const char* reason) {
  if (g_wifiSleepDisabledOnce) return;
  if (tryDisableWifiSleep(reason, true)) {
    g_wifiSleepDisabledOnce = true;
  }
}

static inline void disableWifiSleepSilent() {
  if (g_wifiSleepDisabledOnce) return;
  if (tryDisableWifiSleep("no-sleep-test", false)) {
    g_wifiSleepDisabledOnce = true;
  }
}

static inline bool tryDisableWifiSleep(const char* reason, bool log) {
#if defined(ARDUINO_ARCH_ESP32)
  if (!g_noSleepTestActive) return false;
#if ENABLE_BLE
  // ESP-IDF aborts if WiFi modem sleep is disabled while BLE controller is enabled.
  if (esp_bt_controller_get_status() != ESP_BT_CONTROLLER_STATUS_IDLE) {
#if WIFI_NO_SLEEP_ALLOW_BLE_DEINIT
    // Do NOT deinit BLE at runtime; NimBLE reinit can crash (InstrFetchProhibited).
    // If BLE is active, keep modem sleep until BLE policy turns it off.
    if (esp_bt_controller_get_status() != ESP_BT_CONTROLLER_STATUS_IDLE) {
      const uint32_t nowMs = millis();
      if (!g_wifiSleepBlockLogged || (nowMs - g_lastSleepBlockLogMs) > 60000UL) {
#if WIFI_INFO_LOG
        Serial.println("[WiFi] sleep disable blocked (BLE active)");
#endif
        g_wifiSleepBlockLogged = true;
        g_lastSleepBlockLogMs = nowMs;
      }
      return false;
    }
#else
    const uint32_t nowMs = millis();
    if (!g_wifiSleepBlockLogged || (nowMs - g_lastSleepBlockLogMs) > 60000UL) {
#if WIFI_INFO_LOG
      Serial.println("[WiFi] sleep disable blocked (BLE active)");
#endif
      g_wifiSleepBlockLogged = true;
      g_lastSleepBlockLogMs = nowMs;
    }
    return false;
#endif
  }
#endif
  WiFi.setSleep(false);
  if (WiFi.getMode() != WIFI_MODE_NULL) {
    esp_wifi_set_ps(WIFI_PS_NONE);
  }
  g_wifiBleModemSleepActive = false;
  g_lastSleepEnforcedLogMs = 0;
  g_wifiSleepBlockLogged = false;
  if (log) {
#if WIFI_INFO_LOG
    Serial.printf("[WiFi] sleep disabled (%s)\n", reason ? reason : "-");
#endif
  }
  return true;
#endif
  (void)reason;
  (void)log;
  return false;
}

static inline void updateConnectivityStability(uint32_t nowMs) {
  const bool staUp = (WiFi.status() == WL_CONNECTED);
  const bool mqttUp = g_mqtt.connected();
  if (staUp && mqttUp) {
    if (g_connStableSinceMs == 0) {
      g_connStableSinceMs = nowMs;
    }
  } else {
    g_connStableSinceMs = 0;
  }
}

static inline bool isCloudStable(uint32_t nowMs) {
  if (g_connStableSinceMs == 0) return false;
  return (int32_t)(nowMs - g_connStableSinceMs) >= (int32_t)CONNECT_STABLE_MS;
}

static inline bool primaryTransportAvailable() {
  return ((WiFi.status() == WL_CONNECTED) &&
          (WiFi.localIP() != IPAddress(0, 0, 0, 0))) ||
         g_mqtt.connected();
}

static inline bool recoveryTransportsAllowed(uint32_t nowMs) {
  // IR-first model:
  // - Unowned devices stay locked until an explicit pairing/recovery window is opened.
  // - Owned devices without STA creds can still use recovery transports.
  if (!g_ownerExists) {
    g_recoverySuppressed = !pairingWindowActive(nowMs);
    g_recoveryDeferSinceMs = 0;
    return pairingWindowActive(nowMs);
  }
  if (!g_haveCreds) {
    g_recoverySuppressed = false;
    g_recoveryDeferSinceMs = 0;
    return true;
  }
  if (primaryTransportAvailable()) {
    g_recoverySuppressed = true;
    g_recoveryDeferSinceMs = 0;
    return false;
  }
  if (g_recoveryDeferSinceMs == 0) {
    g_recoverySuppressed = true;
    g_recoveryDeferSinceMs = nowMs;
    Serial.printf("[RECOVERY] primary unavailable; delaying BLE/AP for %lus\n",
                  (unsigned long)(RECOVERY_TRANSPORT_GRACE_MS / 1000UL));
    return false;
  }
  g_recoverySuppressed =
      (uint32_t)(nowMs - g_recoveryDeferSinceMs) < RECOVERY_TRANSPORT_GRACE_MS;
  return (uint32_t)(nowMs - g_recoveryDeferSinceMs) >= RECOVERY_TRANSPORT_GRACE_MS;
}

static inline bool bleConnectionsAllowed(uint32_t nowMs) {
  if (!g_ownerExists) return pairingWindowActive(nowMs);
  if (!g_haveCreds) return true;
  if (pairingWindowActive(nowMs)) return true;
  if (ownerRotateWindowActive(nowMs)) return true;
  return recoveryTransportsAllowed(nowMs);
}

static void maybeRetryStaConnect(uint32_t nowMs) {
  if (!g_haveCreds) return;
  if (WiFi.status() == WL_CONNECTED) {
    g_lastStaRetryMs = 0;
    return;
  }
  if (g_lastStaRetryMs != 0 &&
      (uint32_t)(nowMs - g_lastStaRetryMs) < WIFI_RETRY_INTERVAL_MS) {
    return;
  }
  g_lastStaRetryMs = nowMs;
  wifi_mode_t mode = WiFi.getMode();
  const bool keepAp = (mode == WIFI_AP || mode == WIFI_AP_STA);
  WiFi.mode(keepAp ? WIFI_AP_STA : WIFI_STA);
  applyWifiPowerSave();
  WiFi.begin(g_savedSsid.c_str(), g_savedPass.c_str());
  Serial.printf("[WiFi][STA] retrying '%s'\n", g_savedSsid.c_str());
}

static inline bool bleCloudHandoffReady(uint32_t nowMs, bool transportReady) {
  constexpr uint32_t BLE_POLICY_POST_CLOUD_GRACE_MS = 90000UL;
  const bool cloudReady =
      transportReady &&
      (WiFi.status() == WL_CONNECTED) &&
      g_mqtt.connected() &&
      isCloudStable(nowMs);
  if (!cloudReady) {
    g_bleCloudReadySinceMs = 0;
    return false;
  }
  if (g_bleCloudReadySinceMs == 0) {
    g_bleCloudReadySinceMs = nowMs;
    return false;
  }
  return (int32_t)(nowMs - g_bleCloudReadySinceMs) >=
         (int32_t)BLE_POLICY_POST_CLOUD_GRACE_MS;
}

static inline void markLocalControlReady(uint32_t nowMs, const char* reason) {
  if (WiFi.status() != WL_CONNECTED) return;
  if (!g_localControlReady) {
    Serial.printf("[LOCAL] ready via %s\n", reason ? reason : "unknown");
  }
  g_localControlReady = true;
  // Local LAN control is proven; recovery transports no longer need to stay up.
  g_apGraceUntilMs = 0;
  g_apStopDueMs = nowMs;
#if ENABLE_BLE
  g_bleBootWindowActive = false;
  if (g_blePolicyHoldUntilMs != 0 && (int32_t)(g_blePolicyHoldUntilMs - nowMs) <= 0) {
    g_blePolicyHoldUntilMs = 0;
  }
#endif
}

static bool applyControlDocument(const JsonDocument& doc);

static String randomHexString(size_t bytes) {
  String out;
  out.reserve(bytes * 2);
  for (size_t i = 0; i < bytes; ++i) {
    uint8_t b = static_cast<uint8_t>(esp_random() & 0xFF);
    char buf[3];
    snprintf(buf, sizeof(buf), "%02X", b);
    out += buf;
  }
  return out;
}

#if ENABLE_WAQI
static bool httpBegin(HTTPClient& http, const String& url) {
  Serial.printf("[HTTP] start (using httpNet) %s\n", url.c_str());
  return http.begin(g_httpNet, url);
}

static void httpStop(HTTPClient& http) {
  http.end();
  g_httpNet.stop();
  Serial.println("[HTTP] stop()");
}
#endif

static void factoryReset();
static void pollButton(uint32_t nowMs);
static void scheduleFactoryReset(const char* reason, uint32_t delayMs = 350);
static void processPendingFactoryReset(uint32_t nowMs);

static void persistSecurityState() {
  // Legacy credential keys are no longer used; keep only the QR-derived pair token.
  prefs.begin("aac", false);
  prefs.putString("pair_token", g_pairToken);
  prefs.putBool("pair_token_trusted", g_pairTokenTrusted);
  prefs.putUInt("pair_token_trusted_ip", g_pairTokenTrustedIp);
  // Clean up old keys to avoid accidental fallback paths.
  prefs.remove("auth_user");
  prefs.remove("auth_pass");
  prefs.remove("admin_user");
  prefs.remove("admin_pass");
  prefs.end();
}

static void persistSetupEncIfAny() {
  prefs.begin("aac", false);
  if (g_setupPassEncB64.length()) prefs.putString("setup_pass_enc", g_setupPassEncB64);
  else prefs.remove("setup_pass_enc");
  // Legacy key cleanup
  prefs.remove("setup_pass_plain");
  prefs.end();
}

static void scheduleFactoryReset(const char* reason, uint32_t delayMs) {
  if (g_factoryResetPending) return;
  g_factoryResetPending = true;
  g_factoryResetDueMs = millis() + delayMs;
  Serial.printf("[RESET] factory reset scheduled reason=%s delayMs=%u\n",
                reason ? reason : "unknown",
                (unsigned)delayMs);
}

static void processPendingFactoryReset(uint32_t nowMs) {
  if (!g_factoryResetPending) return;
  if ((int32_t)(nowMs - g_factoryResetDueMs) < 0) return;
  g_factoryResetPending = false;
  factoryReset();
}

// QR log metadata (NVS).
static const char* NVS_KEY_QR_LOG_SIG = "qr_log_sig";
static const char* NVS_KEY_QR_LOG_COUNT = "qr_log_count";

static bool shouldLogFactoryQrNow() {
#if LOG_FACTORY_QR
  String sig = ESP.getSketchMD5();
  sig.trim();
  if (!sig.length()) {
    // If sketch signature is unavailable, keep backward-compatible behavior.
    return true;
  }
  Preferences p;
  if (!p.begin("aac", false)) return true;
  const String lastSig = p.getString(NVS_KEY_QR_LOG_SIG, "");
  if (lastSig.equalsIgnoreCase(sig)) {
    p.end();
    return false;
  }
  p.putString(NVS_KEY_QR_LOG_SIG, sig);
  const uint32_t prev = p.getUInt(NVS_KEY_QR_LOG_COUNT, 0);
  p.putUInt(NVS_KEY_QR_LOG_COUNT, prev + 1);
  p.end();
  return true;
#else
  return false;
#endif
}

// ✅ QR kod log'u - WiFi ve BLE için tam QR JSON formatında
// NOTE: Aynı firmware binary'si için yalnızca 1 kez log'lanır.
static void logQrIfAllowed() {
#if LOG_FACTORY_QR
#if !ALLOW_SECRET_LOGS
  return;
#endif
  if (!shouldLogFactoryQrNow()) return;
  // QR JSON formatını oluştur (WiFi ve BLE için)
  String id6 = shortChipId();
  String deviceId = id6;
  String apSsid = deviceApSsidForId6(id6);
  String apPass = deriveApPass(id6);
  
  // Setup user ve pass bilgileri varsa ekle
  String qrJson;
  if (g_setupPassEncB64.length() > 0) {
    uint8_t raw[16];
    if (decryptSetupSecret16(g_setupPassEncB64, raw)) {
      String setupHex = bytes16ToHex(raw);
      qrJson = String("{\"deviceId\":\"") + deviceId +
               String("\",\"pairToken\":\"") + g_pairToken +
               String("\",\"user\":\"") + g_setupUser +
               String("\",\"pass\":\"") + setupHex +
               String("\",\"apSsid\":\"") + apSsid +
               String("\",\"apPass\":\"") + apPass +
               String("\",\"proto\":1}");
    } else {
      // Setup pass decrypt edilemediyse sadece temel bilgiler
      qrJson = String("{\"deviceId\":\"") + deviceId +
               String("\",\"pairToken\":\"") + g_pairToken +
               String("\",\"apSsid\":\"") + apSsid +
               String("\",\"apPass\":\"") + apPass +
               String("\",\"proto\":1}");
    }
  } else {
    // Setup pass yoksa sadece temel bilgiler
    qrJson = String("{\"deviceId\":\"") + deviceId +
             String("\",\"pairToken\":\"") + g_pairToken +
             String("\",\"apSsid\":\"") + apSsid +
             String("\",\"apPass\":\"") + apPass +
             String("\",\"proto\":1}");
  }
  
  // Log'la - 2 defa (QR oluşturmak için kolay kopyalamak için)
#if QR_DEBUG_LOG
  Serial.println(String("[QR] ") + qrJson);
  Serial.println(String("[QR] ") + qrJson);
#endif
#endif
}

static void ensureAuthDefaults() {
  bool changed = false;
  if (g_pairToken.isEmpty()) {
    g_pairToken = randomHexString(16);
    changed = true;
  }
  auto id = shortChipId();
  if (changed) {
    persistSecurityState();
    // claimSecretHash is derived from pair token, so force cloud refresh.
    g_cloudDirty = true;
  }
  // QR bilgisi, aynı firmware için sadece bir kez seri loga yazılır.
  logQrIfAllowed();
}

static void markPairTokenTrusted(uint32_t ip32) {
  bool dirty = false;
  if (!g_pairTokenTrusted) {
    g_pairTokenTrusted = true;
    dirty = true;
  }
  if (ip32 != 0 && g_pairTokenTrustedIp != ip32) {
    g_pairTokenTrustedIp = ip32;
    dirty = true;
  }
  if (dirty) {
    persistSecurityState();
  }
}

static void rotatePairToken() {
  g_pairToken = randomHexString(16);
  g_pairTokenTrusted = false;
  g_pairTokenTrustedIp = 0;
  persistSecurityState();
  // claimSecretHash changed; publish updated state/shadow.
  g_cloudDirty = true;
  Serial.println("[AUTH] Pair token rotated");
  logQrIfAllowed(); // ✅ QR token'ı log'la
}

// Signed local HTTP authorization (LAN + SoftAP).
// - Unowned devices: require `Authorization: Bearer <pairToken>` (from QR).
// - Owned devices: require either
//   - a short-lived local session token (X-Session-Token/X-Session-Nonce), OR
//   - an ECDSA signature with a fresh nonce (X-Auth-Nonce/X-Auth-Sig).
//
// Pair token is still accepted on SoftAP subnet as a physical-presence bootstrap,
// but not on LAN once an owner exists.
struct HttpNonceEntry {
  uint32_t ip = 0;
  uint32_t expiresAtMs = 0;
  bool used = false;
  String nonceB64;
};
static HttpNonceEntry g_httpNonces[8];

static const char* httpMethodToStr(HTTPMethod m) {
  switch (m) {
    case HTTP_GET: return "GET";
    case HTTP_POST: return "POST";
    case HTTP_PUT: return "PUT";
    case HTTP_DELETE: return "DELETE";
    case HTTP_PATCH: return "PATCH";
    case HTTP_OPTIONS: return "OPTIONS";
    default: return "OTHER";
  }
}

static inline void logHttpRequestDiag(const char* tag) {
#if HTTP_DIAG_LOG
  const IPAddress rip = g_http.client().remoteIP();
  const String uri = g_http.uri();
  const String auth = g_http.header("Authorization");
  const String qr = g_http.header("X-QR-Token");
  const String sessTok = g_http.header("X-Session-Token");
  const String sessNonce = g_http.header("X-Session-Nonce");
  const String nonce = g_http.header("X-Auth-Nonce");
  const String sig = g_http.header("X-Auth-Sig");
  Serial.printf(
      "[HTTP][REQ][%s] %s %s from=%u.%u.%u.%u authLen=%u qrLen=%u sessTok=%u sessNonce=%u nonce=%u sig=%u\n",
      tag ? tag : "-",
      httpMethodToStr(g_http.method()),
      uri.c_str(),
      (unsigned)rip[0], (unsigned)rip[1], (unsigned)rip[2], (unsigned)rip[3],
      (unsigned)auth.length(),
      (unsigned)qr.length(),
      (unsigned)sessTok.length(),
      (unsigned)sessNonce.length(),
      (unsigned)nonce.length(),
      (unsigned)sig.length());
#else
  (void)tag;
#endif
}

static String bodySha256HexForRequest() {
  if (g_http.hasArg("plain")) {
    return sha256HexOfString(g_http.arg("plain"));
  }
  return sha256HexOfString(String(""));
}

static bool verifyHttpSignatureTrusted(const String& nonceB64,
                                       const String& sigB64,
                                       const char* method,
                                       const String& uri,
                                       const String& bodyShaHex,
                                       BleRole& outRole,
                                       String& outUserIdHash) {
  outRole = BleRole::NONE;
  outUserIdHash.clear();
  if (!method || !method[0]) return false;
  if (!nonceB64.length() || !sigB64.length()) return false;
  if (!bodyShaHex.length()) return false;

  // Canonical message: binds the signature to the exact request.
  const String msg = nonceB64 + "|" + String(method) + "|" + uri + "|" + bodyShaHex;
  const uint8_t* msgBytes = reinterpret_cast<const uint8_t*>(msg.c_str());
  const size_t msgLen = msg.length();

  // Owner key always wins.
  if (g_ownerPubKeyB64.length() &&
      verifyEcdsaP256SignatureOverBytes(g_ownerPubKeyB64, msgBytes, msgLen, sigB64)) {
    outRole = BleRole::OWNER;
    return true;
  }

  // Users list (invited phones) may also authenticate.
  if (!g_usersJson.length()) return false;
  JsonDocument doc;
  JsonArray arr;
  loadUsersArray(doc, arr);
  for (JsonVariant v : arr) {
    JsonObject o = v.as<JsonObject>();
    const char* pub = o["pubkey"] | o["pubKey"] | "";
    if (!pub || !pub[0]) continue;
    if (verifyEcdsaP256SignatureOverBytes(String(pub), msgBytes, msgLen, sigB64)) {
      const char* id = o["id"] | o["userIdHash"] | "";
      const char* roleStr = o["role"] | "USER";
      outUserIdHash = id ? String(id) : String();
      BleRole r = roleFromStr(roleStr);
      if (r == BleRole::OWNER || r == BleRole::SETUP || r == BleRole::NONE) {
        r = BleRole::USER;
      }
      outRole = r;
      return true;
    }
  }
  return false;
}

static String issueHttpNonceForIp(uint32_t ip32, uint32_t nowMs) {
  // ~15s validity, single-use.
  const uint32_t ttlMs = 15000UL;
  HttpNonceEntry* slot = nullptr;
  for (auto& e : g_httpNonces) {
    if (e.ip == ip32) { slot = &e; break; }
  }
  if (!slot) {
    for (auto& e : g_httpNonces) {
      if (e.ip == 0 || (e.expiresAtMs != 0 && (int32_t)(nowMs - e.expiresAtMs) > 0)) {
        slot = &e;
        break;
      }
    }
  }
  if (!slot) {
    // ✅ Tablo dolu: en eski entry'yi kullan (LRU benzeri)
    slot = &g_httpNonces[0];
    uint32_t oldestExpiry = slot->expiresAtMs;
    for (auto& e : g_httpNonces) {
      if (e.expiresAtMs < oldestExpiry) {
        oldestExpiry = e.expiresAtMs;
        slot = &e;
      }
    }
  }
  slot->ip = ip32;
  slot->expiresAtMs = nowMs + ttlMs;
  slot->used = false;
  slot->nonceB64 = makeNonceB64();
  return slot->nonceB64;
}

static bool consumeHttpNonce(uint32_t ip32, const String& nonceB64, uint32_t nowMs) {
  for (auto& e : g_httpNonces) {
    if (e.ip != ip32) continue;
    if (e.nonceB64 != nonceB64) continue;
    if (e.used) return false;
    if (e.expiresAtMs == 0 || (int32_t)(nowMs - e.expiresAtMs) > 0) return false;
    e.used = true;
    return true;
  }
  return false;
}

static inline uint32_t packIpAddress(const IPAddress& ip) {
  return ((uint32_t)ip[0] << 24) |
         ((uint32_t)ip[1] << 16) |
         ((uint32_t)ip[2] << 8) |
         (uint32_t)ip[3];
}

static String previewSecret(const String& s, size_t keep = 8) {
  if (s.length() <= (int)keep) return s;
  return s.substring(0, (int)keep) + "...";
}

#if AUTH_HTTP_DEBUG
#define AUTH_HTTP_PRINTF(...) Serial.printf(__VA_ARGS__)
#define AUTH_HTTP_PRINTLN(x)  Serial.println(x)
#else
#define AUTH_HTTP_PRINTF(...) do {} while (0)
#define AUTH_HTTP_PRINTLN(x)  do {} while (0)
#endif

static bool authorizeBearerPairToken(uint32_t ip32) {
  const String bearer = g_http.header("Authorization");
  if (!bearer.startsWith("Bearer ")) return false;
  String token = bearer.substring(7);
  token.trim();
  if (!token.length()) return false;
  if (!token.equalsIgnoreCase(g_pairToken)) return false;
  markPairTokenTrusted(ip32);
  g_httpAuthMode = HttpAuthMode::PAIR_TOKEN;
  return true;
}

static bool authorizeHeaderQrToken(uint32_t ip32) {
  const String qr = g_http.header("X-QR-Token");
  if (!qr.length()) return false;
  if (!qr.equalsIgnoreCase(g_pairToken)) return false;
  markPairTokenTrusted(ip32);
  g_httpAuthMode = HttpAuthMode::PAIR_TOKEN;
  return true;
}

static inline bool authorizeRequest(bool requireOwner = false, bool allowSession = true) {
  const IPAddress rip = g_http.client().remoteIP();
  const bool fromSoftApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
  const uint32_t nowMs = millis();
  const uint32_t ip32 = packIpAddress(rip);
  logHttpRequestDiag("auth");
  AUTH_HTTP_PRINTF("[AUTH][HTTP] req ip=%u.%u.%u.%u owner=%d requireOwner=%d softap=%d method=%s uri=%s\n",
                   (unsigned)rip[0], (unsigned)rip[1], (unsigned)rip[2], (unsigned)rip[3],
                   g_ownerExists ? 1 : 0, requireOwner ? 1 : 0, fromSoftApNet ? 1 : 0,
                   httpMethodToStr(g_http.method()), g_http.uri().c_str());

  // Reset per-request HTTP role.
  g_httpRole = BleRole::NONE;
  g_httpUserIdHash.clear();
  g_httpAuthMode = HttpAuthMode::NONE;

  if (requireOwner && !g_ownerExists) {
#if HTTP_DIAG_LOG
    Serial.printf("[HTTP][AUTH] deny reason=owner_required uri=%s\n", g_http.uri().c_str());
#endif
    setCORS();
#if PRODUCTION_BUILD
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"forbidden\"}");
#else
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"owner_required\"}");
#endif
    return false;
  }

  // ✅ DEĞİŞİKLİK: QR kod her zaman zorunlu
  // 1) Short-lived local session token - SADECE QR ile açılmış session'lar için
  const bool sessActive =
      (!g_apSessionToken.isEmpty() &&
       g_apSessionUntilMs != 0 &&
       (int32_t)(g_apSessionUntilMs - nowMs) > 0);
  if (allowSession && sessActive) {
    // Session yalnızca "trusted" yollarla açıldıysa geçerli sayılır. Bazı akışlar
    // (örn. BLE üzerinden AP_START veya fiziksel buton) session üretir; bu durumda
    // session header'ları yoksa bearer/QR fallback'e izin ver.
    // (Aksi halde cihaz, session açıkken tüm istekleri kilitleyebiliyordu.)
    
    String tok = g_http.header("X-Session-Token");
    String non = g_http.header("X-Session-Nonce");
    String ua  = g_http.header("User-Agent");
    tok.trim(); non.trim(); ua.trim();
    AUTH_HTTP_PRINTF("[AUTH][HTTP] session active=1 token=%u nonce=%u ua=%u openedWithQr=%d bound=%d\n",
                     (unsigned)tok.length(), (unsigned)non.length(), (unsigned)ua.length(),
                     g_apSessionOpenedWithQr ? 1 : 0, g_apSessionBound ? 1 : 0);
    if (tok.length() && tok.equals(g_apSessionToken) &&
        non.length() && non.equals(g_apSessionNonce)) {
      if (!g_apSessionOpenedWithQr) {
        AUTH_HTTP_PRINTLN("[AUTH][HTTP] session not trusted");
        setCORS();
#if PRODUCTION_BUILD
        g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"unauthorized\"}");
#else
        g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"session_not_trusted\"}");
#endif
        return false;
      }
      // Bind session to remote IP + User-Agent on first use.
      const uint32_t ip32 =
          ((uint32_t)rip[0] << 24) | ((uint32_t)rip[1] << 16) | ((uint32_t)rip[2] << 8) | (uint32_t)rip[3];
      uint8_t h[32];
      if (!computeSha256Bytes((const uint8_t*)ua.c_str(), (size_t)ua.length(), h)) {
        h[0] = h[1] = h[2] = h[3] = 0;
      }
      const uint32_t ua32 =
          ((uint32_t)h[0] << 24) | ((uint32_t)h[1] << 16) | ((uint32_t)h[2] << 8) | (uint32_t)h[3];
      if (!g_apSessionBound) {
        g_apSessionBound = true;
        g_apSessionBindIp = ip32;
        g_apSessionBindUa = ua32;
      } else if (g_apSessionBindIp != ip32 || g_apSessionBindUa != ua32) {
        AUTH_HTTP_PRINTLN("[AUTH][HTTP] session bound mismatch");
        setCORS();
#if PRODUCTION_BUILD
        g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"unauthorized\"}");
#else
        g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"session_bound_mismatch\"}");
#endif
        return false;
      }
      g_httpRole = BleRole::OWNER;
      g_httpAuthMode = HttpAuthMode::SESSION;
      AUTH_HTTP_PRINTLN("[AUTH][HTTP] session ok role=OWNER");
      return true;
    }
  }

  // ✅ DEĞİŞİKLİK: Unowned cihazlarda sadece QR pair token
  if (!g_ownerExists) {
    const String hdrAuth = g_http.header("Authorization");
    const String hdrQr = g_http.header("X-QR-Token");
    AUTH_HTTP_PRINTF("[AUTH][HTTP] unowned headers authLen=%u qrLen=%u authPreview=%s qrPreview=%s\n",
                     (unsigned)hdrAuth.length(), (unsigned)hdrQr.length(),
                     previewSecret(hdrAuth, 12).c_str(), previewSecret(hdrQr, 8).c_str());
    if (authorizeHeaderQrToken(ip32) || authorizeBearerPairToken(ip32)) {
      g_httpRole = BleRole::OWNER;
      AUTH_HTTP_PRINTLN("[AUTH][HTTP] unowned qr/bearer ok role=OWNER");
      return true;
    }
    AUTH_HTTP_PRINTLN("[AUTH][HTTP] unowned qr/bearer failed");
#if HTTP_DIAG_LOG
    Serial.printf("[HTTP][AUTH] deny reason=qr_token_required uri=%s\n", g_http.uri().c_str());
#endif
    setCORS();
#if PRODUCTION_BUILD
    g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"unauthorized\"}");
#else
    g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"qr_token_required\"}");
#endif
    return false;
  }

  // Owned cihazlarda QR/pairToken ile local kontrol YOK.
  // Only signed (owner/user) requests are allowed.
  const String nonceB64 = g_http.header("X-Auth-Nonce");
  const String sigB64 = g_http.header("X-Auth-Sig");
  const String uri = g_http.uri();
  const String bodySha = bodySha256HexForRequest();
  AUTH_HTTP_PRINTF("[AUTH][HTTP] owned headers nonceLen=%u sigLen=%u bodySha=%s\n",
                   (unsigned)nonceB64.length(), (unsigned)sigB64.length(),
                   previewSecret(bodySha, 12).c_str());

  BleRole role = BleRole::NONE;
  String userId;
  if (nonceB64.length() && sigB64.length()) {
    // ECDSA signature doğrula
    const uint32_t ip32 =
        ((uint32_t)rip[0] << 24) | ((uint32_t)rip[1] << 16) | ((uint32_t)rip[2] << 8) | (uint32_t)rip[3];
    if (consumeHttpNonce(ip32, nonceB64, nowMs) &&
        verifyHttpSignatureTrusted(nonceB64, sigB64, httpMethodToStr(g_http.method()), uri, bodySha, role, userId)) {
      // Owned devices: ECDSA signature is the only accepted local auth.
      g_httpRole = role;
      g_httpUserIdHash = userId;
      g_httpAuthMode = HttpAuthMode::SIGNATURE;
      AUTH_HTTP_PRINTF("[AUTH][HTTP] owned sig ok role=%s userIdHash=%s\n",
                       roleToStr(role), userId.c_str());
      return true;
    }
  }

  AUTH_HTTP_PRINTLN("[AUTH][HTTP] owned sig failed -> auth_required");
#if HTTP_DIAG_LOG
  Serial.printf("[HTTP][AUTH] deny reason=auth_required uri=%s\n", g_http.uri().c_str());
#endif
  setCORS();
#if PRODUCTION_BUILD
  g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"unauthorized\"}");
#else
  g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"auth_required\"}");
#endif
  return false;
}

static bool requireHttpRole(BleRole minRole) {
  if (!g_ownerExists) return true;
  const BleRole role = effectiveRole(g_httpRole);
  if ((uint8_t)role < (uint8_t)minRole) {
#if HTTP_DIAG_LOG
    Serial.printf("[HTTP][AUTH] deny reason=insufficient_role have=%s need=%s uri=%s\n",
                  roleToStr(role),
                  roleToStr(minRole),
                  g_http.uri().c_str());
#endif
    setCORS();
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"insufficient_role\"}");
    return false;
  }
  return true;
}

// =================== Simple per-IP rate limiting (SoftAP & LAN) ===================
enum class RateKind : uint8_t { BOOTSTRAP = 0, PROV = 1, JOIN = 2, CMD = 3, _MAX = 4 };
struct RateEntry {
  uint32_t ip = 0; // network-order packed (a<<24|b<<16|c<<8|d)
  uint32_t winStart[(uint8_t)RateKind::_MAX] = {0};
  uint8_t  count[(uint8_t)RateKind::_MAX] = {0};
  uint32_t blockedUntil[(uint8_t)RateKind::_MAX] = {0};
};
static RateEntry g_rate[8];

static uint32_t ipToU32(const IPAddress& ip) {
  return ((uint32_t)ip[0] << 24) | ((uint32_t)ip[1] << 16) | ((uint32_t)ip[2] << 8) | (uint32_t)ip[3];
}

static bool rateLimitAllow(RateKind kind,
                           const IPAddress& rip,
                           uint32_t nowMs,
                           uint8_t maxPerSec,
                           uint32_t cooldownMs,
                           uint32_t& outRetryMs) {
  outRetryMs = 0;
  const uint8_t k = (uint8_t)kind;
  const uint32_t ip32 = ipToU32(rip);
  RateEntry* e = nullptr;
  for (auto& it : g_rate) {
    if (it.ip == ip32) {
      e = &it;
      break;
    }
  }
  if (!e) {
    for (auto& it : g_rate) {
      if (it.ip == 0) {
        it.ip = ip32;
        e = &it;
        break;
      }
    }
  }
  if (!e) {
    // ✅ Table full: be conservative and REJECT (güvenlik için)
    outRetryMs = 1000; // 1 saniye sonra tekrar dene
    return false;
  }
  if (e->blockedUntil[k] != 0 && (int32_t)(nowMs - e->blockedUntil[k]) < 0) {
    outRetryMs = e->blockedUntil[k] - nowMs;
    return false;
  }
  if (e->winStart[k] == 0 || (nowMs - e->winStart[k]) >= 1000UL) {
    e->winStart[k] = nowMs;
    e->count[k] = 0;
  }
  if (e->count[k] >= maxPerSec) {
    e->blockedUntil[k] = nowMs + cooldownMs;
    outRetryMs = cooldownMs;
    return false;
  }
  e->count[k]++;
  return true;
}

static bool enforceRateLimitOrSend(RateKind kind, uint8_t maxPerSec, uint32_t cooldownMs) {
  IPAddress rip = g_http.client().remoteIP();
  uint32_t retryMs = 0;
  if (!rateLimitAllow(kind, rip, millis(), maxPerSec, cooldownMs, retryMs)) {
    setCORS();
    JsonDocument d;
    d["ok"] = false;
    d["err"] = "rate_limited";
    d["retryMs"] = retryMs;
    String out;
    serializeJson(d, out);
    g_http.send(429, "application/json", out);
    return false;
  }
  return true;
}

/* =================== Helpers =================== */

static String formatId6FromMac(const uint8_t mac[6]) {
  const uint32_t raw = ((uint32_t)mac[3] << 16) | ((uint32_t)mac[4] << 8) | mac[5];
  const uint32_t id6 = raw % 1000000UL;
  char buf[7];
  snprintf(buf, sizeof(buf), "%06lu", (unsigned long)id6);
  return String(buf);
}

static String shortChipId() {
  uint8_t mac[6] = {0};
  // 1) Prefer SoftAP MAC so the ID matches the AP interface
  if (esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP) == ESP_OK) {
    return formatId6FromMac(mac);
  }
  // 2) Fallback to STA MAC
  if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) {
    return formatId6FromMac(mac);
  }
  // 3) Fallback to base efuse MAC
  if (esp_efuse_mac_get_default(mac) == ESP_OK) {
    return formatId6FromMac(mac);
  }
  // 4) Last resort: use Arduino helper to never return empty
  uint64_t chipid = ESP.getEfuseMac();
  const uint32_t raw = (uint32_t)(chipid & 0xFFFFFFu);
  const uint32_t id6 = raw % 1000000UL;
  char buf[7];
  snprintf(buf, sizeof(buf), "%06lu", (unsigned long)id6);
  return String(buf);
}


static String genCmdIdHex8() {
#if defined(ARDUINO_ARCH_ESP32)
  uint32_t r = (uint32_t)esp_random();
#else
  uint32_t r = (uint32_t)random(0xFFFFFFFFu);
#endif
  char buf[9];
  snprintf(buf, sizeof(buf), "%08lX", (unsigned long)r);
  return String(buf);
}

static inline void queueAlert(const char*, const char*, const char*) {}

// Per-device AP password (stable across reboots/updates, changes only on flash erase).
// We derive it from device_secret so it's not guessable from the SSID/ID.
static String deriveApPass(const String& id6) {
  auto fallbackSecureApPass = [&id6]() -> String {
#if defined(ARDUINO_ARCH_ESP32)
    uint8_t out[32];
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
      mbedtls_sha256_free(&ctx);
      return String("psk") + id6 + chipCode4();
    }
    const uint64_t mac = ESP.getEfuseMac();
    (void)mbedtls_sha256_update_ret(&ctx, (const uint8_t*)&mac, sizeof(mac));
    const char* tag = "AP_FALLBACK|";
    (void)mbedtls_sha256_update_ret(&ctx, (const uint8_t*)tag, strlen(tag));
    (void)mbedtls_sha256_update_ret(&ctx, (const uint8_t*)id6.c_str(), (size_t)id6.length());
    if (mbedtls_sha256_finish_ret(&ctx, out) != 0) {
      mbedtls_sha256_free(&ctx);
      return String("psk") + id6 + chipCode4();
    }
    mbedtls_sha256_free(&ctx);
    return bytes16ToHex(out);
#else
    return String("psk") + id6;
#endif
  };

  if (!g_deviceSecretLoaded) {
    // Fallback (shouldn't happen after loadPrefs): deterministic and not directly guessable.
    return fallbackSecureApPass();
  }
#if defined(ARDUINO_ARCH_ESP32)
  uint8_t out[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  if (mbedtls_sha256_starts_ret(&ctx, 0) != 0) {
    mbedtls_sha256_free(&ctx);
    return fallbackSecureApPass();
  }
  (void)mbedtls_sha256_update_ret(&ctx, g_deviceSecret, sizeof(g_deviceSecret));
  const char* tag = "AP|";
  (void)mbedtls_sha256_update_ret(&ctx, (const uint8_t*)tag, strlen(tag));
  (void)mbedtls_sha256_update_ret(&ctx, (const uint8_t*)id6.c_str(), (size_t)id6.length());
  if (mbedtls_sha256_finish_ret(&ctx, out) != 0) {
    mbedtls_sha256_free(&ctx);
    return fallbackSecureApPass();
  }
  mbedtls_sha256_free(&ctx);
  // 16 bytes -> 32 hex chars (WPA2 PSK limit ok)
  return bytes16ToHex(out);
#else
  return fallbackSecureApPass();
#endif
}

// Return last 4 hex chars of MAC (uppercase)
static String chipCode4() {
  uint32_t macLow = (uint32_t)ESP.getEfuseMac();
  uint16_t last = (uint16_t)(macLow & 0xFFFF);
  char buf[5];
  snprintf(buf, sizeof(buf), "%04X", last);
  return String(buf);
}

static uint32_t derivePasskey() {
  uint32_t macLow = (uint32_t)ESP.getEfuseMac();
  uint32_t n = (macLow ^ 0x5A5A5A) % 900000; // 0..899999
  return 100000 + n;                          // 100000..999999
}

inline void relayWrite(uint8_t pin, bool on) {
  if (pin == 255) return;
  if (g_relayCfg.activeLow) digitalWrite(pin, on ? LOW : HIGH);
  else                      digitalWrite(pin, on ? HIGH : LOW);
}

void setFanPercent(uint8_t pct) {
  static int s_lastPct = -1;
  static int s_lastAppliedPct = -1;
  pct = constrain(pct, 0, 100);
  app.fanPercent = pct;
  const uint8_t appliedPct = app.masterOn ? pct : 0;
  const bool fanEnable = (appliedPct > 0);
  if (PIN_FAN_AUX_EN != 255) {
    digitalWrite(PIN_FAN_AUX_EN,
                 (FAN_AUX_EN_ACTIVE_HIGH ? fanEnable : !fanEnable) ? HIGH : LOW);
  }
  uint32_t duty = map(appliedPct, 0, 100, 0, dutyMax());
  if (FAN_PWM_INVERTED) duty = dutyMax() - duty;
  ledcWrite(CH_FAN, duty);
  uint32_t dutyAlt = duty;
  if (FAN_PWM_MIRROR_ALT_ENABLE) {
    if (FAN_PWM_MIRROR_ALT_INVERT) dutyAlt = dutyMax() - duty;
    ledcWrite(CH_FAN_ALT, dutyAlt);
  }
  if ((int)pct != s_lastPct || (int)appliedPct != s_lastAppliedPct) {
    s_lastPct = (int)pct;
    s_lastAppliedPct = (int)appliedPct;
#if FAN_DEBUG_LOG
    Serial.printf("[FAN] set pct=%u applied=%u duty=%u altDuty=%u/%u auxPin=%u auxEn=%d master=%d\n",
                  (unsigned)pct,
                  (unsigned)appliedPct,
                  (unsigned)duty,
                  (unsigned)dutyAlt,
                  (unsigned)dutyMax(),
                  (unsigned)PIN_FAN_AUX_EN,
                  fanEnable ? 1 : 0,
                  app.masterOn ? 1 : 0);
#endif
  }
}

static void _writeRGB(uint8_t r, uint8_t g, uint8_t b) {
#if USE_ADDR_LED_PROTOCOL
  if (g_frameSolidCacheValid &&
      g_frameSolidLastR == r &&
      g_frameSolidLastG == g &&
      g_frameSolidLastB == b) return;
  g_frameSolidCacheValid = true;
  g_frameSolidLastR = r;
  g_frameSolidLastG = g;
  g_frameSolidLastB = b;
  const uint32_t c = g_framePixels.Color(r, g, b);
  for (uint16_t i = 0; i < g_framePixels.numPixels(); ++i) {
    g_framePixels.setPixelColor(i, c);
  }
  g_framePixels.show();
#else
  auto w = [&](uint8_t ch, uint8_t v){
    uint32_t duty = map(v, 0, 255, 0, dutyMax());
    ledcWrite(ch, duty);
  };
  w(CH_R, r); w(CH_G, g); w(CH_B, b);
#endif
}

static inline bool cleanSnakeShowActive() {
  return g_cleanSnakeShowActive;
}

static inline bool autoSnakeShowActive() {
  return g_autoSnakeShowActive;
}

static bool fanModeShowColor(FanMode mode, uint8_t& r, uint8_t& g, uint8_t& b) {
  switch (mode) {
    case FAN_SLEEP:
    case FAN_LOW:
      r = 0; g = 255; b = 0;
      return true;
    case FAN_MED:
      r = 0; g = 0; b = 255;
      return true;
    case FAN_HIGH:
    case FAN_TURBO:
      r = 255; g = 0; b = 0;
      return true;
    default:
      return false;
  }
}

static void startFanModeShow(FanMode mode, uint32_t nowMs) {
  if (!app.masterOn) return;
  if (mode == FAN_AUTO) {
    startAutoSnakeShow(nowMs);
    return;
  }
  uint8_t r = 0, g = 0, b = 0;
  if (!fanModeShowColor(mode, r, g, b)) return;
  g_fanModeShowActive = true;
  g_fanModeShowStartMs = nowMs;
  g_fanModeShowR = r;
  g_fanModeShowG = g;
  g_fanModeShowB = b;
  // Start from fully off; loop updates will apply the breathing curve.
  _writeRGB((uint16_t)r * FAN_MODE_SHOW_START_LEVEL / 255U,
            (uint16_t)g * FAN_MODE_SHOW_START_LEVEL / 255U,
            (uint16_t)b * FAN_MODE_SHOW_START_LEVEL / 255U);
}

static void updateFanModeShow(uint32_t nowMs) {
  if (!g_fanModeShowActive) return;
  const uint32_t elapsed = nowMs - g_fanModeShowStartMs;
  if (elapsed >= FAN_MODE_SHOW_DURATION_MS) {
    g_fanModeShowActive = false;
    if (autoSnakeShowActive()) updateAutoSnakeShow(nowMs);
    else if (cleanSnakeShowActive()) updateCleanSnakeShow(nowMs);
    else applyRgb();
    return;
  }

  // Use an asymmetric breath:
  // slow, soft rise to full brightness, then a shorter smooth fade-out.
  const float phase = (float)elapsed / (float)FAN_MODE_SHOW_DURATION_MS; // 0..1
  const float pi = 3.14159265f;
  const float riseShare = 0.62f;
  float breath = 0.0f;
  if (phase < riseShare) {
    const float riseT = phase / riseShare; // 0..1
    breath = 0.5f - 0.5f * cosf(riseT * pi); // slow 0 -> 1
  } else {
    const float fallT = (phase - riseShare) / (1.0f - riseShare); // 0..1
    breath = 0.5f + 0.5f * cosf(fallT * pi); // smooth 1 -> 0
  }
  const uint8_t level = g_framePixels.gamma8(
      (uint8_t)roundf(fminf(fmaxf(breath, 0.0f), 1.0f) * 255.0f));

  const uint8_t outR = (uint16_t)g_fanModeShowR * level / 255U;
  const uint8_t outG = (uint16_t)g_fanModeShowG * level / 255U;
  const uint8_t outB = (uint16_t)g_fanModeShowB * level / 255U;
  _writeRGB(outR, outG, outB);
}

static void startCleanSnakeShow(uint32_t nowMs) {
  g_cleanSnakeShowActive = true;
  g_cleanSnakeShowStartMs = nowMs;
}

static void startAutoSnakeShow(uint32_t nowMs) {
  g_autoSnakeShowActive = true;
  g_autoSnakeShowStartMs = nowMs;
}

static void updateAutoSnakeShow(uint32_t nowMs) {
#if USE_ADDR_LED_PROTOCOL
  if (!g_autoSnakeShowActive) return;
  const uint32_t elapsed = nowMs - g_autoSnakeShowStartMs;
  if (elapsed >= CLEAN_SNAKE_SHOW_DURATION_MS) {
    g_autoSnakeShowActive = false;
    g_frameSolidCacheValid = false;
    if (cleanSnakeShowActive()) updateCleanSnakeShow(nowMs);
    else applyRgb();
    return;
  }
  if (g_fanModeShowActive) return;

  g_frameSolidCacheValid = false;

  const uint16_t count = g_framePixels.numPixels();
  if (count == 0) return;

  const uint16_t head = (uint16_t)((nowMs / CLEAN_SNAKE_STEP_MS) % count);
  static const uint8_t kColors[3][3] = {
    {255, 0, 0},
    {0, 255, 0},
    {0, 0, 255},
  };

  for (uint16_t i = 0; i < count; ++i) {
    g_framePixels.setPixelColor(i, 0);
  }

  const uint16_t spacing = count / 3U ? count / 3U : 1U;
  for (uint8_t snake = 0; snake < 3; ++snake) {
    const uint16_t snakeHead = (uint16_t)((head + (snake * spacing)) % count);
    for (uint16_t trail = 0; trail < CLEAN_SNAKE_TAIL_PIXELS; ++trail) {
      const uint16_t pixel = (uint16_t)((snakeHead + count - trail) % count);
      const float t = 1.0f - ((float)trail / (float)CLEAN_SNAKE_TAIL_PIXELS);
      const uint8_t level = g_framePixels.gamma8((uint8_t)roundf(t * 255.0f));
      const uint8_t r = (uint16_t)kColors[snake][0] * level / 255U;
      const uint8_t g = (uint16_t)kColors[snake][1] * level / 255U;
      const uint8_t b = (uint16_t)kColors[snake][2] * level / 255U;
      g_framePixels.setPixelColor(pixel, g_framePixels.Color(r, g, b));
    }
  }
  g_framePixels.show();
#else
  (void)nowMs;
#endif
}

static void updateCleanSnakeShow(uint32_t nowMs) {
#if USE_ADDR_LED_PROTOCOL
  if (!g_cleanSnakeShowActive) {
    return;
  }
  const uint32_t elapsed = nowMs - g_cleanSnakeShowStartMs;
  if (elapsed >= CLEAN_SNAKE_SHOW_DURATION_MS) {
    g_cleanSnakeShowActive = false;
    g_frameSolidCacheValid = false;
    applyRgb();
    return;
  }
  if (g_fanModeShowActive || g_autoSnakeShowActive) return;

  g_frameSolidCacheValid = false;

  const uint16_t count = g_framePixels.numPixels();
  if (count == 0) return;

  const uint16_t head = (uint16_t)((nowMs / CLEAN_SNAKE_STEP_MS) % count);
  const uint8_t baseR = 96;
  const uint8_t baseG = 0;
  const uint8_t baseB = 255;

  for (uint16_t i = 0; i < count; ++i) {
    g_framePixels.setPixelColor(i, 0);
  }

  for (uint16_t trail = 0; trail < CLEAN_SNAKE_TAIL_PIXELS; ++trail) {
    const uint16_t pixel = (uint16_t)((head + count - trail) % count);
    const float t = 1.0f - ((float)trail / (float)CLEAN_SNAKE_TAIL_PIXELS);
    const uint8_t level = g_framePixels.gamma8((uint8_t)roundf(t * 255.0f));
    const uint8_t r = (uint16_t)baseR * level / 255U;
    const uint8_t g = (uint16_t)baseG * level / 255U;
    const uint8_t b = (uint16_t)baseB * level / 255U;
    g_framePixels.setPixelColor(pixel, g_framePixels.Color(r, g, b));
  }
  g_framePixels.show();
#else
  (void)nowMs;
#endif
}

void applyRgb() {
  if (g_fanModeShowActive || cleanSnakeShowActive() || autoSnakeShowActive()) return;
  uint8_t outR = 0, outG = 0, outB = 0;
  if (app.masterOn && app.rgbOn && app.rgbBrightness > 0) {
    outR = (uint16_t)app.r * app.rgbBrightness / 100;
    outG = (uint16_t)app.g * app.rgbBrightness / 100;
    outB = (uint16_t)app.b * app.rgbBrightness / 100;
  }
  _writeRGB(outR, outG, outB);
}

uint8_t modeToPercent(FanMode m) {
  switch (m) {
    case FAN_SLEEP: return 20;
    case FAN_LOW:   return 35;
    case FAN_MED:   return 50;
    case FAN_HIGH:  return 65;
    case FAN_TURBO: return 100;
    default:        return app.fanPercent; // AUTO
  }
}

/* ===== Relay helper (simple apply) ===== */
// Otomatik sulama/nem için ek bir röle:
// PIN_RLY_WATER (ATOM_EN / IO32) g_waterRelayOn durumuna göre sürülür.
static bool     g_waterRelayOn      = false;
static uint32_t g_waterRelayOffAtMs = 0;
// Doa otomatik / manuel sulama durumu
static bool     g_waterManualOn     = false;
static bool     g_waterAutoEnabled  = false;
static uint16_t g_waterDurationMin  = 0;   // dakika
static uint16_t g_waterIntervalMin  = 0;   // dakika
static uint32_t g_lastWaterStartMs  = 0;
// Doa için nem bazlı otomatik sulama
static bool     g_doaHumAutoEnabled    = false;
static bool     g_doaHumHadWaterCycle  = false;
static uint32_t g_doaHumNextCheckMs    = 0;
static uint8_t  g_irFactoryResetSeqIndex = 0;
static uint32_t g_irFactoryResetSeqDeadlineMs = 0;
static uint8_t  g_irSoftRecoverySeqIndex = 0;
static uint32_t g_irSoftRecoverySeqDeadlineMs = 0;

static void resetIrFactoryResetSequence(const char* reason = nullptr) {
  if (reason && g_irFactoryResetSeqIndex != 0) {
    Serial.printf("[IR][RESET] sequence cleared (%s)\n", reason);
  }
  g_irFactoryResetSeqIndex = 0;
  g_irFactoryResetSeqDeadlineMs = 0;
}

static void resetIrSoftRecoverySequence(const char* reason = nullptr) {
  if (reason && g_irSoftRecoverySeqIndex != 0) {
    Serial.printf("[IR][RECOVERY] sequence cleared (%s)\n", reason);
  }
  g_irSoftRecoverySeqIndex = 0;
  g_irSoftRecoverySeqDeadlineMs = 0;
}

static void startSoftRecoveryWindow(uint32_t nowMs, const char* reason) {
  Serial.printf("[IR][RECOVERY] soft recovery window opened reason=%s ttl=%lus\n",
                reason ? reason : "unknown",
                (unsigned long)(SOFT_RECOVERY_WINDOW_MS / 1000UL));
  // For recovery we rotate pair token so old leaked tokens cannot be reused.
  rotatePairToken();
  startAP();
  g_apSessionToken = randomHexString(8);
  g_apSessionNonce = randomHexString(8);
  g_apSessionUntilMs = nowMs + SOFT_RECOVERY_WINDOW_MS;
  g_apSessionOpenedWithQr = true;
  g_apSessionBound = false;
  g_apSessionBindIp = 0;
  g_apSessionBindUa = 0;
  openPairingWindow(SOFT_RECOVERY_WINDOW_MS);
  openOwnerRotateWindow(SOFT_RECOVERY_WINDOW_MS);
  Serial.printf("[IR][RECOVERY] window opened ttl_ms=%u\n",
                (unsigned)SOFT_RECOVERY_WINDOW_MS);
}

static bool handleIrSoftRecoverySequence(uint32_t necCode, uint32_t nowMs) {
  static const uint32_t kSeq[] = {
      IR_CODE_AUTO_HUM_TOGGLE,
      IR_CODE_AUTO_HUM_TOGGLE,
      IR_CODE_AUTO_HUM_TOGGLE,
      IR_CODE_ION_TOGGLE,
      IR_CODE_ION_TOGGLE,
      IR_CODE_ION_TOGGLE,
  };

  if ((g_irSoftRecoverySeqDeadlineMs != 0) &&
      (int32_t)(nowMs - g_irSoftRecoverySeqDeadlineMs) >= 0) {
    resetIrSoftRecoverySequence("timeout");
  }

  if (necCode == kSeq[g_irSoftRecoverySeqIndex]) {
    g_irSoftRecoverySeqIndex++;
    g_irSoftRecoverySeqDeadlineMs = nowMs + IR_SOFT_RECOVERY_STEP_TIMEOUT_MS;
    Serial.printf("[IR][RECOVERY] sequence step %u/%u\n",
                  (unsigned)g_irSoftRecoverySeqIndex,
                  (unsigned)(sizeof(kSeq) / sizeof(kSeq[0])));
    if (g_irSoftRecoverySeqIndex >= (sizeof(kSeq) / sizeof(kSeq[0]))) {
      resetIrSoftRecoverySequence("confirmed");
      startSoftRecoveryWindow(nowMs, "ir_combo");
      return true;
    }
    return false;
  }

  if (necCode == kSeq[0]) {
    g_irSoftRecoverySeqIndex = 1;
    g_irSoftRecoverySeqDeadlineMs = nowMs + IR_SOFT_RECOVERY_STEP_TIMEOUT_MS;
    Serial.printf("[IR][RECOVERY] sequence restarted 1/%u\n",
                  (unsigned)(sizeof(kSeq) / sizeof(kSeq[0])));
    return false;
  }

  if (g_irSoftRecoverySeqIndex != 0) {
    resetIrSoftRecoverySequence("mismatch");
  }
  return false;
}

static bool handleIrFactoryResetSequence(uint32_t necCode, uint32_t nowMs) {
  static const uint32_t kSeq[] = {
      IR_CODE_ION_TOGGLE,
      IR_CODE_FAN_MODE_DOWN,
      IR_CODE_AUTO_HUM_TOGGLE,
      IR_CODE_FAN_MODE_UP,
      IR_CODE_ION_TOGGLE,
      IR_CODE_ION_TOGGLE,
      IR_CODE_ION_TOGGLE,
  };

  if ((g_irFactoryResetSeqDeadlineMs != 0) &&
      (int32_t)(nowMs - g_irFactoryResetSeqDeadlineMs) >= 0) {
    resetIrFactoryResetSequence("timeout");
  }

  if (necCode == kSeq[g_irFactoryResetSeqIndex]) {
    g_irFactoryResetSeqIndex++;
    g_irFactoryResetSeqDeadlineMs = nowMs + IR_FACTORY_RESET_STEP_TIMEOUT_MS;
    Serial.printf("[IR][RESET] sequence step %u/%u\n",
                  (unsigned)g_irFactoryResetSeqIndex,
                  (unsigned)(sizeof(kSeq) / sizeof(kSeq[0])));
    if (g_irFactoryResetSeqIndex >= (sizeof(kSeq) / sizeof(kSeq[0]))) {
      Serial.println("[IR][RESET] factory reset confirmed by IR");
      resetIrFactoryResetSequence("confirmed");
      scheduleFactoryReset("ir_sequence", 500);
      return true;
    }
    return false;
  }

  if (necCode == kSeq[0]) {
    g_irFactoryResetSeqIndex = 1;
    g_irFactoryResetSeqDeadlineMs = nowMs + IR_FACTORY_RESET_STEP_TIMEOUT_MS;
    Serial.printf("[IR][RESET] sequence restarted 1/%u\n",
                  (unsigned)(sizeof(kSeq) / sizeof(kSeq[0])));
    return false;
  }

  if (g_irFactoryResetSeqIndex != 0) {
    resetIrFactoryResetSequence("mismatch");
  }
  return false;
}

static void applyRelays() {
  const bool ionOut = app.masterOn && (app.cleanOn || app.ionOn);
  const bool lightOut = app.masterOn && app.lightOn;
  const bool humOut =
      (g_relayCfg.waterRequiresMaster ? app.masterOn : true) && g_waterRelayOn;

  // Board-specific logical inversions per channel.
  const bool lightDrive = g_relayCfg.invertLight ? !lightOut : lightOut;
  const bool ionDrive   = g_relayCfg.invertIon   ? !ionOut  : ionOut;
  const bool humDrive   = g_relayCfg.invertWater ? !humOut  : humOut;
  // Debug: logical state + effective drive levels (before relayWrite active-low/high conversion).
  Serial.printf(
      "[RELAY] master=%d light=%d clean=%d ion=%d ionOut=%d %sOut=%d drive(light=%d ion=%d %s=%d)\n",
      app.masterOn ? 1 : 0,
      app.lightOn ? 1 : 0,
      app.cleanOn ? 1 : 0,
      app.ionOn ? 1 : 0,
      ionOut ? 1 : 0,
      g_relayCfg.waterLabel,
      humOut ? 1 : 0,
      lightDrive ? 1 : 0,
      ionDrive ? 1 : 0,
      g_relayCfg.waterLabel,
      humDrive ? 1 : 0);
  relayWrite(g_relayCfg.pinLight, lightDrive);
  relayWrite(g_relayCfg.pinIon,   ionDrive);
  relayWrite(g_relayCfg.pinMain,  app.masterOn);
  relayWrite(g_relayCfg.pinWater, humDrive);
}

static void handleIrNecCommand(uint32_t necCode) {
#if ENABLE_IR_RX_DEBUG
  static uint32_t s_lastCode = 0;
  static uint32_t s_lastMs = 0;
  const uint32_t nowMs = millis();
  if (necCode == s_lastCode && (nowMs - s_lastMs) < 220) {
    return;
  }
  s_lastCode = necCode;
  s_lastMs = nowMs;

#if ENABLE_IR_FACTORY_RESET_COMBO
  if (handleIrFactoryResetSequence(necCode, nowMs)) {
    return;
  }
#endif
#if ENABLE_IR_SOFT_RECOVERY_COMBO
  if (handleIrSoftRecoverySequence(necCode, nowMs)) {
    return;
  }
#endif

  bool changed = false;
  bool relaysNeedApply = false;
  bool rgbNeedApply = false;
  bool fanNeedApply = false;
  const char* voicePath = nullptr;
  const char* voiceFallback = nullptr;

  if (necCode == IR_CODE_POWER_TOGGLE) {
    app.masterOn = !app.masterOn;
    startCleanSnakeShow(nowMs);
    changed = true;
    relaysNeedApply = true;
    rgbNeedApply = true;
    fanNeedApply = true;
    voicePath = app.masterOn ? IR_VOICE_POWER_ON : IR_VOICE_POWER_OFF;
    voiceFallback = nullptr;
    Serial.printf("[IR] power toggle -> masterOn=%d\n", app.masterOn ? 1 : 0);
  } else if (necCode == IR_CODE_FRAME_LIGHT_TOGGLE) {
    app.lightOn = !app.lightOn;
    changed = true;
    relaysNeedApply = true;
    voicePath = app.lightOn ? IR_VOICE_LIGHT_ON : IR_VOICE_LIGHT_OFF;
    voiceFallback = nullptr;
    Serial.printf("[IR] light toggle -> lightOn=%d\n", app.lightOn ? 1 : 0);
  } else if (necCode == IR_CODE_ION_TOGGLE) {
    app.ionOn = !app.ionOn;
    changed = true;
    relaysNeedApply = true;
    voicePath = app.ionOn ? IR_VOICE_ION_ON : IR_VOICE_ION_OFF;
    voiceFallback = nullptr;
    Serial.printf("[IR] ion toggle -> ionOn=%d\n", app.ionOn ? 1 : 0);
  } else if (IR_CODE_AUTO_HUM_TOGGLE != 0UL && necCode == IR_CODE_AUTO_HUM_TOGGLE) {
    app.autoHumEnabled = !app.autoHumEnabled;
    changed = true;
    voicePath = app.autoHumEnabled ? IR_VOICE_HUM_ON : IR_VOICE_HUM_OFF;
    voiceFallback = nullptr;
    Serial.printf("[IR] auto humidity toggle -> autoHumEnabled=%d\n", app.autoHumEnabled ? 1 : 0);
  } else if (necCode == IR_CODE_FAN_MODE_UP || necCode == IR_CODE_FAN_MODE_DOWN) {
    static const FanMode kModes[] = {FAN_SLEEP, FAN_LOW, FAN_MED, FAN_HIGH, FAN_TURBO};
    int idx = -1;
    for (int i = 0; i < 5; ++i) {
      if (app.mode == kModes[i]) { idx = i; break; }
    }
    if (idx < 0) {
      const uint8_t fp = app.fanPercent;
      if (fp <= 27) idx = 0;
      else if (fp <= 42) idx = 1;
      else if (fp <= 57) idx = 2;
      else if (fp <= 82) idx = 3;
      else idx = 4;
    }

    FanMode newMode = app.mode;
    if (necCode == IR_CODE_FAN_MODE_UP) {
      if (app.mode == FAN_AUTO) {
        newMode = FAN_AUTO;
      } else if (idx < 4) {
        newMode = kModes[idx + 1];
      } else {
        // TURBO'dan sonra AUTO
        newMode = FAN_AUTO;
      }
    } else {
      if (app.mode == FAN_AUTO) {
        // AUTO'dan aşağı inince TURBO'ya dön
        newMode = FAN_TURBO;
      } else if (idx > 0) {
        newMode = kModes[idx - 1];
      } else {
        newMode = FAN_SLEEP;
      }
    }

    if (app.mode != newMode) {
      app.mode = newMode;
      setFanPercent(modeToPercent(app.mode));
      startFanModeShow(app.mode, nowMs);
      changed = true;
      if (app.mode == FAN_SLEEP) {
        voicePath = IR_VOICE_FAN_SLEEP;
      } else if (app.mode == FAN_LOW || app.mode == FAN_MED) {
        voicePath = IR_VOICE_FAN_MED;
      } else if (app.mode == FAN_HIGH || app.mode == FAN_TURBO) {
        voicePath = IR_VOICE_FAN_TURBO;
      } else {
        voicePath = IR_VOICE_FAN_AUTO;
      }
      voiceFallback = nullptr;
      Serial.printf("[IR] fan mode %s -> %s (%u%%)\n",
                    (necCode == IR_CODE_FAN_MODE_UP) ? "up" : "down",
                    fanModeToStr(app.mode),
                    (unsigned)app.fanPercent);
    }
  }

  bool feedbackPlayed = false;
  const char* resolvedVoice = resolveVoicePath(voicePath, voiceFallback);
  if (resolvedVoice) {
    feedbackPlayed = playWavI2s(resolvedVoice);
  }
  if (!feedbackPlayed) {
    triggerIrKeyBeep(nowMs);
  }

  if (changed) {
    if (relaysNeedApply) applyRelays();
    if (rgbNeedApply) applyRgb();
    if (fanNeedApply) setFanPercent(app.fanPercent);
    savePrefs();
    g_cloudDirty = true;
  }
#else
  (void)necCode;
#endif
}

// Simple humidity-based watering for ArtAirCleaner:
// - Eğer autoHumEnabled=false ise 33 numaralı röle kapalı kalır.
// - autoHumEnabled=true ve nem hedefin oldukça altına düşerse röle açılır.
// - Nem hedefe ulaştığında röle kapatılır.
static void runAutoHumidityControl(uint32_t nowMs) {
  static uint32_t lastCheckMs = 0;
  const uint32_t CHECK_INTERVAL_MS = 10000; // 10 saniye

  // Doa profili için: Zamanlayıcıya bağlı sulama (waterAuto/Manual) aktifken
  // nem tabanlı kontrol röleye dokunmamalı. Böylece süre bittiğinde pompa
  // kendiliğinden tekrar açılmaz.
  if (g_waterAutoEnabled || g_waterManualOn) {
    return;
  }

  if (!app.autoHumEnabled) {
    // Nem kontrolü kapalı. Bu durumda sadece ArtAirCleaner profili
    // (autoHum kullanırken) pompaya müdahale etmek istiyoruz.
    // Doa tarafında sulama PIN_RLY_WATER'ı su döngüsü (waterAuto/Manual)
    // kontrol ediyor; burada kapatmayalım.
    if (!g_waterAutoEnabled && !g_waterManualOn && g_waterRelayOn) {
      g_waterRelayOn = false;
      applyRelays();
    }
    return;
  }
  if (!app.masterOn) {
    if (g_waterRelayOn) {
      g_waterRelayOn = false;
      applyRelays();
    }
    return;
  }
  if ((nowMs - lastCheckMs) < CHECK_INTERVAL_MS) return;
  lastCheckMs = nowMs;

  float h = app.humPct;
  if (isnan(h)) return;
  const float target = (float)app.autoHumTarget;
  const float HYST   = 2.0f; // basit histerezis

  if (h < target - HYST) {
    if (!g_waterRelayOn) {
      g_waterRelayOn = true;
      applyRelays();
    }
  } else if (h >= target) {
    if (g_waterRelayOn) {
      g_waterRelayOn = false;
      applyRelays();
    }
  }
}

// Doa için DHT/Nem tabanlı otomatik sulama:
// - Hedef nem yaklaşık %70 civarı tutulmaya çalışılır.
// - Nem %60 altına düştüğünde 1 dakika sulama yapılır.
// - Sulamadan 5 dakika sonra nem tekrar ölçülür:
//   * %70 veya üzerindeyse yeni sulama yapılmaz, döngü sıfırlanır.
//   * %70'in altındaysa yeniden 1 dakika sulanır ve 5 dakika sonra tekrar kontrol edilir.
static void runDoaHumWatering(uint32_t nowMs) {
  if (!g_doaHumAutoEnabled) return;
  if (!app.masterOn) return;

  // Manuel sulama aktifken nem döngüsü devreye girmesin.
  if (g_waterManualOn) return;

  // Zamanlanmış bir sulama devam ediyorsa, önce bu turun bitmesini bekle.
  if (g_waterRelayOn && g_waterRelayOffAtMs != 0) return;

  if (g_doaHumNextCheckMs != 0 &&
      (int32_t)(nowMs - g_doaHumNextCheckMs) < 0) {
    return;
  }

  // Nem kaynağı olarak DHT11 kullan (sera/toprak ortamı farklı).
  float h = app.dhtHumPct;
  if (isnan(h)) {
    // Geçici ölçüm hatasında kısa bir süre sonra tekrar dene
    g_doaHumNextCheckMs = nowMs + 60000UL; // 1 dk
    return;
  }

  const float LOW_START = 60.0f;
  const float TARGET    = 70.0f;

  // İlk tetik: sadece nem %60 altına inmişse sulamayı başlat
  if (!g_doaHumHadWaterCycle) {
    if (h < LOW_START) {
      g_waterRelayOn      = true;
      g_waterRelayOffAtMs = nowMs + 60000UL; // 1 dk sulama
      applyRelays();
      g_doaHumHadWaterCycle = true;
      // 1 dk sulama + 5 dk bekleme sonrası tekrar kontrol
      g_doaHumNextCheckMs = nowMs + 60000UL + 5UL * 60000UL;
    } else {
      // Henüz yeterince kuru değil; bir süre sonra tekrar kontrol et
      g_doaHumNextCheckMs = nowMs + 5UL * 60000UL;
    }
    return;
  }

  // En az bir sulama turu yapıldı; hedefe ulaşıldı mı?
  if (h >= TARGET) {
    // Hedefe ulaşıldı, döngüyü sıfırla
    g_doaHumHadWaterCycle = false;
    g_doaHumNextCheckMs   = nowMs + 5UL * 60000UL;
    return;
  }

  // Hedefe gelinmediyse tekrar 1 dk sulama yap ve 5 dk sonra yeniden kontrol et
  g_waterRelayOn      = true;
  g_waterRelayOffAtMs = nowMs + 60000UL;
  applyRelays();
  g_doaHumNextCheckMs = nowMs + 60000UL + 5UL * 60000UL;
}

// Doa otomatik sulama scheduler'ı:
// - g_waterAutoEnabled=true ve manuel kapalıysa,
//   her g_waterIntervalMin dakikada bir, g_waterDurationMin dakika
//   boyunca PIN_RLY_WATER (ATOM_EN / IO32) açılır.
// - Reset / elektrik kesintisi sonrası g_lastWaterStartMs=0 olduğu için
//   döngü yeniden başlarken ilk scheduler çağrısında hemen sulamayı başlatır.
static void startWatering(uint32_t nowMs) {
  if (g_waterDurationMin == 0) return;
  g_waterRelayOn      = true;
  g_waterRelayOffAtMs = nowMs + (uint32_t)g_waterDurationMin * 60000UL;
  g_lastWaterStartMs  = nowMs;
  applyRelays();
}

static void runWaterScheduler(uint32_t nowMs) {
  if (g_waterManualOn) return;        // manuel modda otomatik dokunma
  if (!g_waterAutoEnabled) return;    // otomatik kapalı
  if (!app.masterOn) return;          // cihaz kapalıyken sulama yok
  if (g_waterDurationMin == 0 || g_waterIntervalMin == 0) return;

  // Röle zaten açıksa (süre sayacı kapanmayı yönetecek)
  if (g_waterRelayOn) return;

  uint32_t intervalMs = (uint32_t)g_waterIntervalMin * 60000UL;

  // İlk boot veya döngünün yeniden başlatılması -> hemen sulamayı başlat
  if (g_lastWaterStartMs == 0) {
    startWatering(nowMs);
    return;
  }

  // Son sulamadan bu yana interval doldu mu?
  if ((uint32_t)(nowMs - g_lastWaterStartMs) >= intervalMs) {
    startWatering(nowMs);
  }
}

/* =================== Sensors =================== */
static const int   GP2Y_SAMPLES_PER_READ = 7;
static const int   GP2Y_WINDOWS_PER_MEAS = 3;
static const uint32_t GP2Y_LED_SETTLE_US = 280;
static const uint32_t GP2Y_BETWEEN_WIN_US = 1000;
static const float GP2Y_EMA_ALPHA = 0.45f;
static float g_gp2y_ema = NAN;

static const int   MQ4_SAMPLES_PER_READ = 9;
static const float MQ4_EMA_ALPHA        = 0.35f;
static const int   MQ135_SAMPLES_PER_READ = 9;
static const float MQ135_EMA_ALPHA        = 0.35f;

static const float AUTO_SEVERITY_ALPHA = 0.25f;

static float g_envSeverityEma = 0.0f;
static bool  g_envSeverityValid = false;
static uint32_t g_envSeq = 0;
static bool  g_forceAutoStep = false;
// Timestamp of last manual (non-AUTO) mode selection from mobile/commands
static uint32_t g_lastManualModeMs = 0;
static const uint32_t MANUAL_MODE_HOLD_MS = 0; // do not ignore AUTO after manual change

static float quickMedianFloat(float *arr, int n) {
  for (int i = 0; i < n - 1; ++i) {
    int m = i;
    for (int j = i + 1; j < n; ++j) if (arr[j] < arr[m]) m = j;
    if (m != i) { float t = arr[i]; arr[i] = arr[m]; arr[m] = t; }
  }
  if (n & 1) return arr[n/2];
  return 0.5f * (arr[n/2 - 1] + arr[n/2]);
}

static float gp2y_readWindowVoltage() {
  if (!GP2Y_LED_ALWAYS_ON) { gp2y_led_on(); delayMicroseconds(GP2Y_LED_SETTLE_US); }
  float vs[GP2Y_SAMPLES_PER_READ];
  for (int i = 0; i < GP2Y_SAMPLES_PER_READ; ++i) {
    uint16_t raw = analogRead(PIN_GP2Y_AO);
    vs[i] = (float)raw * (ADC_VREF / (float)ADC_MAX);
    delayMicroseconds(5);
  }
  if (!GP2Y_LED_ALWAYS_ON) gp2y_led_off();
  float tmp[GP2Y_SAMPLES_PER_READ];
  for (int i = 0; i < GP2Y_SAMPLES_PER_READ; ++i) tmp[i] = vs[i];
  return quickMedianFloat(tmp, GP2Y_SAMPLES_PER_READ);
}

float sampleGP2Y10_V() {
  float ws[GP2Y_WINDOWS_PER_MEAS];
  for (int w = 0; w < GP2Y_WINDOWS_PER_MEAS; ++w) {
    ws[w] = gp2y_readWindowVoltage();
    if (w + 1 < GP2Y_WINDOWS_PER_MEAS) delayMicroseconds(GP2Y_BETWEEN_WIN_US);
  }
  float tmp[GP2Y_WINDOWS_PER_MEAS];
  for (int i = 0; i < GP2Y_WINDOWS_PER_MEAS; ++i) tmp[i] = ws[i];
  float v = quickMedianFloat(tmp, GP2Y_WINDOWS_PER_MEAS);
  if (isnan(g_gp2y_ema)) g_gp2y_ema = v;
  g_gp2y_ema = GP2Y_EMA_ALPHA * v + (1.0f - GP2Y_EMA_ALPHA) * g_gp2y_ema;
  return g_gp2y_ema;
}

float sampleMQ4_V() {
  gp2y_led_off();
  delayMicroseconds(500);
  uint16_t buf[MQ4_SAMPLES_PER_READ];
  for (int i = 0; i < MQ4_SAMPLES_PER_READ; ++i) { buf[i] = analogRead(PIN_MQ4_AO); delayMicroseconds(200); }
  uint16_t tmp[MQ4_SAMPLES_PER_READ];
  for (int i = 0; i < MQ4_SAMPLES_PER_READ; ++i) tmp[i] = buf[i];
  for (int i = 0; i < MQ4_SAMPLES_PER_READ - 1; ++i) { int m=i; for (int j=i+1;j<MQ4_SAMPLES_PER_READ;++j) if (tmp[j]<tmp[m]) m=j; if(m!=i){uint16_t t=tmp[i];tmp[i]=tmp[m];tmp[m]=t;} }
  uint16_t med = tmp[MQ4_SAMPLES_PER_READ / 2];
  float v = (float)med * (ADC_VREF / (float)ADC_MAX);
  static float ema = NAN; if (isnan(ema)) ema = v; else ema = MQ4_EMA_ALPHA * v + (1.0f - MQ4_EMA_ALPHA) * ema;
  return ema;
}

float sampleMQ135_V() {
  uint16_t buf[MQ135_SAMPLES_PER_READ];
  for (int i = 0; i < MQ135_SAMPLES_PER_READ; ++i) { buf[i] = analogRead(PIN_MQ135_AO); delayMicroseconds(200); }
  uint16_t tmp[MQ135_SAMPLES_PER_READ];
  for (int i = 0; i < MQ135_SAMPLES_PER_READ; ++i) tmp[i] = buf[i];
  for (int i = 0; i < MQ135_SAMPLES_PER_READ - 1; ++i) { int m=i; for (int j=i+1;j<MQ135_SAMPLES_PER_READ;++j) if (tmp[j]<tmp[m]) m=j; if(m!=i){uint16_t t=tmp[i];tmp[i]=tmp[m];tmp[m]=t;} }
  uint16_t med = tmp[MQ135_SAMPLES_PER_READ / 2];
  float v = (float)med * (ADC_VREF / (float)ADC_MAX);
  static float ema = NAN; if (isnan(ema)) ema = v; else ema = MQ135_EMA_ALPHA * v + (1.0f - MQ135_EMA_ALPHA) * ema;
  return ema;
}

DHT dht(PIN_DHT, DHTTYPE);
void sampleDHT(float &t, float &h) {
  float ht = dht.readHumidity();
  float tt = dht.readTemperature();
  if (!isnan(ht)) {
    h = ht;
    app.dhtHumPct = ht;
  }
  if (!isnan(tt)) {
    t = tt;
    app.dhtTempC = tt;
  }
}

/* =================== SEN55 =================== */
SensirionI2CSen5x sen55;
static bool sen55_ok = false;
static uint8_t sen55_addr_found = 0x00;
static uint8_t bme_addr_found = 0x00;
// SEN55 error/backoff management
static uint8_t  sen55_err_streak = 0;
static uint32_t sen55_nextRetryMs = 0; // millis when we should retry init

static void i2cScan() {
  initI2C();
#if I2C_SCAN_LOG
  Serial.println("[I2C] Scanning bus...");
#endif
  uint8_t found = 0;
  int count = 0;
  bool sen55Found = false;
  bool bmeFound = false;
  for (uint8_t addr = 1; addr < 127; ++addr) {
    Wire.beginTransmission(addr);
    uint8_t err = Wire.endTransmission();
    if (err == 0) {
#if I2C_SCAN_LOG
      Serial.printf("[I2C] Found 0x%02X\n", addr);
#endif
      found = addr;
      count++;
      if (addr == SEN55_I2C_ADDR) sen55Found = true;
      if (addr == 0x76 || addr == 0x77) {
        bme_addr_found = addr;
        bmeFound = true;
      }
    }
  }
  if (count==0) {
    static uint8_t i2c_no_dev_printed = 0;
    if (i2c_no_dev_printed < 1) {
#if I2C_SCAN_LOG
      Serial.println("[I2C] No devices found");
#endif
      i2c_no_dev_printed++;
    }
  }
  sen55_addr_found = sen55Found ? SEN55_I2C_ADDR : found;
  if (!bmeFound) {
    bme_addr_found = 0x00;
  }
}

/* =================== BME688 (classic mode) =================== */
// We keep the classic Adafruit_BME680 driver as a fallback for platforms
// where the Bosch BSEC2 runtime is not available or fails to start.
static Adafruit_BME680 g_bme;  // supports BME688 as well
static bool g_bmeOk = false;
static uint8_t g_bmeAddr = 0x00;
static uint32_t g_bmeLastLogMs = 0;

static void bmeInit() {
  if (g_bmeOk) return;
  initI2C();
  i2cScan();
  // Try common I2C addresses 0x76 and 0x77
  bool ok = false;
  if (bme_addr_found == 0x76 || bme_addr_found == 0x77) {
    ok = g_bme.begin(bme_addr_found);
    if (ok) g_bmeAddr = bme_addr_found;
  }
  if (!ok) {
    ok = g_bme.begin(0x76);
    if (ok) g_bmeAddr = 0x76;
  }
  if (!ok) {
    ok = g_bme.begin(0x77);
    if (ok) g_bmeAddr = 0x77;
  }
  if (!ok) {
    Serial.printf("[BME688] (classic) not detected on I2C (0x76/0x77) using SDA=%u SCL=%u.\n",
                  (unsigned)PIN_I2C_SDA,
                  (unsigned)PIN_I2C_SCL);
    g_bmeOk = false;
    return;
  }
  // Oversampling and filter configuration (Bosch recommended defaults)
  g_bme.setTemperatureOversampling(BME680_OS_8X);
  g_bme.setHumidityOversampling(BME680_OS_2X);
  g_bme.setPressureOversampling(BME680_OS_4X);
  g_bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
  // Classic gas heater profile: 320 °C for 150 ms
  g_bme.setGasHeater(320, 150);
  g_bmeOk = true;
  Serial.printf("[BME688] initialized (classic mode fallback) at 0x%02X.\n", g_bmeAddr);
}

static bool bmeReadClassic(float& tC, float& rh, float& pressure_hPa, float& gas_kOhm) {
  if (!g_bmeOk) return false;
  if (!g_bme.performReading()) {
    Serial.println("[BME688] (classic) performReading failed");
    return false;
  }
  tC = g_bme.temperature;
  rh = g_bme.humidity;
  pressure_hPa = g_bme.pressure / 100.0f;
  gas_kOhm = g_bme.gas_resistance / 1000.0f;
#if BME688_DEBUG_LOG
  const uint32_t nowMs = millis();
  if ((nowMs - g_bmeLastLogMs) >= 3000U) {
    g_bmeLastLogMs = nowMs;
    Serial.printf("[BME688] classic t=%.2fC rh=%.2f%% p=%.2fhPa gas=%.2fkOhm\n",
                  tC, rh, pressure_hPa, gas_kOhm);
  }
#endif
  return true;
}

/* =================== BME688 AI (BSEC2) =================== */
// BSEC2 gives IAQ / CO2eq / bVOCeq ve ısıtıcı etkisi
// kompanse edilmiş sıcaklık/nem/basınç çıktıları.
#if defined(DISABLE_BSEC) && (DISABLE_BSEC == 1)
 // BSEC Disabled
 static bool   g_bsecOk          = false;
 static uint8_t g_bsecIaqAccuracy = 0;
#else
 static Bsec2  g_bsec;
 static bool   g_bsecOk          = false;
 static uint8_t g_bsecIaqAccuracy = 0;
#endif

static void logBsecStatus(const char* where, Bsec2& bsec) {
  if (bsec.status != BSEC_OK) {
    Serial.printf("[BSEC] %s: status=%d\n", where, bsec.status);
  }
  if (bsec.sensor.status != BME68X_OK) {
    Serial.printf("[BSEC] %s: sensorStatus=%d\n", where, bsec.sensor.status);
  }
}

static void bsecNewDataCallback(const bme68xData data,
                                const bsecOutputs outputs,
                                Bsec2 bsec) {
  (void)data;
  if (!outputs.nOutputs) return;

  float aiTempC     = NAN;
  float aiHumPct    = NAN;
  float aiPressure  = NAN;
  float aiGasKOhm   = NAN;
  float aiIaq       = NAN;
  float aiCo2Eq     = NAN;
  float aiBVocEq    = NAN;
  uint8_t iaqAcc    = 0;

  for (uint8_t i = 0; i < outputs.nOutputs; ++i) {
    const bsecData out = outputs.output[i];
    switch (out.sensor_id) {
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE:
        aiTempC = out.signal;
        break;
      case BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY:
        aiHumPct = out.signal;
        break;
      case BSEC_OUTPUT_RAW_PRESSURE:
        // BSEC returns pressure in Pa
        aiPressure = out.signal / 100.0f; // hPa
        break;
      case BSEC_OUTPUT_RAW_GAS:
        aiGasKOhm = out.signal / 1000.0f; // Ohm -> kOhm
        break;
      case BSEC_OUTPUT_IAQ:
        // Bazı konfigürasyonlarda STATIC_IAQ yerine IAQ gelebilir.
        aiIaq  = out.signal;
        iaqAcc = out.accuracy;
        break;
      case BSEC_OUTPUT_STATIC_IAQ:
        aiIaq    = out.signal;
        iaqAcc   = out.accuracy;
        break;
      case BSEC_OUTPUT_CO2_EQUIVALENT:
        aiCo2Eq  = out.signal;
        break;
      case BSEC_OUTPUT_BREATH_VOC_EQUIVALENT:
        aiBVocEq = out.signal;
        break;
      default:
        break;
    }
  }

  bool changed = false;
  if (!isnan(aiTempC)) {
    changed |= updateFloatIfChanged(app.aiTempC, aiTempC, 0.2f);
  }
  if (!isnan(aiHumPct)) {
    changed |= updateFloatIfChanged(app.aiHumPct, aiHumPct, 0.5f);
  }
  if (!isnan(aiPressure)) {
    changed |= updateFloatIfChanged(app.aiPressure, aiPressure, 0.5f);
  }
  if (!isnan(aiGasKOhm)) {
    changed |= updateFloatIfChanged(app.aiGasKOhm, aiGasKOhm, 0.5f);
  }
  if (!isnan(aiIaq)) {
    changed |= updateFloatIfChanged(app.aiIaq, aiIaq, 1.0f);
    g_bsecIaqAccuracy = iaqAcc;
  }
  if (!isnan(aiCo2Eq)) {
    changed |= updateFloatIfChanged(app.aiCo2Eq, aiCo2Eq, 25.0f);
  }
  if (!isnan(aiBVocEq)) {
    changed |= updateFloatIfChanged(app.aiBVocEq, aiBVocEq, 5.0f);
  }

  if (changed) {
    // sensör verisi değiştiyse otomatik kontrol döngüsünü tetikle
    g_forceAutoStep = true;
  }

#if BME688_DEBUG_LOG
  const uint32_t nowMs = millis();
  if ((nowMs - g_bmeLastLogMs) >= 3000U) {
    g_bmeLastLogMs = nowMs;
    Serial.printf("[BME688] bsec t=%.2fC rh=%.2f%% p=%.2fhPa gas=%.2fkOhm iaq=%.1f co2=%.1f bvoc=%.2f acc=%u\n",
                  aiTempC,
                  aiHumPct,
                  aiPressure,
                  aiGasKOhm,
                  aiIaq,
                  aiCo2Eq,
                  aiBVocEq,
                  (unsigned)iaqAcc);
  }
#endif
}

static void bsecInit() {
  if (g_bsecOk) return;

  initI2C();
  i2cScan();

  bsecSensor sensorList[] = {
      BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
      BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
      BSEC_OUTPUT_RAW_PRESSURE,
      BSEC_OUTPUT_RAW_GAS,
      BSEC_OUTPUT_IAQ,
      BSEC_OUTPUT_STATIC_IAQ,
      BSEC_OUTPUT_CO2_EQUIVALENT,
      BSEC_OUTPUT_BREATH_VOC_EQUIVALENT,
  };

  // BSEC2 çalışmazsa, sadece klasik sürücü ile devam ederiz.
#if defined(DISABLE_BSEC) && (DISABLE_BSEC == 1)
  Serial.println("[BSEC] Disabled by build flag (mem optim)");
  g_bsecOk = false;
#else
  bool bsecBegun = false;
  if (bme_addr_found == BME68X_I2C_ADDR_LOW || bme_addr_found == BME68X_I2C_ADDR_HIGH) {
    bsecBegun = g_bsec.begin(bme_addr_found, Wire);
  }
  if (!bsecBegun) {
    bsecBegun = g_bsec.begin(BME68X_I2C_ADDR_LOW, Wire);
  }
  if (!bsecBegun) {
    bsecBegun = g_bsec.begin(BME68X_I2C_ADDR_HIGH, Wire);
  }
  if (!bsecBegun) {
    logBsecStatus("begin", g_bsec);
    Serial.printf("[BSEC] begin failed on SDA=%u SCL=%u, using classic BME688 only.\n",
                  (unsigned)PIN_I2C_SDA,
                  (unsigned)PIN_I2C_SCL);
    g_bsecOk = false;
    return;
  }
#endif

#if !defined(DISABLE_BSEC) || (DISABLE_BSEC == 0)
  const float sampleRate = BSEC_SAMPLE_RATE_LP; // ~3 sn
  if (sampleRate == BSEC_SAMPLE_RATE_ULP) {
    g_bsec.setTemperatureOffset(TEMP_OFFSET_ULP);
  } else if (sampleRate == BSEC_SAMPLE_RATE_LP) {
    g_bsec.setTemperatureOffset(TEMP_OFFSET_LP);
  }

  // IAQ/CO2/bVOC gibi gelişmiş çıktılar için Bosch konfigürasyon blob'u.
  if (!g_bsec.setConfig(bsec_config)) {
    logBsecStatus("setConfig", g_bsec);
    Serial.println("[BSEC] setConfig failed, falling back to built‑in defaults.");
  }

  if (!g_bsec.updateSubscription(sensorList,
                                 sizeof(sensorList) / sizeof(sensorList[0]),
                                 sampleRate)) {
    logBsecStatus("updateSubscription", g_bsec);
    Serial.println("[BSEC] updateSubscription failed, disabling BSEC.");
    g_bsecOk = false;
    return;
  }

  g_bsec.attachCallback(bsecNewDataCallback);
  g_bsecOk = true;

#if BSEC_INFO_LOG
  Serial.printf("[BSEC] init OK v%u.%u.%u.%u\n",
                g_bsec.version.major,
                g_bsec.version.minor,
                g_bsec.version.major_bugfix,
                g_bsec.version.minor_bugfix);
#endif
#endif
}

static void sen55Init() {
  initI2C();
  sen55.begin(Wire);
  sen55_err_streak = 0;
  sen55_nextRetryMs = 0;
  uint16_t error = 0;
  i2cScan();
#if SEN55_DEBUG_LOG
  if (sen55_addr_found != SEN55_I2C_ADDR) {
    // Keep this as warning only: some boards have additional I2C devices and
    // scanner visibility may differ, but direct SEN55 commands can still work.
    Serial.printf("[SEN55] WARN expected 0x%02X not seen in scan, trying direct init anyway.\n",
                  SEN55_I2C_ADDR);
  }
#endif

  // Bring device to a known state, but do not hard-fail on stop/reset errors.
  uint16_t serr = sen55.stopMeasurement();
#if SEN55_DEBUG_LOG
  if (serr) {
    Serial.printf("[SEN55] stopMeasurement info: 0x%04X\n", serr);
  }
#endif
  uint16_t rerr = sen55.deviceReset();
#if SEN55_DEBUG_LOG
  if (rerr) {
    Serial.printf("[SEN55] deviceReset error: 0x%04X\n", rerr);
  }
#endif
  delay(1200); // wait for SEN55 boot-up before querying product name
  // Try to read product name to verify communication
  unsigned char productName[32];
  uint8_t productNameSize = sizeof(productName);
  error = sen55.getProductName(productName, productNameSize);
#if SEN55_DEBUG_LOG
  if (error) {
    Serial.printf("[SEN55] WARN getProductName error: 0x%04X\n", error);
  } else {
    Serial.printf("[SEN55] Product: %s\n", productName);
  }
#endif

  // Start measurement (continuous)
  error = sen55.startMeasurement();
  if (error) {
#if SEN55_DEBUG_LOG
    Serial.printf("[SEN55] startMeasurement error: 0x%04X\n", error);
#endif
    sen55_ok = false;
    sen55_nextRetryMs = millis() + 60000;
  } else {
    sen55_ok = true;
    sen55_err_streak = 0;
    sen55_nextRetryMs = 0;
#if SEN55_DEBUG_LOG
    Serial.println("[SEN55] Measurement started.");
#endif
  }
}

static bool sen55Read(float &pm25, float &tC, float &rh) {
  if (!sen55_ok) return false;
  uint16_t error;
  float massConcentrationPm1p0, massConcentrationPm2p5, massConcentrationPm4p0, massConcentrationPm10p0;
  float ambientHumidity, ambientTemperature; // t in degC, RH in %
  float vocIndex, noxIndex;
  error = sen55.readMeasuredValues(massConcentrationPm1p0, massConcentrationPm2p5,
                                   massConcentrationPm4p0, massConcentrationPm10p0,
                                   ambientHumidity, ambientTemperature,
                                   vocIndex, noxIndex);
  if (error) {
    // Increment streak and optionally mute further reads for a while
    if (sen55_err_streak < 0xFF) sen55_err_streak++;
#if SEN55_DEBUG_LOG
    if (sen55_err_streak == 1) {
      Serial.printf("[SEN55] read error: 0x%04X\n", error);
    } else if (sen55_err_streak == 3) {
      Serial.printf("[SEN55] read error: 0x%04X (x3) -> muting & disabling sensor for 60s\n", error);
    }
#endif
    if (sen55_err_streak == 3) {
      sen55_ok = false;
      sen55_nextRetryMs = millis() + 60000; // retry after 60 seconds
    }
    return false;
  }
  pm25 = massConcentrationPm2p5;
  tC = ambientTemperature;
  rh = ambientHumidity;
  app.vocIndex = vocIndex;
  app.noxIndex = noxIndex;
  app.pm1_0 = massConcentrationPm1p0;
  app.pm2_5 = massConcentrationPm2p5;
  app.pm4_0 = massConcentrationPm4p0;
  app.pm10_0 = massConcentrationPm10p0;
  sen55_err_streak = 0;
#if SEN55_DEBUG_LOG
  static uint32_t s_lastSen55LogMs = 0;
  const uint32_t nowMs = millis();
  if ((nowMs - s_lastSen55LogMs) >= 3000U) {
    s_lastSen55LogMs = nowMs;
    Serial.printf("[SEN55] ok pm1=%.1f pm2.5=%.1f pm4=%.1f pm10=%.1f t=%.2fC rh=%.2f%% voc=%.1f nox=%.1f\n",
                  massConcentrationPm1p0,
                  massConcentrationPm2p5,
                  massConcentrationPm4p0,
                  massConcentrationPm10p0,
                  ambientTemperature,
                  ambientHumidity,
                  vocIndex,
                  noxIndex);
  }
#endif
  return true;
}

// Helper: periodically retry SEN55 init if muted/disabled
static void sen55MaybeRetryInit() {
  if (sen55_ok) return;
  uint32_t now = millis();
  if (now == 0) return; // millis not ready yet
  if (sen55_nextRetryMs != 0 && (int32_t)(now - sen55_nextRetryMs) < 0) return;
#if SEN55_DEBUG_LOG
  Serial.println("[SEN55] retrying init...");
#endif
  sen55Init();
  // If it still fails, ensure we don't hammer: set a new backoff window
  if (!sen55_ok) {
    sen55_nextRetryMs = now + 60000;
  } else {
    sen55_err_streak = 0;
    sen55_nextRetryMs = 0;
  }
}

/* =================== AUTO control =================== */
static inline float clamp01(float v) {
  if (v < 0.0f) return 0.0f;
  if (v > 1.0f) return 1.0f;
  return v;
}

static const char* fanAutoReasonToStr(FanAutoReason reason) {
  switch (reason) {
    case FanAutoReason::ODOR_CLEANUP: return "odor_cleanup";
    case FanAutoReason::HEALTH:
    default:
      return "health";
  }
}

static float piecewiseMap(float value, const float* xs, const float* ys, size_t count) {
  if (count == 0) return 0.0f;
  if (value <= xs[0]) return ys[0];
  for (size_t i = 1; i < count; ++i) {
    if (value <= xs[i]) {
      const float span = xs[i] - xs[i - 1];
      if (span <= 1e-6f) return ys[i];
      const float t = (value - xs[i - 1]) / span;
      return ys[i - 1] + t * (ys[i] - ys[i - 1]);
    }
  }
  return ys[count - 1];
}

static float comfortSeverityFromDelta(float delta, const float* xs, const float* ys, size_t count) {
  delta = fabsf(delta);
  return piecewiseMap(delta, xs, ys, count);
}

static float computeHealthSeverity() {
  // Indoor health score: PM dominates, VOC/NOx contribute, odor does not.
  // PM breakpoints are aligned to WHO 2021 guideline magnitudes.
  static const float PM25_BREAKS[] = {0.0f, 5.0f, 10.0f, 15.0f, 25.0f, 37.5f, 50.0f};
  static const float PM10_BREAKS[] = {0.0f, 15.0f, 30.0f, 45.0f, 75.0f, 112.5f, 150.0f};
  static const float PM_SCORES[]   = {0.0f, 0.15f, 0.32f, 0.50f, 0.72f, 0.88f, 1.0f};
  static const float VOC_BREAKS[]  = {0.0f, 100.0f, 150.0f, 200.0f, 300.0f, 500.0f};
  static const float VOC_SCORES[]  = {0.0f, 0.12f, 0.28f, 0.45f, 0.72f, 1.0f};
  static const float NOX_BREAKS[]  = {0.0f, 20.0f, 50.0f, 100.0f, 200.0f, 400.0f};
  static const float NOX_SCORES[]  = {0.0f, 0.10f, 0.28f, 0.50f, 0.78f, 1.0f};

  float pmSeverity = NAN;
  if (!isnan(app.pm2_5))  pmSeverity = isnan(pmSeverity) ? piecewiseMap(app.pm2_5, PM25_BREAKS, PM_SCORES, 7)
                                                         : fmaxf(pmSeverity, piecewiseMap(app.pm2_5, PM25_BREAKS, PM_SCORES, 7));
  if (!isnan(app.pm10_0)) pmSeverity = isnan(pmSeverity) ? piecewiseMap(app.pm10_0, PM10_BREAKS, PM_SCORES, 7)
                                                         : fmaxf(pmSeverity, piecewiseMap(app.pm10_0, PM10_BREAKS, PM_SCORES, 7));

  const float vocSeverity = isnan(app.vocIndex) ? NAN : piecewiseMap(app.vocIndex, VOC_BREAKS, VOC_SCORES, 6);
  const float noxSeverity = isnan(app.noxIndex) ? NAN : piecewiseMap(app.noxIndex, NOX_BREAKS, NOX_SCORES, 6);

  const float W_PM  = 0.65f;
  const float W_VOC = 0.20f;
  const float W_NOX = 0.15f;

  float quadSum = 0.0f;
  float weightSum = 0.0f;
  if (!isnan(pmSeverity)) {
    quadSum += W_PM * pmSeverity * pmSeverity;
    weightSum += W_PM;
  }
  if (!isnan(vocSeverity)) {
    quadSum += W_VOC * vocSeverity * vocSeverity;
    weightSum += W_VOC;
  }
  if (!isnan(noxSeverity)) {
    quadSum += W_NOX * noxSeverity * noxSeverity;
    weightSum += W_NOX;
  }

  if (weightSum <= 0.0f) return 0.0f;
  return clamp01(sqrtf(quadSum / weightSum));
}

static float computeComfortSeverity() {
  // Konfor (ASHRAE 55 ve EN 16798 aralıkları)
  static const float TEMP_DELTA_BREAKS[] = {0.0f, 2.0f, 4.0f, 6.0f, 9.0f, 12.0f};
  static const float TEMP_DELTA_SCORES[] = {0.0f, 0.20f, 0.45f, 0.65f, 0.85f, 1.0f};
  static const float HUM_DELTA_BREAKS[]  = {0.0f, 5.0f, 10.0f, 20.0f, 30.0f, 40.0f};
  static const float HUM_DELTA_SCORES[]  = {0.0f, 0.20f, 0.45f, 0.65f, 0.85f, 1.0f};

  float tempSeverity = isnan(app.tempC) ? NAN
                                        : comfortSeverityFromDelta(app.tempC - 23.0f,
                                                                   TEMP_DELTA_BREAKS,
                                                                   TEMP_DELTA_SCORES,
                                                                   6);
  float humSeverity = NAN;
  if (!isnan(app.humPct)) {
    float delta = 0.0f;
    if (app.humPct < 40.0f) delta = 40.0f - app.humPct;
    else if (app.humPct > 60.0f) delta = app.humPct - 60.0f;
    humSeverity = comfortSeverityFromDelta(delta, HUM_DELTA_BREAKS, HUM_DELTA_SCORES, 6);
  }

  float comfortSeverity = NAN;
  if (!isnan(tempSeverity) && !isnan(humSeverity)) {
    comfortSeverity = sqrtf(0.5f * tempSeverity * tempSeverity + 0.5f * humSeverity * humSeverity);
  } else if (!isnan(tempSeverity)) {
    comfortSeverity = tempSeverity;
  } else if (!isnan(humSeverity)) {
    comfortSeverity = humSeverity;
  }

  return isnan(comfortSeverity) ? 0.0f : clamp01(comfortSeverity);
}

static float computeOdorBoostSeverity(uint32_t nowMs) {
  static const float VOC_BREAKS[] = {0.0f, 100.0f, 150.0f, 200.0f, 300.0f, 500.0f};
  static const float VOC_SCORES[] = {0.0f, 0.10f, 0.22f, 0.38f, 0.65f, 1.0f};
  static const float IAQ_BREAKS[] = {0.0f, 50.0f, 100.0f, 150.0f, 200.0f, 300.0f, 500.0f};
  static const float IAQ_SCORES[] = {0.0f, 0.05f, 0.15f, 0.35f, 0.60f, 0.82f, 1.0f};
  static const float BVOC_BREAKS[] = {0.0f, 0.3f, 0.6f, 1.0f, 2.0f, 4.0f, 8.0f};
  static const float BVOC_SCORES[] = {0.0f, 0.08f, 0.18f, 0.35f, 0.60f, 0.82f, 1.0f};

  const float vocSeverity = isnan(app.vocIndex) ? NAN : piecewiseMap(app.vocIndex, VOC_BREAKS, VOC_SCORES, 6);
  const float iaqSeverity = isnan(app.aiIaq) ? NAN : piecewiseMap(app.aiIaq, IAQ_BREAKS, IAQ_SCORES, 7);
  const float bVocSeverity = isnan(app.aiBVocEq) ? NAN : piecewiseMap(app.aiBVocEq, BVOC_BREAKS, BVOC_SCORES, 7);

  float blended = 0.0f;
  float weight = 0.0f;
  if (!isnan(vocSeverity)) {
    blended += 0.45f * vocSeverity;
    weight += 0.45f;
  }
  if (!isnan(iaqSeverity)) {
    blended += 0.30f * iaqSeverity;
    weight += 0.30f;
  }
  if (!isnan(bVocSeverity)) {
    blended += 0.25f * bVocSeverity;
    weight += 0.25f;
  }
  blended = (weight > 0.0f) ? (blended / weight) : 0.0f;

  bool odorSpike = false;
  if (!isnan(app.vocIndex) && !isnan(g_prevVocIndexForOdor) && (app.vocIndex - g_prevVocIndexForOdor) >= 35.0f) {
    odorSpike = true;
  }
  if (!isnan(app.aiIaq) && !isnan(g_prevAiIaqForOdor) && (app.aiIaq - g_prevAiIaqForOdor) >= 25.0f) {
    odorSpike = true;
  }
  if (!isnan(app.aiBVocEq) && !isnan(g_prevAiBVocEqForOdor) && (app.aiBVocEq - g_prevAiBVocEqForOdor) >= 0.35f) {
    odorSpike = true;
  }

  if (odorSpike || blended >= 0.72f) {
    g_odorBoostUntilMs = nowMs + 180000UL;
  }

  float boosted = blended;
  if ((int32_t)(g_odorBoostUntilMs - nowMs) > 0) {
    boosted = fmaxf(boosted, odorSpike ? 0.90f : 0.72f);
  }

  g_prevVocIndexForOdor = app.vocIndex;
  g_prevAiIaqForOdor = app.aiIaq;
  g_prevAiBVocEqForOdor = app.aiBVocEq;

  return clamp01(boosted);
}

static int indoorHealthScoreFromSeverity(float severity) {
  int score = (int)roundf(100.0f * (1.0f - clamp01(severity)));
  if (score < 0) score = 0;
  if (score > 100) score = 100;
  return score;
}

static uint8_t severityToFanPercent(float severity) {
  severity = clamp01(severity);
  if (severity <= 0.015f) return 20;
  const float minPct = 22.0f;
  const float maxPct = 100.0f;
  float curve = powf(severity, 1.25f);
  float pct = minPct + (maxPct - minPct) * curve;
  if (severity >= 0.85f) pct = maxPct;
  pct = fminf(fmaxf(pct, minPct), maxPct);
  return (uint8_t)roundf(pct);
}

void autoControlStep(bool force)
{
  const uint32_t nowMs = millis();
  const float healthSeverity = computeHealthSeverity();
  const float comfortSeverity = computeComfortSeverity();
  const float odorBoostSeverity = computeOdorBoostSeverity(nowMs);

  // Health remains primary; comfort can gently bias airflow, odor can trigger
  // a temporary cleanup boost without degrading the indoor AQI score.
  float controlSeverity = healthSeverity;
  controlSeverity = fmaxf(controlSeverity, comfortSeverity * 0.35f);
  controlSeverity = fmaxf(controlSeverity, odorBoostSeverity);
  controlSeverity = clamp01(controlSeverity);

  if (!g_envSeverityValid || force) {
    g_envSeverityEma = controlSeverity;
  } else {
    g_envSeverityEma = AUTO_SEVERITY_ALPHA * controlSeverity + (1.0f - AUTO_SEVERITY_ALPHA) * g_envSeverityEma;
  }
  g_envSeverityValid = true;
  g_healthSeverity = healthSeverity;
  g_odorBoostSeverity = odorBoostSeverity;
  g_controlSeverity = g_envSeverityEma;
  g_fanAutoReason = (odorBoostSeverity > fmaxf(healthSeverity, comfortSeverity * 0.35f))
                      ? FanAutoReason::ODOR_CLEANUP
                      : FanAutoReason::HEALTH;
  app.pm_v = g_controlSeverity;
  setFanPercent(severityToFanPercent(g_envSeverityEma));
}

/* =================== Persistence =================== */
void savePrefs() {
  prefs.begin("aac", false);
  prefs.putBool("masterOn", app.masterOn);
  prefs.putBool("lightOn",  app.lightOn);
  prefs.putBool("cleanOn",  app.cleanOn);
  prefs.putBool("ionOn",    app.ionOn);
  prefs.putUChar("mode",    (uint8_t)app.mode);
  prefs.putUChar("fanPct",  app.fanPercent);
  prefs.putBool("autoHumEn", app.autoHumEnabled);
  prefs.putUChar("autoHumT", app.autoHumTarget);
  prefs.putUChar("rgbR",    app.r);
  prefs.putUChar("rgbG",    app.g);
  prefs.putUChar("rgbB",    app.b);
  prefs.putBool("rgbOn",    app.rgbOn);
  prefs.putUChar("rgbBr",   app.rgbBrightness);
  prefs.putBool("haveCal",  true);
  prefs.putBytes("calRPM",  app.calibRPM, sizeof(app.calibRPM));
  prefs.putUChar("planCount", g_planCount);
  if (g_planCount > MAX_PLANS) g_planCount = MAX_PLANS;
  prefs.putBytes("plans", g_plans, sizeof(PlanItem) * g_planCount);
  prefs.putString("tz", g_tz);
  // Wi-Fi creds kept in same ns
  prefs.putString("wifi_ssid", g_savedSsid);
  prefs.putString("wifi_pass", g_savedPass);
  prefs.putBool("ap_only", AP_ONLY);
  prefs.putBool("cloud_en", g_cloudUserEnabled);
  prefs.putString("cloud_ep", g_cloudEndpointOverride);
  // Owner / invite security state (legacy + secure owner)
  prefs.putString("owner_hash", g_ownerHash); // legacy (kept for migration)
  prefs.putBool("owner_exists", g_ownerExists);
  prefs.putString("owner_pubkey", g_ownerPubKeyB64);
  prefs.putString("setup_user", g_setupUser);
  prefs.putString("setup_pass_hash", g_setupPassHashHex);
  prefs.putString("users_json", g_usersJson);
  prefs.putUInt("acl_v", g_shadowAclVersion);
  prefs.putBool("setup_done", g_setupDone);
  // device_secret: yalnızca üretildiyse yaz
  if (g_deviceSecretLoaded) {
    prefs.putBytes("device_secret", g_deviceSecret, sizeof(g_deviceSecret));
  }
  prefs.putString("pair_token", g_pairToken);
  // Legacy credential cleanup (no longer used)
  prefs.remove("auth_user");
  prefs.remove("auth_pass");
  prefs.remove("admin_user");
  prefs.remove("admin_pass");
  prefs.end();
}

void loadPrefs() {
  // ensure plan array starts in a known, safe state
  initPlans();
  prefs.begin("aac", true);
  app.masterOn = prefs.getBool("masterOn", true);
  app.lightOn  = prefs.getBool("lightOn", false);
  app.cleanOn  = prefs.getBool("cleanOn", false);
  app.ionOn    = prefs.getBool("ionOn", false);
  app.mode     = (FanMode)prefs.getUChar("mode", FAN_LOW);
  app.fanPercent = prefs.getUChar("fanPct", 35);
  app.autoHumEnabled = prefs.getBool("autoHumEn", false);
  app.autoHumTarget  = prefs.getUChar("autoHumT", 55);
  app.r        = prefs.getUChar("rgbR", 0);
  app.g        = prefs.getUChar("rgbG", 0);
  app.b        = prefs.getUChar("rgbB", 0);
  app.rgbOn         = prefs.getBool("rgbOn", (app.r||app.g||app.b));
  app.rgbBrightness = prefs.getUChar("rgbBr", 100);

  bool have = prefs.getBool("haveCal", false);
  if (have) { size_t n=prefs.getBytesLength("calRPM"); if (n==sizeof(app.calibRPM)) prefs.getBytes("calRPM", app.calibRPM, n); }
  g_planCount = prefs.getUChar("planCount", 0);
  size_t want = sizeof(PlanItem) * g_planCount;
  size_t havePlans = prefs.getBytesLength("plans");
  if (g_planCount > MAX_PLANS) g_planCount = MAX_PLANS;
  if (havePlans >= sizeof(PlanItem) && want <= havePlans) prefs.getBytes("plans", g_plans, sizeof(PlanItem) * g_planCount);
  else g_planCount = 0;

  String tzs = prefs.getString("tz", g_tz); tzs.toCharArray(g_tz, sizeof(g_tz));

  g_pairToken = prefs.getString("pair_token", "");
  g_pairTokenTrusted = prefs.getBool("pair_token_trusted", false);
  g_pairTokenTrustedIp = prefs.getUInt("pair_token_trusted_ip", 0);
  g_postResetOpenRecoveryAtBoot = prefs.getBool("post_reset_pair_win", false);
  g_cloudUserEnabled = prefs.getBool("cloud_en", false);
  g_cloudEndpointOverride = prefs.getString("cloud_ep", "");
  g_provisioned = prefs.getBool("provOk", false);

  size_t secLen = prefs.getBytesLength("device_secret");
  if (secLen == sizeof(g_deviceSecret)) {
    prefs.getBytes("device_secret", g_deviceSecret, sizeof(g_deviceSecret));
    g_deviceSecretLoaded = true;
  } else {
    g_deviceSecretLoaded = false;
  }

  // Wi-Fi creds (prefer encrypted storage; migrate legacy plaintext when possible)
  g_savedSsid = prefs.getString("wifi_ssid", prefs.getString("ssid", ""));
  
  // Prefer encrypted credentials. In production, do not silently continue using
  // legacy plaintext if encrypted material is present but cannot be decrypted.
  String encryptedPass = prefs.getString("wifi_pass_enc", "");
  if (encryptedPass.length() > 0) {
    String decrypted;
    if (decryptWifiPassword(encryptedPass, decrypted)) {
      g_savedPass = decrypted;
      if (prefs.isKey("wifi_pass")) prefs.remove("wifi_pass");
      if (prefs.isKey("pass")) prefs.remove("pass");
    } else {
      // Corrupted or stale encrypted state: fail closed in production.
#if PRODUCTION_BUILD
      g_savedPass = "";
      if (prefs.isKey("wifi_pass")) prefs.remove("wifi_pass");
      if (prefs.isKey("pass")) prefs.remove("pass");
#else
      g_savedPass = prefs.getString("wifi_pass", prefs.getString("pass", ""));
#endif
    }
  } else {
    // One-time migration from legacy plaintext storage.
    g_savedPass = prefs.getString("wifi_pass", prefs.getString("pass", ""));
    if (g_savedPass.length() > 0) {
      String enc;
      if (encryptWifiPassword(g_savedPass, enc)) {
        prefs.putString("wifi_pass_enc", enc);
        prefs.remove("wifi_pass");
        prefs.remove("pass");
      }
    }
  }
  AP_ONLY      = prefs.getBool("ap_only", false);
  // Owner / invite security state
  g_ownerHash  = prefs.getString("owner_hash", ""); // legacy
  g_ownerExists = prefs.getBool("owner_exists", false);
  g_ownerPubKeyB64 = prefs.getString("owner_pubkey", "");
  g_pairTokenTrusted = prefs.getBool("pair_token_trusted", false);
  g_pairTokenTrustedIp = prefs.getUInt("pair_token_trusted_ip", 0);
  g_setupUser = prefs.getString("setup_user", FACTORY_SETUP_USER);
  g_setupPassHashHex = prefs.getString("setup_pass_hash", "");
  g_setupPassEncB64 = prefs.getString("setup_pass_enc", "");
  const uint32_t qrPrintedCount = prefs.getUInt("qr_printed", 0);
  // Legacy migration: if plain exists, migrate to encrypted storage and delete plain.
  {
    const String legacyPlain = prefs.getString("setup_pass_plain", "");
    if (legacyPlain.length() == 32 && !g_setupPassEncB64.length()) {
      uint8_t raw[16];
      if (hexToBytes16(legacyPlain, raw)) {
        String enc;
        if (encryptSetupSecret16(raw, enc)) {
          g_setupPassEncB64 = enc;
          prefs.end();
          persistSetupEncIfAny();
          prefs.begin("aac", true);
        }
      }
    }
  }
  g_usersJson  = prefs.getString("users_json", "[]");
  g_shadowAclVersion = prefs.getUInt("acl_v", 0);
  g_setupDone  = prefs.getBool("setup_done", false);
  g_lastOtaStatus.phase = prefs.getString("ota_phase", "");
  g_lastOtaStatus.reason = prefs.getString("ota_reason", "");
  g_lastOtaStatus.jobId = prefs.getString("ota_job_id", "");
  g_lastOtaStatus.targetVersion = prefs.getString("ota_target_ver", "");
  g_lastOtaStatus.updatedAtMs = prefs.getUInt("ota_updated_ms", 0);
  // device_secret: varsa oku, yoksa ilk boot'ta üretilecek
  prefs.end();
  g_haveCreds = (g_savedSsid.length() && g_savedPass.length());
#if WIFI_INFO_LOG
  Serial.printf("[WiFi] loaded creds ssid='%s' pass=%s\n",
                g_savedSsid.c_str(),
                g_savedPass.length() ? "<set>" : "<empty>");
#endif

  // Eğer device_secret NVS'de yoksa, ilk boot'ta üret.
  if (!g_deviceSecretLoaded) {
    // 32 bayt kriptografik olarak güçlü rastgele değer üret
    for (size_t i = 0; i < sizeof(g_deviceSecret); ++i) {
      g_deviceSecret[i] = (uint8_t)(esp_random() & 0xFF);
    }
    g_deviceSecretLoaded = true;
    // NVS'e kalıcı olarak yaz
    prefs.begin("aac", false);
    prefs.putBytes("device_secret", g_deviceSecret, sizeof(g_deviceSecret));
    prefs.end();
    Serial.println("[SEC] device_secret generated and stored in NVS");
  }

  // Ensure factory setup creds exist (per-device):
  // user is fixed (AAC), pass is a per-device random secret (printed as QR/sticker at manufacturing).
  // We only store sha256(pass) on-device.
  bool setupDirty = false;
  g_setupPassJustGenerated = false;
  const String desiredUser = String(FACTORY_SETUP_USER);
  const String legacyUser = "factory_user";
  const String legacyHash = sha256HexOfString("839201");

  // If device is UNOWNED, migrate old defaults to new per-device scheme.
  if (!g_ownerExists) {
    if (!g_setupUser.length() || equalsIgnoreCaseStr(g_setupUser, legacyUser)) {
      g_setupUser = desiredUser;
      setupDirty = true;
    }
    if (!g_setupPassHashHex.length() || equalsIgnoreCaseStr(g_setupPassHashHex, legacyHash)) {
      // Generate a new random setup secret (16 bytes -> 32 hex chars).
      uint8_t raw[16];
      for (int i = 0; i < 16; ++i) raw[i] = (uint8_t)(esp_random() & 0xFF);
      const String setupSecretHex = bytes16ToHex(raw);
      String enc;
      if (encryptSetupSecret16(raw, enc)) {
        g_setupPassEncB64 = enc;
      }
      g_setupPassHashHex = sha256HexOfString(setupSecretHex);
      setupDirty = true;
      g_setupPassJustGenerated = true;
    }
  } else {
    // If already owned, only fill missing values (do not mutate).
    if (!g_setupUser.length()) {
      g_setupUser = desiredUser;
      setupDirty = true;
    }
    if (!g_setupPassHashHex.length()) {
      // Fill missing hash with a new random secret (cannot recover old secret).
      uint8_t raw[16];
      for (int i = 0; i < 16; ++i) raw[i] = (uint8_t)(esp_random() & 0xFF);
      const String setupSecretHex = bytes16ToHex(raw);
      String enc;
      if (encryptSetupSecret16(raw, enc)) {
        g_setupPassEncB64 = enc;
      }
      g_setupPassHashHex = sha256HexOfString(setupSecretHex);
      setupDirty = true;
      g_setupPassJustGenerated = true;
    }
  }
  if (setupDirty) {
    prefs.begin("aac", false);
    prefs.putString("setup_user", g_setupUser);
    prefs.putString("setup_pass_hash", g_setupPassHashHex);
    if (g_setupPassEncB64.length()) prefs.putString("setup_pass_enc", g_setupPassEncB64);
    prefs.end();
  }

  // Factory/label fallback:
  // If we have a hash but no plaintext (e.g. upgraded from older firmware, or
  // manufacturing forgot to capture the first QR print), reconstruct ONLY if it's the
  // legacy deterministic scheme. Never rotate automatically here; setup secret must
  // remain stable across reboots/updates unless flash/NVS is erased.
  if (!g_ownerExists && g_setupPassHashHex.length() && !g_setupPassEncB64.length()) {
    const String id6 = shortChipId();
    const String legacyPlain = String("aac") + id6;
    const String legacyHash2 = sha256HexOfString(legacyPlain);
    if (legacyHash2.length() && legacyHash2.equalsIgnoreCase(g_setupPassHashHex)) {
      uint8_t raw[16];
      if (hexToBytes16(legacyPlain, raw)) {
        String enc;
        if (encryptSetupSecret16(raw, enc)) {
          g_setupPassEncB64 = enc;
          persistSetupEncIfAny();
          g_setupPassJustGenerated = true; // allow printing once for labeling
        }
      }
    } else {
      Serial.println("[QR] setup_pass_plain missing; cannot recover from hash. "
                     "Do a full flash erase to generate a new label QR.");
    }
  }

  // If the device is still UNOWNED and the encrypted setup secret is missing,
  // regenerate a new per-device setup secret so manufacturing can print the
  // label QR (printed is throttled to max 2 times at boot).
  //
  // This path only triggers when qr_printed < 2, so once the label is captured
  // (and printed twice), it will no longer rotate unexpectedly.
  if (!g_ownerExists && !g_setupPassEncB64.length() && (qrPrintedCount < 2)) {
    uint8_t raw[16];
    for (int i = 0; i < 16; ++i) raw[i] = (uint8_t)(esp_random() & 0xFF);
    const String setupSecretHex = bytes16ToHex(raw);
    String enc;
    if (encryptSetupSecret16(raw, enc)) {
      g_setupUser = desiredUser;
      g_setupPassEncB64 = enc;
      g_setupPassHashHex = sha256HexOfString(setupSecretHex);
      g_setupPassJustGenerated = true;

      // Persist and re-enable QR printing allowance (boot code will consume it).
      prefs.end();
      prefs.begin("aac", false);
      prefs.putString("setup_user", g_setupUser);
      prefs.putString("setup_pass_hash", g_setupPassHashHex);
      prefs.putString("setup_pass_enc", g_setupPassEncB64);
      prefs.putUInt("qr_printed", 0);
      prefs.remove("setup_pass_plain");
      prefs.end();
      prefs.begin("aac", true);
      Serial.println("[QR] regenerated setup secret for labeling (enc was missing)");
    } else {
      Serial.println("[QR] failed to regenerate setup secret (encrypt failed)");
    }
  }
  const bool computedOwned =
      g_ownerExists || g_ownerPubKeyB64.length() || g_ownerHash.length();
  setOwned(computedOwned, "boot_after_nvs_load");
  if (!isOwned()) {
    g_cloudUserEnabled = false;
  }


  ensureAuthDefaults(); // ✅ QR bilgisi burada log'lanır (logQrIfAllowed ile)

  // Load persisted daily sensor history (if any)
  g_dailyCount = prefs.getUChar("dailyCount", 0);
  if (g_dailyCount > DAILY_HISTORY_CAPACITY) g_dailyCount = DAILY_HISTORY_CAPACITY;
  size_t haveDaily = prefs.getBytesLength("histDaily");
  size_t wantDaily = sizeof(DailySample) * g_dailyCount;
  if (g_dailyCount > 0 && haveDaily >= wantDaily) {
    DailySample tmp[DAILY_HISTORY_CAPACITY];
    prefs.getBytes("histDaily", tmp, wantDaily);
    for (uint8_t i = 0; i < g_dailyCount; ++i) {
      g_daily[i] = tmp[i];
    }
    g_dailyHead = g_dailyCount % DAILY_HISTORY_CAPACITY;
    // Restore last day key from most recent sample
    DailySample& last = g_daily[(g_dailyHead + DAILY_HISTORY_CAPACITY -
                                 (g_dailyCount ? 1 : 0)) %
                                DAILY_HISTORY_CAPACITY];
    if (last.dayStart != 0) {
      time_t t = (time_t)last.dayStart;
      struct tm tmLast;
      memset(&tmLast, 0, sizeof(tmLast));
      localtime_r(&t, &tmLast);
      g_lastDailyKey = (tmLast.tm_year + 1900) * 10000 +
                       (tmLast.tm_mon + 1) * 100 +
                       tmLast.tm_mday;
    }
  } else {
    g_dailyCount = 0;
    g_dailyHead = 0;
    g_lastDailyKey = -1;
  }

#if ENABLE_WAQI
  // WAQI şehir konfigürasyonunu yükle (varsa)
  Preferences prefsWaqi;
  prefsWaqi.begin("aac", true);
  double wLat = prefsWaqi.getDouble("waqiLat", WAQI_LAT_DEFAULT);
  double wLon = prefsWaqi.getDouble("waqiLon", WAQI_LON_DEFAULT);
  String wName = prefsWaqi.getString("waqiName", "");
  prefsWaqi.end();
  g_waqiConfig.lat   = wLat;
  g_waqiConfig.lon   = wLon;
  g_waqiConfig.name  = wName;
  g_waqiConfig.valid = !isnan(wLat) && !isnan(wLon);
#endif

}


static bool isAuthLikeCommand(const JsonDocument& doc) {
  const char* type = doc["type"] | "";
  const char* cmd  = doc["cmd"] | "";
  if (type[0]) {
    if (strcmp(type, "GET_NONCE") == 0) return true;
    if (strcmp(type, "AUTH") == 0) return true;
    if (strcmp(type, "AUTH_SETUP") == 0) return true;
    if (strcmp(type, "CLAIM_REQUEST") == 0) return true;
  }
  if (cmd[0]) {
    if (strcmp(cmd, "GET_NONCE") == 0) return true;
    if (strcmp(cmd, "AUTH") == 0) return true;
    if (strcmp(cmd, "AUTH_SETUP") == 0) return true;
  }
  return false;
}

static bool isOnlyCloudToggleCommand(const JsonDocument& doc) {
  // Allow enabling/disabling cloud without allowing other local controls.
  // Accepted shapes:
  // - { "cloudEnabled": true/false, "cmdId": "..."? }
  // - { "cloud": { "enabled": true/false }, "cmdId": "..."? }
  if (!doc.is<JsonObjectConst>()) return false;
  JsonObjectConst o = doc.as<JsonObjectConst>();

  bool hasToggle = false;
  bool toggleOk = false;
  if (o["cloudEnabled"].is<bool>()) {
    hasToggle = true;
    toggleOk = true;
  }
  if (!hasToggle) {
    JsonObjectConst c = o["cloud"].as<JsonObjectConst>();
    if (!c.isNull() && c["enabled"].is<bool>()) {
      hasToggle = true;
      // Ensure "cloud" object doesn't carry extra fields (avoid smuggling controls).
      if (c.size() == 1) toggleOk = true;
    }
  }
  if (!hasToggle || !toggleOk) return false;

  for (JsonPairConst kv : o) {
    const char* k = kv.key().c_str();
    if (!k || !k[0]) continue;
    // Common correlation keys we allow alongside the cloud toggle.
    if (strcmp(k, "cmdId") == 0 || strcmp(k, "cmd_id") == 0 || strcmp(k, "id") == 0) continue;
    if (strcmp(k, "cloudEnabled") == 0) continue;
    if (strcmp(k, "cloud") == 0) continue;
    // Anything else makes it a non-pure toggle.
    return false;
  }
  return true;
}

static bool allowLocalControlWhileCloudEnabled(const JsonDocument& doc, CmdSource src) {
  if (!g_cloudUserEnabled) return true;
  if (!g_ownerExists) return true; // onboarding/bootstrap
  if (src == CmdSource::MQTT) return true; // cloud path itself
  if (isOnlyCloudToggleCommand(doc)) return true;

  const char* type = doc["type"] | "";
  const char* cmd = doc["cmd"] | "";
  if ((type[0] && strcmp(type, "CLAIM_REQUEST") == 0) ||
      (type[0] && strcmp(type, "AUTH") == 0) ||
      (type[0] && strcmp(type, "AUTH_SETUP") == 0) ||
      (type[0] && strcmp(type, "GET_NONCE") == 0) ||
      (type[0] && strcmp(type, "JOIN") == 0) ||
      (cmd[0] && strcmp(cmd, "AUTH") == 0) ||
      (cmd[0] && strcmp(cmd, "AUTH_SETUP") == 0) ||
      (cmd[0] && strcmp(cmd, "GET_NONCE") == 0)) {
    return true;
  }

  BleRole role = BleRole::NONE;
  if (src == CmdSource::HTTP) {
    role = effectiveRole(g_httpRole);
  } else if (src == CmdSource::BLE) {
    role = effectiveRole(g_bleRole);
  } else {
    return false;
  }
  return role == BleRole::OWNER || role == BleRole::USER || role == BleRole::GUEST;
}

static bool handleIncomingControlJson(JsonDocument& doc,
                                      CmdSource src,
                                      const char* srcName,
                                      bool skipAck,
                                      bool* acceptedOut) {
  if (acceptedOut) *acceptedOut = true;
  g_mqttRole = BleRole::NONE;
  // Allow owner claim while unowned (CLAIM_REQUEST is handled in applyControlDocument).
  const char* type = doc["type"] | "";
  const bool isClaimRequest = (type[0] && strcmp(type, "CLAIM_REQUEST") == 0);
  const bool isJoinRequest = (type[0] && strcmp(type, "JOIN") == 0);
  const bool owned = isOwned();
  const bool mqttUnownedAllowed =
      (src == CmdSource::MQTT &&
       !owned &&
       g_cloudUserEnabled &&
       g_cloud.linked &&
       g_cloud.mqttConnected);
  if (src == CmdSource::MQTT && !owned && !mqttUnownedAllowed) {
    Serial.println("[CMD] MQTT rejected (device unclaimed)");
    if (acceptedOut) *acceptedOut = false;
    return false;
  }
  if (mqttUnownedAllowed) {
    Serial.println("[CMD] MQTT accepted while unclaimed (cloud-linked fallback)");
  }
  // Unowned policy:
  // - BLE/TCP/MQTT: keep strict owner requirement (except CLAIM_REQUEST).
  // - HTTP: allow command handling when request is already authorized by
  //   authorizeRequest() (pairToken/session). This enables AP onboarding control
  //   without forcing immediate BLE owner-claim.
  if (!owned && !isClaimRequest && src != CmdSource::HTTP && !mqttUnownedAllowed) {
    Serial.printf("[CMD] rejected (device unclaimed; owner required) src=%s\n",
                  srcName ? srcName : "?");
    if (acceptedOut) *acceptedOut = false;
#if ENABLE_BLE
    if (src == CmdSource::BLE) {
      bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"owner_required\"}}"));
    }
#endif
    return false;
  }
  if (!allowLocalControlWhileCloudEnabled(doc, src)) {
    Serial.printf("[CMD] rejected (local disabled in cloud mode) src=%s type=%s\n",
                  srcName ? srcName : "?",
                  type[0] ? type : "-");
    if (acceptedOut) *acceptedOut = false;
#if ENABLE_BLE
    if (src == CmdSource::BLE) {
      bleScheduleNotify(String("{\"ok\":false,\"err\":\"local_disabled_cloud\"}"));
    }
#endif
    return false;
  }
  // ✅ Input validation: cmdId length
  String cmdId;
  if (doc["cmdId"].is<const char*>()) cmdId = String(doc["cmdId"].as<const char*>());
  else if (doc["cmd_id"].is<const char*>()) cmdId = String(doc["cmd_id"].as<const char*>());
  else if (doc["id"].is<const char*>()) cmdId = String(doc["id"].as<const char*>());
  cmdId.trim();
  if (cmdId.length() > 64) {
    Serial.printf("[CMD] cmdId too long (%u), rejecting\n", (unsigned)cmdId.length());
    if (acceptedOut) *acceptedOut = false;
    return false;
  }
  if (cmdId.isEmpty()) {
    cmdId = genCmdIdHex8();
    doc["cmdId"] = cmdId;
  }

  // MQTT shadow ACL deltas must be applied before role resolution.
  // Otherwise a first-time/updated user can be stuck at role=NONE forever.
  if (src == CmdSource::MQTT) {
    JsonObjectConst aclObj = doc["acl"].as<JsonObjectConst>();
    if (!aclObj.isNull()) {
      const uint32_t incomingAclVer = (uint32_t)(aclObj["version"] | aclObj["ver"] | 0);
      if (incomingAclVer > 0 && incomingAclVer > g_shadowAclVersion) {
        JsonDocument aclOnlyDoc;
        aclOnlyDoc["acl"] = aclObj;
        const bool aclTouched = applyControlDocument(aclOnlyDoc);
        Serial.printf(
            "[CMD][MQTT] pre-ACL apply incomingVer=%u localVer=%u changed=%d\n",
            (unsigned)incomingAclVer,
            (unsigned)g_shadowAclVersion,
            aclTouched ? 1 : 0);
      }
    }
  }

  // Role enforcement (owned devices only)
  if (g_ownerExists && !(src == CmdSource::MQTT && isJoinRequest)) {
    BleRole role = BleRole::OWNER;
    if (src == CmdSource::BLE) role = effectiveRole(g_bleRole);
    else if (src == CmdSource::HTTP) role = effectiveRole(g_httpRole);
    else if (src == CmdSource::MQTT) {
      const String userIdHash = extractUserIdHashFromDoc(doc);
      String resolvedId;
      role = roleFromUserIdHash(userIdHash, resolvedId);
      Serial.printf("[CMD][MQTT] userIdHash=%s resolvedRole=%s\n",
                    userIdHash.length() ? userIdHash.c_str() : "-",
                    roleToStr(role));
      if (role == BleRole::NONE) {
        Serial.printf("[CMD][MQTT] rejected (role none) type=%s cmdId=%s\n",
                      type[0] ? type : "-", cmdId.c_str());
        if (acceptedOut) *acceptedOut = false;
        return false;
      }
    }

    if (role == BleRole::NONE) role = BleRole::GUEST;
    if (src == CmdSource::MQTT) g_mqttRole = role;

    // Guest: read-only (reject all control updates)
    if (role == BleRole::GUEST) {
      if (acceptedOut) *acceptedOut = false;
      if (src == CmdSource::BLE) {
        bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
      }
      return false;
    }

    // User: no planning
    if (role == BleRole::USER) {
      bool hasPlans = doc["plans"].is<JsonArray>();
      JsonVariant cmdVar = doc["cmd"];
      if (!hasPlans && cmdVar.is<JsonObject>()) {
        JsonObjectConst cmdObj = cmdVar.as<JsonObjectConst>();
        if (!cmdObj["plans"].isNull()) hasPlans = true;
      }
      if (hasPlans) {
        if (acceptedOut) *acceptedOut = false;
        if (src == CmdSource::BLE) {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
        }
        return false;
      }
    }
  }
  if (src == CmdSource::MQTT && isJoinRequest) {
    Serial.printf("[JOIN][MQTT] bypass role check type=JOIN cmdId=%s\n", cmdId.c_str());
  }
  
  // ✅ Input validation: numeric fields range check
  if (doc["fanPct"].is<int>()) {
    int fanPct = doc["fanPct"];
    if (fanPct < 0 || fanPct > 100) {
      Serial.printf("[CMD] fanPct out of range: %d, rejecting\n", fanPct);
      if (acceptedOut) *acceptedOut = false;
      return false;
    }
  }
  if (doc["fanPercent"].is<int>()) {
    int fanPercent = doc["fanPercent"];
    if (fanPercent < 0 || fanPercent > 100) {
      Serial.printf("[CMD] fanPercent out of range: %d, rejecting\n", fanPercent);
      if (acceptedOut) *acceptedOut = false;
      return false;
    }
  }
  if (doc["rgbBrightness"].is<int>()) {
    int rgbBrightness = doc["rgbBrightness"];
    if (rgbBrightness < 0 || rgbBrightness > 100) {
      Serial.printf("[CMD] rgbBrightness out of range: %d, rejecting\n", rgbBrightness);
      if (acceptedOut) *acceptedOut = false;
      return false;
    }
  }
  if (doc["r"].is<int>() || doc["g"].is<int>() || doc["b"].is<int>()) {
    int r = doc["r"] | 0;
    int g = doc["g"] | 0;
    int b = doc["b"] | 0;
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      Serial.printf("[CMD] RGB out of range: r=%d g=%d b=%d, rejecting\n", r, g, b);
      if (acceptedOut) *acceptedOut = false;
      return false;
    }
  }




  g_lastCmdSource = src;
  const bool changed = applyControlDocument(doc);
  g_lastCmdSource = CmdSource::UNKNOWN;

  if (changed || CMD_LOG_UNCHANGED) {
    Serial.printf("[CMD] handled cmdId=%s src=%s changed=%d\n",
                  cmdId.c_str(), srcName ? srcName : "?", changed ? 1 : 0);
  }

  if (changed) {
    g_cloudDirty = true;
  }
  return changed;
}


/* =================== BLE callbacks =================== */
class ProvCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    ScopedPerfLog perfScope("ble_prov_write");
    g_blePolicyHoldUntilMs = millis() + 120000UL;
    std::string s = c->getValue();
    Serial.printf("[BLE][PROV] raw write (%u bytes)\n", (unsigned)s.size());
    logPerfSnapshot("ble_prov_write_start");
    
    // ✅ Input validation: JSON size limit
    if (s.size() > 512) {
      Serial.println("[BLE][PROV] payload too large, rejecting");
      String resp = "{\"ok\":false,\"err\":\"payload_too_large\"}";
      c->setValue(resp.c_str());
      c->notify();
      return;
    }
    
    JsonDocument doc;
    if (deserializeJson(doc, s)) {
      Serial.println("[BLE][PROV] JSON parse failed");
      return;
    }

    if (handleBleCommandJson(doc)) {
      return;
    }

    const char* ssid = doc["ssid"] | "";
    const char* pass = doc["pass"] | "";
    
    // ✅ Input validation: SSID ve password length
    if (!ssid || !*ssid) return;
    if (strlen(ssid) > 32) {
      Serial.println("[BLE][PROV] SSID too long, rejecting");
      String resp = "{\"ok\":false,\"err\":\"ssid_too_long\"}";
      c->setValue(resp.c_str());
      c->notify();
      return;
    }
    if (pass && strlen(pass) > 64) {
      Serial.println("[BLE][PROV] password too long, rejecting");
      String resp = "{\"ok\":false,\"err\":\"pass_too_long\"}";
      c->setValue(resp.c_str());
      c->notify();
      return;
    }
    if (g_ownerExists && g_bleAuthed && effectiveRole(g_bleRole) != BleRole::OWNER) {
      Serial.println("[BLE][PROV] rejected (insufficient role)");
      String resp = "{\"ok\":false,\"err\":\"insufficient_role\"}";
      c->setValue(resp.c_str());
      c->notify();
      return;
    }
    if (g_ownerExists && !g_bleAuthed) {
      Serial.println("[BLE][PROV] rejected (owner auth required)");
      String resp = "{\"ok\":false,\"err\":\"auth_required\"}";
      c->setValue(resp.c_str());
      c->notify();
      return;
    }
    const char* pair = doc["pair"] | doc["qrToken"] | doc["qr_token"] | doc["pairToken"] | doc["pair_token"] | "";
    const bool pairOk = (pair && *pair && equalsIgnoreCase(pair, g_pairToken.c_str()));
    if (!pairOk) {
      if (!g_bleAuthed) {
        Serial.printf(
            "[BLE] Provisioning rejected: invalid pair token (got_len=%u expected_len=%u authed=%d)\n",
            (unsigned)strlen(pair ? pair : ""),
            (unsigned)g_pairToken.length(),
            (int)g_bleAuthed);
        String resp = "{\"ok\":false,\"err\":\"pair_invalid\"}";
        c->setValue(resp.c_str());
        c->notify();
        // Do NOT disconnect: keep BLE session alive so the user can retry / rescan QR.
        return;
      }
      // If the BLE session is already authenticated (AUTH_SETUP / owner AUTH), accept provisioning even if
      // the client has a stale pairToken cached; the device will echo the current pairToken back in the ack.
      Serial.printf(
          "[BLE] Provisioning pair token mismatch but session authed -> accepting (got_len=%u expected_len=%u)\n",
          (unsigned)strlen(pair ? pair : ""),
          (unsigned)g_pairToken.length());
    }

    Serial.printf("[BLE][PROV] creds received (ssidLen=%u, passLen=%u)\n", (unsigned)strlen(ssid), (unsigned)strlen(pass));

    logPerfSnapshot("ble_prov_before_save_creds");
    saveCreds(ssid, pass);
    logPerfSnapshot("ble_prov_after_save_creds");
    if (!AP_ONLY) {
      Serial.printf("[BLE] Wi-Fi creds saved. Try connect to '%s'...\n", ssid);
      logPerfSnapshot("ble_prov_before_sta_begin");
      WiFi.disconnect(true,true);
      WiFi.mode(WIFI_AP_STA);
      WiFi.begin(g_savedSsid.c_str(), g_savedPass.c_str());
      logPerfSnapshot("ble_prov_after_sta_begin");
      unsigned long t0 = millis();
      while (WiFi.status()!=WL_CONNECTED && millis()-t0<15000) delay(200);
      logPerfSnapshot("ble_prov_after_sta_wait");
    } else {
      Serial.printf("[BLE] Creds saved (AP_ONLY active, STA disabled)\n");
    }
    // Do NOT rotate pairToken here: QR/pairToken is designed as a stable local trust anchor.
    JsonDocument ack;
    bool staOk = (WiFi.status() == WL_CONNECTED);
    ack["ok"] = true;
    ack["sta"] = staOk;
    ack["status"] = (int)WiFi.status();
    ack["ssid"] = g_savedSsid;
    if (staOk) {
      ack["ip"] = WiFi.localIP().toString();
    } else {
      ack["note"] = "sta_failed";
    }
    ack["mdnsHost"] = deviceMdnsFqdnForId6(shortChipId());
    String ackOut;
    serializeJson(ack, ackOut);
    c->setValue(ackOut.c_str());
    logPerfSnapshot("ble_prov_before_notify");
    c->notify();
    logPerfSnapshot("ble_prov_after_notify");

    if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
      // Also publish provisioning result over INFO notify so clients that don't subscribe to PROV can see it.
      // This helps mobile apps confirm the stored QR/pairToken matches the device.
      bleScheduleNotify(String("{\"prov\":") + ackOut + "}");
      bleNotifyJson(buildBleStatusJson());
    }
  }
};


class CmdCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    ScopedPerfLog perfScope("ble_cmd_write");
    g_blePolicyHoldUntilMs = millis() + 120000UL;
    std::string s = c->getValue();
    Serial.printf("[BLE][CMD] raw write (%u bytes)\n", (unsigned)s.size());
    logPerfSnapshot("ble_cmd_write_start");
    
    // ✅ Input validation: JSON size limit
    if (s.size() > 8192) {
      Serial.println("[BLE][CMD] payload too large, rejecting");
      return;
    }
    
    uint32_t nowMs = millis();
    JsonDocument doc;
    if (deserializeJson(doc, s)) {
      Serial.println("[BLE][CMD] JSON parse failed, ignoring");
      return; // parse error -> ignore
    }
    // Keep payload contents out of logs; size/type are enough for diagnostics.
    String dbgJson;
    serializeJson(doc, dbgJson);
    Serial.printf("[BLE][CMD] parsed json (%u bytes)\n", (unsigned)dbgJson.length());

#if ENABLE_BLE
    g_lastCmdSource = CmdSource::BLE;
#endif

    const char* dbgType = doc["type"] | "";
    if (dbgType[0]) {
      Serial.printf("[BLE][CMD] parsed type=%s (src=BLE)\n", dbgType);
    }

#if ENABLE_BLE
    // --- Signature auth is allowed both in owned and unowned modes ---
    const char* cmd = doc["cmd"] | "";
    const char* type = doc["type"] | "";
    const char* getVal = doc["get"] | "";
    const bool isGetNonce =
        (cmd[0] && strcmp(cmd, "GET_NONCE") == 0) ||
        (type[0] && strcmp(type, "GET_NONCE") == 0);
    const bool isAuth =
        (cmd[0] && strcmp(cmd, "AUTH") == 0) ||
        (type[0] && strcmp(type, "AUTH") == 0);
    Serial.printf(
      "[BLE][CMDDBG] cmd=%s type=%s get=%s owner=%d authed=%d\n",
      cmd[0] ? cmd : "-",
      type[0] ? type : "-",
      getVal[0] ? getVal : "-",
      g_ownerExists ? 1 : 0,
      g_bleAuthed ? 1 : 0
    );

    if (isGetNonce) {
      g_bleNonceB64 = makeNonceB64();
      // Do not clear an existing authenticated session on GET_NONCE.
      // The mobile app can probe with GET_NONCE periodically; logging out here
      // makes "connected but can't control" failures likely.
      JsonDocument out;
      out["auth"]["nonce"] = g_bleNonceB64;
      out["auth"]["owned"] = isOwned();
      // Include stable identity hints so the app can resolve per-device
      // cached setup credentials / pair token before sending AUTH_SETUP.
      out["auth"]["deviceId"] = canonicalDeviceId();
      out["auth"]["id6"] = shortChipId();
      out["auth"]["pairingWindowActive"] = g_pairingWindowActive;
      // Expose current pair token only in recovery/authorized contexts.
      const uint32_t nowMsNonce = millis();
      if (!isOwned() || ownerRotateWindowActive(nowMsNonce) || g_bleAuthed) {
        out["auth"]["pairToken"] = g_pairToken;
      }
      String resp;
      serializeJson(out, resp);
      bleScheduleNotify(resp);
      return;
    }

    if (isAuth) {
      const char* qrToken = doc["qrToken"] | doc["qr_token"] | doc["pairToken"] | doc["pair_token"] | "";
      if (qrToken && *qrToken) {
        if (g_ownerExists) {
          Serial.println("[BLE] auth denied: owner already exists");
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"owner_already_exists\"}}"));
          return;
        }
        if (g_pairToken.isEmpty()) {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"missing_pairToken\"}}"));
          return;
        }
        if (!equalsIgnoreCaseStr(String(qrToken), g_pairToken)) {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"invalid_qr_token\"}}"));
          return;
        }
        g_bleAuthed = true;
        g_bleRole = BleRole::OWNER;
        g_bleUserIdHash.clear();
        g_bleAuthDeadlineMs = 0;
        bleScheduleNotify(String("{\"auth\":{\"ok\":true,\"mode\":\"qr\"}}"));
        return;
      }

      const char* sig = doc["sig"] | doc["signature"] | "";
      const char* nonce = doc["nonce"] | "";
      if (!sig[0] || !nonce[0]) {
        bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"missing_sig_or_nonce\"}}"));
        return;
      }
      // Queue for main loop verification (avoid NimBLE host stack overflow).
      bleQueueAuthVerify(nonce, sig);
      return;
    }

    const bool isAuthSetup =
        (cmd[0] && strcmp(cmd, "AUTH_SETUP") == 0) ||
        (type[0] && strcmp(type, "AUTH_SETUP") == 0);
    const bool isClaim = (type[0] && strcmp(type, "CLAIM_REQUEST") == 0);

    // QR token policy:
    // - Unowned devices: require QR token for all commands except GET_NONCE/AUTH/AUTH_SETUP/CLAIM_REQUEST.
    // - Owned devices: once an OWNER BLE session is authenticated, ECDSA auth is sufficient; do not require
    //   QR token as a second factor (prevents lockouts when NVS/token changes).
    if (!g_ownerExists && !g_bleAuthed && !isGetNonce && !isAuth && !isAuthSetup && !isClaim) {
      const char* qrToken = doc["qrToken"] | doc["qr_token"] | doc["pairToken"] | doc["pair_token"] | "";
      if (!qrToken || !qrToken[0]) {
        // QR token yoksa reddet, ama bağlantıyı koparma: kullanıcı yeniden deneyebilsin.
        bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"qr_token_required\"}}"));
        return;
      }
      
      // QR token doğrula
      Serial.printf("[BLE] qr token verify (got_len=%u expected_len=%u)\n",
                    (unsigned)strlen(qrToken),
                    (unsigned)g_pairToken.length());
      if (!equalsIgnoreCaseStr(String(qrToken), g_pairToken)) {
        bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"invalid_qr_token\"}}"));
        // Do NOT disconnect: leave the session open so the client can rescan/update QR and retry.
        return;
      }
      // QR doğrulaması başarılıysa unowned BLE session'ı kısa süreli yetkilendir.
      // Bu, AP-guided akışta AUTH_SETUP zorunluluğu olmadan komutların (örn. ap_credentials)
      // stabil şekilde işlenmesini sağlar.
      g_bleAuthed = true;
      g_bleRole = BleRole::SETUP;
      g_bleAuthDeadlineMs = 0;
      Serial.println("[BLE][CMDDBG] qr verified -> session authed=1 role=SETUP");
    }

    // --- Secure owner mode: when owned, require AUTH before allowing control ---
    if (g_ownerExists) {
      BleRole role = BleRole::OWNER;
      bool authed = false;
      if (g_lastCmdSource == CmdSource::BLE) {
        role = effectiveRole(g_bleRole);
        authed = g_bleAuthed;
      } else if (g_lastCmdSource == CmdSource::HTTP) {
        role = effectiveRole(g_httpRole);
        authed = ((uint8_t)role >= (uint8_t)BleRole::OWNER);
      }
      if (role == BleRole::NONE) role = BleRole::GUEST;

      // For any other command while owned, require an authenticated session.
      if (!authed) {
        const bool rotateWin = ownerRotateWindowActive(nowMs);
        // Physical-presence recovery: allow factory QR auth/claim within rotate window.
        if (rotateWin && (isAuthSetup || isClaim)) {
          if (isAuthSetup) {
            const char* user = doc["user"] | "";
            const char* pass = doc["pass"] | "";
            if (!user[0] || !pass[0]) {
              bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"missing_user_or_pass\"}}"));
              if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
                g_bleServer->disconnect(g_bleConnHandle);
              }
              return;
            }
            const bool ok = verifySetupUserPass(user, pass);
            g_bleAuthed = ok;
            g_bleRole = ok ? BleRole::SETUP : BleRole::NONE;
            g_bleUserIdHash.clear();
            if (ok) g_bleAuthDeadlineMs = 0;
            if (ok) {
              bleScheduleNotify(String("{\"auth\":{\"ok\":true,\"mode\":\"rotate\"}}"));
            } else {
              bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"invalid_user_or_pass\"}}"));
              if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
                g_bleServer->disconnect(g_bleConnHandle);
              }
            }
            return;
          }
          // CLAIM_REQUEST is allowed (it validates the same factory secret).
        } else {
          if (g_lastCmdSource == CmdSource::BLE) {
            bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"not_authenticated\"}}"));
            if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
              g_bleServer->disconnect(g_bleConnHandle);
            }
          }
          g_lastCmdSource = CmdSource::UNKNOWN;
          return;
        }
      }

      // If the recovery window is open and we're processing CLAIM_REQUEST, allow it
      // to proceed even if the session isn't otherwise authenticated yet.
      if (!authed && !(ownerRotateWindowActive(nowMs) && isClaim)) {
        if (g_lastCmdSource == CmdSource::BLE) {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"not_authenticated\"}}"));
          if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
            g_bleServer->disconnect(g_bleConnHandle);
          }
        }
        g_lastCmdSource = CmdSource::UNKNOWN;
        return;
      }

      // Owner-only operations: deny for invited USER role.
      const bool isOwnerOnly =
          (type[0] && (strcmp(type, "GET_INVITE") == 0 ||
                       strcmp(type, "OPEN_JOIN_WINDOW") == 0 ||
                       strcmp(type, "REVOKE_USER") == 0 ||
                       strcmp(type, "UNOWN") == 0 ||
                       strcmp(type, "CLEAR_OWNER") == 0 ||
                       strcmp(type, "ROTATE_PAIR") == 0 ||
                       strcmp(type, "ROTATE_OWNER_KEY") == 0 ||
                       strcmp(type, "SET_JWT") == 0 ||
                       strcmp(type, "AP_MODE") == 0 ||
                       strcmp(type, "AP_START") == 0)) ||
          (cmd[0] && (strcmp(cmd, "ROTATE_PAIR") == 0));
      if (isOwnerOnly && role != BleRole::OWNER) {
        if (g_lastCmdSource == CmdSource::BLE) {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
          if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
            g_bleServer->disconnect(g_bleConnHandle);
          }
        }
        g_lastCmdSource = CmdSource::UNKNOWN;
        return;
      }
    }
#endif

#if ENABLE_BLE
    // --- Unowned mode: require factory QR auth before allowing control ---
    if (!g_ownerExists) {
      const bool isAuthSetup =
          (cmd[0] && strcmp(cmd, "AUTH_SETUP") == 0) ||
          (type[0] && strcmp(type, "AUTH_SETUP") == 0);
      const bool isClaim = (type[0] && strcmp(type, "CLAIM_REQUEST") == 0);
      const bool isGetApCredentials =
          equalsIgnoreCase(cmd, "get_ap_credentials") ||
          equalsIgnoreCase(cmd, "ap_credentials") ||
          equalsIgnoreCase(getVal, "ap_credentials") ||
          (doc["ap_credentials"].is<bool>() && doc["ap_credentials"].as<bool>());

      if (isAuthSetup) {
        const char* user = doc["user"] | "";
        const char* pass = doc["pass"] | "";
        uint32_t retryMs = 0;
        if (setupAuthLocked(nowMs, &retryMs)) {
          JsonDocument out;
          out["auth"]["ok"] = false;
          out["auth"]["err"] = "setup_locked";
          out["auth"]["retryMs"] = retryMs;
          String resp;
          serializeJson(out, resp);
          bleScheduleNotify(resp);
          if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
            Serial.println("[BLE][DISC] unowned setup_locked");
            g_bleServer->disconnect(g_bleConnHandle);
          }
          return;
        }
        if (!user[0] || !pass[0]) {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"missing_user_or_pass\"}}"));
          if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
            Serial.println("[BLE][DISC] unowned missing_user_or_pass");
            g_bleServer->disconnect(g_bleConnHandle);
          }
          return;
        }
        const bool ok = verifySetupUserPass(user, pass);
        if (ok) noteSetupAuthSuccess();
        else noteSetupAuthFailure(nowMs);
        g_bleAuthed = ok;
        g_bleRole = ok ? BleRole::SETUP : BleRole::NONE;
        g_bleUserIdHash.clear();
        if (ok) g_bleAuthDeadlineMs = 0;
      if (ok) {
        // AUTH_SETUP authenticates the factory QR only.
        // It must NOT set owner; ownership is assigned via CLAIM_REQUEST.
        JsonDocument out;
        out["auth"]["ok"] = true;
        out["auth"]["deviceId"] = canonicalDeviceId();
        out["auth"]["id6"] = shortChipId();
        out["auth"]["pairingWindowActive"] = g_pairingWindowActive;
        out["auth"]["owned"] = isOwned();
        out["auth"]["pairToken"] = g_pairToken;
        String resp;
        serializeJson(out, resp);
        bleScheduleNotify(resp);
      } else {
          bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"invalid_user_or_pass\"}}"));
          if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
            Serial.println("[BLE][DISC] unowned invalid_user_or_pass");
            g_bleServer->disconnect(g_bleConnHandle);
          }
        }
        return;
      }

      // Allow owner claim without prior auth (it already validates setup user/pass).
      // Unowned AP-guided flow may fetch AP credentials with only a valid QR token.
      // QR token was already validated in the gate above; do not force AUTH_SETUP here.
      if (!isClaim && !isGetApCredentials && !g_bleAuthed) {
        bleScheduleNotify(String("{\"auth\":{\"ok\":false,\"err\":\"not_authenticated\"}}"));
        if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
          Serial.println("[BLE][DISC] unowned not_authenticated");
          g_bleServer->disconnect(g_bleConnHandle);
        }
        g_lastCmdSource = CmdSource::UNKNOWN;
        return;
      }
    }
#endif

#if ENABLE_BLE
    if (isClaim) {
      // CLAIM_REQUEST does crypto/JSON/storage work; defer to main loop to avoid
      // running heavy logic on nimble_host's limited stack.
      bleQueueClaimRequest(s.c_str());
      g_lastCmdSource = CmdSource::UNKNOWN;
      return;
    }
    if (handleBleCommandJson(doc)) {
      g_lastCmdSource = CmdSource::UNKNOWN;
      return;
    }
#endif

    // Unified command pipeline: BLE/HTTP/TCP all go through the same handler.
    const bool changed = handleIncomingControlJson(doc, CmdSource::BLE, "BLE", false, nullptr);
    // BLE: send compact status to avoid MTU/chunking issues on iOS.
    bleNotifyJson(buildBleStatusJson());
    if (changed) savePrefs();
    g_lastCmdSource = CmdSource::UNKNOWN;
  }
};

void bleCoreInit() {
#if ENABLE_BLE
  if (g_bleForceOff) {
    Serial.println("[BLE] disabled by policy");
    return;
  }
  if (g_bleCoreInitDone) return;
  Serial.println("[BLE] core init: NimBLEDevice::init()");

  // --- SAFETY PRE-FLIGHT: fully stop/deinit any prior BT controller state ---
  esp_bt_controller_status_t btStat = esp_bt_controller_get_status();
  Serial.printf("[BLE] controller status before init: %d\n", (int)btStat);

  // If the controller is already INITED or ENABLED (some cores leave it that way),
  // Do NOT attempt runtime deinit/cleanup here: NimBLE timers/callouts can still be
  // pending and deinitializing can crash (InstrFetchProhibited). If the controller
  // is already active, keep it as-is and skip re-init.
  if (btStat == ESP_BT_CONTROLLER_STATUS_ENABLED || btStat == ESP_BT_CONTROLLER_STATUS_INITED) {
    Serial.printf("[BLE] controller already %d; skipping NimBLE init\n", (int)btStat);
    g_bleCoreInitDone = true;
    return;
  }

  // Build name first (uses MAC helpers already available)
  String fullBleName = deviceBleNameForId6(shortChipId());
  g_bleName = fullBleName; // remember for later logs

  delay(20); // give Wi‑Fi/Coex a breath before bringing up BLE controller
  // Initialize NimBLE stack (no classic mem releases here; rely on default)
  NimBLEDevice::init(fullBleName.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P3);
  NimBLEDevice::setDeviceName(fullBleName.c_str());
  NimBLEDevice::setCustomGapHandler(bleGapLogHandler);
  // Not clearing bonds on every boot: doing so can cause iOS "Peer removed pairing information"
  // errors if the phone has a cached bond. Bonds are cleared on factory reset instead.

  // Keep BLE link-layer security disabled for maximum iOS/Android compatibility.
  // Application-layer security is enforced via AUTH_SETUP / owner AUTH.
  // Optional link-layer security:
  // - When the device is OWNED, enable bonding/SC so already-bonded phones can
  //   transparently encrypt the link (reduces MITM). We DO NOT require
  //   encryption for GATT access; we only auto-initiate security when a bond
  //   already exists to avoid intrusive pairing prompts.
  const bool enableBonding = g_ownerExists;
  NimBLEDevice::setSecurityAuth(enableBonding, false /*mitm*/, enableBonding /*sc*/);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

  class ServerCB : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* s, ble_gap_conn_desc* desc) override {
      (void)s;
      if (desc) {
        g_bleConnHandle = desc->conn_handle;
        const NimBLEAddress peer(desc->peer_id_addr);
        if (g_ownerExists) {
          if (NimBLEDevice::isBonded(peer)) {
            Serial.printf("[BLE] bonded peer %s -> startSecurity\n", peer.toString().c_str());
            NimBLEDevice::startSecurity(g_bleConnHandle);
          }
        }
      } else {
        g_bleConnHandle = BLE_HS_CONN_HANDLE_NONE;
      }
      const uint32_t nowMs = millis();
      if (!bleConnectionsAllowed(nowMs)) {
        Serial.printf("[BLE] rejecting connect (recovery disabled, conn_handle=%u)\n",
                      (unsigned)g_bleConnHandle);
        g_bleAuthed = false;
        g_bleRole = BleRole::NONE;
        g_bleUserIdHash.clear();
        g_bleNonceB64.clear();
        g_bleAuthDeadlineMs = 0;
        g_bleConnectedAtMs = 0;
        g_blePolicyHoldUntilMs = 0;
        if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
          g_bleServer->disconnect(g_bleConnHandle);
        }
        g_bleConnHandle = BLE_HS_CONN_HANDLE_NONE;
        return;
      }
      // New connection => reset session auth state.
      bool restoreAuth = false;
      if (desc && g_ownerExists) {
        const NimBLEAddress peer(desc->peer_id_addr);
        if (NimBLEDevice::isBonded(peer)) {
          restoreAuth = true;
        }
      }
      if (!restoreAuth && g_ownerExists &&
          g_bleOwnerAuthGraceUntilMs != 0 &&
          (int32_t)(g_bleOwnerAuthGraceUntilMs - nowMs) > 0) {
        restoreAuth = true;
      }
      if (restoreAuth) {
        Serial.println("[BLE] owner auth restored on reconnect");
        g_bleAuthed = true;
        g_bleRole = BleRole::OWNER;
        g_bleAuthDeadlineMs = 0;
      } else {
        g_bleAuthed = false;
        g_bleRole = BleRole::NONE;
        g_bleAuthDeadlineMs = nowMs + 15000UL;
      }
      g_bleUserIdHash.clear();
      g_bleNonceB64.clear();
      g_bleConnectedAtMs = nowMs;
      g_blePolicyHoldUntilMs = nowMs + 45000UL;
      g_bleLastStatusMs = 0;
      Serial.printf("[BLE] Connected (conn_handle=%u)\n", (unsigned)g_bleConnHandle);
    }
    void onDisconnect(NimBLEServer* s) override {
      g_bleAuthed = false;
      g_bleRole = BleRole::NONE;
      g_bleUserIdHash.clear();
      g_bleNonceB64.clear();
      g_bleConnHandle = BLE_HS_CONN_HANDLE_NONE;
      g_bleAuthDeadlineMs = 0;
      g_bleLastStatusMs = 0;
      g_bleConnectedAtMs = 0;
      g_blePolicyHoldUntilMs = 0;
      // Resume advertising only if allowed by the current policy (pair/join window).
      if (!g_bleForceOff && g_bleDesiredOn) {
        bleStartAdvertising();
      }
      if (g_bleAdvStarted) Serial.println("[BLE] Disconnected -> advertising restarted");
    }
  };

  g_bleServer = NimBLEDevice::createServer();
  g_bleServer->setCallbacks(new ServerCB());

  NimBLEService* svc = g_bleServer->createService(SVC_UUID);
  // Keep writes unencrypted at the BLE link layer for compatibility; access is still gated
  // by app-level secrets (pair token / AUTH_SETUP / owner AUTH) and we disconnect on failures.
  g_chProv = svc->createCharacteristic(CH_PROV, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR); g_chProv->setCallbacks(new ProvCB());
  g_chInfo = svc->createCharacteristic(CH_INFO, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY); g_chInfo->setValue(buildStatusJson());
  g_chCmd  = svc->createCharacteristic(CH_CMD,  NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR); g_chCmd->setCallbacks(new CmdCB());
  svc->start();

  // Prepare advertising payloads but DO NOT start yet
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData ad, sd;
  ad.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  adv->addServiceUUID(NimBLEUUID(SVC_UUID));
  sd.setName(fullBleName.c_str());
  adv->setAdvertisementData(ad);
  adv->setScanResponseData(sd);
  adv->setMinInterval(0x0120); // ~180ms
  adv->setMaxInterval(0x0190); // ~250ms

  g_bleCoreInitDone = true;
  Serial.println("[BLE] core init: OK (advertising not started)");
#endif
}

void bleStartAdvertising() {
#if ENABLE_BLE
  ScopedPerfLog perfScope("ble_adv_start", 10000);
  if (g_bleForceOff || !g_bleDesiredOn) return;
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();

  if (!g_bleCoreInitDone) {
    bleCoreInit();
  }
  if (!g_bleCoreInitDone || g_bleAdvStarted) return;
  Serial.println("[BLE] advertising start");
  logPerfSnapshot("ble_adv_before_start");
  if (adv) {
    adv->start();
    g_bleAdvStarted = true;
    // Print final name for debugging
    Serial.printf("[BLE] Advertising: %s\n", g_bleName.c_str());
    logPerfSnapshot("ble_adv_after_start");
  }
#endif
}

#if ENABLE_BLE
static void bleShutdown(const char* reason) {
  ScopedPerfLog perfScope("ble_shutdown");
  if (!g_bleCoreInitDone && esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_IDLE) {
    return;
  }
  Serial.printf("[BLE] shutdown (%s)\n", reason ? reason : "unknown");
  logPerfSnapshot("ble_shutdown_start");
  if (g_bleServer && g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
    g_bleServer->disconnect(g_bleConnHandle);
  }
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  if (adv) {
    adv->stop();
  }
  logPerfSnapshot("ble_shutdown_after_stop");
  g_bleAdvStarted = false;
  g_bleConnHandle = BLE_HS_CONN_HANDLE_NONE;
  g_bleAuthed = false;
  g_bleAuthDeadlineMs = 0;
  // Keep BLE stack initialized; only stop advertising to avoid reinit crashes.
}

static inline bool bleShouldBeOn(uint32_t nowMs) {
  if (!g_ownerExists) return pairingWindowActive(nowMs);
  if (pairingWindowActive(nowMs)) return true;
  if (ownerRotateWindowActive(nowMs)) return true;
  if (g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) return true;
  if (!WiFi.isConnected()) return true;
  if (!g_mqtt.connected()) return true;
  if (!bleCloudHandoffReady(nowMs, true)) return true;
  return false;
}

static void manageBleByConnectivity(uint32_t nowMs) {
#if WIFI_FORCE_NO_SLEEP
  static bool s_blePolicyOff = false;
  const bool wifiConnected = (WiFi.status() == WL_CONNECTED);
  const bool hasStaIp = (wifiConnected && (WiFi.localIP() != IPAddress(0, 0, 0, 0)));
  const bool mdnsReady = g_mdnsStarted;
  const bool bleInUse = (g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE);
  const bool holdBleForSession =
      bleInUse || (g_blePolicyHoldUntilMs != 0 && (int32_t)(g_blePolicyHoldUntilMs - nowMs) > 0);
  // Major-vendor style handoff: keep BLE alive until cloud is not only connected
  // but has remained stable for a grace period, and never cut BLE during an
  // active BLE session/command flow.
  const bool cloudHandoffReady = bleCloudHandoffReady(nowMs, hasStaIp || mdnsReady);
  const bool localHandoffReady = g_localControlReady && hasStaIp;
  // Do not count "just has STA IP" as handoff-ready. Otherwise BLE can be
  // turned off before cloud is stable or before local control is actually proven.
  const bool transportAvailable = g_mqtt.connected() || localHandoffReady;
  const bool recoveryAllowed = recoveryTransportsAllowed(nowMs);
  const bool forceOffNow =
      (cloudHandoffReady || localHandoffReady) && !holdBleForSession;
  // Hybrid: BLE açık kalsın (boot window), sonra kapat ve no-sleep uygula.
  if (g_bleBootWindowActive) {
    if ((int32_t)(nowMs - g_bleBootUntilMs) >= 0) {
      g_bleBootWindowActive = false;
      // Keep BLE on while a BLE control/provision session is active.
      if (holdBleForSession) {
        s_blePolicyOff = false;
        g_bleDesiredOn = true;
        g_bleForceOff = false;
        if (!g_bleCoreInitDone) bleCoreInit();
        if (!g_bleAdvStarted) bleStartAdvertising();
      } else {
        if (!s_blePolicyOff) {
          g_bleForceOff = true;
          g_bleDesiredOn = false;
          if (g_bleAdvStarted || g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
            bleShutdown("policy");
          }
          Serial.println("[BLE] policy -> OFF (no-sleep)");
          s_blePolicyOff = true;
        }
      }
      applyWifiPowerSave();
    } else {
      // Wi‑Fi hazırsa (IP veya mDNS) boot window'u erken kapat.
      if (forceOffNow) {
        g_bleBootWindowActive = false;
      } else {
      s_blePolicyOff = false;
      g_bleDesiredOn = true;
      if (g_bleForceOff) g_bleForceOff = false;
      if (!g_bleCoreInitDone) bleCoreInit();
      if (!g_bleAdvStarted) bleStartAdvertising();
      }
    }
  }
  // After boot window: keep BLE ON if Wi-Fi is not connected (provisioning).
  if (!g_bleBootWindowActive) {
    const bool wantBle = recoveryAllowed && !forceOffNow && (!transportAvailable || holdBleForSession);
    if (wantBle) {
      s_blePolicyOff = false;
      g_bleDesiredOn = true;
      if (g_bleForceOff) g_bleForceOff = false;
      if (!g_bleCoreInitDone) bleCoreInit();
      if (!g_bleAdvStarted) bleStartAdvertising();
    } else {
      if (!s_blePolicyOff) {
        g_bleDesiredOn = false;
        g_bleForceOff = true;
        if (g_bleAdvStarted || g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE) {
          bleShutdown("policy");
        }
        Serial.println("[BLE] policy -> OFF (no-sleep)");
        s_blePolicyOff = true;
      }
    }
    applyWifiPowerSave();
  }
  return;
#endif
  static bool lastWantBle = true;
  const bool wantBle = bleShouldBeOn(nowMs);
  g_bleDesiredOn = wantBle;
  if (wantBle && !lastWantBle) {
    g_bleForceOff = false;
    Serial.println("[BLE] policy -> ON");
    bleCoreInit();
    bleStartAdvertising();
  } else if (!wantBle && lastWantBle) {
    g_bleForceOff = true;
    bleShutdown("policy");
    Serial.println("[BLE] policy -> OFF");
  }
  if (wantBle != lastWantBle) {
    applyWifiPowerSave(); // adjust Wi-Fi sleep based on BLE policy
    lastWantBle = wantBle;
  }
}
#endif

/* =================== Wi-Fi =================== */
static wl_status_t trySTAOnceDetailed(uint32_t timeoutMs, int *outRssi) {
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - t0) < timeoutMs) delay(200);
  if (outRssi) *outRssi = (WiFi.status() == WL_CONNECTED) ? WiFi.RSSI() : 0;
  return WiFi.status();
}

static void ensureNetworkServersStarted(const char* reason) {
  if (!g_httpStarted) {
    setupHttp();
    g_http.begin();
    g_httpStarted = true;
#if HTTP_DIAG_LOG
    const String baseHost = deviceMdnsHostForId6(shortChipId());
    Serial.printf("[HTTP] server started reason=%s port=80 baseHost=%s.local staIp=%s apIp=%s\n",
                  reason ? reason : "-",
                  baseHost.c_str(),
                  WiFi.localIP().toString().c_str(),
                  WiFi.softAPIP().toString().c_str());
#endif
  }
#if ENABLE_TCP_CMD
  if (!g_tcpCmdStarted) {
    g_cmdServer.begin();
    g_tcpCmdStarted = true;
  }
#endif
}

static void logApPassIfAllowed() {
#if LOG_AP_PASS
  // Boot sırasında her zaman log'la - seri monitörde QR/AP bilgisini kaçırmamak için.
  Serial.printf("[WiFi][AP] SSID: %s\n", g_apSsid.c_str());
  Serial.printf("[WiFi][AP] Password: %s\n", g_apPass.c_str());
  Serial.printf("[WiFi][AP] SSID: %s\n", g_apSsid.c_str());
  Serial.printf("[WiFi][AP] Password: %s\n", g_apPass.c_str());
#endif
}

void startAP() {
  ScopedPerfLog perfScope("wifi_start_ap");
  // Stabil, her zaman görünebilir AP için temiz başlat
  String id6 = shortChipId();
  g_apSsid = deviceApSsidForId6(id6);
  g_apPass = deriveApPass(id6);
#if WIFI_INFO_LOG
  Serial.printf("[WiFi][AP] ssid=%s\n", g_apSsid.c_str());
#endif
#if LOG_AP_PASS
  logApPassIfAllowed(); // ✅ WiFi AP SSID ve Password burada log'lanır (2 defa)
#endif
  {
    const String host = deviceMdnsHostForId6(id6);
    WiFi.softAPsetHostname(host.c_str());
  }
  applyWifiPowerSave(); // ensure modem sleep flag is primed before mode changes

  // Ülke/kanal ve güç ayarları (TR, 1-13 kanal)
  wifi_country_t country = { .cc = "TR", .schan = 1, .nchan = 13, .max_tx_power = 78, .policy = WIFI_COUNTRY_POLICY_AUTO };

  // ---- IMPORTANT ORDER ----
  // Wi-Fi yığınını başlatmadan önce esp_wifi_* çağırmak crash sebebi olur.
  // Önce bir moda alın (AP veya AP+STA), sonra ülke/güç ayarlarını verin.
  WiFi.persistent(false);

  // Bağlı AP/STA'ları temizle
  logPerfSnapshot("wifi_start_ap_before_disconnect");
  WiFi.softAPdisconnect(true);
  WiFi.disconnect(true, true);
  delay(100);
  logPerfSnapshot("wifi_start_ap_after_disconnect");

  // Wi‑Fi'yi AP modunda başlat (WIFI_OFF yapma!) — doğrudan init et
  WiFi.mode(WIFI_AP);
  delay(100);
  applyWifiPowerSave(); // Wi-Fi stack resets PS on mode change
  logPerfSnapshot("wifi_start_ap_after_mode");

  // Ülke/güç ayarları (artık yığın init edildi) + BLE ile birlikteyken modem sleep ZORUNLU
  esp_wifi_set_country(&country);
  applyWifiPowerSave();
  WiFi.setTxPower(WIFI_POWER_15dBm);
  // Force 2.4GHz 11b/g/n with 20MHz bandwidth for widest compatibility
  esp_wifi_set_protocol(WIFI_IF_AP, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N);
  esp_wifi_set_bandwidth(WIFI_IF_AP, WIFI_BW_HT20);

  // Statik IP ver ve AP'yi başlat
  WiFi.softAPConfig(AP_IP, AP_GW, AP_MASK);
  logPerfSnapshot("wifi_start_ap_before_softap");
  bool up = WiFi.softAP(g_apSsid.c_str(), g_apPass.c_str(), 1 /*ch*/, 0 /*visible*/, 4 /*maxconn*/);
  applyWifiPowerSave(); // SoftAP call can toggle PS internally
  logPerfSnapshot("wifi_start_ap_after_softap");

#if WIFI_INFO_LOG
  Serial.printf("[WiFi] AP %s: %s  ch=%d\n", up ? "UP" : "FAIL", WiFi.softAPIP().toString().c_str(), 1);
#endif
  if (up) {
    ensureNetworkServersStarted("ap_up");
  }
}

void trySTA() {
  ScopedPerfLog perfScope("wifi_try_sta");
  if (!g_haveCreds) return;
#if WIFI_INFO_LOG
  Serial.println("[WiFi] trySTA triggered (haveCreds=true)");
#endif
  applyWifiPowerSave();
  logPerfSnapshot("wifi_try_sta_before_mode");
  WiFi.mode(WIFI_AP_STA);
  applyWifiPowerSave();
  logPerfSnapshot("wifi_try_sta_after_mode");
  {
    String host = deviceMdnsHostForId6(shortChipId());
    WiFi.setHostname(host.c_str());
  }
  logPerfSnapshot("wifi_try_sta_before_begin");
  WiFi.begin(g_savedSsid.c_str(), g_savedPass.c_str());
  applyWifiPowerSave();
  logPerfSnapshot("wifi_try_sta_after_begin");
#if WIFI_INFO_LOG
  Serial.printf("[WiFi] STA trying '%s' ...\n", g_savedSsid.c_str());
#endif
  int rssi = 0; wl_status_t st = trySTAOnceDetailed(20000, &rssi);
  logPerfSnapshot("wifi_try_sta_after_wait");
#if WIFI_INFO_LOG
  Serial.printf("[WiFi] STA: %s  ip=%s  rssi=%d  status=%d\n",
                (st == WL_CONNECTED ? "CONNECTED" : "FAILED"),
                WiFi.localIP().toString().c_str(), rssi, (int)st);
#endif
  if (st == WL_CONNECTED) {
    startMdnsIfNeeded();
    // NTP sync is handled asynchronously via pollNtpSync(); do not block boot here.
    kickNtpSyncIfNeeded("trySTA", true);

    // Notify over BLE about current status (IP, host, etc.)
    if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
      bleNotifyJson(buildBleStatusJson());
    }
  }
  ensureNetworkServersStarted("sta_mode");
}

static void startMdnsIfNeeded() {
  if (g_mdnsStarted) return;
  String host = deviceMdnsHostForId6(shortChipId());
  if (MDNS.begin(host.c_str())) {
    MDNS.addService("http", "tcp", 80);
    Serial.printf("[mDNS] %s.local ready service=_http._tcp port=80 ip=%s\n",
                  host.c_str(),
                  WiFi.localIP().toString().c_str());
    g_mdnsStarted = true;
  } else {
    Serial.println("[mDNS] start failed");
  }
}

static bool g_apStoppedDueToOnline = false;
static uint32_t g_lastApToggleMs = 0;
static constexpr uint32_t AP_TOGGLE_COOLDOWN_MS = 15000;

static void ensureSoftApUp(uint32_t nowMs) {
  ScopedPerfLog perfScope("wifi_ensure_softap_up");
  if (AP_ONLY) return;
  if ((int32_t)(nowMs - g_lastApToggleMs) < (int32_t)AP_TOGGLE_COOLDOWN_MS) return;

  wifi_mode_t mode = WiFi.getMode();
  if (mode == WIFI_AP || mode == WIFI_AP_STA) return;

  String id6 = shortChipId();
  if (g_apSsid.isEmpty()) g_apSsid = deviceApSsidForId6(id6);
  if (g_apPass.isEmpty()) g_apPass = deriveApPass(id6);

  // If we have STA creds, keep STA enabled so it can reconnect while AP is up.
  const bool keepSta = g_haveCreds;

  Serial.printf("[WiFi][AP] starting SoftAP (offline) keepSta=%d\n", keepSta ? 1 : 0);
  WiFi.persistent(false);
  applyWifiPowerSave();
  logPerfSnapshot("wifi_ensure_ap_before_mode");
  WiFi.mode(keepSta ? WIFI_AP_STA : WIFI_AP);
  delay(50);
  applyWifiPowerSave();
  logPerfSnapshot("wifi_ensure_ap_after_mode");

  wifi_country_t country = { .cc = "TR", .schan = 1, .nchan = 13, .max_tx_power = 78, .policy = WIFI_COUNTRY_POLICY_AUTO };
  esp_wifi_set_country(&country);
  WiFi.setTxPower(WIFI_POWER_15dBm);
  esp_wifi_set_protocol(WIFI_IF_AP, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N);
  esp_wifi_set_bandwidth(WIFI_IF_AP, WIFI_BW_HT20);

  {
    const String host = deviceMdnsHostForId6(id6);
    WiFi.softAPsetHostname(host.c_str());
  }
  WiFi.softAPConfig(AP_IP, AP_GW, AP_MASK);
  logPerfSnapshot("wifi_ensure_ap_before_softap");
  bool up = WiFi.softAP(g_apSsid.c_str(), g_apPass.c_str(), 1 /*ch*/, 0 /*visible*/, 4 /*maxconn*/);
  applyWifiPowerSave();
  logPerfSnapshot("wifi_ensure_ap_after_softap");
  Serial.printf("[WiFi] AP %s: %s  ch=%d\n", up ? "UP" : "FAIL", WiFi.softAPIP().toString().c_str(), 1);
  g_lastApToggleMs = nowMs;
}

static void maybeManageApByConnectivity(uint32_t nowMs) {
  // Policy:
  // - Owned + STA IP available => keep SoftAP off.
  // - Owned + WiFi+MQTT stable => keep SoftAP off.
  // - Owned + local app session proven on STA LAN => keep SoftAP off.
  // - Otherwise => keep SoftAP on (recovery).
  if (!g_ownerExists) return;
  if (AP_ONLY) return;

  const bool onlineStable = isCloudStable(nowMs);
  const bool hasStaIp =
      (WiFi.status() == WL_CONNECTED) &&
      (WiFi.localIP() != IPAddress(0, 0, 0, 0));
  const bool localReady = g_localControlReady && (WiFi.status() == WL_CONNECTED);
  const bool recoveryAllowed = recoveryTransportsAllowed(nowMs);
  const bool shouldKeepApOff = hasStaIp || onlineStable || localReady;

  wifi_mode_t mode = WiFi.getMode();
  const bool apUp = (mode == WIFI_AP || mode == WIFI_AP_STA);

  if (shouldKeepApOff) {
    if (g_apGraceUntilMs != 0 &&
        (int32_t)(g_apGraceUntilMs - nowMs) > 0) {
      return; // keep SoftAP during grace window
    }
    if (g_apStopDueMs != 0 &&
        (int32_t)(nowMs - g_apStopDueMs) < 0) {
      return; // defer SoftAP stop until grace delay elapses
    }
    if (!g_apStoppedDueToOnline && apUp) {
      if ((int32_t)(nowMs - g_lastApToggleMs) < (int32_t)AP_TOGGLE_COOLDOWN_MS) return;
      Serial.println("[WiFi][AP] stopping SoftAP (sta online)");
      logPerfSnapshot("wifi_ap_before_stop");
      WiFi.softAPdisconnect(true);
      delay(50);
      logPerfSnapshot("wifi_ap_after_stop");
      // Avoid switching Wi‑Fi mode here: changing WIFI_AP_STA -> WIFI_STA can
      // momentarily restart the Wi‑Fi driver and drop active TCP/TLS sockets.
      g_apStoppedDueToOnline = true;
      g_lastApToggleMs = nowMs;
      g_apStopDueMs = 0;
    }
    return;
  }

  // Not stable online: ensure SoftAP is up.
  if (!recoveryAllowed) {
    return;
  }
  if (!apUp) {
    ensureSoftApUp(nowMs);
  }
  if (g_apStoppedDueToOnline) {
    wifi_mode_t m2 = WiFi.getMode();
    if (m2 == WIFI_AP || m2 == WIFI_AP_STA) {
      g_apStoppedDueToOnline = false;
    }
  }
}

#if ENABLE_TCP_CMD
/* =================== TCP JSON command (optional) =================== */
void handleTcpServer() {
  if (!g_cmdClient || !g_cmdClient.connected()) { g_cmdClient = g_cmdServer.available(); return; }
  static String line;
  while (g_cmdClient.available()) {
    char ch = (char)g_cmdClient.read();
    if (ch=='\n') {
      line.trim();
      if (line.length()) {
        JsonDocument doc;
        if (!deserializeJson(doc, line)) {
          bool modeProvided = !doc["mode"].isNull();
          int modeVal = modeProvided ? doc["mode"].as<int>() : -1;

          if (doc["masterOn"].is<bool>()) app.masterOn = doc["masterOn"].as<bool>();

          if (modeProvided) {
            const FanMode prevMode = app.mode;
            if (modeVal == (int)FAN_AUTO) {
              app.mode = FAN_AUTO;
              g_envSeverityValid = false;
              g_forceAutoStep = true;
            } else {
              app.mode = (FanMode)modeVal;
              g_lastManualModeMs = millis();
              if (doc["fanPercent"].is<int>()) setFanPercent(doc["fanPercent"].as<int>());
              else setFanPercent(modeToPercent(app.mode));
            }
            if (app.mode != prevMode) {
              startFanModeShow(app.mode, millis());
            }
          } else {
            if (doc["fanPercent"].is<int>()) { setFanPercent(doc["fanPercent"].as<int>()); g_lastManualModeMs = millis(); }
          }

          if (doc["rgb"].is<JsonObject>()) {
            auto rgb = doc["rgb"].as<JsonObject>();
            if (rgb["on"].is<bool>()) app.rgbOn = rgb["on"].as<bool>();
            if (rgb["r"].is<int>()) app.r = rgb["r"].as<int>();
            if (rgb["g"].is<int>()) app.g = rgb["g"].as<int>();
            if (rgb["b"].is<int>()) app.b = rgb["b"].as<int>();
          }

          applyRelays(); applyRgb();
          g_cmdClient.println(buildStatusJson());
        }
      }
      line = "";
    } else if (isPrintable(ch)) line += ch;
  }
}
#else
static inline void handleTcpServer() {}
#endif


/* =================== Status JSON =================== */
static constexpr size_t STATUS_JSON_DOC_CAP = 14336;
static constexpr size_t STATUS_JSON_MIN_DOC_CAP = 6144;

static void fillCapabilitiesJson(JsonObject caps) {
  caps["schemaVersion"] = "1";
  caps["deviceProduct"] = DEVICE_PRODUCT;
  caps["hwRev"] = DEVICE_HW_REV;
  caps["boardRev"] = DEVICE_BOARD_REV;
  caps["fwChannel"] = DEVICE_FW_CHANNEL;

  JsonObject switches = caps["switches"].to<JsonObject>();
  switches["masterOn"] = true;
  switches["lightOn"] = true;
  switches["cleanOn"] = true;
  switches["ionOn"] = true;
  switches["rgbOn"] = true;

  JsonObject controls = caps["controls"].to<JsonObject>();
  JsonObject mode = controls["mode"].to<JsonObject>();
  mode["supported"] = true;
  mode["type"] = "enum";
  JsonArray modeValues = mode["values"].to<JsonArray>();
  modeValues.add("AUTO");
  modeValues.add("SLEEP");
  modeValues.add("LOW");
  modeValues.add("MID");
  modeValues.add("HIGH");

  JsonObject fanPercent = controls["fanPercent"].to<JsonObject>();
  fanPercent["supported"] = true;
  fanPercent["type"] = "range";
  fanPercent["min"] = 0;
  fanPercent["max"] = 100;

  JsonObject rgb = controls["rgb"].to<JsonObject>();
  rgb["supported"] = true;
  rgb["type"] = "rgb";

  JsonObject autoHumEnabled = controls["autoHumEnabled"].to<JsonObject>();
  autoHumEnabled["supported"] = true;
  autoHumEnabled["type"] = "bool";

  JsonObject autoHumTarget = controls["autoHumTarget"].to<JsonObject>();
  autoHumTarget["supported"] = true;
  autoHumTarget["type"] = "range";
  autoHumTarget["min"] = 30;
  autoHumTarget["max"] = 70;

  JsonObject sensors = caps["sensors"].to<JsonObject>();
  sensors["tempC"] = true;
  sensors["humPct"] = true;
  sensors["pm2_5"] = true;
  sensors["vocIndex"] = true;
  sensors["noxIndex"] = true;
  sensors["rpm"] = true;
  sensors["aqi"] = true;
}

static void fillStatusJsonDoc(JsonDocument& doc) {

  // Top-level firmware version for mobile app
  doc["fwVersion"] = FW_VERSION;

  JsonObject meta = doc["meta"].to<JsonObject>();
  meta["fwVersion"]   = FW_VERSION;
  meta["schema"]      = SCHEMA_VERSION;
  meta["id6"]         = shortChipId();
  meta["deviceId"]    = canonicalDeviceId();
  meta["product"]     = DEVICE_PRODUCT;
  meta["hwRev"]       = DEVICE_HW_REV;
  meta["boardRev"]    = DEVICE_BOARD_REV;
  meta["fwChannel"]   = DEVICE_FW_CHANNEL;
  meta["ts_ms"]       = (uint64_t)millis();
  meta["tz"]          = g_tz;

  JsonObject cloud = doc["cloud"].to<JsonObject>();
  cloud["enabled"] = g_cloudUserEnabled;
  cloud["linked"] = g_cloud.linked;
  cloud["email"] = g_cloud.email;
  cloud["iotEndpoint"] = g_cloud.iotEndpoint;
  cloud["streamActive"] = g_cloud.streamActive;
  cloud["mqttConnected"] = g_cloud.mqttConnected;
  cloud["mqttPort"] = g_cloud.mqttPort;
  cloud["mqttState"] = g_cloud.mqttState;
  cloud["mqttStateCode"] = g_cloud.mqttStateCode;
  cloud["state"] = cloudStateToString(g_cloudState);
  cloud["stateCode"] = static_cast<int>(g_cloudState);
  cloud["stateReason"] = g_cloud.stateReason;
  cloud["stateSinceMs"] = g_cloud.stateSinceMs;
  JsonObject ota = cloud["ota"].to<JsonObject>();
  ota["currentVersion"] = FW_VERSION;
  ota["pending"] = hasPendingOtaJob();
  if (hasPendingOtaJob()) {
    ota["jobId"] = g_pendingOtaJob.jobId;
    ota["version"] = g_pendingOtaJob.targetVersion;
    ota["requiresUserApproval"] = true;
  }
  appendLastOtaStatus(ota);
  if (g_lastDesiredDebugPingMs > 0 || g_lastDesiredDebugClientTsMs > 0) {
    JsonObject dbg = cloud["debug"].to<JsonObject>();
    if (g_lastDesiredDebugPingMs > 0) {
      dbg["lastDesiredPingMs"] = g_lastDesiredDebugPingMs;
    }
    if (g_lastDesiredDebugClientTsMs > 0) {
      dbg["lastDesiredClientTsMs"] = g_lastDesiredDebugClientTsMs;
    }
  }

  JsonObject caps = doc["capabilities"].to<JsonObject>();
  fillCapabilitiesJson(caps);
  // Owner / invite security meta (kimlik verisi sızdırmadan durum raporu)
  JsonObject owner = doc["owner"].to<JsonObject>();
  owner["setupDone"] = g_setupDone;
  // Secure-owner model: owner exists iff we've stored a valid owner pubkey (or flag)
  owner["hasOwner"]  = (g_ownerExists || g_ownerPubKeyB64.length() > 0);
  // BLE pairing penceresi (yalnızca durum bilgisi)
  uint32_t nowMsOwner = millis();
  owner["pairingWindowActive"] = pairingWindowActive(nowMsOwner);
  const uint32_t softRecoveryRemainMsOwner = softRecoveryRemainingMs(nowMsOwner);
  owner["softRecoveryActive"] = (softRecoveryRemainMsOwner > 0);
  owner["softRecoveryRemainingSec"] = (softRecoveryRemainMsOwner + 999UL) / 1000UL;

  // Cloud claim-proof bootstrap helper:
  // Expose only SHA-256(pairToken), never the plaintext token.
  JsonObject claim = doc["claim"].to<JsonObject>();
  const bool hasOwner = (g_ownerExists || g_ownerPubKeyB64.length() > 0);
  claim["claimed"] = hasOwner;
  if (g_pairToken.length() > 0) {
    claim["claimSecretHash"] = sha256HexOfString(g_pairToken);
  }

  // Auth/session info (role + context)
  BleRole httpRole = effectiveRole(g_httpRole);
  BleRole bleRole = effectiveRole(g_bleRole);
  BleRole effRole = (httpRole != BleRole::NONE) ? httpRole : bleRole;
  JsonObject auth = doc["auth"].to<JsonObject>();
  auth["role"] = roleToStr(effRole);
  auth["httpRole"] = roleToStr(httpRole);
  auth["bleRole"] = roleToStr(bleRole);
  if (g_httpUserIdHash.length()) auth["httpUserIdHash"] = g_httpUserIdHash;
  if (g_bleUserIdHash.length()) auth["bleUserIdHash"] = g_bleUserIdHash;
  if (effRole == BleRole::OWNER && g_usersJson.length()) {
    JsonArray usersOut = doc["users"].to<JsonArray>();
    const size_t usersCap = g_usersJson.length() + 256;
    JsonDocument usersDoc;
    JsonArray usersArr;
    loadUsersArray(usersDoc, usersArr);
    for (JsonVariant v : usersArr) {
      JsonObject src = v.as<JsonObject>();
      const char* id = src["id"] | src["userIdHash"] | "";
      const char* role = src["role"] | "USER";
      if (!id[0]) continue;
      JsonObject o = usersOut.add<JsonObject>();
      o["id"] = id;
      o["role"] = role;
      if (!src["pubkey"].isNull()) {
        o["pubkey"] = src["pubkey"];
      }
    }
  }

  JsonObject status = doc["status"].to<JsonObject>();
  status["masterOn"]   = app.masterOn;
  status["lightOn"]    = app.lightOn;
  status["cleanOn"]    = app.cleanOn;
  status["ionOn"]      = app.ionOn;
  status["mode"]       = (int)app.mode;
  status["modeLabel"]  = fanModeToStr(app.mode);
  status["fanPercent"] = app.fanPercent;

  // Environmental metrics from SEN55 (and derived severity)
  JsonObject env = doc["env"].to<JsonObject>();
  env["seq"]      = (uint32_t)(++g_envSeq);
  env["sampleCount"] = (uint32_t)g_envSeq;
  env["pm_v"]     = app.pm_v;   // 0..1 severity used for auto mode
  env["health_v"] = g_healthSeverity;
  env["odorBoost_v"] = g_odorBoostSeverity;
  env["odorBoostActive"] = (g_odorBoostSeverity >= 0.72f);
  env["tempC"]    = app.tempC;  // °C
  env["humPct"]   = app.humPct; // 0..100
  env["hum"]      = app.humPct; // alias for Flutter parser
  env["dhtTempC"] = app.dhtTempC;
  env["dhtHumPct"]= app.dhtHumPct;
  env["vocIndex"] = app.vocIndex;
  env["noxIndex"] = app.noxIndex;
  env["pm1_0"]    = app.pm1_0;
  env["pm2_5"]    = app.pm2_5;
  env["pm4_0"]    = app.pm4_0;
  env["pm10_0"]   = app.pm10_0;
  // BME688 classic channels (AI pipeline inputs) – prefixed with "ai" for UI ayrımı
  env["aiTempC"]      = app.aiTempC;
  env["aiHumPct"]     = app.aiHumPct;
  env["aiPressure"]   = app.aiPressure;
  env["aiGasKOhm"]    = app.aiGasKOhm;
  env["aiIaq"]        = app.aiIaq;
  env["aiIaqAcc"]     = g_bsecIaqAccuracy;
  env["aiCo2Eq"]      = app.aiCo2Eq;
  env["aiBVocEq"]     = app.aiBVocEq;
  env["autoHumEnabled"] = app.autoHumEnabled;
  env["autoHumTarget"]  = app.autoHumTarget;
  env["waterAutoEnabled"] = g_waterAutoEnabled;
  env["waterDurationMin"] = (int)g_waterDurationMin;
  env["waterIntervalMin"] = (int)g_waterIntervalMin;
  env["waterManual"] = g_waterManualOn;
  env["waterHumAutoEnabled"] = g_doaHumAutoEnabled;

  // Şehir (WAQI) snapshot'ı – sadece okuma için, dış ortam kıyası
  JsonObject city = doc["city"].to<JsonObject>();
#if ENABLE_WAQI
  if (g_city.hasData) {
    if (g_city.name.length())        city["name"]   = g_city.name;
    if (g_city.description.length()) city["desc"]   = g_city.description;
    if (!isnan(g_city.tempC))        city["tempC"]  = g_city.tempC;
    if (!isnan(g_city.humPct))       city["humPct"] = g_city.humPct;
    if (!isnan(g_city.windKph))      city["windKph"] = g_city.windKph;
    if (!isnan(g_city.aqiScore))     city["aqi"]    = g_city.aqiScore;
    if (!isnan(g_city.pm2_5))        city["pm2_5"]  = g_city.pm2_5;
  }
#endif

  // High-level air quality score (0..100) and text bucket for UI
  JsonObject aq = doc["airQuality"].to<JsonObject>();
  const int score = indoorHealthScoreFromSeverity(g_healthSeverity);
  aq["score"]  = score;
  aq["level"]  = airQualityLevelFromScore(score);
  aq["model"]  = "who_health";
  aq["healthSeverity"] = g_healthSeverity;

  JsonObject fan = doc["fan"].to<JsonObject>();
  fan["rpm"]        = (uint32_t)g_lastRPM;
  fan["targetPct"]  = app.fanPercent;
  fan["autoActive"] = (app.mode == FAN_AUTO);
  fan["reason"]     = (app.mode == FAN_AUTO) ? fanAutoReasonToStr(g_fanAutoReason) : "manual";
  fan["odorBoostActive"] = (app.mode == FAN_AUTO) && (g_fanAutoReason == FanAutoReason::ODOR_CLEANUP);

  JsonObject filter = doc["filter"].to<JsonObject>();
  filter["alert"] = app.filterAlert;

  JsonObject ui = doc["ui"].to<JsonObject>();
  ui["rgbOn"]         = app.rgbOn;
  ui["rgbR"]          = app.r;
  ui["rgbG"]          = app.g;
  ui["rgbB"]          = app.b;
  ui["rgbBrightness"] = app.rgbBrightness;

  JsonObject net = doc["network"].to<JsonObject>();
  net["apSsid"]    = g_apSsid;
  // Do not expose AP password over status channels (BLE/HTTP).
  net["apOnly"]    = AP_ONLY;
  net["haveCreds"] = g_haveCreds;
  if (g_savedSsid.length() > 0) {
    net["wifiSsid"] = g_savedSsid;
  } else {
    net["wifiSsid"].set(nullptr);
  }
  net["staStatus"] = (int)WiFi.status();
  net["staIp"]     = WiFi.localIP().toString();
  net["mdnsHost"]  = deviceMdnsFqdnForId6(shortChipId());

  // Aktif davet/join penceresini expose et (sadece durum bilgisi, payload yok)
  JsonObject join = doc["join"].to<JsonObject>();
  uint32_t nowMs = millis();
  bool joinActive = (g_joinUntilMs != 0) &&
                    ((int32_t)(g_joinUntilMs - nowMs) > 0);
  join["active"]   = joinActive;
  if (joinActive) {
    join["inviteId"] = g_joinInviteId;
    join["role"]     = g_joinRole;
    join["untilMs"]  = g_joinUntilMs;
  }
  bool apSessActive = (g_apSessionUntilMs != 0) &&
                      ((int32_t)(g_apSessionUntilMs - nowMs) > 0);
  join["apSessionActive"] = apSessActive;
  const uint32_t softRecoveryRemainMs = softRecoveryRemainingMs(nowMs);
  join["softRecoveryActive"] = (softRecoveryRemainMs > 0);
  join["softRecoveryRemainingSec"] = (softRecoveryRemainMs + 999UL) / 1000UL;

  // Davetli kullanıcılar (owner görünümü)
  const bool isOwnerRole =
      (httpRole == BleRole::OWNER) || (bleRole == BleRole::OWNER);
  if (isOwnerRole) {
    JsonArray usersOut = doc["users"].to<JsonArray>();
    if (g_usersJson.length()) {
      const size_t usersCap = g_usersJson.length() + 256;
      JsonDocument usersDoc;
      JsonArray usersArr;
      loadUsersArray(usersDoc, usersArr);
      for (JsonVariant v : usersArr) {
        JsonObject src = v.as<JsonObject>();
        const char* id = src["id"] | src["userIdHash"] | "";
        const char* role = src["role"] | "USER";
        if (!id[0]) continue;
        JsonObject o = usersOut.add<JsonObject>();
        o["id"] = id;
        o["role"] = role;
        if (!src["pubkey"].isNull()) {
          o["pubkey"] = src["pubkey"];
        }
      }
    }
  }

  // Son üretilen davet (GET_INVITE) varsa expose et
  if (g_lastInviteJson.length()) {
    const size_t invCap = g_lastInviteJson.length() + 256;
    JsonDocument invDoc;
    if (!deserializeJson(invDoc, g_lastInviteJson)) {
      JsonObject invObj = invDoc.as<JsonObject>();
      doc["lastInvite"] = invObj;
      const char* invId = invObj["inviteId"] | "";
      Serial.printf("[STATE] lastInvite attached inviteId=%s\n", invId);
    }
  }

  JsonArray alerts = doc["alerts"].to<JsonArray>();
  if (app.filterAlert) {
    JsonObject a = alerts.add<JsonObject>();
    a["type"]     = "filter";
    a["severity"] = "warning";
    a["msg"]      = "Filter replacement recommended";
  }

  if (g_planCount > 0) {
    JsonArray plans = doc["plans"].to<JsonArray>();
    for (uint8_t i = 0; i < g_planCount; ++i) {
      JsonObject o = plans.add<JsonObject>();
      o["enabled"]    = g_plans[i].enabled;
      // New keys preferred by mobile app
      o["startMin"]   = g_plans[i].startMin;
      o["endMin"]     = g_plans[i].endMin;
      // Legacy keys kept for backward compatibility
      o["start"]      = g_plans[i].startMin;
      o["end"]        = g_plans[i].endMin;
      o["mode"]       = g_plans[i].mode;
      o["fanPercent"] = g_plans[i].fanPercent;
      o["lightOn"]    = g_plans[i].lightOn;
      o["ionOn"]      = g_plans[i].ionOn;
      o["rgbOn"]      = g_plans[i].rgbOn;
    }
  }

}

String buildStatusJson() {
  JsonDocument doc;
  fillStatusJsonDoc(doc);
  String out;
  serializeJson(doc, out);
  return out;
}

static void fillStatusJsonMinDoc(JsonDocument& doc) {
  doc["fwVersion"] = FW_VERSION;
  JsonObject meta = doc["meta"].to<JsonObject>();
  meta["schema"]   = SCHEMA_VERSION;
  meta["id6"]      = shortChipId();
  meta["deviceId"] = canonicalDeviceId();
  meta["product"]  = DEVICE_PRODUCT;
  meta["hwRev"]    = DEVICE_HW_REV;
  meta["boardRev"] = DEVICE_BOARD_REV;
  meta["fwChannel"] = DEVICE_FW_CHANNEL;
  meta["ts_ms"]    = (uint64_t)millis();
  JsonObject cloud = doc["cloud"].to<JsonObject>();
  cloud["enabled"] = g_cloudUserEnabled;
  cloud["mqttConnected"] = g_cloud.mqttConnected;
  cloud["state"] = cloudStateToString(g_cloudState);
  cloud["stateCode"] = static_cast<int>(g_cloudState);
  JsonObject ota = cloud["ota"].to<JsonObject>();
  ota["currentVersion"] = FW_VERSION;
  ota["pending"] = hasPendingOtaJob();
  if (hasPendingOtaJob()) {
    ota["jobId"] = g_pendingOtaJob.jobId;
    ota["version"] = g_pendingOtaJob.targetVersion;
    ota["requiresUserApproval"] = true;
  }
  appendLastOtaStatus(ota);
  if (g_lastDesiredDebugPingMs > 0 || g_lastDesiredDebugClientTsMs > 0) {
    JsonObject dbg = cloud["debug"].to<JsonObject>();
    if (g_lastDesiredDebugPingMs > 0) {
      dbg["lastDesiredPingMs"] = g_lastDesiredDebugPingMs;
    }
    if (g_lastDesiredDebugClientTsMs > 0) {
      dbg["lastDesiredClientTsMs"] = g_lastDesiredDebugClientTsMs;
    }
  }
  JsonObject caps = doc["capabilities"].to<JsonObject>();
  fillCapabilitiesJson(caps);
  JsonObject env = doc["env"].to<JsonObject>();
  env["seq"] = (uint32_t)(++g_envSeq);
  env["sampleCount"] = (uint32_t)g_envSeq;
  env["tempC"] = app.tempC;
  env["humPct"] = app.humPct;
  env["pm2_5"] = app.pm2_5;
  env["vocIndex"] = app.vocIndex;
  env["noxIndex"] = app.noxIndex;
  // BME688 / BSEC outputs
  env["aiTempC"]    = app.aiTempC;
  env["aiHumPct"]   = app.aiHumPct;
  env["aiPressure"] = app.aiPressure;
  env["aiGasKOhm"]  = app.aiGasKOhm;
  env["aiIaq"]      = app.aiIaq;
  env["aiIaqAcc"]   = g_bsecIaqAccuracy;
  env["aiCo2Eq"]    = app.aiCo2Eq;
  env["aiBVocEq"]   = app.aiBVocEq;
  env["autoHumEnabled"] = app.autoHumEnabled;
  env["autoHumTarget"]  = app.autoHumTarget;
  env["waterAutoEnabled"] = g_waterAutoEnabled;
  env["waterDurationMin"] = (int)g_waterDurationMin;
  env["waterIntervalMin"] = (int)g_waterIntervalMin;
  env["waterManual"] = g_waterManualOn;
  env["waterHumAutoEnabled"] = g_doaHumAutoEnabled;
  JsonObject status = doc["status"].to<JsonObject>();
  status["masterOn"]   = app.masterOn;
  status["lightOn"]    = app.lightOn;
  status["cleanOn"]    = app.cleanOn;
  status["ionOn"]      = app.ionOn;
  status["mode"]       = (int)app.mode;
  status["fanPercent"] = app.fanPercent;
  // Fan RPM (tach)
  JsonObject fan = doc["fan"].to<JsonObject>();
  fan["rpm"]        = (uint32_t)g_lastRPM;
  fan["targetPct"]  = app.fanPercent;
  fan["autoActive"] = (app.mode == FAN_AUTO);

  JsonObject owner = doc["owner"].to<JsonObject>();
  owner["setupDone"] = g_setupDone;
  owner["hasOwner"]  = (g_ownerExists || g_ownerPubKeyB64.length() > 0);
  uint32_t nowMsOwner = millis();
  owner["pairingWindowActive"] = pairingWindowActive(nowMsOwner);
  const uint32_t softRecoveryRemainMsOwner = softRecoveryRemainingMs(nowMsOwner);
  owner["softRecoveryActive"] = (softRecoveryRemainMsOwner > 0);
  owner["softRecoveryRemainingSec"] = (softRecoveryRemainMsOwner + 999UL) / 1000UL;

  JsonObject claim = doc["claim"].to<JsonObject>();
  const bool hasOwner = (g_ownerExists || g_ownerPubKeyB64.length() > 0);
  claim["claimed"] = hasOwner;
  if (g_pairToken.length() > 0) {
    claim["claimSecretHash"] = sha256HexOfString(g_pairToken);
  }

  // WAQI / external air quality snapshot
  if (g_city.hasData) {
    JsonObject city = doc["city"].to<JsonObject>();
    if (g_city.name.length())        city["name"]   = g_city.name;
    if (g_city.description.length()) city["desc"]   = g_city.description;
    if (!isnan(g_city.tempC))        city["tempC"]  = g_city.tempC;
    if (!isnan(g_city.humPct))       city["humPct"] = g_city.humPct;
    if (!isnan(g_city.windKph))      city["windKph"] = g_city.windKph;
    if (!isnan(g_city.aqiScore))     city["aqi"]    = g_city.aqiScore;
    if (!isnan(g_city.pm2_5))        city["pm2_5"]  = g_city.pm2_5;
  }

  // Davetli kullanıcılar listesi (cloud/mqtt durumundan erişilebilsin)
  if (g_usersJson.length()) {
    JsonArray usersOut = doc["users"].to<JsonArray>();
    const size_t usersCap = g_usersJson.length() + 256;
    JsonDocument usersDoc;
    JsonArray usersArr;
    loadUsersArray(usersDoc, usersArr);
    for (JsonVariant v : usersArr) {
      JsonObject src = v.as<JsonObject>();
      const char* id = src["id"] | src["userIdHash"] | "";
      const char* role = src["role"] | "USER";
      if (!id[0]) continue;
      JsonObject o = usersOut.add<JsonObject>();
      o["id"] = id;
      o["role"] = role;
      if (!src["pubkey"].isNull()) {
        o["pubkey"] = src["pubkey"];
      }
    }
  }
}

static String buildStatusJsonMin() {
  JsonDocument doc;
  fillStatusJsonMinDoc(doc);
  String out;
  serializeJson(doc, out);
  return out;
}


// Daha küçük bir BLE status JSON'u (yalnızca UI için temel alanlar)
// Büyük buildStatusJson() çıktısı BLE MTU sınırına yaklaşabildiği için,
// BLE üzerinden istenen status taleplerinde bu kompakt sürümü kullanıyoruz.
static String buildBleStatusJson() {
  // BLE should use a compact schema to avoid MTU/chunking issues on iOS.
  // Keep keys compatible with `buildStatusJson()` where the mobile app expects them.
  JsonDocument doc;
  doc["fwVersion"] = FW_VERSION;

  JsonObject meta = doc["meta"].to<JsonObject>();
  meta["fwVersion"]   = FW_VERSION;
  meta["schema"]      = SCHEMA_VERSION;
  meta["id6"]         = shortChipId();
  meta["deviceId"]    = canonicalDeviceId();
  meta["product"]     = DEVICE_PRODUCT;
  meta["hwRev"]       = DEVICE_HW_REV;
  meta["boardRev"]    = DEVICE_BOARD_REV;
  meta["fwChannel"]   = DEVICE_FW_CHANNEL;
  meta["ts_ms"]       = (uint64_t)millis();
  meta["tz"]          = g_tz;

  JsonObject owner = doc["owner"].to<JsonObject>();
  owner["setupDone"] = g_setupDone;
  owner["hasOwner"]  = (g_ownerExists || g_ownerPubKeyB64.length() > 0);
  uint32_t nowMsOwner = millis();
  owner["pairingWindowActive"] = pairingWindowActive(nowMsOwner);
  const uint32_t softRecoveryRemainMsOwner = softRecoveryRemainingMs(nowMsOwner);
  owner["softRecoveryActive"] = (softRecoveryRemainMsOwner > 0);
  owner["softRecoveryRemainingSec"] = (softRecoveryRemainMsOwner + 999UL) / 1000UL;

  // Auth/session info (compact)
  BleRole httpRole = effectiveRole(g_httpRole);
  BleRole bleRole = effectiveRole(g_bleRole);
  BleRole effRole = (httpRole != BleRole::NONE) ? httpRole : bleRole;
  JsonObject auth = doc["auth"].to<JsonObject>();
  auth["role"] = roleToStr(effRole);
  auth["httpRole"] = roleToStr(httpRole);
  auth["bleRole"] = roleToStr(bleRole);
  if (g_httpUserIdHash.length()) auth["httpUserIdHash"] = g_httpUserIdHash;
  if (g_bleUserIdHash.length()) auth["bleUserIdHash"] = g_bleUserIdHash;

  JsonObject status = doc["status"].to<JsonObject>();
  status["masterOn"]   = app.masterOn;
  status["lightOn"]    = app.lightOn;
  status["cleanOn"]    = app.cleanOn;
  status["ionOn"]      = app.ionOn;
  status["mode"]       = (int)app.mode;
  status["modeLabel"]  = fanModeToStr(app.mode);
  status["fanPercent"] = app.fanPercent;

  JsonObject env = doc["env"].to<JsonObject>();
  env["pm_v"]     = app.pm_v;
  env["health_v"] = g_healthSeverity;
  env["odorBoost_v"] = g_odorBoostSeverity;
  env["odorBoostActive"] = (g_odorBoostSeverity >= 0.72f);
  env["tempC"]    = app.tempC;
  env["humPct"]   = app.humPct;
  env["hum"]      = app.humPct;
  env["dhtTempC"] = app.dhtTempC;
  env["dhtHumPct"]= app.dhtHumPct;
  env["vocIndex"] = app.vocIndex;
  env["noxIndex"] = app.noxIndex;
  env["pm1_0"]    = app.pm1_0;
  env["pm2_5"]    = app.pm2_5;
  env["pm4_0"]    = app.pm4_0;
  env["pm10_0"]   = app.pm10_0;
  env["aiTempC"]      = app.aiTempC;
  env["aiHumPct"]     = app.aiHumPct;
  env["aiPressure"]   = app.aiPressure;
  env["aiGasKOhm"]    = app.aiGasKOhm;
  env["aiIaq"]        = app.aiIaq;
  env["aiIaqAcc"]     = g_bsecIaqAccuracy;
  env["aiCo2Eq"]      = app.aiCo2Eq;
  env["aiBVocEq"]     = app.aiBVocEq;
  env["autoHumEnabled"] = app.autoHumEnabled;
  env["autoHumTarget"]  = app.autoHumTarget;
  env["waterAutoEnabled"] = g_waterAutoEnabled;
  env["waterDurationMin"] = (int)g_waterDurationMin;
  env["waterIntervalMin"] = (int)g_waterIntervalMin;
  env["waterManual"] = g_waterManualOn;
  env["waterHumAutoEnabled"] = g_doaHumAutoEnabled;

  JsonObject aq = doc["airQuality"].to<JsonObject>();
  const int score = indoorHealthScoreFromSeverity(g_healthSeverity);
  aq["score"]  = score;
  aq["level"]  = airQualityLevelFromScore(score);
  aq["model"]  = "who_health";
  aq["healthSeverity"] = g_healthSeverity;

  JsonObject fan = doc["fan"].to<JsonObject>();
  fan["rpm"]        = (uint32_t)g_lastRPM;
  fan["targetPct"]  = app.fanPercent;
  fan["autoActive"] = (app.mode == FAN_AUTO);
  fan["reason"]     = (app.mode == FAN_AUTO) ? fanAutoReasonToStr(g_fanAutoReason) : "manual";
  fan["odorBoostActive"] = (app.mode == FAN_AUTO) && (g_fanAutoReason == FanAutoReason::ODOR_CLEANUP);

  JsonObject filter = doc["filter"].to<JsonObject>();
  filter["alert"] = app.filterAlert;

  JsonObject ui = doc["ui"].to<JsonObject>();
  ui["rgbOn"]         = app.rgbOn;
  ui["rgbR"]          = app.r;
  ui["rgbG"]          = app.g;
  ui["rgbB"]          = app.b;
  ui["rgbBrightness"] = app.rgbBrightness;

  JsonObject net = doc["network"].to<JsonObject>();
  net["apSsid"]    = g_apSsid;
  net["apOnly"]    = AP_ONLY;
  net["haveCreds"] = g_haveCreds;
  if (g_savedSsid.length() > 0) net["wifiSsid"] = g_savedSsid;
  else net["wifiSsid"].set(nullptr);
  net["staStatus"] = (int)WiFi.status();
  net["staIp"]     = WiFi.localIP().toString();
  net["mdnsHost"]  = deviceMdnsFqdnForId6(shortChipId());

  JsonObject cloud = doc["cloud"].to<JsonObject>();
  cloud["enabled"] = g_cloudUserEnabled;
  cloud["mqttConnected"] = g_cloud.mqttConnected;
  cloud["state"] = cloudStateToString(g_cloudState);
  JsonObject ota = cloud["ota"].to<JsonObject>();
  ota["currentVersion"] = FW_VERSION;
  ota["pending"] = hasPendingOtaJob();
  if (hasPendingOtaJob()) {
    ota["jobId"] = g_pendingOtaJob.jobId;
    ota["version"] = g_pendingOtaJob.targetVersion;
    ota["requiresUserApproval"] = true;
  }
  appendLastOtaStatus(ota);

  JsonObject join = doc["join"].to<JsonObject>();
  uint32_t nowMs = millis();
  bool joinActive = (g_joinUntilMs != 0) && ((int32_t)(g_joinUntilMs - nowMs) > 0);
  join["active"] = joinActive;
  bool apSessActive = (g_apSessionUntilMs != 0) && ((int32_t)(g_apSessionUntilMs - nowMs) > 0);
  join["apSessionActive"] = apSessActive;
  const uint32_t softRecoveryRemainMs = softRecoveryRemainingMs(nowMs);
  join["softRecoveryActive"] = (softRecoveryRemainMs > 0);
  join["softRecoveryRemainingSec"] = (softRecoveryRemainMs + 999UL) / 1000UL;

  JsonArray alerts = doc["alerts"].to<JsonArray>();
  if (app.filterAlert) {
    JsonObject a = alerts.add<JsonObject>();
    a["type"]     = "filter";
    a["severity"] = "warning";
    a["msg"]      = "Filter replacement recommended";
  }

  String out;
  serializeJson(doc, out);
  return out;
}

static bool applyControlDocument(const JsonDocument& doc) {
  bool changed = false;
  bool relaysNeedApply = false;
  bool rgbNeedApply = false;
  bool fanNeedApply = false;

  // ---- Cloud Shadow ACL sync ----
  // Cloud writes desired.acl to IoT Shadow; device receives it on /shadow/update/delta
  // as `state.acl`. Keep a local id/role mirror for MQTT role resolution:
  // - revoked/deleted users are removed
  // - active/pending/accepted users are upserted (id + role only)
  {
    JsonObjectConst acl = doc["acl"].as<JsonObjectConst>();
    if (!acl.isNull()) {
      const uint8_t schemaV = (uint8_t)(acl["v"] | 1);
      const uint32_t ver = (uint32_t)(acl["version"] | acl["ver"] | 0);
      if (schemaV == 1 && ver > 0 && ver > g_shadowAclVersion) {
        bool modified = false;
        bool ownerHashChanged = false;
        bool ownerStateChanged = false;
        bool ownerSeenInAcl = false;
        String ownerHashFromAcl;

        JsonDocument usersDoc;
        JsonArray arr;
        loadUsersArray(usersDoc, arr);

        auto findUserIndexById = [&](const String& targetId) -> int {
          for (size_t i = 0; i < arr.size(); ++i) {
            JsonObject o = arr[i].as<JsonObject>();
            const char* existing = o["id"] | o["userIdHash"] | "";
            if (existing && targetId.equalsIgnoreCase(String(existing))) {
              return (int)i;
            }
          }
          return -1;
        };

        JsonArrayConst users = acl["users"].as<JsonArrayConst>();
        for (JsonVariantConst uv : users) {
          if (!uv.is<JsonObjectConst>()) continue;
          JsonObjectConst u = uv.as<JsonObjectConst>();
          const char* idRaw =
              u["userIdHash"] | u["user_id_hash"] | u["id"] | u["uid"] | "";
          if (!idRaw || !idRaw[0]) continue;
          String id = String(idRaw);
          id.trim();
          id.toLowerCase();
          if (!id.length()) continue;

          const char* stRaw = u["status"] | "";
          String st = String(stRaw);
          st.trim();
          st.toLowerCase();
          const bool isRevoked = (st == "revoked" || st == "deleted");

          const int idx = findUserIndexById(id);
          if (isRevoked) {
            if (idx >= 0) {
              arr.remove((size_t)idx);
              modified = true;
            }
            continue;
          }

          const char* roleRaw = u["role"] | "USER";
          BleRole role = roleFromStr(roleRaw);
          const char* roleNorm = "USER";
          if (role == BleRole::GUEST) roleNorm = "GUEST";
          else if (role == BleRole::OWNER) roleNorm = "OWNER";

          if (role == BleRole::OWNER) {
            ownerSeenInAcl = true;
            ownerHashFromAcl = id;
          }

          if (idx >= 0) {
            JsonObject o = arr[(size_t)idx].as<JsonObject>();
            const char* existingRole = o["role"] | "USER";
            if (!id.equalsIgnoreCase(String(o["id"] | ""))) {
              o["id"] = id;
              modified = true;
            }
            if (!String(existingRole).equalsIgnoreCase(String(roleNorm))) {
              o["role"] = roleNorm;
              modified = true;
            }
          } else {
            JsonObject o = arr.add<JsonObject>();
            o["id"] = id;
            o["role"] = roleNorm;
            modified = true;
          }
        }

        if (ownerSeenInAcl &&
            (!g_ownerHash.length() || !g_ownerHash.equalsIgnoreCase(ownerHashFromAcl))) {
          g_ownerHash = ownerHashFromAcl;
          ownerHashChanged = true;
        }
        if (ownerSeenInAcl && ownerHashFromAcl.length() && !isOwned()) {
          setOwned(true, "shadow_acl_owner");
          ownerStateChanged = true;
        }

        if (modified) {
          String out;
          serializeJson(arr, out);
          g_usersJson = out;
        }

        g_shadowAclVersion = ver;
        // Persist version always (prevents re-applying the same delta after reboot).
        // Persist users_json when changed, and owner_hash if ACL provided owner hash.
        prefs.begin("aac", false);
        prefs.putUInt("acl_v", g_shadowAclVersion);
        if (modified) {
          prefs.putString("users_json", g_usersJson);
        }
        if (ownerHashChanged) {
          prefs.putString("owner_hash", g_ownerHash);
        }
        if (ownerStateChanged) {
          prefs.putBool("owner_exists", g_ownerExists);
        }
        prefs.end();
        Serial.printf("[SHADOW][ACL] applied v=%u modified=%d ownerHashChanged=%d ownerStateChanged=%d usersJsonLen=%u\n",
                      (unsigned)g_shadowAclVersion,
                      modified ? 1 : 0,
                      ownerHashChanged ? 1 : 0,
                      ownerStateChanged ? 1 : 0,
                      (unsigned)g_usersJson.length());
        changed = changed || modified || ownerHashChanged || ownerStateChanged;
      }
    }
  }

  // Debug-only desired probe: lets app verify shadow desired path end-to-end.
  bool desiredProbeTouched = false;
  JsonVariantConst dbgPing = doc["appDebugPing"];
  if (!dbgPing.isNull()) {
    bool ping = false;
    if (dbgPing.is<bool>()) ping = dbgPing.as<bool>();
    else if (dbgPing.is<int>()) ping = (dbgPing.as<int>() != 0);
    else if (dbgPing.is<const char*>()) {
      String s = String(dbgPing.as<const char*>());
      s.trim();
      s.toLowerCase();
      ping = (s == "1" || s == "true" || s == "yes" || s == "on");
    }
    if (ping) {
      g_lastDesiredDebugPingMs = millis();
      desiredProbeTouched = true;
    }
  }
  JsonVariantConst dbgTs = doc["appDebugTs"];
  if (!dbgTs.isNull()) {
    uint64_t tsMs = 0;
    if (dbgTs.is<uint64_t>()) {
      tsMs = dbgTs.as<uint64_t>();
    } else if (dbgTs.is<int64_t>()) {
      const int64_t signedTs = dbgTs.as<int64_t>();
      if (signedTs > 0) tsMs = static_cast<uint64_t>(signedTs);
    } else if (dbgTs.is<const char*>()) {
      const String raw = String(dbgTs.as<const char*>());
      tsMs = static_cast<uint64_t>(strtoull(raw.c_str(), nullptr, 10));
    }
    if (tsMs > 0) {
      g_lastDesiredDebugClientTsMs = tsMs;
      desiredProbeTouched = true;
    }
  }
  if (desiredProbeTouched) {
    // Avoid flooding logs when cloud keeps re-sending the same debug probe payload.
    const uint32_t nowForLogMs = millis();
    const bool clientTsChanged =
        (g_lastDesiredDebugClientTsMs > 0) &&
        (g_lastDesiredDebugClientTsMs != g_lastDesiredDebugLogClientTsMs);
    const bool logCooldownElapsed =
        (g_lastDesiredDebugLogAtMs == 0) ||
        ((int32_t)(nowForLogMs - g_lastDesiredDebugLogAtMs) >= 15000);
    if (clientTsChanged || logCooldownElapsed) {
      Serial.printf("[SHADOW] desired debug probe received pingMs=%u clientTsMs=%llu\n",
                    (unsigned)g_lastDesiredDebugPingMs,
                    (unsigned long long)g_lastDesiredDebugClientTsMs);
      g_lastDesiredDebugLogClientTsMs = g_lastDesiredDebugClientTsMs;
      g_lastDesiredDebugLogAtMs = nowForLogMs;
    }
    changed = true;
  }

  // ---- Typed command envelope (spec-style) ----
  // Eğer "type" alanı varsa, önce onu yorumla. Bu, STREAM_*/JOIN/AP_START gibi
  // yeni nesil komutlar için kullanılır. Mevcut düz alan tabanlı protokolle
  // geriye dönük uyum korunur.
  // ArduinoJson: avoid `| nullptr` (can bind to std::nullptr_t overload and always return null)
  const char* type = doc["type"] | "";
  if (type[0]) {
    Serial.printf("[CMD] typed type=%s src=%d owner_exists=%d ble_authed=%d\n",
                  type,
                  (int)g_lastCmdSource,
                  g_ownerExists ? 1 : 0,
                  g_bleAuthed ? 1 : 0);
    uint32_t nowMs = millis();

    if (strcmp(type, "PING") == 0 ||
        strcmp(type, "STREAM_ON") == 0 ||
        strcmp(type, "STREAM_RENEW") == 0 ||
        strcmp(type, "STREAM_OFF") == 0) {
      // Cloud streaming commands are deprecated in local-only firmware.
      return true;
    } else if (strcmp(type, "OTA_APPROVE") == 0) {
      const char* reqJobId = doc["jobId"] | doc["otaJobId"] | "";
      if (!hasPendingOtaJob()) {
        Serial.println("[JOBS] OTA_APPROVE ignored (no pending OTA)");
        return true;
      }
      if (reqJobId[0] && !g_pendingOtaJob.jobId.equals(String(reqJobId))) {
        Serial.printf("[JOBS] OTA_APPROVE ignored (jobId mismatch req=%s pending=%s)\n",
                      reqJobId,
                      g_pendingOtaJob.jobId.c_str());
        return true;
      }
      g_pendingOtaRejectRequested = false;
      g_pendingOtaApproveRequested = true;
      g_cloudDirty = true;
      Serial.printf("[JOBS] OTA_APPROVE accepted jobId=%s\n", g_pendingOtaJob.jobId.c_str());
      return true;
    } else if (strcmp(type, "OTA_REJECT") == 0) {
      const char* reqJobId = doc["jobId"] | doc["otaJobId"] | "";
      if (!hasPendingOtaJob()) {
        Serial.println("[JOBS] OTA_REJECT ignored (no pending OTA)");
        return true;
      }
      if (reqJobId[0] && !g_pendingOtaJob.jobId.equals(String(reqJobId))) {
        Serial.printf("[JOBS] OTA_REJECT ignored (jobId mismatch req=%s pending=%s)\n",
                      reqJobId,
                      g_pendingOtaJob.jobId.c_str());
        return true;
      }
      g_pendingOtaApproveRequested = false;
      g_pendingOtaRejectRequested = true;
      g_cloudDirty = true;
      Serial.printf("[JOBS] OTA_REJECT accepted jobId=%s\n", g_pendingOtaJob.jobId.c_str());
      return true;
    } else if (strcmp(type, "CLAIM_OWNER") == 0) {
      // Legacy owner claim is deprecated. Owner can only be claimed via BLE + QR
      // (CLAIM_REQUEST). Keep returning "handled" so old apps don't fall through.
      Serial.println("[OWNER] CLAIM_OWNER rejected (deprecated; use CLAIM_REQUEST over BLE)");
      return true;
    } else if (strcmp(type, "CLAIM_REQUEST") == 0) {
      // BLE-only secure owner claim (factory QR):
      // { "type":"CLAIM_REQUEST","user":"factory_user","pass":"839201","owner_pubkey":"base64(65b)" }
      const bool claimViaBle = (g_lastCmdSource == CmdSource::BLE);
      const bool claimViaHttp = (g_lastCmdSource == CmdSource::HTTP);
      if (!claimViaBle && !claimViaHttp) {
        Serial.println("[OWNER] CLAIM_REQUEST rejected (source not allowed)");
        if (claimViaBle) {
          bleNotifyJson(String("{\"claim\":{\"ok\":false,\"err\":\"ble_only\"}}"));
        }
        return true;
      }
      const bool rotateWin = ownerRotateWindowActive(nowMs);
      if ((g_ownerExists || g_ownerPubKeyB64.length()) && !rotateWin) {
        Serial.println("[OWNER] CLAIM_REQUEST rejected (owner already exists)");
        if (claimViaBle) bleNotifyJson(String("{\"claim\":{\"ok\":false,\"err\":\"owner_already_exists\"}}"));
        return true;
      }
      const char* user = doc["user"] | "";
      const char* pass = doc["pass"] | "";
      const char* pub  = doc["owner_pubkey"] | doc["ownerPubKey"] | "";
      if (!user[0] || !pass[0] || !pub[0]) {
        Serial.println("[OWNER] CLAIM_REQUEST invalid payload");
        if (claimViaBle) bleNotifyJson(String("{\"claim\":{\"ok\":false,\"err\":\"invalid_payload\"}}"));
        return true;
      }
      uint32_t retryMs = 0;
      if (setupAuthLocked(nowMs, &retryMs)) {
        JsonDocument out;
        out["claim"]["ok"] = false;
        out["claim"]["err"] = "setup_locked";
        out["claim"]["retryMs"] = retryMs;
        String resp;
        serializeJson(out, resp);
        if (claimViaBle) bleNotifyJson(resp);
        return true;
      }
      // Validate base64 characters early (detect embedded NUL / whitespace / URL-safe etc.)
      {
        const size_t n = strlen(pub);
        int badAt = -1;
        int badCh = -1;
        for (size_t i = 0; i < n; ++i) {
          const unsigned char ch = (unsigned char)pub[i];
          const bool ok =
              (ch >= 'A' && ch <= 'Z') ||
              (ch >= 'a' && ch <= 'z') ||
              (ch >= '0' && ch <= '9') ||
              (ch == '+') || (ch == '/') || (ch == '=') || (ch == '-') || (ch == '_');
          if (!ok) {
            badAt = (int)i;
            badCh = (int)ch;
            break;
          }
        }
        if (badAt >= 0) {
          Serial.printf("[OWNER] CLAIM_REQUEST pubkey contains invalid char idx=%d ch=0x%02X\n", badAt, badCh);
        }
      }
      if (!verifySetupUserPass(user, pass)) {
        Serial.println("[OWNER] CLAIM_REQUEST invalid setup credentials");
        noteSetupAuthFailure(nowMs);
        if (claimViaBle) bleNotifyJson(String("{\"claim\":{\"ok\":false,\"err\":\"invalid_pass\"}}"));
        return true;
      }
      // Validate pubkey decodes to 65 bytes.
      std::vector<uint8_t> pubBytes;
      if (!base64Decode(String(pub), pubBytes) || pubBytes.size() != 65) {
        Serial.printf("[OWNER] CLAIM_REQUEST invalid pubkey (b64len=%u decoded=%u)\n",
                      (unsigned)strlen(pub),
                      (unsigned)pubBytes.size());
        if (claimViaBle) bleNotifyJson(String("{\"claim\":{\"ok\":false,\"err\":\"invalid_pubkey\"}}"));
        return true;
      }
      const bool rotatingOwner = (g_ownerExists || g_ownerPubKeyB64.length());
      if (rotatingOwner) {
        Serial.println("[OWNER] CLAIM_REQUEST rotating owner (physical presence)");
        // Clear invited users when owner rotates.
        g_usersJson.clear();
        g_ownerHash.clear(); // legacy
        g_bleUserIdHash.clear();
        // Close join window, if any.
        g_joinInviteId.clear();
        g_joinRole.clear();
        g_joinUntilMs = 0;
      }
      g_ownerPubKeyB64 = String(pub);
      g_ownerPubKeyB64.trim();
      noteSetupAuthSuccess();
      setOwned(true, "claim_request");
      // Cloud is opt-in per user. Keep it disabled on initial claim.
      g_cloudUserEnabled = false;
      g_cloudDirty = true;
      g_setupDone = true;
      markPairTokenTrusted(0);
      closeTransientOnboardingState();
      // The claimant is, by definition, the owner for this BLE session.
      // Mark session authed so control works immediately after claiming.
      g_bleAuthed = true;
      g_bleRole = BleRole::OWNER;
      g_bleAuthDeadlineMs = 0;
      g_bleOwnerAuthGraceUntilMs = millis() + BLE_OWNER_AUTH_GRACE_MS;
      g_bleNonceB64.clear();
      savePrefs();
      // Do not touch advertising state from NimBLE host callback context.
      // Main loop already maintains advertising policy safely.
      Serial.println("[OWNER] CLAIM_REQUEST accepted; device is now OWNED");
      if (claimViaBle) {
        JsonDocument out;
        out["claim"]["ok"] = true;
        out["claim"]["deviceId"] = canonicalDeviceId();
        out["claim"]["id6"] = shortChipId();
        out["claim"]["pairToken"] = g_pairToken;
        String resp;
        serializeJson(out, resp);
        bleNotifyJson(resp);
      }
      changed = true;
      return true;
    } else if (strcmp(type, "ROTATE_OWNER_KEY") == 0) {
      // Rotate owner pubkey while already authenticated as OWNER.
      // { "type":"ROTATE_OWNER_KEY","owner_pubkey":"base64(65b)" }
      if (g_lastCmdSource != CmdSource::BLE) {
        Serial.println("[OWNER] ROTATE_OWNER_KEY rejected (BLE-only)");
        bleNotifyJson(String("{\"ownerRotate\":{\"ok\":false,\"err\":\"ble_only\"}}"));
        return true;
      }
      if (!g_ownerExists || !g_bleAuthed || effectiveRole(g_bleRole) != BleRole::OWNER) {
        Serial.println("[OWNER] ROTATE_OWNER_KEY rejected (not owner)");
        bleNotifyJson(String("{\"ownerRotate\":{\"ok\":false,\"err\":\"not_owner\"}}"));
        return true;
      }
      const char* pub =
          doc["owner_pubkey"] | doc["ownerPubKey"] | doc["new_owner_pubkey"] | doc["newOwnerPubKey"] | "";
      if (!pub[0]) {
        bleNotifyJson(String("{\"ownerRotate\":{\"ok\":false,\"err\":\"missing_pubkey\"}}"));
        return true;
      }
      std::vector<uint8_t> pubBytes;
      if (!base64Decode(String(pub), pubBytes) || pubBytes.size() != 65) {
        Serial.printf("[OWNER] ROTATE_OWNER_KEY invalid pubkey (b64len=%u decoded=%u)\n",
                      (unsigned)strlen(pub),
                      (unsigned)pubBytes.size());
        bleNotifyJson(String("{\"ownerRotate\":{\"ok\":false,\"err\":\"invalid_pubkey\"}}"));
        return true;
      }
      g_ownerPubKeyB64 = String(pub);
      g_ownerPubKeyB64.trim();
      savePrefs();
      bleNotifyJson(String("{\"ownerRotate\":{\"ok\":true}}"));
      Serial.println("[OWNER] ROTATE_OWNER_KEY accepted");
      changed = true;
      return true;
    } else if (strcmp(type, "UNOWN") == 0 || strcmp(type, "CLEAR_OWNER") == 0) {
      // Remove current owner (BLE-only, requires BLE auth when owned).
      // { "type":"UNOWN" }
      if (g_lastCmdSource != CmdSource::BLE) {
        Serial.println("[OWNER] UNOWN rejected (BLE-only)");
        return true;
      }
      if (g_ownerExists && !g_bleAuthed) {
        Serial.println("[OWNER] UNOWN rejected (not authenticated)");
        bleNotifyJson(String("{\"unown\":{\"ok\":false,\"err\":\"not_authenticated\"}}"));
        return true;
      }

      Serial.println("[OWNER] UNOWN accepted; clearing owner and setup flags");
      g_ownerHash.clear(); // legacy
      setOwned(false, "unown");
      g_ownerPubKeyB64.clear();
      g_setupDone = false;
      g_bleAuthed = false;
      g_bleNonceB64.clear();
      savePrefs();
      bleNotifyJson(String("{\"unown\":{\"ok\":true}}"));
      changed = true;
      return true;
    } else if (strcmp(type, "FACTORY_RESET") == 0) {
      if (g_lastCmdSource != CmdSource::BLE) {
        Serial.println("[RESET] FACTORY_RESET rejected (BLE-only)");
        bleNotifyJson(String("{\"factoryReset\":{\"ok\":false,\"err\":\"ble_only\"}}"));
        return true;
      }
      if (g_ownerExists && (!g_bleAuthed || effectiveRole(g_bleRole) != BleRole::OWNER)) {
        Serial.println("[RESET] FACTORY_RESET rejected (owner auth required)");
        bleNotifyJson(String("{\"factoryReset\":{\"ok\":false,\"err\":\"owner_required\"}}"));
        return true;
      }
      bleNotifyJson(String("{\"factoryReset\":{\"ok\":true,\"pending\":true}}"));
      scheduleFactoryReset("ble_command", 600);
      Serial.println("[RESET] FACTORY_RESET accepted");
      return true;
    } else if (strcmp(type, "OPEN_JOIN_WINDOW") == 0) {
      // { "type":"OPEN_JOIN_WINDOW","inviteId":"...","ttl":120,"role":"USER" }
      // Owner-only: allow BLE/HTTP/MQTT if caller role resolves to OWNER.
      BleRole callerRole = BleRole::NONE;
      if (g_lastCmdSource == CmdSource::BLE) {
        callerRole = effectiveRole(g_bleRole);
      } else if (g_lastCmdSource == CmdSource::HTTP) {
        callerRole = effectiveRole(g_httpRole);
      } else if (g_lastCmdSource == CmdSource::MQTT) {
        callerRole = effectiveRole(g_mqttRole);
      }
      if (g_ownerExists && callerRole == BleRole::NONE) {
        Serial.println("[JOIN] OPEN_JOIN_WINDOW rejected (not authenticated)");
        return true;
      }
      if (g_ownerExists && callerRole != BleRole::OWNER) {
        Serial.println("[JOIN] OPEN_JOIN_WINDOW rejected (insufficient role)");
        bleNotifyJson(String("{\"join\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
        return true;
      }
      const char* inviteId = doc["inviteId"] | "";
      const char* roleRaw  = doc["role"]     | "USER";
      BleRole roleEnum = roleFromStr(roleRaw);
      const char* role = (roleEnum == BleRole::GUEST) ? "GUEST" : "USER";
      int ttlSec           = doc["ttl"]      | 180;
      if (ttlSec < 10) ttlSec = 10;
      if (ttlSec > 180) ttlSec = 180;
      g_joinInviteId = String(inviteId);
      g_joinRole     = String(role);
      g_joinUntilMs  = nowMs + (uint32_t)ttlSec * 1000UL;
      Serial.printf("[JOIN] OPEN_JOIN_WINDOW inviteId=%s role=%s ttl=%d\n",
                    g_joinInviteId.c_str(),
                    g_joinRole.c_str(),
                    ttlSec);
      changed = true;
      // Join penceresi ile birlikte BLE pairing penceresini de aç (aynı TTL).
      openPairingWindow((uint32_t)ttlSec * 1000UL);
      // İlk owner/invite akışı için setup_done'i işaretlemek ileride kullanılacak.
      if (!g_setupDone) {
        g_setupDone = true;
        savePrefs();
      }
      // Typed komutlarda aşağıdaki klasik alanları da işlemek isteyebiliriz;
      // şimdilik sadece join penceresini ele alıyoruz.
      return true;
    } else if (strcmp(type, "GET_INVITE") == 0) {
      // Owner-only: allow BLE/HTTP/MQTT if caller role resolves to OWNER.
      BleRole callerRole = BleRole::NONE;
      if (g_lastCmdSource == CmdSource::BLE) {
        callerRole = effectiveRole(g_bleRole);
      } else if (g_lastCmdSource == CmdSource::HTTP) {
        callerRole = effectiveRole(g_httpRole);
      } else if (g_lastCmdSource == CmdSource::MQTT) {
        callerRole = effectiveRole(g_mqttRole);
      }
      if (g_ownerExists && callerRole == BleRole::NONE) {
        Serial.println("[INVITE] GET_INVITE rejected (not authenticated)");
        return true;
      }
      if (g_ownerExists && callerRole != BleRole::OWNER) {
        Serial.println("[INVITE] GET_INVITE rejected (insufficient role)");
        bleNotifyJson(String("{\"invite\":{\"ok\":false,\"err\":\"insufficient_role\"}}"));
        return true;
      }
      // { "type":"GET_INVITE","role":"USER","ttl":120 }
      const char* roleRaw = doc["role"] | "USER";
      BleRole roleEnum = roleFromStr(roleRaw);
      const char* role = (roleEnum == BleRole::GUEST) ? "GUEST" : "USER";
      int ttlSec = doc["ttl"] | 180;
      if (ttlSec < 10) ttlSec = 10;
      if (ttlSec > 180) ttlSec = 180;

      String deviceId = shortChipId();
      String inviteId = doc["inviteId"] | "";
      if (!inviteId.length()) {
        inviteId = randomHexString(8); // 8 byte -> 16 hex
      }

      // NTP yoksa exp=0 (time doğrulaması yapılmaz, joinWindow süre sınırı devrede)
      time_t nowEpoch = time(nullptr);
      int exp = 0;
      if (nowEpoch >= kMinValidEpoch) {
        exp = (int)(nowEpoch + ttlSec);
      }

      String canon = deviceId;
      canon += '|';
      canon += inviteId;
      canon += '|';
      canon += role;
      canon += '|';
      canon += String(exp);

      uint8_t mac[32];
      bool hmacOk = g_deviceSecretLoaded &&
                    computeHmacSha256(g_deviceSecret,
                                      sizeof(g_deviceSecret),
                                      (const uint8_t*)canon.c_str(),
                                      (size_t)canon.length(),
                                      mac);
      if (!hmacOk) {
        Serial.println("[INVITE] GET_INVITE failed (device_secret not ready)");
      } else {
        String sigHex;
        sigHex.reserve(64);
        for (size_t i = 0; i < sizeof(mac); ++i) {
          char buf[3];
          snprintf(buf, sizeof(buf), "%02x", mac[i]);
          sigHex += buf;
        }

        JsonDocument invDoc;
        JsonObject inv = invDoc.to<JsonObject>();
        inv["v"]        = 1;
        inv["deviceId"] = deviceId;
        inv["inviteId"] = inviteId;
        inv["role"]     = role;
        inv["exp"]      = exp;
        inv["sig"]      = sigHex;

        String out;
        serializeJson(invDoc, out);
        g_lastInviteJson = out;
        // BLE-first UX: immediately return the invite payload over BLE so the app
        // doesn't need to fetch /state over Wi-Fi.
        if (g_lastCmdSource == CmdSource::BLE) {
          JsonDocument respDoc;
          respDoc["invite"] = inv;
          String respOut;
          serializeJson(respDoc, respOut);
          bleNotifyJson(respOut);
        }
        changed = true;
        Serial.printf("[INVITE] GET_INVITE inviteId=%s role=%s exp=%d\n",
                      inviteId.c_str(), role, exp);
      }
      return changed;
    } else if (strcmp(type, "AP_START") == 0) {
      // { "type":"AP_START","ttl":600, ... }
      // Cihaz zaten AP'yi default olarak açıyor; bu komut kurtarma senaryosu
      // için AP parametrelerini tazelemek amacıyla kullanılır.
      int ttlSec = doc["ttl"] | 600;
      if (ttlSec < 60) ttlSec = 60;
      Serial.printf("[AP] AP_START requested ttl=%d\n", ttlSec);
      startAP();
      // SoftAP üzerinden yapılacak kurtarma işlemleri için kısa ömürlü bir
      // oturum token'ı üret. Bu token yalnızca cihazın kendi AP'sinde ve
      // verilen TTL süresince geçerlidir.
      g_apSessionToken = randomHexString(8); // 8 byte -> 16 hex
      g_apSessionNonce = randomHexString(8);
      g_apSessionUntilMs = nowMs + (uint32_t)ttlSec * 1000UL;
      g_apSessionOpenedWithQr = true; // trusted session (BLE-authenticated command)
      g_apSessionBound = false;
      g_apSessionBindIp = 0;
      g_apSessionBindUa = 0;
      Serial.printf("[AP] session opened ttl_ms=%u\n",
                    (unsigned)((uint32_t)ttlSec * 1000UL));
      changed = true;
      // Return the session token over BLE to the already-authenticated phone,
      // so the app can call /api/bootstrap_auth and other AP endpoints without
      // exposing long-term credentials.
      if (g_chInfo && g_chInfo->getSubscribedCount() > 0) {
        JsonDocument resp;
        resp["apSession"]["token"] = g_apSessionToken;
        resp["apSession"]["nonce"] = g_apSessionNonce;
        resp["apSession"]["ttl"] = ttlSec;
        String out;
        serializeJson(resp, out);
        bleNotifyJson(out);
      }
      // Şimdilik ttl'yi sadece log'luyoruz; AP kapatma için ayrı bir
      // planlama gerekecek (ileride join window ile entegre edilebilir).
      return true;
    } else if (strcmp(type, "JOIN") == 0) {
      // { "type":"JOIN", "invite":{...} }
      JsonObjectConst invite = doc["invite"].as<JsonObjectConst>();
      if (invite.isNull()) {
        // Bazı durumlarda root doğrudan davet olabilir.
        invite = doc.as<JsonObjectConst>();
      }
      String userIdHash;
      bool ok = false;
    if (!invite.isNull()) {
      ok = handleJoinInvite(invite, userIdHash);
    } else {
      Serial.println("[JOIN] no invite object in JOIN payload");
    }
    Serial.printf("[JOIN] JOIN handled ok=%d userIdHash=%s\n",
                  ok ? 1 : 0,
                  userIdHash.c_str());
      // JOIN, cihaz durumunu değiştirdiği için owner/invite alanları güncellensin.
      if (ok) {
        savePrefs();
        changed = true;
      }
      return changed;
    } else if (strcmp(type, "REVOKE_USER") == 0) {
      // Back-compat: older clients send { "userIdHash":"<target>" } over BLE/HTTP.
      // For MQTT, "userIdHash" is used for *caller identity* (role enforcement),
      // so allow the target to be specified separately.
      // Preferred:
      //  - { "type":"REVOKE_USER","userIdHash":"<caller>","targetUserIdHash":"<target>" }
      // Back-compat:
      //  - { "type":"REVOKE_USER","userIdHash":"<target>" }
      const char* targetRaw =
          doc["targetUserIdHash"] | doc["target_user_id_hash"] |
          doc["revokeUserIdHash"] | doc["revoke_user_id_hash"] | "";
      const char* legacy = doc["userIdHash"] | "";
      const char* hash = (targetRaw && targetRaw[0]) ? targetRaw : legacy;
      if (hash && hash[0]) {
        String target = String(hash);
        Serial.printf("[OWNER] REVOKE_USER targetUserIdHash=%s\n", target.c_str());
        JsonDocument usersDoc;
        JsonArray arr;
        if (g_usersJson.length()) {
          DeserializationError err = deserializeJson(usersDoc, g_usersJson);
          if (!err && usersDoc.is<JsonArray>()) {
            arr = usersDoc.as<JsonArray>();
          } else {
            arr = usersDoc.to<JsonArray>();
          }
        } else {
          arr = usersDoc.to<JsonArray>();
        }

        bool modified = false;
        for (size_t i = 0; i < arr.size();) {
          JsonObject o = arr[i].as<JsonObject>();
          const char* existing = o["id"] | o["userIdHash"] | "";
          if (existing && target.equalsIgnoreCase(String(existing))) {
            arr.remove(i);
            modified = true;
          } else {
            ++i;
          }
        }

        if (modified) {
          String out;
          serializeJson(usersDoc, out);
          g_usersJson = out;
          savePrefs();
          changed = true;
          Serial.println("[OWNER] REVOKE_USER updated users_json");
        }
      }
      return changed;
    }
    // Diğer typed komutlar (STREAM_ON/RENEW/OFF, JOIN vb.) ileride
    // eklenecek. Şimdilik klasik alan tabanlı kontrol mantığına devam ediyoruz.
  }

  bool masterOnProvided = false;
  bool cleanOnProvided = false;

  // master switch
  if (doc["masterOn"].is<bool>()) {
    masterOnProvided = true;
    bool v = doc["masterOn"].as<bool>();
    if (app.masterOn != v) {
      app.masterOn = v;
      changed = true;
      relaysNeedApply = true;
      rgbNeedApply = true;
      fanNeedApply = true;
      startCleanSnakeShow(millis());
    }
  }

  // mode / fanPercent
  bool modeProvided = !doc["mode"].isNull();
  int modeVal = modeProvided ? doc["mode"].as<int>() : -1;
  if (modeProvided) {
    const FanMode prevMode = app.mode;
    if (modeVal == (int)FAN_AUTO) {
      if (app.mode != FAN_AUTO) { changed = true; }
      app.mode = FAN_AUTO;
      g_envSeverityValid = false;
      g_forceAutoStep = true;
      if (app.mode != prevMode) {
        startFanModeShow(app.mode, millis());
      }
    } else {
      if ((int)app.mode != modeVal) { changed = true; }
      app.mode = (FanMode)modeVal;
      g_lastManualModeMs = millis();
      if (doc["fanPercent"].is<int>()) {
        int fp = doc["fanPercent"].as<int>();
        if (fp < 0) fp = 0; if (fp > 100) fp = 100;
        if (app.fanPercent != (uint8_t)fp) changed = true;
        setFanPercent(fp);
      } else {
        int fp = modeToPercent(app.mode);
        if (app.fanPercent != (uint8_t)fp) changed = true;
        setFanPercent(fp);
      }
      if (app.mode != prevMode) {
        startFanModeShow(app.mode, millis());
      }
    }
  } else if (doc["fanPercent"].is<int>()) {
    int fp = doc["fanPercent"].as<int>();
    if (fp < 0) fp = 0; if (fp > 100) fp = 100;
    if (app.fanPercent != (uint8_t)fp) changed = true;
    setFanPercent(fp);
    g_lastManualModeMs = millis();
  }

  // light/clean/ion toggles if provided
  if (doc["lightOn"].is<bool>()) {
    bool v = doc["lightOn"].as<bool>();
    if (app.lightOn != v) { app.lightOn = v; changed = true; relaysNeedApply = true; }
  }
  if (doc["cleanOn"].is<bool>()) {
    cleanOnProvided = true;
    bool v = doc["cleanOn"].as<bool>();
    if (app.cleanOn != v) {
      app.cleanOn = v;
      changed = true;
      relaysNeedApply = true;
      if (v) startCleanSnakeShow(millis());
    }
  }
  if (doc["ionOn"].is<bool>()) {
    bool v = doc["ionOn"].as<bool>();
    // Debug: ionOn alanı geldiğinde eski/yeni değerleri logla
    Serial.printf("[CMD] ionOn field present -> new=%d old=%d master=%d\n",
                  v ? 1 : 0,
                  app.ionOn ? 1 : 0,
                  app.masterOn ? 1 : 0);
    if (app.ionOn != v) { app.ionOn = v; changed = true; relaysNeedApply = true; }
  }

  // Backward compatibility:
  // Some clients toggle only masterOn; make cleanOn follow masterOn when
  // cleanOn is not explicitly provided so fan path is enabled as expected.
  if (masterOnProvided && !cleanOnProvided) {
    const bool desiredClean = app.masterOn;
    if (app.cleanOn != desiredClean) {
      app.cleanOn = desiredClean;
      changed = true;
      relaysNeedApply = true;
      if (desiredClean) startCleanSnakeShow(millis());
      Serial.printf("[CMD] cleanOn auto-follow master -> %d\n", desiredClean ? 1 : 0);
    }
  }

  // Safety net: if device is commanded ON for cleaning but fan percent is 0
  // (common after legacy/off sessions), force a sane startup airflow.
  if (app.masterOn && app.cleanOn && app.fanPercent == 0 &&
      !doc["fanPercent"].is<int>()) {
    app.fanPercent = 35;
    fanNeedApply = true;
    changed = true;
    Serial.println("[CMD] fanPercent auto-restore -> 35");
  }

  // Auto humidity control (ArtAirCleaner)
  if (!doc["autoHumEnabled"].isNull()) {
    bool en;
    if (doc["autoHumEnabled"].is<bool>()) {
      en = doc["autoHumEnabled"].as<bool>();
    } else if (doc["autoHumEnabled"].is<int>()) {
      en = doc["autoHumEnabled"].as<int>() != 0;
    } else {
      en = app.autoHumEnabled;
    }
    if (app.autoHumEnabled != en) {
      app.autoHumEnabled = en;
      changed = true;
    }
  }
  if (doc["autoHumTarget"].is<int>()) {
    int t = doc["autoHumTarget"].as<int>();
    if (t < 30) t = 30;
    if (t > 70) t = 70;
    if (app.autoHumTarget != (uint8_t)t) {
      app.autoHumTarget = (uint8_t)t;
      changed = true;
    }
  }

  // RGB: accept both nested payloads (`rgb:{...}`) and flat aliases
  // (`rgbOn`, `r`, `g`, `b`, `rgbBrightness`) so cloud/local paths converge.
  {
    const bool hadRgbObj = doc["rgb"].is<JsonObjectConst>();
    JsonObjectConst rgb = doc["rgb"].as<JsonObjectConst>();
    bool sawRgbField = false;
    const bool prevRgbOn = app.rgbOn;
    const int prevR = app.r;
    const int prevG = app.g;
    const int prevB = app.b;
    const int prevBrightness = app.rgbBrightness;

    if (hadRgbObj && !rgb.isNull()) {
      if (rgb["on"].is<bool>()) {
        bool v = rgb["on"].as<bool>();
        if (app.rgbOn != v) { app.rgbOn = v; changed = true; }
        rgbNeedApply = true;
        sawRgbField = true;
      }
      if (rgb["r"].is<int>()) {
        int v = rgb["r"].as<int>();
        if (app.r != v) { app.r = v; changed = true; rgbNeedApply = true; }
        sawRgbField = true;
      }
      if (rgb["g"].is<int>()) {
        int v = rgb["g"].as<int>();
        if (app.g != v) { app.g = v; changed = true; rgbNeedApply = true; }
        sawRgbField = true;
      }
      if (rgb["b"].is<int>()) {
        int v = rgb["b"].as<int>();
        if (app.b != v) { app.b = v; changed = true; rgbNeedApply = true; }
        sawRgbField = true;
      }
      if (rgb["brightness"].is<int>()) {
        int v = rgb["brightness"].as<int>();
        if (app.rgbBrightness != v) {
          app.rgbBrightness = v;
          changed = true;
          rgbNeedApply = true;
        }
        sawRgbField = true;
      }
    }

    if (doc["rgbOn"].is<bool>()) {
      bool v = doc["rgbOn"].as<bool>();
      if (app.rgbOn != v) { app.rgbOn = v; changed = true; }
      rgbNeedApply = true;
      sawRgbField = true;
    }
    if (doc["r"].is<int>()) {
      int v = doc["r"].as<int>();
      if (app.r != v) { app.r = v; changed = true; rgbNeedApply = true; }
      sawRgbField = true;
    }
    if (doc["g"].is<int>()) {
      int v = doc["g"].as<int>();
      if (app.g != v) { app.g = v; changed = true; rgbNeedApply = true; }
      sawRgbField = true;
    }
    if (doc["b"].is<int>()) {
      int v = doc["b"].as<int>();
      if (app.b != v) { app.b = v; changed = true; rgbNeedApply = true; }
      sawRgbField = true;
    }
    if (doc["rgbBrightness"].is<int>()) {
      int v = doc["rgbBrightness"].as<int>();
      if (app.rgbBrightness != v) {
        app.rgbBrightness = v;
        changed = true;
        rgbNeedApply = true;
      }
      sawRgbField = true;
    }

    if (sawRgbField) {
      const char* rgbSrc = "?";
      switch (g_lastCmdSource) {
        case CmdSource::BLE: rgbSrc = "BLE"; break;
        case CmdSource::HTTP: rgbSrc = "HTTP"; break;
        case CmdSource::MQTT: rgbSrc = "MQTT"; break;
        case CmdSource::TCP: rgbSrc = "TCP"; break;
        default: rgbSrc = "?"; break;
      }
      Serial.printf(
          "[CMD][RGB] src=%s hadRgbObj=%d on:%d->%d rgb:(%d,%d,%d)->(%d,%d,%d) br:%d->%d apply=%d changed=%d\n",
          rgbSrc,
          hadRgbObj ? 1 : 0,
          prevRgbOn ? 1 : 0,
          app.rgbOn ? 1 : 0,
          prevR, prevG, prevB,
          app.r, app.g, app.b,
          prevBrightness,
          app.rgbBrightness,
          rgbNeedApply ? 1 : 0,
          changed ? 1 : 0);
    }
  }

  // Otomatik sulama / nem (Doa için)
  // App tarafı:
  //  - waterManual:    manuel sulama (ON iken röle sürekli açık)
  //  - waterAutoEnabled: otomatik döngü açık/kapalı
  //  - waterDurationMin: her sulama turunda kaç dakika açık kalacak
  //  - waterIntervalMin: iki tur arası kaç dakika bekleme
  //  - waterHumAutoEnabled: nem tabanlı otomatik sulama (Doa)
  if (!doc["waterManual"].isNull()) {
    bool on;
    if (doc["waterManual"].is<bool>()) {
      on = doc["waterManual"].as<bool>();
    } else if (doc["waterManual"].is<int>()) {
      on = doc["waterManual"].as<int>() != 0;
    } else {
      on = g_waterManualOn;
    }
    if (g_waterManualOn != on) {
      g_waterManualOn = on;
      if (on) {
        g_waterRelayOn      = true;
        g_waterRelayOffAtMs = 0; // manuel modda süreyle kapanma yok
      } else {
        g_waterRelayOn      = false;
        g_waterRelayOffAtMs = 0;
      }
      changed = true;
      relaysNeedApply = true;
    }
  }

  if (!doc["waterAutoEnabled"].isNull()) {
    bool en;
    if (doc["waterAutoEnabled"].is<bool>()) {
      en = doc["waterAutoEnabled"].as<bool>();
    } else if (doc["waterAutoEnabled"].is<int>()) {
      en = doc["waterAutoEnabled"].as<int>() != 0;
    } else {
      en = g_waterAutoEnabled;
    }
    if (g_waterAutoEnabled != en) {
      g_waterAutoEnabled = en;
      if (en) {
        // Döngü yeniden açıldığında, bir sonraki scheduler çağrısında
        // hemen sulamayı başlatmak için son zamanı sıfırla.
        g_lastWaterStartMs = 0;
      } else {
        // Otomatik sulama kapatıldıysa, sadece otomatikten gelen akımı durdur.
        // Manuel mod açıksa kullanıcının isteğine saygı duy (pompa açık kalabilir).
        if (!g_waterManualOn && g_waterRelayOn) {
          g_waterRelayOn      = false;
          g_waterRelayOffAtMs = 0;
          applyRelays();
        }
      }
      changed = true;
      relaysNeedApply = true;
    }
  }

  if (!doc["waterHumAutoEnabled"].isNull()) {
    bool en;
    if (doc["waterHumAutoEnabled"].is<bool>()) {
      en = doc["waterHumAutoEnabled"].as<bool>();
    } else if (doc["waterHumAutoEnabled"].is<int>()) {
      en = doc["waterHumAutoEnabled"].as<int>() != 0;
    } else {
      en = g_doaHumAutoEnabled;
    }
    if (g_doaHumAutoEnabled != en) {
      g_doaHumAutoEnabled   = en;
      g_doaHumHadWaterCycle = false;
      g_doaHumNextCheckMs   = 0;
      if (!en) {
        // Nem bazlı otomatik sulama kapandığında ve başka mod aktif değilse pompayı kapat
        if (!g_waterManualOn && !g_waterAutoEnabled && g_waterRelayOn) {
          g_waterRelayOn      = false;
          g_waterRelayOffAtMs = 0;
          applyRelays();
        }
      }
      changed = true;
      relaysNeedApply = true;
    }
  }

  if (doc["waterDurationMin"].is<int>()) {
    int durMin = doc["waterDurationMin"].as<int>();
    if (durMin < 0) durMin = 0;
    if (durMin > 600) durMin = 600; // güvenlik sınırı
    uint16_t v = (uint16_t)durMin;
    if (g_waterDurationMin != v) {
      g_waterDurationMin = v;
      changed = true;
    }
  }

  if (doc["waterIntervalMin"].is<int>()) {
    int iv = doc["waterIntervalMin"].as<int>();
    if (iv < 1) iv = 1;
    if (iv > 24 * 60) iv = 24 * 60;
    uint16_t v = (uint16_t)iv;
    if (g_waterIntervalMin != v) {
      g_waterIntervalMin = v;
      changed = true;
    }
  }

  // streamMs / otaCheckNow / otaStart are deprecated

  // WAQI şehir konfigürasyonu (lat/lon + görünen ad)
  {
    JsonObjectConst waqi = doc["waqi"].as<JsonObjectConst>();
    if (waqi.isNull()) {
      JsonObjectConst cmd = doc["cmd"].as<JsonObjectConst>();
      if (!cmd.isNull()) {
        waqi = cmd["waqi"].as<JsonObjectConst>();
      }
    }
    if (!waqi.isNull()) {
#if ENABLE_WAQI
      bool confChanged = false;
      if (waqi["lat"].is<float>() || waqi["lat"].is<double>()) {
        double v = waqi["lat"].as<double>();
        if (!isnan(v) && g_waqiConfig.lat != v) {
          g_waqiConfig.lat = v;
          confChanged = true;
        }
      }
      if (waqi["lon"].is<float>() || waqi["lon"].is<double>()) {
        double v = waqi["lon"].as<double>();
        if (!isnan(v) && g_waqiConfig.lon != v) {
          g_waqiConfig.lon = v;
          confChanged = true;
        }
      }
      if (waqi["name"].is<const char*>()) {
        String name = String(waqi["name"].as<const char*>());
        if (g_waqiConfig.name != name) {
          g_waqiConfig.name = name;
          confChanged = true;
        }
      }
      if (confChanged) {
        g_waqiConfig.valid = true;
        // Konum değiştiğinde, bir sonraki döngüde yeniden çekilsin diye
        // mevcut şehir snapshot'ını geçersiz kıl.
        g_city.hasData   = false;
        g_forceWaqiFetch = true;
        Preferences p;
        p.begin("aac", false);
        p.putDouble("waqiLat", g_waqiConfig.lat);
        p.putDouble("waqiLon", g_waqiConfig.lon);
        p.putString("waqiName", g_waqiConfig.name);
        p.end();
        // Local-only build.
      }
#else
      (void)waqi;
#endif
    }
  }

  // Planner: gelen "plans" dizisini ESP32 tarafındaki plan tablosuna uygula
  {
    // Planlar hem doğrudan kökte "plans" alanı olarak, hem de ayrı path olarak
    // üzerinden "cmd.plans" altından gelebilir.
    JsonArrayConst plans = doc["plans"].as<JsonArrayConst>();
    if (plans.isNull()) {
      JsonObjectConst cmd = doc["cmd"].as<JsonObjectConst>();
      if (!cmd.isNull()) {
        plans = cmd["plans"].as<JsonArrayConst>();
      }
    }
    if (!plans.isNull()) {
      uint8_t count = (uint8_t)plans.size();
      if (count > MAX_PLANS) count = MAX_PLANS;
      g_planCount = count;
      for (uint8_t i = 0; i < count; ++i) {
        JsonObjectConst p = plans[i].as<JsonObjectConst>();
        g_plans[i].enabled    = p["enabled"]  | false;
        g_plans[i].startMin   = p["startMin"] | 0;
        g_plans[i].endMin     = p["endMin"]   | 0;
        g_plans[i].mode       = p["mode"]     | 1;
        g_plans[i].fanPercent = p["fanPercent"] | 35;
        g_plans[i].lightOn    = p["lightOn"]  | false;
        g_plans[i].ionOn      = p["ionOn"]    | false;
        g_plans[i].rgbOn      = p["rgbOn"]    | false;
      }
      for (uint8_t i = count; i < MAX_PLANS; ++i) {
        g_plans[i].enabled    = false;
        g_plans[i].startMin   = 0;
        g_plans[i].endMin     = 0;
        g_plans[i].mode       = 1;
        g_plans[i].fanPercent = 35;
        g_plans[i].lightOn    = false;
        g_plans[i].ionOn      = false;
        g_plans[i].rgbOn      = false;
      }
      savePrefs();
      changed = true; // planner state changed; treat as config change
      Serial.printf("[PLAN] updated %u plans via %s\n",
                    (unsigned)g_planCount,
                    doc["plans"].isNull() ? "cmd.plans" : "plans");
    }
  }

  // Cloud enable/disable (user opt-in)
  {
    bool haveCloudToggle = false;
    bool newCloudEnabled = g_cloudUserEnabled;
    bool haveEndpointUpdate = false;
    String newEndpoint = g_cloudEndpointOverride;
    if (doc["cloudEnabled"].is<bool>()) {
      haveCloudToggle = true;
      newCloudEnabled = doc["cloudEnabled"].as<bool>();
    } else {
      JsonObjectConst cloudObj = doc["cloud"].as<JsonObjectConst>();
      if (!cloudObj.isNull() && cloudObj["enabled"].is<bool>()) {
        haveCloudToggle = true;
        newCloudEnabled = cloudObj["enabled"].as<bool>();
      }
      if (!cloudObj.isNull()) {
        if (cloudObj["endpoint"].is<const char*>()) {
          haveEndpointUpdate = true;
          newEndpoint = normalizeCloudEndpoint(String(cloudObj["endpoint"].as<const char*>()));
        } else if (cloudObj["iotEndpoint"].is<const char*>()) {
          haveEndpointUpdate = true;
          newEndpoint = normalizeCloudEndpoint(String(cloudObj["iotEndpoint"].as<const char*>()));
        }
      }
    }
    if (doc["cloudEndpoint"].is<const char*>()) {
      haveEndpointUpdate = true;
      newEndpoint = normalizeCloudEndpoint(String(doc["cloudEndpoint"].as<const char*>()));
    }
    if (haveEndpointUpdate && newEndpoint != g_cloudEndpointOverride) {
      g_cloudEndpointOverride = newEndpoint;
      g_cloudDirty = true;
      if (g_mqtt.connected()) g_mqtt.disconnect();
      savePrefs();
      changed = true;
      Serial.printf("[CLOUD] endpoint override set=%s\n",
                    g_cloudEndpointOverride.length() ? g_cloudEndpointOverride.c_str() : "(empty)");
    }
    if (haveCloudToggle && newCloudEnabled != g_cloudUserEnabled) {
      g_cloudUserEnabled = newCloudEnabled;
      savePrefs();
      changed = true;
      g_cloudDirty = true;
      Serial.printf("[CLOUD] user enabled=%d\n", g_cloudUserEnabled ? 1 : 0);
    }
  }

  if (changed) {
    // Important: autoHum config (enable/target) should not force an immediate
    // relay write; watering relay must be decided by runAutoHumidityControl()
    // according to humidity threshold/hysteresis.
    if (relaysNeedApply) {
      applyRelays();
    }
    if (rgbNeedApply) {
      applyRgb();
    }
    if (fanNeedApply) {
      setFanPercent(app.fanPercent);
    }
  }
  return changed;
}

/* =================== HTTP mini portal =================== */

static void handleHttpCmdRequest(bool deprecatedPath) {
  logHttpRequestDiag(deprecatedPath ? "cmd_legacy" : "cmd");
  if (!enforceRateLimitOrSend(RateKind::CMD, 4 /*per sec*/, 3000 /*cooldown*/)) return;
  if (!authorizeRequest()) return;

  JsonDocument resp;
  if (deprecatedPath) {
    resp["deprecated"] = true;
    resp["canonical"] = "/cmd";
  }
  if (!g_http.hasArg("plain") || !g_http.arg("plain").length()) {
    resp["ok"] = false;
    resp["err"] = "missing_body";
  } else {
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, g_http.arg("plain"));
    if (err) {
      resp["ok"] = false;
      resp["err"] = err.f_str();
    } else {
      // Optional command target guard:
      // If client provides deviceId/id6, enforce strict match with this device.
      String cmdTarget = "";
      if (doc["deviceId"].is<const char*>()) {
        cmdTarget = String(doc["deviceId"].as<const char*>());
      }
      if (cmdTarget.length() == 0 && doc["id6"].is<const char*>()) {
        cmdTarget = String(doc["id6"].as<const char*>());
      }
      cmdTarget.trim();
      if (cmdTarget.length() > 0) {
        const String localId6 = getDeviceId6();
        const String normalizedTarget = normalizeDeviceId6(cmdTarget);
        if (normalizedTarget.length() == 0 || !normalizedTarget.equals(localId6)) {
          resp["ok"] = false;
          resp["err"] = "device_mismatch";
          resp["expectedId6"] = localId6;
          resp["targetId6"] = normalizedTarget.length() ? normalizedTarget : cmdTarget;
          resp["state"] = buildStatusJson();
          String out;
          serializeJson(resp, out);
          setCORS();
          g_http.send(409, "application/json", out);
          return;
        }
      }

      // Cloud mode: disable local control except recovery/auth primitives and pure cloud toggle.
      if (!allowLocalControlWhileCloudEnabled(doc, CmdSource::HTTP)) {
        JsonDocument out;
        out["ok"] = false;
        out["err"] = "local_disabled_cloud";
        out["cloud"]["enabled"] = true;
        String body;
        serializeJson(out, body);
        setCORS();
        g_http.send(403, "application/json", body);
        return;
      }
      // Ensure cmdId is present for correlation.
      String cmdId;
      if (doc["cmdId"].is<const char*>()) cmdId = String(doc["cmdId"].as<const char*>());
      cmdId.trim();
      if (cmdId.isEmpty()) {
        cmdId = genCmdIdHex8();
        doc["cmdId"] = cmdId;
      }

      bool accepted = true;
      bool changed = handleIncomingControlJson(doc, CmdSource::HTTP, "HTTP", false, &accepted);
      if (!accepted) {
        resp["ok"] = false;
        resp["err"] = "insufficient_role";
      } else {
        resp["ok"] = true;
        resp["changed"] = changed;
      }
      resp["cmdId"] = cmdId;
      resp["state"] = buildStatusJson();
    }
  }

  String out;
  serializeJson(resp, out);
  setCORS();
  g_http.send(resp["ok"].is<bool>() && resp["ok"].as<bool>() ? 200 : 400, "application/json", out);
}

static bool g_httpOtaAuthOk = false;
static bool g_httpOtaUploadOk = false;
static bool g_httpOtaShaInit = false;
static size_t g_httpOtaBytes = 0;
static String g_httpOtaErr;
static String g_httpOtaExpectedSha;
static String g_httpOtaActualSha;
static mbedtls_sha256_context g_httpOtaShaCtx;
static uint32_t g_httpOtaLastStartMs = 0;
static uint32_t g_httpOtaLastSuccessMs = 0;

static void resetHttpOtaState() {
  g_httpOtaAuthOk = false;
  g_httpOtaUploadOk = false;
  g_httpOtaShaInit = false;
  g_httpOtaBytes = 0;
  g_httpOtaErr = "";
  g_httpOtaExpectedSha = "";
  g_httpOtaActualSha = "";
}

static bool finalizeHttpOtaSha() {
  if (!g_httpOtaShaInit) return false;
  uint8_t digest[32] = {0};
  if (mbedtls_sha256_finish_ret(&g_httpOtaShaCtx, digest) != 0) {
    mbedtls_sha256_free(&g_httpOtaShaCtx);
    g_httpOtaShaInit = false;
    return false;
  }
  mbedtls_sha256_free(&g_httpOtaShaCtx);
  g_httpOtaShaInit = false;
  static const char* kHex = "0123456789abcdef";
  g_httpOtaActualSha = "";
  g_httpOtaActualSha.reserve(64);
  for (size_t i = 0; i < 32; ++i) {
    g_httpOtaActualSha += kHex[(digest[i] >> 4) & 0x0F];
    g_httpOtaActualSha += kHex[digest[i] & 0x0F];
  }
  return true;
}

void setupHttp() {
  // Ensure custom headers are parsed so authorizeRequest() can see them.
  // WebServer only exposes headers that are explicitly collected.
  static const char* kHeaderKeys[] = {
    "Authorization",
    "Origin",
    "Host",
    "X-QR-Token",
    "X-Session-Token",
    "X-Session-Nonce",
    "User-Agent",
    "X-Auth-Nonce",
    "X-Auth-Sig",
    "X-FW-SHA256",
  };
  g_http.collectHeaders(kHeaderKeys, sizeof(kHeaderKeys) / sizeof(kHeaderKeys[0]));
#if HTTP_DIAG_LOG
  Serial.printf("[HTTP] setup collectHeaders=%u\n",
                (unsigned)(sizeof(kHeaderKeys) / sizeof(kHeaderKeys[0])));
#endif

  // Captive / connectivity check endpoints (help iOS/Android stay on AP)
  g_http.on("/generate_204", HTTP_GET, [](){ setCORS(); g_http.send(204, "text/plain", ""); });               // Android
  g_http.on("/hotspot-detect.html", HTTP_GET, [](){ setCORS(); g_http.send(200, "text/html", "OK"); });       // iOS
  g_http.on("/fwlink", HTTP_GET, [](){ setCORS(); g_http.send(200, "text/plain", "OK"); });                   // Windows
  g_http.on("/ncsi.txt", HTTP_GET, [](){ setCORS(); g_http.send(200, "text/plain", "Microsoft NCSI"); });     // Windows (alt)
  g_http.on("/connecttest.txt", HTTP_GET, [](){ setCORS(); g_http.send(200, "text/plain", "OK"); });          // Some Android variants
  g_http.on("/health", HTTP_GET, [](){
    logHttpRequestDiag("health");
    JsonDocument d;
    d["ok"] = true;
    d["fw"] = FW_VERSION;
    d["apOnly"] = AP_ONLY;
    d["sta"] = (WiFi.status() == WL_CONNECTED);
    d["ip"] = WiFi.localIP().toString();
    d["cloudUserEnabled"] = g_cloudUserEnabled;
    String out;
    serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });
  g_http.on("/", HTTP_GET, [](){
    const IPAddress rip = g_http.client().remoteIP();
    const bool fromSoftApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
    if (!fromSoftApNet) {
      setCORS();
      g_http.send(403, "text/plain", "forbidden");
      return;
    }
    String html;
    html += F("<!DOCTYPE html><html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>");
    html += String("<title>") + deviceBrandName() + String("</title><style>body{font-family:sans-serif;margin:1rem}input,button,select{font-size:1rem;margin:.25rem 0}.row{display:flex;gap:.5rem;align-items:center}.card{border:1px solid #ccc;padding:1rem;border-radius:.5rem;margin-bottom:1rem}code{background:#f6f6f6;padding:.2rem .35rem;border-radius:.25rem}.warn{background:#fff3cd;border:1px solid #ffeeba;padding:.5rem;border-radius:.25rem;margin:.5rem 0;display:none}.disabled{opacity:.5;pointer-events:none}</style></head><body>");
    html += String("<h2>") + deviceBrandName() + String(" - Kurulum & Kontrol</h2>");

    // Auth / pair token
    html += F("<div class='card'><h3>Yerel Yetkilendirme</h3>");
    html += F("<div id='authWarn' class='warn'>PairToken bulunamadı. QR üzerinden token alın veya URL'ye <code>?t=TOKEN</code> ekleyin.</div>");
    html += F("<div class='row'><span>PairToken:</span> <code id='tokMask'>(yok)</code></div>");
    html += F("<div class='row'><label>Token:</label><input id='tokInput' type='text' placeholder='pairToken'></div>");
    html += F("<div class='row'><button id='tokSave'>Kaydet</button><small>Kaynak: <span id='tokSource'>-</span></small></div>");
    html += F("</div>");

    // Wi-Fi Ayarlari
    html += F("<div class='card'><h3>Wi-Fi Ayarları</h3>");
    html += F("<div class='row'><button id='scanBtn' data-auth='1'>Ağları Tara</button><span id='scanInfo'></span></div>");
    html += F("<div class='row'><label>SSID:</label><select id='ssidList'></select></div>");
    html += F("<div class='row'><label>Şifre:</label><input id='pw' type='password' placeholder='Ağ şifresi'></div>");
    html += F("<div class='row'><button id='connectBtn' data-auth='1'>Kaydet ve Bağlan</button><span id='provInfo'></span></div>");
    html += F("<details style='margin-top:.5rem'><summary>Mevcut AP bilgisi</summary><div>AP SSID: "); html += g_apSsid;
    html += F("<br>ID6: "); html += shortChipId(); html += F("</div></details></div>");

#if ENABLE_HTTP_CMD
    // Hizli kontrol
    html += F("<div class='card'><h3>Hızlı Kontrol</h3>");
    if (g_cloudUserEnabled) {
      html += F("<p>Cloud modu aktif: yerel kontrol komutları kapalı.</p>");
      html += F("<p>Kontrol için mobil uygulama veya AWS bulutu kullanın.</p>");
    } else {
      html += F("<button data-auth='1' onclick=\"authFetch('/api/cmd',{method:'POST',headers:{'Content-Type':'application/json'},body:'{\\\"masterOn\\\":true}'}).then(_=>location.reload())\">Aç</button> ");
      html += F("<button data-auth='1' onclick=\"authFetch('/api/cmd',{method:'POST',headers:{'Content-Type':'application/json'},body:'{\\\"masterOn\\\":false}'}).then(_=>location.reload())\">Kapat</button>");
      html += F("<br>% Fan:<input id='fp' type='number' min='0' max='100' value='35'> <button data-auth='1' onclick=\"authFetch('/api/cmd',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({fanPercent:parseInt(document.getElementById('fp').value)||0})}).then(_=>location.reload())\">Ayarla</button>");
    }
    html += F("</div>");
#else
    html += F("<div class='card'><h3>Hızlı Kontrol</h3><p>Yerel komutlar geçici olarak kapalıdır. Lütfen mobil uygulama veya AWS bulut kontrolünü kullanın.</p></div>");
#endif

    // OTA + durum + bakım
    html += F("<div class='card'><h3>OTA</h3>");
    html += F("<div>Mevcut sürüm: <code id='otaCurrent'>-</code></div>");
    html += F("<div>Bekleyen sürüm: <code id='otaPending'>-</code></div>");
    html += F("<div>Son OTA durumu: <code id='otaLastStatus'>-</code></div>");
    html += F("<div>Son hedef sürüm: <code id='otaLastTarget'>-</code></div>");
    html += F("<div id='otaHint' style='margin-top:.5rem;color:#856404'></div>");
    html += F("<div class='row' style='margin-top:.5rem'><button id='otaApproveBtn' data-auth='1' class='disabled' disabled>Onayla ve Güncelle</button><button id='otaRejectBtn' data-auth='1' class='disabled' disabled>Reddet</button><span id='otaActionInfo'></span></div>");
    html += F("</div>");
    html += F("<div class='card'><h3>Durum</h3><pre id='st'></pre>");
    html += F("<div class='row'><button data-auth='1' onclick=\"authFetch('/wifi/forget').then(()=>location.reload())\">Wi-Fi Bilgilerini Unut</button><button data-auth='1' style='margin-left:.5rem' onclick=\"authFetch('/api/reboot').then(()=>{document.body.innerHTML='Yeniden başlatılıyor…';})\">Yeniden Başlat</button></div>");
    html += F("</div>");

    // JS
    html += F("<script>\n");
    html += F("const tokSourceEl=document.getElementById('tokSource');\n"
               "const warnEl=document.getElementById('authWarn');\n"
               "const tokMaskEl=document.getElementById('tokMask');\n"
               "const tokInput=document.getElementById('tokInput');\n"
               "const tokSave=document.getElementById('tokSave');\n"
               "const qs=new URLSearchParams(location.search);\n"
               "const qsToken=(qs.get('t')||qs.get('token')||'').trim();\n"
               "let pairToken='';\n"
               "let source='none';\n"
               "function applyToken(t,src){pairToken=(t||'').trim();source=src||'manual';tokMaskEl.textContent=maskToken(pairToken);tokSourceEl.textContent=source;tokInput.value=pairToken;setAuthUi(!!pairToken);}\n"
               "if(qsToken){applyToken(qsToken,'query');}\n"
               "const ssidList=document.getElementById('ssidList');\n"
               "const scanBtn=document.getElementById('scanBtn');\n"
               "const scanInfo=document.getElementById('scanInfo');\n"
               "const provInfo=document.getElementById('provInfo');\n"
               "const otaCurrentEl=document.getElementById('otaCurrent');\n"
               "const otaPendingEl=document.getElementById('otaPending');\n"
               "const otaHintEl=document.getElementById('otaHint');\n"
               "const otaLastStatusEl=document.getElementById('otaLastStatus');\n"
               "const otaLastTargetEl=document.getElementById('otaLastTarget');\n"
               "const otaApproveBtn=document.getElementById('otaApproveBtn');\n"
               "const otaRejectBtn=document.getElementById('otaRejectBtn');\n"
               "const otaActionInfo=document.getElementById('otaActionInfo');\n"
               "const pw=document.getElementById('pw');\n"
               "function maskToken(t){if(!t)return'(yok)';if(t.length<=8)return t;return t.slice(0,4)+'...'+t.slice(-4)}\n"
               "tokSave.addEventListener('click',()=>{const v=(tokInput.value||'').trim();if(!v){warnEl.style.display='block';return;}applyToken(v,'manual');});\n"
               "function setAuthUi(has){document.querySelectorAll('[data-auth=\"1\"]').forEach(b=>{b.disabled=!has;b.classList.toggle('disabled',!has);});warnEl.style.display=has?'none':'block';}\n"
               "setAuthUi(!!pairToken);\n"
               "function rssiBars(r){if(r>=-55)return'▮▮▮▮';if(r>=-65)return'▮▮▮▯';if(r>=-75)return'▮▮▯▯';return'▮▯▯▯'}\n"
               "function authFetch(url,opts){opts=opts||{};if(!pairToken){return Promise.reject(new Error('missing_token'));}const headers=Object.assign({'Authorization':'Bearer '+pairToken,'X-QR-Token':pairToken},opts.headers||{});opts.headers=headers;return fetch(url,opts);}\n"
               "function setOtaButtonsEnabled(enabled){otaApproveBtn.disabled=!enabled;otaRejectBtn.disabled=!enabled;otaApproveBtn.classList.toggle('disabled',!enabled);otaRejectBtn.classList.toggle('disabled',!enabled)}\n"
               "function otaStatusLabel(status){switch(status){case 'waiting_approval':return 'Onay bekleniyor';case 'starting':return 'Guncelleme baslatildi';case 'succeeded':return 'Guncelleme basarili';case 'failed':return 'Guncelleme basarisiz';case 'rejected':return 'Guncelleme reddedildi';default:return status||'-';}}\n"
               "function renderOta(j){const ota=((j||{}).cloud||{}).ota||{};const current=ota.currentVersion||j.fwVersion||(((j||{}).meta||{}).fwVersion)||'-';const pending=ota.pending?(ota.version||'-'):'-';const lastStatus=ota.lastStatus||'';const lastTarget=ota.lastTargetVersion||'-';otaCurrentEl.textContent=current;otaPendingEl.textContent=pending;otaLastStatusEl.textContent=otaStatusLabel(lastStatus);otaLastTargetEl.textContent=lastTarget;if(ota.pending){otaHintEl.textContent='Bu surum cihaza geldi ve onay bekliyor. Onay verirseniz kurulum baslar.';setOtaButtonsEnabled(true);otaApproveBtn.dataset.jobId=ota.jobId||'';otaRejectBtn.dataset.jobId=ota.jobId||'';}else{setOtaButtonsEnabled(false);otaApproveBtn.dataset.jobId='';otaRejectBtn.dataset.jobId='';if(lastStatus==='succeeded'){otaHintEl.textContent=(current===lastTarget&&lastTarget!=='-'?('Son OTA basariyla kuruldu: '+current):'Son OTA basarili gorunuyor. Gecerli surumu yukaridan kontrol edin.');}else if(lastStatus==='failed'){otaHintEl.textContent='Son OTA denemesi basarisiz oldu'+(ota.lastReason?(': '+ota.lastReason):'.');}else if(lastStatus==='starting'){otaHintEl.textContent='OTA onayi gonderildi. Cihaz kurulum asamasinda olabilir; yeniden baslayip surumu guncellemesi gerekir.';}else if(lastStatus==='rejected'){otaHintEl.textContent='Son OTA kullanici tarafindan reddedildi.';}else if(lastStatus==='waiting_approval'){otaHintEl.textContent='Bekleyen OTA onay bekliyor.';}else{otaHintEl.textContent='Bekleyen OTA yok.';}if(!otaActionInfo.dataset.busy)otaActionInfo.textContent='';}}\n"
               "function loadStatus(){if(!pairToken){document.getElementById('st').textContent='PairToken yok';renderOta({});return;}authFetch('/api/status').then(r=>r.json()).then(j=>{document.getElementById('st').textContent=JSON.stringify(j,null,2);renderOta(j)}).catch(()=>{document.getElementById('st').textContent='Durum alınamadı';renderOta({});})}\n"
               "function sendOtaDecision(type,jobId){otaActionInfo.dataset.busy='1';otaActionInfo.textContent=(type==='OTA_APPROVE'?'Onay gönderiliyor…':'Red gönderiliyor…');setOtaButtonsEnabled(false);return authFetch('/api/cmd',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({type:type,jobId:jobId||''})}).then(r=>r.json()).then(()=>{otaActionInfo.textContent=(type==='OTA_APPROVE'?'Onay gönderildi. Güncelleme başlatılıyor…':'Red gönderildi.');setTimeout(()=>{delete otaActionInfo.dataset.busy;loadStatus();},800);}).catch(()=>{delete otaActionInfo.dataset.busy;otaActionInfo.textContent='OTA komutu gönderilemedi';loadStatus();});}\n"
               "function scan(){scanInfo.textContent='Taranıyor…';authFetch('/api/scan').then(r=>r.json()).then(list=>{ssidList.innerHTML='';list.forEach(x=>{const o=document.createElement('option');o.value=x.ssid;o.text=x.ssid+'  '+rssiBars(x.rssi)+(x.secure?' 🔒':'');ssidList.appendChild(o);});scanInfo.textContent=(list.length?'Bulunan ağlar: '+list.length:'Ağ bulunamadı');}).catch(()=>{scanInfo.textContent='Tarama hatası';})}\n"
               "scanBtn.addEventListener('click',scan);\n"
               "document.getElementById('connectBtn').addEventListener('click',()=>{const ssid=ssidList.value||'';const pass=pw.value||'';if(!ssid){provInfo.textContent='SSID seçin';return;}provInfo.textContent='Bağlanıyor…';authFetch('/api/prov',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ssid:ssid,pass:pass})}).then(r=>r.json()).then(j=>{provInfo.textContent=j.sta?'Bağlandı IP: '+(j.ip||''):'Bağlantı başarısız ('+(j.status||'')+')';loadStatus();}).catch(()=>{provInfo.textContent='Hata';});});\n"
               "otaApproveBtn.addEventListener('click',()=>{const jobId=otaApproveBtn.dataset.jobId||'';if(!jobId)return;sendOtaDecision('OTA_APPROVE',jobId);});\n"
               "otaRejectBtn.addEventListener('click',()=>{const jobId=otaRejectBtn.dataset.jobId||'';if(!jobId)return;sendOtaDecision('OTA_REJECT',jobId);});\n"
               "loadStatus();\n"
               "</script>");
    setCORS();
    g_http.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
    g_http.sendHeader("Pragma", "no-cache");
    g_http.send(200, "text/html", html);
  });

  // AP/ID info endpoint (helps mobile app to confirm the 6-digit id)
  g_http.on("/api/ap_info", HTTP_GET, [](){
    // ✅ Güvenlik: Rate limiting ekle
    if (!enforceRateLimitOrSend(RateKind::BOOTSTRAP, 10 /*per sec*/, 1000 /*cooldown*/)) return;
    
    // ✅ Güvenlik: Sadece SoftAP network'ünden erişime izin ver
    const IPAddress rip = g_http.client().remoteIP();
    const bool fromSoftApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
    if (!fromSoftApNet) {
      setCORS();
      g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"forbidden\"}");
      return;
    }
    
    JsonDocument d;
    d["ssid"] = g_apSsid;
    d["id6"]  = shortChipId();
    String out; serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });

  // SoftAP /info endpoint: basit cihaz ve owner/invite durumu
  g_http.on("/info", HTTP_GET, [](){
    // ✅ Güvenlik: Rate limiting ekle
    if (!enforceRateLimitOrSend(RateKind::BOOTSTRAP, 10 /*per sec*/, 1000 /*cooldown*/)) return;
    
    // ✅ Güvenlik: Sadece SoftAP network'ünden erişime izin ver
    const IPAddress rip = g_http.client().remoteIP();
    const bool fromSoftApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
    if (!fromSoftApNet) {
      setCORS();
      g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"forbidden\"}");
      return;
    }
    
    JsonDocument d;
    d["id6"]        = shortChipId();
    d["fwVersion"]  = FW_VERSION;
    d["apSsid"]     = g_apSsid;
    d["apOnly"]     = AP_ONLY;
    JsonObject owner = d["owner"].to<JsonObject>();
    owner["setupDone"] = g_setupDone;
    owner["hasOwner"]  = (g_ownerExists || g_ownerPubKeyB64.length() > 0);
    JsonObject join = d["join"].to<JsonObject>();
    uint32_t nowMs = millis();
    bool joinActive = (g_joinUntilMs != 0) &&
                      ((int32_t)(g_joinUntilMs - nowMs) > 0);
    bool apSessActive = (!g_apSessionToken.isEmpty() &&
                         g_apSessionUntilMs != 0 &&
                         (int32_t)(g_apSessionUntilMs - nowMs) > 0);
    join["active"]         = joinActive;
    join["apSessionActive"] = apSessActive;
    const uint32_t softRecoveryRemainMs = softRecoveryRemainingMs(nowMs);
    owner["softRecoveryActive"] = (softRecoveryRemainMs > 0);
    owner["softRecoveryRemainingSec"] = (softRecoveryRemainMs + 999UL) / 1000UL;
    join["softRecoveryActive"] = (softRecoveryRemainMs > 0);
    join["softRecoveryRemainingSec"] = (softRecoveryRemainMs + 999UL) / 1000UL;
    String out; serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });

  // Signed nonce for local HTTP requests.
  g_http.on("/api/nonce", HTTP_GET, [](){
    logHttpRequestDiag("nonce");
    if (!enforceRateLimitOrSend(RateKind::BOOTSTRAP, 5 /*per sec*/, 2000 /*cooldown*/)) return;
    IPAddress rip = g_http.client().remoteIP();
    const uint32_t ip32 =
        ((uint32_t)rip[0] << 24) | ((uint32_t)rip[1] << 16) | ((uint32_t)rip[2] << 8) | (uint32_t)rip[3];
    const String nonce = issueHttpNonceForIp(ip32, millis());
    JsonDocument d;
    d["ok"] = true;
    d["nonce"] = nonce;
    d["owned"] = g_ownerExists ? true : false;
    String out;
    serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });

  // Open a short-lived local session to avoid per-request signatures.
  // POST /api/session/open -> { ok, token, nonce, ttl }
  g_http.on("/api/session/open", HTTP_POST, [](){
    logHttpRequestDiag("session_open");
    if (!enforceRateLimitOrSend(RateKind::BOOTSTRAP, 4 /*per sec*/, 1200 /*cooldown*/)) return;

    uint32_t nowMs = millis();
    const IPAddress rip = g_http.client().remoteIP();
    const bool fromSoftApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
    // Unowned + SoftAP => allow bootstrapping a short local session without
    // pair token. This keeps AP-guided onboarding resilient even if BLE is
    // unavailable or recovery window has elapsed.
    const bool allowUnownedApBootstrap = (!g_ownerExists && fromSoftApNet);

    if (!allowUnownedApBootstrap) {
      // Session renewal must re-prove trust. Do not allow an existing session
      // to extend itself indefinitely without a fresh pair-token or signature.
      if (!authorizeRequest(false, false)) return;
      if (!g_ownerExists && g_httpAuthMode != HttpAuthMode::PAIR_TOKEN) {
        setCORS();
        g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"unauthorized\"}");
        return;
      }
      if (g_ownerExists && g_httpAuthMode != HttpAuthMode::SIGNATURE) {
        setCORS();
        g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"unauthorized\"}");
        return;
      }
    } else {
      g_httpAuthMode = HttpAuthMode::PAIR_TOKEN;
      g_httpRole = BleRole::OWNER;
      AUTH_HTTP_PRINTLN("[AUTH][HTTP] session_open bootstrap allowed (unowned softap recovery)");
    }

    int ttlSec = 180;
    if (g_http.hasArg("plain") && g_http.arg("plain").length()) {
      JsonDocument doc;
      if (!deserializeJson(doc, g_http.arg("plain"))) {
        ttlSec = doc["ttl"] | doc["ttlSec"] | ttlSec;
      }
    }
    if (ttlSec < 30) ttlSec = 30;
    if (ttlSec > 900) ttlSec = 900;
#if PRODUCTION_BUILD
    if (ttlSec > 300) ttlSec = 300;
#endif

    const uint32_t ip32 =
        ((uint32_t)rip[0] << 24) | ((uint32_t)rip[1] << 16) | ((uint32_t)rip[2] << 8) | (uint32_t)rip[3];
    String ua = g_http.header("User-Agent");
    ua.trim();
    uint8_t h[32];
    if (!computeSha256Bytes((const uint8_t*)ua.c_str(), (size_t)ua.length(), h)) {
      h[0] = h[1] = h[2] = h[3] = 0;
    }
    const uint32_t ua32 =
        ((uint32_t)h[0] << 24) | ((uint32_t)h[1] << 16) | ((uint32_t)h[2] << 8) | (uint32_t)h[3];
    const bool sessActive =
        (!g_apSessionToken.isEmpty() &&
         g_apSessionUntilMs != 0 &&
         (int32_t)(g_apSessionUntilMs - nowMs) > 0);
    const bool sameClient =
        (!g_apSessionBound ||
         (g_apSessionBindIp == ip32 && g_apSessionBindUa == ua32));

    if (sessActive && sameClient) {
      g_apSessionUntilMs = nowMs + (uint32_t)ttlSec * 1000UL;
      g_apSessionBindIp = ip32;
      g_apSessionBindUa = ua32;
      g_apSessionBound = true;
    } else {
      g_apSessionToken = randomHexString(8);
      g_apSessionNonce = randomHexString(8);
      g_apSessionUntilMs = nowMs + (uint32_t)ttlSec * 1000UL;
      g_apSessionBound = true;
      g_apSessionBindIp = ip32;
      g_apSessionBindUa = ua32;
    }
    g_apSessionOpenedWithQr =
        (g_httpAuthMode == HttpAuthMode::PAIR_TOKEN ||
         g_httpAuthMode == HttpAuthMode::SIGNATURE);

    JsonDocument d;
    d["ok"] = true;
    d["token"] = g_apSessionToken;
    d["nonce"] = g_apSessionNonce;
    d["ttl"] = ttlSec;
    String out;
    serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);

    // If the app reached us over the home LAN (not our SoftAP), local control is proven.
    // At that point recovery transports can be turned off to reduce coexistence load.
    if (!(rip[0] == 192 && rip[1] == 168 && rip[2] == 4)) {
      markLocalControlReady(nowMs, "http_session_open");
    }
  });

  // Claim owner without BLE (phones without Bluetooth): only while unowned,
  // during boot pairing window, and only from SoftAP subnet with the QR pair token.
  g_http.on("/api/claim_owner", HTTP_POST, [](){
    if (!enforceRateLimitOrSend(RateKind::BOOTSTRAP, 1 /*per sec*/, 8000 /*cooldown*/)) return;
    IPAddress rip = g_http.client().remoteIP();
    bool fromApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
    if (!fromApNet) {
      setCORS();
      g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"ap_only\"}");
      return;
    }
    if ((g_ownerExists || g_ownerPubKeyB64.length()) &&
        !ownerRotateWindowActive(millis())) {
      setCORS();
      g_http.send(409, "application/json", "{\"ok\":false,\"err\":\"owner_already_exists\"}");
      return;
    }
    uint32_t nowMs = millis();
    uint32_t retryMs = 0;
    if (setupAuthLocked(nowMs, &retryMs)) {
      JsonDocument d;
      d["ok"] = false;
      d["err"] = "setup_locked";
      d["retryMs"] = retryMs;
      String out;
      serializeJson(d, out);
      setCORS();
      g_http.send(429, "application/json", out);
      return;
    }
    if (!pairingWindowActive(nowMs)) {
      setCORS();
      g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"pairing_window_closed\"}");
      return;
    }
    if (!authorizeRequest()) return; // unowned => requires pair token
    if (!g_http.hasArg("plain") || !g_http.arg("plain").length()) {
      setCORS();
      g_http.send(400, "application/json", "{\"ok\":false,\"err\":\"missing_body\"}");
      return;
    }
    JsonDocument doc;
    if (deserializeJson(doc, g_http.arg("plain"))) {
      setCORS();
      g_http.send(400, "application/json", "{\"ok\":false,\"err\":\"invalid_json\"}");
      return;
    }
    const char* user = doc["user"] | "";
    const char* pass = doc["pass"] | "";
    const char* pub  = doc["owner_pubkey"] | doc["ownerPubKey"] | "";
    if (!user[0] || !pass[0] || !pub[0]) {
      setCORS();
      g_http.send(400, "application/json", "{\"ok\":false,\"err\":\"missing_fields\"}");
      return;
    }
    const bool rotateWin = ownerRotateWindowActive(nowMs);
    if ((g_ownerExists || g_ownerPubKeyB64.length()) && !rotateWin) {
      setCORS();
      g_http.send(409, "application/json", "{\"ok\":false,\"err\":\"owner_already_exists\"}");
      return;
    }
    if (!verifySetupUserPass(user, pass)) {
      noteSetupAuthFailure(nowMs);
      setCORS();
      g_http.send(401, "application/json", "{\"ok\":false,\"err\":\"invalid_setup_creds\"}");
      return;
    }
    std::vector<uint8_t> pubBytes;
    if (!base64Decode(String(pub), pubBytes) || pubBytes.size() != 65) {
      setCORS();
      g_http.send(400, "application/json", "{\"ok\":false,\"err\":\"invalid_pubkey\"}");
      return;
    }
    const bool rotatingOwner = (g_ownerExists || g_ownerPubKeyB64.length());
    if (rotatingOwner) {
      g_usersJson.clear();
      g_ownerHash.clear();
      g_bleUserIdHash.clear();
      g_joinInviteId.clear();
      g_joinRole.clear();
      g_joinUntilMs = 0;
    }
    g_ownerPubKeyB64 = String(pub);
    g_ownerPubKeyB64.trim();
    noteSetupAuthSuccess();
    setOwned(true, "http_claim_owner");
    g_cloudUserEnabled = false;
    g_cloudDirty = true;
    g_setupDone = true;
    markPairTokenTrusted(0);
    closeTransientOnboardingState();
    savePrefs();
    setCORS();
    g_http.send(200, "application/json", "{\"ok\":true}");
  });

  // Status JSON
  g_http.on("/api/status", HTTP_GET, [](){
    logHttpRequestDiag("status");
    if (!authorizeRequest()) return;
    setCORS();
    g_http.send(200, "application/json", buildStatusJson());
  });

  // Short‑term + daily sensor history (RAM + flash).
  // Şekil:
  // {
  //   "home": { "short":[...], "daily":[...] },
  //   "city": { "short":[...], "daily":[...] }
  // }
  g_http.on("/api/history", HTTP_GET, [](){
    if (!authorizeRequest()) return;

    String json;
    json.reserve(8192);
    json += "{\"home\":{\"short\":[";

    // Indoor kısa history
    uint16_t count = g_historyCount;
    for (uint16_t i = 0; i < count; ++i) {
      uint16_t idx =
          (g_historyHead + HISTORY_CAPACITY - count + i) %
          HISTORY_CAPACITY;
      const HistorySample& s = g_history[idx];
      auto f10 = [](int16_t v) -> float { return (float)v / 10.0f; };
      if (i > 0) json += ',';
      json += '{';
      json += "\"ts\":";        json += (unsigned long)s.tsSec; json += ',';
      json += "\"pm2_5\":";     json += String(f10(s.pm25_x10), 2);    json += ',';
      json += "\"tempC\":";     json += String(f10(s.tempC_x10), 2);   json += ',';
      json += "\"hum\":";       json += String(f10(s.humPct_x10), 2);  json += ',';
      json += "\"vocIndex\":";  json += String(f10(s.voc_x10), 2);     json += ',';
      json += "\"noxIndex\":";  json += String(f10(s.nox_x10), 2);     json += ',';
      json += "\"aiTempC\":";   json += String(f10(s.aiTempC_x10), 2); json += ',';
      json += "\"aiHumPct\":";  json += String(f10(s.aiHum_x10), 2);   json += ',';
      json += "\"aiPressure\":";json += String(f10(s.aiPress_x10),2);  json += ',';
      json += "\"aiGasKOhm\":"; json += String(f10(s.aiGas_x10),2);    json += ',';
      json += "\"rpm\":";       json += (unsigned long)s.rpm;
      json += '}';
    }

    json += "],\"daily\":[";

    uint8_t dcount = g_dailyCount;
    for (uint8_t i = 0; i < dcount; ++i) {
      uint8_t idx =
          (g_dailyHead + DAILY_HISTORY_CAPACITY - dcount + i) %
          DAILY_HISTORY_CAPACITY;
      const DailySample& d = g_daily[idx];
      if (i > 0) json += ',';
      json += '{';
      json += "\"day\":";       json += (unsigned long)d.dayStart; json += ',';
      json += "\"pm2_5\":";     json += String(d.pm2_5, 2);       json += ',';
      json += "\"tempC\":";     json += String(d.tempC, 2);       json += ',';
      json += "\"hum\":";       json += String(d.humPct, 2);      json += ',';
      json += "\"vocIndex\":";  json += String(d.vocIndex, 2);    json += ',';
      json += "\"noxIndex\":";  json += String(d.noxIndex, 2);    json += ',';
      json += "\"aiTempC\":";   json += String(d.aiTempC, 2);     json += ',';
      json += "\"aiHumPct\":";  json += String(d.aiHumPct, 2);    json += ',';
      json += "\"aiPressure\":";json += String(d.aiPressure, 2);  json += ',';
      json += "\"aiGasKOhm\":"; json += String(d.aiGasKOhm, 2);   json += ',';
      json += "\"rpm\":";       json += (unsigned long)d.rpm;
      json += '}';
    }

    json += "]},\"city\":{\"short\":[";

    // Mobil uygulama artık dış ortam history'sini WAQI üzerinden tuttuğu için
    // firmware tarafında sadece iç ortam geçmişi döndürülüyor.
    json += "],\"daily\":[]}}";
    setCORS();
    g_http.send(200, "application/json", json);
  });

  // Wi-Fi ağ tarama
  g_http.on("/api/scan", HTTP_GET, [](){
    ScopedPerfLog perfScope("http_scan");
    if (!authorizeRequest()) return;
    if (!requireHttpRole(BleRole::OWNER)) return;
    if (AP_ONLY) {
      // AP-only iken senkron tarama AP beaconlarını anlık dondurabilir; boş liste döndür
      JsonDocument doc;
      JsonArray arr = doc.to<JsonArray>();
      String out; serializeJson(arr, out);
      setCORS();
      g_http.send(200, "application/json", out);
      return;
    }
    logPerfSnapshot("http_scan_before_scanNetworks");
    int n = WiFi.scanNetworks(false, true);
    logPerfSnapshot("http_scan_after_scanNetworks");
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    for (int i = 0; i < n; ++i) {
      JsonObject o = arr.add<JsonObject>();
      o["ssid"] = WiFi.SSID(i);
      o["rssi"] = WiFi.RSSI(i);
      o["ch"]   = WiFi.channel(i);
      o["secure"] = (WiFi.encryptionType(i) != WIFI_AUTH_OPEN);
    }
    logPerfSnapshot("http_scan_before_scanDelete");
    WiFi.scanDelete();
    logPerfSnapshot("http_scan_after_scanDelete");
    String out; serializeJson(arr, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });

  // Canlı STA teşhis JSON
  g_http.on("/api/sta_status", HTTP_GET, [](){
    if (!authorizeRequest()) return;
    wl_status_t st = WiFi.status(); int rssi = (st == WL_CONNECTED) ? WiFi.RSSI() : 0;
    String json = "{";
    json += "\"sta\":"; json += (st == WL_CONNECTED ? "true" : "false"); json += ",";
    json += "\"status\":"; json += (int)st; json += ",";
    json += "\"rssi\":"; json += rssi; json += ",";
    json += "\"ip\":\""; json += WiFi.localIP().toString(); json += "\"";
    json += "}";
    setCORS();
    g_http.send(200, "application/json", json);
  });

  // Runtime bellek / flash durumu (debug)
  g_http.on("/api/mem", HTTP_GET, [](){
    if (!authorizeRequest()) return;
    if (!requireHttpRole(BleRole::OWNER)) return;
    JsonDocument d;
    d["freeHeap"]     = ESP.getFreeHeap();
    d["minFreeHeap"]  = ESP.getMinFreeHeap();
    d["maxAllocHeap"] = ESP.getMaxAllocHeap();
    d["largest8BitFree"] = perfLargestBlock8Bit();
    d["largest32BitFree"] = perfLargestBlock32Bit();
    d["internal8BitFree"] = perfInternalFree8Bit();
    d["taskStackHighWater"] = perfTaskStackHighWaterBytes();
    d["cpuMHz"] = ESP.getCpuFreqMHz();
    d["flashSize"]    = ESP.getFlashChipSize();
    d["sketchSize"]   = ESP.getSketchSize();
    d["freeSketch"]   = ESP.getFreeSketchSpace();
    String out;
    serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });

  // Wi-Fi provisioning (save STA creds and attempt connect)
  g_http.on("/api/prov", HTTP_POST, [](){
    logHttpRequestDiag("prov");
    ScopedPerfLog perfScope("http_prov");
    if (!enforceRateLimitOrSend(RateKind::PROV, 1 /*per sec*/, 12000 /*cooldown*/)) return;
    if (!authorizeRequest()) return;
    if (!requireHttpRole(BleRole::OWNER)) return;
    String ssid, pass;
    if (g_http.hasArg("plain") && g_http.arg("plain").length()) {
      JsonDocument d;
      if (!deserializeJson(d, g_http.arg("plain"))) {
        ssid = d["ssid"].as<String>();
        pass = d["pass"].as<String>();
      }
    }
    if (!ssid.length() && g_http.hasArg("ssid")) ssid = g_http.arg("ssid");
    if (!pass.length() && g_http.hasArg("pass")) pass = g_http.arg("pass");

    JsonDocument resp;
    if (!ssid.length()) {
      resp["ok"] = false;
      resp["err"] = "missing_ssid";
    } else {
      logPerfSnapshot("http_prov_before_save_creds");
      saveCreds(ssid.c_str(), pass.c_str());
      logPerfSnapshot("http_prov_after_save_creds");
      if (!AP_ONLY) {
        logPerfSnapshot("http_prov_before_try_sta");
        trySTA();
        logPerfSnapshot("http_prov_after_try_sta");
      }
      bool staOk = (WiFi.status() == WL_CONNECTED);
      resp["ok"] = true;
      resp["sta"] = staOk;
      resp["status"] = (int)WiFi.status();
      if (staOk) resp["ip"] = WiFi.localIP().toString();
      else if (AP_ONLY) resp["note"] = "ap_only";
      resp["ssid"] = g_savedSsid;
    }
    String out; serializeJson(resp, out);
    setCORS();
    g_http.send(resp["ok"].as<bool>() ? 200 : 400, "application/json", out);
  });

  // SoftAP join endpoint:
  //  - Sadece cihazın kendi AP'si (192.168.4.x) üzerinden erişilebilir.
  //  - Body: JOIN komutunda kullanılan invite JSON'u (veya { "invite": { ... } }).
  g_http.on("/join", HTTP_POST, [](){
    if (!enforceRateLimitOrSend(RateKind::JOIN, 1 /*per sec*/, 12000 /*cooldown*/)) return;
    IPAddress rip = g_http.client().remoteIP();
    bool fromApNet = (rip[0] == 192 && rip[1] == 168 && rip[2] == 4);
    Serial.printf("[JOIN][HTTP] req from=%s ap=%d len=%d\n",
                  rip.toString().c_str(),
                  fromApNet ? 1 : 0,
                  g_http.hasArg("plain") ? g_http.arg("plain").length() : 0);
    if (!fromApNet) {
      setCORS();
      g_http.send(403, "application/json",
                  "{\"ok\":false,\"err\":\"forbidden_not_softap\"}");
      return;
    }

    if (!g_http.hasArg("plain") || !g_http.arg("plain").length()) {
      setCORS();
      g_http.send(400, "application/json",
                  "{\"ok\":false,\"err\":\"missing_body\"}");
      return;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, g_http.arg("plain"));
    if (err) {
      setCORS();
      g_http.send(400, "application/json",
                  "{\"ok\":false,\"err\":\"invalid_json\"}");
      return;
    }

    JsonObjectConst root = doc.as<JsonObjectConst>();
    JsonObjectConst invite = root["invite"].as<JsonObjectConst>();
    if (invite.isNull()) {
      // Bazı durumlarda root doğrudan invite olabilir.
      invite = root;
    }
    String userIdHash;
    bool ok = false;
    if (!invite.isNull()) {
      const char* invId = invite["inviteId"] | "";
      Serial.printf("[JOIN][HTTP] inviteId=%s\n", invId);
      ok = handleJoinInvite(invite, userIdHash);
    } else {
      Serial.println("[JOIN][HTTP] no invite object");
    }

    JsonDocument resp;
    resp["ok"] = ok;
    if (ok) {
      resp["userIdHash"] = userIdHash;
    } else {
      resp["err"] = "join_failed";
    }
    String out; serializeJson(resp, out);
    setCORS();
    Serial.printf("[JOIN][HTTP] resp ok=%d err=%s\n",
                  ok ? 1 : 0,
                  ok ? "-" : "join_failed");
    g_http.send(ok ? 200 : 400, "application/json", out);
  });


  // Forget stored Wi-Fi credentials and stay in AP mode
  auto handleForget = [](){
    if (!authorizeRequest()) return;
    if (!requireHttpRole(BleRole::OWNER)) return;
    saveCreds(nullptr, nullptr);
    g_haveCreds = false;
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_AP);
    startAP();
    JsonDocument resp;
    resp["ok"] = true;
    resp["apSsid"] = g_apSsid;
    resp["note"] = "creds_cleared";
    String out; serializeJson(resp, out);
    setCORS();
    g_http.send(200, "application/json", out);
  };
  g_http.on("/wifi/forget", HTTP_GET, handleForget);
  g_http.on("/wifi/forget", HTTP_POST, handleForget);

  // AP-only (direct) mode: cihaz sadece kendi Wi-Fi AP'si ile çalışsın mı?
  // GET  /api/ap_mode          -> mevcut durumu döndürür
  // POST /api/ap_mode {"ap_only":true/false} -> modu değiştirir ve kalıcı kaydeder
  g_http.on("/api/ap_mode", HTTP_ANY, [](){
    if (!authorizeRequest()) return;
    if (!requireHttpRole(BleRole::OWNER)) return;

    bool changed = false;
    // Yalnızca yazan metodlarda güncelle
    if (g_http.method() == HTTP_POST || g_http.method() == HTTP_PUT) {
      bool wantApOnly = AP_ONLY;

      // JSON body varsa oku
      if (g_http.hasArg("plain") && g_http.arg("plain").length()) {
        JsonDocument d;
        if (!deserializeJson(d, g_http.arg("plain"))) {
          if (d["ap_only"].is<bool>()) {
            wantApOnly = d["ap_only"].as<bool>();
          } else if (d["apOnly"].is<bool>()) {
            wantApOnly = d["apOnly"].as<bool>();
          }
        }
      }

      // Query / form parametresi ile override
      if (g_http.hasArg("ap_only")) {
        String v = g_http.arg("ap_only");
        v.toLowerCase();
        if (v == "1" || v == "true" || v == "yes")  wantApOnly = true;
        if (v == "0" || v == "false" || v == "no")   wantApOnly = false;
      }

      if (wantApOnly != AP_ONLY) {
        AP_ONLY = wantApOnly;
        // Kalıcı kaydet
        prefs.begin("aac", false);
        prefs.putBool("ap_only", AP_ONLY);
        prefs.end();
        changed = true;

        if (AP_ONLY) {
          // Ev Wi-Fi bağlantısını kapat, sadece cihaz AP'si açık kalsın
          WiFi.disconnect(true, true);
          WiFi.mode(WIFI_AP);
          startAP();
        } else {
          // Tekrar STA denemesi yap (varsa)
          if (g_haveCreds) {
            trySTA();
          }
        }
      }
    }

    JsonDocument resp;
    resp["ok"]       = true;
    resp["changed"]  = changed;
    resp["ap_only"]  = AP_ONLY;
    resp["apOnly"]   = AP_ONLY;
    resp["apSsid"]   = g_apSsid;
    resp["sta"]      = (WiFi.status() == WL_CONNECTED);
    resp["staIp"]    = WiFi.localIP().toString();
    resp["haveCreds"] = g_haveCreds;
    if (g_savedSsid.length()) {
      resp["wifiSsid"] = g_savedSsid;
    }
    String out; serializeJson(resp, out);
    setCORS();
    g_http.send(200, "application/json", out);
  });

#if ENABLE_HTTP_CMD
  // Canonical REST control endpoint (same payload as BLE/app commands)
  g_http.on("/cmd", HTTP_POST, [](){ handleHttpCmdRequest(false); });

  // Legacy endpoints kept for backward compatibility (return deprecation hints).
  g_http.on("/api/cmd", HTTP_POST, [](){ handleHttpCmdRequest(true); });
  g_http.on("/command", HTTP_POST, [](){ handleHttpCmdRequest(true); });
  g_http.on("/api/control", HTTP_POST, [](){ handleHttpCmdRequest(true); });
#else
  g_http.on("/cmd", HTTP_POST, [](){
    setCORS();
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"local_disabled\"}");
  });
  g_http.on("/api/cmd", HTTP_POST, [](){
    setCORS();
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"local_disabled\"}");
  });
  g_http.on("/command", HTTP_POST, [](){
    setCORS();
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"local_disabled\"}");
  });
  g_http.on("/api/control", HTTP_POST, [](){
    setCORS();
    g_http.send(403, "application/json", "{\"ok\":false,\"err\":\"local_disabled\"}");
  });
#endif

  // Simple reboot hook
  g_http.on("/api/reboot", HTTP_POST, [](){
    if (!authorizeRequest()) return;
    if (!requireHttpRole(BleRole::OWNER)) return;
    JsonDocument resp;
    resp["ok"] = true;
    resp["message"] = "restarting";
    String out; serializeJson(resp, out);
    setCORS();
    g_http.send(200, "application/json", out);
    delay(150);
    ESP.restart();
  });

  // Local OTA fallback (owner-only, local auth/session required).
  // Upload binary via multipart/form-data field name: "firmware".
  // Optional SHA256 validation: header X-FW-SHA256 or query/body field "sha256".
  g_http.on("/api/ota/local", HTTP_POST, [](){
    if (!enforceRateLimitOrSend(RateKind::PROV, 1 /*per sec*/, 20000 /*cooldown*/)) return;

    // If auth failed during upload callback, response already sent by authorizeRequest().
    if (!g_httpOtaAuthOk) {
      resetHttpOtaState();
      return;
    }
    if (!g_httpOtaUploadOk) {
      JsonDocument d;
      d["ok"] = false;
      d["err"] = g_httpOtaErr.length() ? g_httpOtaErr : "ota_upload_failed";
      if (g_httpOtaErr == "ota_cooldown" && g_httpOtaLastStartMs != 0) {
        const uint32_t nowMs = millis();
        const uint32_t elapsed = (uint32_t)(nowMs - g_httpOtaLastStartMs);
        const uint32_t waitMs =
            (elapsed < (uint32_t)OTA_LOCAL_MIN_INTERVAL_MS)
                ? ((uint32_t)OTA_LOCAL_MIN_INTERVAL_MS - elapsed)
                : 0;
        d["retryAfterMs"] = waitMs;
      }
      if (g_httpOtaActualSha.length()) d["sha256"] = g_httpOtaActualSha;
      d["bytes"] = (uint32_t)g_httpOtaBytes;
      String out;
      serializeJson(d, out);
      setCORS();
      g_http.send(400, "application/json", out);
      resetHttpOtaState();
      return;
    }

    JsonDocument d;
    d["ok"] = true;
    d["rebooting"] = true;
    d["bytes"] = (uint32_t)g_httpOtaBytes;
    if (g_httpOtaActualSha.length()) d["sha256"] = g_httpOtaActualSha;
    String out;
    serializeJson(d, out);
    setCORS();
    g_http.send(200, "application/json", out);
    resetHttpOtaState();
    delay(400);
    ESP.restart();
  }, [](){
    HTTPUpload& upload = g_http.upload();
    if (upload.status == UPLOAD_FILE_START) {
      resetHttpOtaState();
      const uint32_t nowMs = millis();
      if (OTA_LOCAL_REQUIRE_STRONG_AUTH) {
        const String nonceB64 = g_http.header("X-Auth-Nonce");
        const String sigB64 = g_http.header("X-Auth-Sig");
        if (!nonceB64.length() || !sigB64.length()) {
          g_httpOtaErr = "auth_signature_required";
          return;
        }
      }
      if (g_httpOtaLastStartMs != 0 &&
          (uint32_t)(nowMs - g_httpOtaLastStartMs) < (uint32_t)OTA_LOCAL_MIN_INTERVAL_MS) {
        g_httpOtaErr = "ota_cooldown";
        return;
      }
      if (!authorizeRequest(true, OTA_LOCAL_REQUIRE_STRONG_AUTH ? false : true)) {
        g_httpOtaErr = "unauthorized";
        return;
      }
      if (!requireHttpRole(BleRole::OWNER)) {
        g_httpOtaErr = "insufficient_role";
        return;
      }
      g_httpOtaAuthOk = true;
      g_httpOtaExpectedSha = toLowerAscii(g_http.header("X-FW-SHA256"));
      if (!g_httpOtaExpectedSha.length()) {
        if (g_http.hasArg("sha256")) g_httpOtaExpectedSha = toLowerAscii(g_http.arg("sha256"));
        else if (g_http.hasArg("plain") && g_http.arg("plain").length()) {
          JsonDocument doc;
          if (!deserializeJson(doc, g_http.arg("plain"))) {
            g_httpOtaExpectedSha = toLowerAscii(String(doc["sha256"] | ""));
          }
        }
      }
      if (OTA_LOCAL_REQUIRE_SHA256 && !g_httpOtaExpectedSha.length()) {
        g_httpOtaErr = "sha256_required";
        g_httpOtaAuthOk = false;
        return;
      }
      if (g_httpOtaExpectedSha.length() && !isHex64String(g_httpOtaExpectedSha)) {
        g_httpOtaErr = "bad_sha256";
        g_httpOtaAuthOk = false;
        return;
      }
      if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
        g_httpOtaErr = String("update_begin_") + String((int)Update.getError());
        g_httpOtaAuthOk = false;
        return;
      }
      mbedtls_sha256_init(&g_httpOtaShaCtx);
      if (mbedtls_sha256_starts_ret(&g_httpOtaShaCtx, 0) != 0) {
        Update.abort();
        mbedtls_sha256_free(&g_httpOtaShaCtx);
        g_httpOtaErr = "sha_init_failed";
        g_httpOtaAuthOk = false;
        return;
      }
      g_httpOtaShaInit = true;
      g_httpOtaBytes = 0;
      g_httpOtaLastStartMs = nowMs;
      Serial.printf("[HTTP][OTA] start filename=%s\n", upload.filename.c_str());
    } else if (upload.status == UPLOAD_FILE_WRITE) {
      if (!g_httpOtaAuthOk) return;
      const size_t len = upload.currentSize;
      if (Update.write(upload.buf, len) != len) {
        g_httpOtaErr = String("update_write_") + String((int)Update.getError());
        Update.abort();
        if (g_httpOtaShaInit) {
          mbedtls_sha256_free(&g_httpOtaShaCtx);
          g_httpOtaShaInit = false;
        }
        g_httpOtaAuthOk = false;
        return;
      }
      if (g_httpOtaShaInit &&
          mbedtls_sha256_update_ret(&g_httpOtaShaCtx, upload.buf, len) != 0) {
        g_httpOtaErr = "sha_update_failed";
        Update.abort();
        mbedtls_sha256_free(&g_httpOtaShaCtx);
        g_httpOtaShaInit = false;
        g_httpOtaAuthOk = false;
        return;
      }
      g_httpOtaBytes += len;
    } else if (upload.status == UPLOAD_FILE_END) {
      if (!g_httpOtaAuthOk) return;
      if (!finalizeHttpOtaSha()) {
        g_httpOtaErr = "sha_finish_failed";
        Update.abort();
        g_httpOtaAuthOk = false;
        return;
      }
      if (g_httpOtaExpectedSha.length() &&
          toLowerAscii(g_httpOtaActualSha) != g_httpOtaExpectedSha) {
        g_httpOtaErr = "sha256_mismatch";
        Update.abort();
        g_httpOtaAuthOk = false;
        return;
      }
      if (!Update.end(true)) {
        g_httpOtaErr = String("update_end_") + String((int)Update.getError());
        g_httpOtaAuthOk = false;
        return;
      }
      if (!Update.isFinished()) {
        g_httpOtaErr = "update_not_finished";
        g_httpOtaAuthOk = false;
        return;
      }
      g_httpOtaUploadOk = true;
      g_httpOtaLastSuccessMs = millis();
      Serial.printf("[HTTP][OTA] done bytes=%u sha=%s\n",
                    (unsigned)g_httpOtaBytes,
                    g_httpOtaActualSha.c_str());
    } else if (upload.status == UPLOAD_FILE_ABORTED) {
      if (g_httpOtaShaInit) {
        mbedtls_sha256_free(&g_httpOtaShaCtx);
        g_httpOtaShaInit = false;
      }
      Update.abort();
      g_httpOtaErr = "upload_aborted";
      g_httpOtaAuthOk = false;
      g_httpOtaUploadOk = false;
      Serial.println("[HTTP][OTA] upload aborted");
    }
  });

  // Provision mTLS cert/key/ca (local, pairToken required)

  g_http.onNotFound([](){
    logHttpRequestDiag("not_found");
    if (g_http.method() == HTTP_OPTIONS) {
      setCORS();
      g_http.send(204, "text/plain", "");
      return;
    }
    setCORS();
    g_http.send(404, "application/json", "{\"ok\":false,\"err\":\"not_found\"}");
  });
}

/* =================== Main entry =================== */
static const uint32_t SENSOR_SAMPLE_INTERVAL_MS = 2000;
static const uint32_t AUTO_STEP_INTERVAL_MS    = 4000;
static uint32_t g_lastSensorSampleMs = 0;
static uint32_t g_lastAutoStepMs     = 0;
static uint32_t g_lastTachSampleMs   = 0;
static uint32_t g_lastTachCount      = 0;
static bool updateFloatIfChanged(float& target, float value, float epsilon) {
  if (isnan(value)) return false;
  if (isnan(target) || fabsf(target - value) > epsilon) {
    target = value;
    return true;
  }
  return false;
}

static void factoryReset() {
  Serial.println("[BTN] FACTORY RESET requested");

  // Wi-Fi credentials
  g_savedSsid.clear();
  g_savedPass.clear();
  g_haveCreds = false;

  // Owner / invite / security
  g_ownerHash.clear(); // legacy
  setOwned(false, "factory_reset");
  g_ownerPubKeyB64.clear();
  g_usersJson = "[]";
  g_setupDone = false;
  g_joinInviteId.clear();
  g_joinRole.clear();
  g_joinUntilMs = 0;
  g_apSessionToken.clear();
  g_apSessionNonce.clear();
  g_apSessionUntilMs = 0;
  g_apSessionBound = false;
  g_apSessionBindIp = 0;
  g_apSessionBindUa = 0;

  // Local auth
  // Rotate pairToken on factory reset so previous printed/shared tokens are invalidated.
  g_pairToken = randomHexString(16);
  g_pairTokenTrusted = false;
  g_pairTokenTrustedIp = 0;
  g_cloudUserEnabled = false;
  g_cloudDirty = true;
  g_factoryResetPending = false;
  g_factoryResetDueMs = 0;
  resetIrFactoryResetSequence("factory_reset");
  resetIrSoftRecoverySequence("factory_reset");

  // Cloud identity must be reprovisioned after a factory reset. Keeping a stale
  // device cert/key on SPIFFS can lock the device into permanent MQTT failures.
  if (ensureSpiffsReadyLogged("factory_reset")) {
    spiffsRemoveIfExists(kDeviceCertPath);
    spiffsRemoveIfExists(kDeviceKeyPath);
  }

  // Önce reset durumunu kalıcı yaz: BLE bond temizliği hata verse bile
  // cihaz sonraki boot'ta "unowned" olarak açılabilsin.
  savePrefs();
  persistSecurityState();
  prefs.begin("aac", false);
  prefs.putBool("post_reset_pair_win", true);
  prefs.remove("wifi_pass");
  prefs.remove("wifi_pass_enc");
  prefs.end();

#if ENABLE_BLE
  // NimBLE bond silme çağrısı, BLE host aktif değilken assert'e düşebilir
  // (npl_freertos_mutex_pend: mu->handle). Bu yüzden yalnızca güvenli durumda çağır.
  const esp_bt_controller_status_t btStat = esp_bt_controller_get_status();
  const bool canClearBleBonds =
      g_bleCoreInitDone && (btStat == ESP_BT_CONTROLLER_STATUS_ENABLED);
  if (canClearBleBonds) {
    Serial.println("[BTN] Clearing BLE bonds");
    NimBLEDevice::deleteAllBonds();
  } else {
    Serial.printf("[BTN] Skip BLE bond clear (bleCoreInitDone=%d btStatus=%d)\n",
                  g_bleCoreInitDone ? 1 : 0,
                  (int)btStat);
  }
#endif

  Serial.println("[BTN] Factory reset complete, restarting...");
  delay(250);
  ESP.restart();
}

static void pollButton(uint32_t nowMs) {
  static bool     prev = false;
  static uint32_t pressStartMs = 0;
  static uint32_t lastPollMs = 0;

  bool pressed = (digitalRead(PIN_BTN) == LOW); // varsayılan: pull-up, active-low

  if (lastPollMs != 0 &&
      (uint32_t)(nowMs - lastPollMs) > BUTTON_POLL_MAX_GAP_MS) {
    // MQTT/TLS gibi bloklarda tek örnekten sahte long-press üretme.
    prev = pressed;
    pressStartMs = pressed ? nowMs : 0;
    lastPollMs = nowMs;
    return;
  }
  lastPollMs = nowMs;

  if (pressed && !prev) {
    pressStartMs = nowMs;
  } else if (!pressed && prev) {
    uint32_t heldMs = nowMs - pressStartMs;
    if (heldMs >= BTN_RESET_MS) {
      factoryReset();
      return;
    } else if (heldMs >= BTN_PAIR_MS) {
      const uint32_t activeRecoveryMs = softRecoveryRemainingMs(nowMs);
      if (activeRecoveryMs > 0) {
        Serial.printf("[BTN] Pair/join ignored: recovery already active remaining=%u ms\n",
                      (unsigned)activeRecoveryMs);
        prev = pressed;
        return;
      }
      Serial.printf("[BTN] Pair/join window request, held=%u ms\n",
                    (unsigned)heldMs);
      // Online cihazda startAP() yıkıcıdır; STA'yı düşürmeden recovery AP aç.
      if ((WiFi.status() == WL_CONNECTED) || g_haveCreds) {
        ensureSoftApUp(nowMs);
      } else {
        startAP();
      }
      g_apSessionToken = randomHexString(8);
      g_apSessionNonce = randomHexString(8);
      g_apSessionUntilMs = nowMs + 60000UL; // 60s
      g_apSessionOpenedWithQr = true; // trusted session (physical presence)
      g_apSessionBound = false;
      g_apSessionBindIp = 0;
      g_apSessionBindUa = 0;
      Serial.printf("[BTN] AP session opened ttl_ms=%u\n",
                    (unsigned)60000UL);
      // Aynı anda BLE pairing penceresini de aç (ör. 60 sn).
      openPairingWindow(60000UL);
      // If the device is already owned, also open an owner-rotation window so the
      // factory label QR can re-claim ownership with physical presence.
      if (g_ownerExists) {
        openOwnerRotateWindow(60000UL);
      }
    }
  }

  prev = pressed;
}

static void initPinsAndPwm() {
  if (g_relayCfg.pinMain != 255) pinMode(g_relayCfg.pinMain, OUTPUT);
  if (g_relayCfg.pinLight != 255) pinMode(g_relayCfg.pinLight, OUTPUT);
  if (g_relayCfg.pinIon != 255) pinMode(g_relayCfg.pinIon, OUTPUT);
  if (g_relayCfg.pinWater != 255) pinMode(g_relayCfg.pinWater, OUTPUT);
  relayWrite(g_relayCfg.pinMain, false);
  relayWrite(g_relayCfg.pinLight, false);
  relayWrite(g_relayCfg.pinIon, false);
  relayWrite(g_relayCfg.pinWater, false);

  pinMode(PIN_FAN_PWM, OUTPUT);
  if (PIN_FAN_AUX_EN != 255) {
    pinMode(PIN_FAN_AUX_EN, OUTPUT);
    digitalWrite(PIN_FAN_AUX_EN, FAN_AUX_EN_ACTIVE_HIGH ? LOW : HIGH);
  }
  pinMode(PIN_RGB_R, OUTPUT);
  pinMode(PIN_RGB_G, OUTPUT);
  pinMode(PIN_RGB_B, OUTPUT);
  pinMode(PIN_GP2Y_LED, OUTPUT);
  if (GP2Y_LED_ALWAYS_ON) gp2y_led_on();
  else gp2y_led_off();

  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);

  pinMode(PIN_FAN_TACH, FAN_TACH_USE_PULLUP ? INPUT_PULLUP : INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_FAN_TACH), onTach, FAN_TACH_EDGE);
#if FAN_DEBUG_LOG
  Serial.printf("[FAN] pwmPin=%u tachPin=%u auxEnPin=%u mirrorAltPin=%u mirror=%d ppr=%u edge=%d edgeFactor=%u pullup=%d invert=%d auxActiveHigh=%d\n",
                (unsigned)PIN_FAN_PWM,
                (unsigned)PIN_FAN_TACH,
                (unsigned)PIN_FAN_AUX_EN,
                (unsigned)PIN_FAN_PWM_ALT,
                (int)FAN_PWM_MIRROR_ALT_ENABLE,
                (unsigned)FAN_TACH_PPR,
                (int)FAN_TACH_EDGE,
                (unsigned)FAN_TACH_EDGE_FACTOR,
                FAN_TACH_USE_PULLUP ? 1 : 0,
                FAN_PWM_INVERTED ? 1 : 0,
                FAN_AUX_EN_ACTIVE_HIGH ? 1 : 0);
#endif
#if ENABLE_IR_RX_DEBUG
  pinMode(PIN_IR_RX, INPUT);
  g_irLastLevel = (uint8_t)digitalRead(PIN_IR_RX);
  g_irLastEdgeUs = micros();
  attachInterrupt(digitalPinToInterrupt(PIN_IR_RX), onIrRxEdge, CHANGE);
  Serial.printf("[IR] ready pin=%u\n", (unsigned)PIN_IR_RX);
#endif
  pinMode(PIN_ADDR_LED_DATA, OUTPUT);
  digitalWrite(PIN_ADDR_LED_DATA, LOW);
#if USE_ADDR_LED_PROTOCOL
  g_framePixels.begin();
  g_framePixels.clear();
  g_framePixels.show();
  Serial.printf("[FRAME] addrLed pin=%u proto=WS2812 count=%u\n",
                (unsigned)PIN_ADDR_LED_DATA,
                (unsigned)g_framePixels.numPixels());
#else
  Serial.printf("[FRAME] addrLed pin=%u proto=disabled\n",
                (unsigned)PIN_ADDR_LED_DATA);
#endif

  ledcSetup(CH_FAN, PWM_FREQ_FAN, PWM_RES_BITS);
  ledcAttachPin(PIN_FAN_PWM, CH_FAN);
  if (FAN_PWM_MIRROR_ALT_ENABLE) {
    ledcSetup(CH_FAN_ALT, PWM_FREQ_FAN, PWM_RES_BITS);
    ledcAttachPin(PIN_FAN_PWM_ALT, CH_FAN_ALT);
  }
  ledcWrite(CH_FAN, 0);
  if (FAN_PWM_MIRROR_ALT_ENABLE) {
    ledcWrite(CH_FAN_ALT, 0);
  }

  ledcSetup(CH_R, PWM_FREQ_LED, PWM_RES_BITS);
  ledcAttachPin(PIN_RGB_R, CH_R);
  ledcSetup(CH_G, PWM_FREQ_LED, PWM_RES_BITS);
  ledcAttachPin(PIN_RGB_G, CH_G);
  ledcSetup(CH_B, PWM_FREQ_LED, PWM_RES_BITS);
  ledcAttachPin(PIN_RGB_B, CH_B);
  _writeRGB(0, 0, 0);
}

static void pollSensorsIfDue(uint32_t nowMs) {
  if (nowMs - g_lastSensorSampleMs < SENSOR_SAMPLE_INTERVAL_MS) return;
  g_lastSensorSampleMs = nowMs;

  bool changed = false;
  float pm25 = NAN;
  float temp = NAN;
  float rh   = NAN;
  bool senOk = sen55Read(pm25, temp, rh);
  if (senOk) {
    changed = true; // SEN55 updates PM/VOC fields internally
    changed |= updateFloatIfChanged(app.tempC, temp, 0.2f);
    changed |= updateFloatIfChanged(app.humPct, rh, 0.5f);
  }

  // DHT11'i her döngüde ayrı olarak da örnekle; ancak SEN55
  // değerlerinden tamamen bağımsız tut (farklı ortamı ölçüyor).
  float dhtT = app.dhtTempC;
  float dhtH = app.dhtHumPct;
  sampleDHT(dhtT, dhtH);

  // BME688 AI kanalı:
  //  - Eğer BSEC2 aktifse, callback içinden app.ai* alanları zaten güncelleniyor.
  //  - BSEC2 başlatılamadıysa klasik sürücüden okuma yap.
  if (!g_bsecOk) {
    float aiT = NAN, aiH = NAN, aiP = NAN, aiGas = NAN;
    if (bmeReadClassic(aiT, aiH, aiP, aiGas)) {
      bool aiChanged = false;
      aiChanged |= updateFloatIfChanged(app.aiTempC, aiT, 0.2f);
      aiChanged |= updateFloatIfChanged(app.aiHumPct, aiH, 0.5f);
      aiChanged |= updateFloatIfChanged(app.aiPressure, aiP, 0.5f);
      aiChanged |= updateFloatIfChanged(app.aiGasKOhm, aiGas, 0.5f);
      if (aiChanged) changed = true;
    }
  } else {
    // BSEC verisi callback'te güncellendi; burada ekstra bir şey yapmaya gerek yok.
  }

  // --- Fan RPM hesaplama (tachPulses -> g_lastRPM) ---
  // Effective PPR can increase when counting both edges (CHANGE mode).
  const uint8_t pulsesPerRev = (uint8_t)(FAN_TACH_PPR * FAN_TACH_EDGE_FACTOR);
  uint32_t dtMs = nowMs - g_lastTachSampleMs;
  if (dtMs >= FAN_RPM_SAMPLE_WINDOW_MS) {
    uint32_t pulses = tachPulses - g_lastTachCount;
    const uint32_t rawRpm = calcRPM(pulses, dtMs, pulsesPerRev);
    if (pulses == 0) {
      if (g_rpmZeroWindows < 255U) g_rpmZeroWindows++;
      if (g_rpmZeroWindows >= FAN_RPM_ZERO_HOLD_WINDOWS) {
        g_rpmFiltered = 0;
      }
    } else {
      g_rpmZeroWindows = 0;
      g_rpmFiltered = (g_rpmFiltered == 0)
                        ? rawRpm
                        : (uint32_t)(((uint64_t)g_rpmFiltered * 3ULL + rawRpm) / 4ULL);
    }
    g_lastRPM = g_rpmFiltered;
#if TACH_PIN12_DEBUG_LOG
    static uint32_t s_lastTachDbgMs = 0;
    if (nowMs - s_lastTachDbgMs >= 2000U) {
      s_lastTachDbgMs = nowMs;
      Serial.printf("[TACH12] pin=%u level=%d pulses=%lu dt=%lu raw=%lu rpm=%lu\n",
                    (unsigned)PIN_FAN_TACH,
                    digitalRead(PIN_FAN_TACH),
                    (unsigned long)pulses,
                    (unsigned long)dtMs,
                    (unsigned long)rawRpm,
                    (unsigned long)g_lastRPM);
    }
#endif
    g_lastTachCount = tachPulses;
    g_lastTachSampleMs = nowMs;
  }

  // Kısa süreli history buffer'ına örnek ekle
  historyPushSample(nowMs);

  if (changed) {
    g_forceAutoStep = true;
  }
}

static void runAutoControlIfNeeded(uint32_t nowMs) {
  if (app.mode != FAN_AUTO) {
    g_lastAutoStepMs = nowMs;
    return;
  }
  if (!g_forceAutoStep && (nowMs - g_lastAutoStepMs) < AUTO_STEP_INTERVAL_MS) return;
  autoControlStep(g_forceAutoStep);
  g_forceAutoStep = false;
  g_lastAutoStepMs = nowMs;
}


void setup() {
  Serial.begin(115200);
  delay(200);
  // No-sleep test window (BLE must be off to allow WIFI_PS_NONE)
#if WIFI_FORCE_NO_SLEEP
  g_noSleepTestActive = true;
  g_noSleepTestUntilMs = millis() + WIFI_NO_SLEEP_TEST_MS;
  g_wifiSleepDisabledOnce = false;
  g_wifiSleepBlockLogged = false;
#if ENABLE_BLE
  Serial.printf("[TEST] WiFi no-sleep test %lus: BLE policy-managed\n",
                (unsigned long)(WIFI_NO_SLEEP_TEST_MS / 1000UL));
#else
  Serial.printf("[TEST] WiFi no-sleep test %lus\n",
                (unsigned long)(WIFI_NO_SLEEP_TEST_MS / 1000UL));
#endif
#endif
  Serial.println();
  Serial.printf("[BOOT] %s starting...\n", deviceBrandName().c_str());
  Serial.printf("[BUILD] fw=%s schema=%d built=%s %s\n",
                FW_VERSION, (int)SCHEMA_VERSION, __DATE__, __TIME__);
  Serial.printf("[BUILD] product=%s hwRev=%s boardRev=%s channel=%s\n",
                DEVICE_PRODUCT, DEVICE_HW_REV, DEVICE_BOARD_REV, DEVICE_FW_CHANNEL);
  {
    String rawProduct = String(DEVICE_PRODUCT);
    rawProduct.trim();
    rawProduct.toLowerCase();
    const String normalizedProduct = deviceProductSlug();
    if (rawProduct != normalizedProduct) {
      Serial.printf("[BUILD] normalized product=%s (from %s)\n",
                    normalizedProduct.c_str(),
                    rawProduct.c_str());
    }
  }
  
  // Device ID'yi log'la (her cihaz için unique)
  const String& id6 = getDeviceId6();
  const String fullId12 = fullChipId12();
  Serial.printf("[DEVICE] ID6 (short): %s\n", id6.c_str());
  Serial.printf("[DEVICE] ID12 (full): %s\n", fullId12.c_str());
  Serial.printf("[IOT] deviceId6=%s\n", id6.c_str());

  bleReleaseClassicEarlyOnce(); // release Classic BT heap before Wi-Fi/coex starts

  initRelayRoutingConfig();
  initPinsAndPwm();
  randomSeed(esp_random());

  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(I2C_BUS_HZ);
  dht.begin();
  // Önce BSEC2 (AI) dene; başarısız olursa klasik sürücüye düş.
  bsecInit();
  if (!g_bsecOk) {
    bmeInit();
  }

  WiFi.onEvent(onWiFiEvent);
#if WIFI_EVENT_DEBUG
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t){
    Serial.printf("[WiFi][EVT] %d\n", (int)event);
  });
#endif
#if ENABLE_BLE
  g_bleDesiredOn = true; // boot with BLE available for pairing/provisioning
#if WIFI_FORCE_NO_SLEEP
  // Hybrid: allow BLE briefly only when recovery is needed at boot.
  g_bleBootWindowActive = false;
  g_bleBootUntilMs = 0;
  g_bleForceOff = false;
#endif
#endif
  applyWifiPowerSave(); // prime desired sleep mode before Wi-Fi brings interfaces up

  loadPrefs();
  if (g_postResetOpenRecoveryAtBoot) {
    prefs.begin("aac", false);
    prefs.putBool("post_reset_pair_win", false);
    prefs.end();
    Serial.println("[RECOVERY] post-reset recovery window requested");
  }
  const bool suppressRecoveryAtBoot =
      (((!g_ownerExists) || (g_ownerExists && g_haveCreds)) &&
       !g_postResetOpenRecoveryAtBoot);
  g_recoverySuppressed = suppressRecoveryAtBoot;
#if ENABLE_BLE
  if (suppressRecoveryAtBoot) {
    g_bleDesiredOn = false;
    g_bleForceOff = true;
    g_bleBootWindowActive = false;
    g_bleBootUntilMs = 0;
    Serial.println("[RECOVERY] boot suppressed (locked by policy)");
  } else {
#if WIFI_FORCE_NO_SLEEP
    g_bleDesiredOn = true;
    g_bleBootWindowActive = true;
    g_bleBootUntilMs = millis() + BLE_BOOT_WINDOW_MS;
    g_bleForceOff = false;
#endif
  }
#endif
#if BOOT_FORCE_OUTPUTS_OFF
  app.masterOn = false;
  app.lightOn = false;
  app.cleanOn = false;
  app.ionOn = false;
  app.rgbOn = false;
  Serial.println("[BOOT] outputs forced OFF");
#endif
  cloudInit();
  Serial.printf("[OWNER] boot owner_exists=%s\n", g_ownerExists ? "true" : "false");
  Serial.println("[OWNER] setup user loaded");
  Serial.println("[OWNER] setup password hash loaded");
  
  // NOTE: QR bilgisi ensureAuthDefaults() içinde logQrIfAllowed() ile log'lanır (her boot'ta)
  // NOTE: WiFi AP bilgileri startAP() içinde logApPassIfAllowed() ile log'lanır
  if (g_ownerPubKeyB64.length()) {
    Serial.printf("[OWNER] boot owner_pubkey_b64_len=%u\n", (unsigned)g_ownerPubKeyB64.length());
  }
  setFanPercent(app.fanPercent);
  applyRelays();
  applyRgb();

  // IR-first onboarding by default. Exception: post-factory-reset one-shot recovery window.
  if (g_postResetOpenRecoveryAtBoot) {
    startSoftRecoveryWindow(millis(), "post_factory_reset");
    g_postResetOpenRecoveryAtBoot = false;
  } else if (!g_ownerExists) {
    Serial.println("[PAIR] unowned boot locked; open IR recovery window to pair");
  }

  sen55Init();

  // Kullanıcı butonu (varsa) için pull-up giriş
  pinMode(PIN_BTN, INPUT_PULLUP);

#if ENABLE_BLE
  if (!g_bleForceOff) {
    bleCoreInit();  // bring up BLE stack before Wi-Fi init to keep coex stable
  }
#endif

  if (recoveryTransportsAllowed(millis())) {
    startAP();
  }
  if (!AP_ONLY) {
    if (g_haveCreds) {
      trySTA();
    } else {
      Serial.println("[WiFi] STA skipped (no stored credentials)");
    }
    WiFi.setAutoReconnect(true);
  }

#if ENABLE_BLE
  if (!g_bleForceOff) {
    bleStartAdvertising();
  }
#endif

  uint32_t now = millis();
  g_lastSensorSampleMs = now - SENSOR_SAMPLE_INTERVAL_MS;
  g_lastAutoStepMs = now - AUTO_STEP_INTERVAL_MS;
  g_forceAutoStep = true;


  Serial.println("[BOOT] Setup complete");
}

void loop() {
  uint32_t now = millis();
  static uint32_t s_lastLoopTickMs = 0;
  if (s_lastLoopTickMs != 0) {
    const uint32_t loopDeltaMs = now - s_lastLoopTickMs;
    if (loopDeltaMs >= 2000UL) {
      Serial.printf("[LOOP] lag=%lu ms lastPhase=%s wifi=%d mqtt=%d heap=%u\n",
                    (unsigned long)loopDeltaMs,
                    g_loopPhase ? g_loopPhase : "unknown",
                    (int)WiFi.status(),
                    g_mqtt.connected() ? 1 : 0,
                    (unsigned)ESP.getFreeHeap());
    }
  }
  s_lastLoopTickMs = now;
  processPendingFactoryReset(now);
  g_loopPhase = "frame_show";
  updateFanModeShow(now);
  updateAutoSnakeShow(now);
  updateCleanSnakeShow(now);
  if (g_noSleepTestActive && !WIFI_FORCE_NO_SLEEP &&
      (int32_t)(now - g_noSleepTestUntilMs) >= 0) {
    g_noSleepTestActive = false;
#if ENABLE_BLE
    g_bleForceOff = false;
    Serial.println("[TEST] WiFi no-sleep test ended; BLE re-enabled");
    applyWifiPowerSave(); // re-apply sleep policy now that BLE is back
    bleStartAdvertising();
#else
    Serial.println("[TEST] WiFi no-sleep test ended");
    applyWifiPowerSave();
#endif
  }
  g_loopPhase = "loop";
  g_loopPhase = "http";
  g_http.handleClient();
#if ENABLE_TCP_CMD
  g_loopPhase = "tcp";
  handleTcpServer();
#endif
  if (g_bsecOk) {
#if !defined(DISABLE_BSEC) || (DISABLE_BSEC == 0)
    g_loopPhase = "bsec";
    if (!g_bsec.run()) {
#if BSEC_RUNTIME_STATUS_LOG
      logBsecStatus("run", g_bsec);
#endif
    }
#endif
  }
  g_loopPhase = "sensors";
  pollSensorsIfDue(now);
#if ENABLE_IR_RX_DEBUG
  g_loopPhase = "ir";
  processIrRxDebug();
#endif
  g_loopPhase = "waqi";
  pollWaqiIfDue(now);
  g_loopPhase = "auto";
  runAutoControlIfNeeded(now);
  g_loopPhase = "humidity";
  runAutoHumidityControl(now);
  g_loopPhase = "water";
  runWaterScheduler(now);
  g_loopPhase = "ntp";
  pollNtpSync(now);
  g_loopPhase = "sta_retry";
  maybeRetryStaConnect(now);
  g_loopPhase = "cloud";
  cloudLoop(now);
  g_loopPhase = "ota_pending";
  handlePendingOtaDecision();
  g_loopPhase = "conn";
  updateConnectivityStability(now);
  // Event-driven alerts (publish only on transitions; cost-saving)
  if (app.filterAlert && !g_lastFilterAlert) {
    queueAlert("filter", "warning", "Filter replacement recommended");
  }
  g_lastFilterAlert = app.filterAlert;
#if ENABLE_BLE
  manageBleByConnectivity(now);
  if (!g_bleForceOff) {
    g_loopPhase = "ble_adv";
    bleStartAdvertising();
    g_loopPhase = "ble_claim";
    bleProcessClaimPending(now);
    g_loopPhase = "ble_auth";
    bleProcessAuthPending(now);
    g_loopPhase = "ble_notify";
    bleMaybeNotifyStatusPeriodic(now);
    g_loopPhase = "ble_defer";
    bleProcessDeferredNotify(now);
    // Hard gate: if the peer doesn't authenticate shortly after connect, drop it.
    if (g_bleConnHandle != BLE_HS_CONN_HANDLE_NONE &&
        !g_bleAuthed &&
        g_bleAuthDeadlineMs != 0 &&
        (int32_t)(now - g_bleAuthDeadlineMs) >= 0) {
      Serial.println("[BLE] auth timeout -> disconnect");
      if (g_bleServer) {
        g_bleServer->disconnect(g_bleConnHandle);
      }
      g_bleAuthDeadlineMs = 0;
    }
  }
#endif
  // AP bring-up requested from BLE command path.
  // Process it outside BLE policy gating so AP setup cannot be skipped when BLE
  // is force-off right after disconnect.
  if (g_bleApStartPending) {
    g_bleApStartPending = false;
    Serial.println("[BLE][AP] deferred startAP (forced)");
    startAP();
  }
  g_loopPhase = "ap";
  maybeManageApByConnectivity(now);
  g_loopPhase = "sta";
  // Otomatik sulama süresi bittiyse 33 numaralı röleyi kapat
  if (g_waterRelayOn && g_waterRelayOffAtMs != 0 &&
      (int32_t)(now - g_waterRelayOffAtMs) >= 0) {
    g_waterRelayOn      = false;
    g_waterRelayOffAtMs = 0;
    applyRelays();
  }
  // Doa nem tabanlı otomatik sulamayı çalıştır
  g_loopPhase = "doa";
  runDoaHumWatering(now);
  g_loopPhase = "button";
  pollButton(now);
  g_loopPhase = "buzzer";
  serviceBuzzer(now);
  g_loopPhase = "idle";
  delay(1);
}
