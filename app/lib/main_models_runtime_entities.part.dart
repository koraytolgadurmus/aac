part of 'main.dart';

class _PlanItem {
  bool enabled;
  TimeOfDay start;
  TimeOfDay end;
  int mode; // 0..5
  int fanPercent; // kept for FW: we auto-fill from mode
  bool lightOn;
  bool ionOn;
  bool rgbOn; // NEW
  // Otomatik nem için (plan bazında)
  bool autoHumEnabled;
  int autoHumTarget; // yüzde

  _PlanItem({
    required this.enabled,
    required this.start,
    required this.end,
    required this.mode,
    required this.fanPercent,
    required this.lightOn,
    required this.ionOn,
    required this.rgbOn,
    required this.autoHumEnabled,
    required this.autoHumTarget,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'startMin': start.hour * 60 + start.minute,
      'endMin': end.hour * 60 + end.minute,
      'mode': mode,
      'fanPercent': _pctForMode(mode),
      'lightOn': lightOn,
      'ionOn': ionOn,
      'rgbOn': rgbOn, // NEW
      'autoHumEnabled': autoHumEnabled,
      'autoHumTarget': autoHumTarget,
    };
  }

  static _PlanItem fromJson(Map<String, dynamic> j) => _PlanItem(
    enabled: j['enabled'] ?? true,
    start: _minToTod((j['startMin'] ?? 0) as int),
    end: _minToTod((j['endMin'] ?? 0) as int),
    mode: (j['mode'] ?? 1) as int,
    fanPercent: _pctForMode((j['mode'] ?? 1) as int),
    lightOn: (j['lightOn'] ?? false) as bool,
    ionOn: (j['ionOn'] ?? false) as bool,
    rgbOn: (j['rgbOn'] ?? false) as bool, // NEW
    autoHumEnabled: (j['autoHumEnabled'] ?? false) as bool,
    autoHumTarget: (j['autoHumTarget'] ?? 55) as int,
  );

  static TimeOfDay _minToTod(int m) =>
      TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  static int _pctForMode(int mode) {
    switch (mode) {
      case 0:
        return 20;
      case 1:
        return 35;
      case 2:
        return 50;
      case 3:
        return 65;
      case 4:
        return 100;
      default:
        return 35;
    }
  }
}

class _SavedDevice {
  _SavedDevice({
    required this.id,
    required this.brand,
    this.suffix = '',
    required this.baseUrl,
    this.lastIp,
    this.thingName,
    this.mdnsHost,
    this.doaWaterDurationMin,
    this.doaWaterIntervalHr,
    this.doaWaterAutoEnabled,
    this.pairToken,
    this.cloudLinked = false,
    this.cloudEnabledLocal = false,
    this.cloudRole,
    this.cloudSource,
    this.waqiName,
    this.waqiLat,
    this.waqiLon,
    this.waqiCityName,
    this.waqiAqi,
    this.waqiPm25,
    this.waqiTempC,
    this.waqiHumPct,
    this.waqiWindKph,
    this.waqiUpdatedAtMs,
  });

  String id;
  String brand; // e.g. ArtAirCleaner, Doa, Boom
  String suffix; // optional user label (max ~6 chars used in UI)
  String baseUrl;
  String? lastIp;
  String? thingName; // Cloud IoT thing name (aac-<id6>)
  String? mdnsHost; // Local mDNS host (artair-<id6>)
  String? pairToken;
  bool cloudLinked;
  bool cloudEnabledLocal;
  String? cloudRole;
  String? cloudSource;
  String? waqiName;
  double? waqiLat;
  double? waqiLon;
  String? waqiCityName;
  double? waqiAqi;
  double? waqiPm25;
  double? waqiTempC;
  double? waqiHumPct;
  double? waqiWindKph;
  int? waqiUpdatedAtMs;
  double? doaWaterDurationMin;
  double? doaWaterIntervalHr;
  bool? doaWaterAutoEnabled;

  String get displayName {
    final trimmedSuffix = suffix.trim();
    if (trimmedSuffix.isEmpty) return brand;
    return '$brand $trimmedSuffix';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'brand': brand,
    'suffix': suffix,
    'baseUrl': baseUrl,
    'lastIp': lastIp,
    'thingName': thingName,
    'mdnsHost': mdnsHost,
    'pairToken': pairToken,
    'cloudLinked': cloudLinked,
    'cloudEnabledLocal': cloudEnabledLocal,
    'cloudRole': cloudRole,
    'cloudSource': cloudSource,
    'waqiName': waqiName,
    'waqiLat': waqiLat,
    'waqiLon': waqiLon,
    'waqiCityName': waqiCityName,
    'waqiAqi': waqiAqi,
    'waqiPm25': waqiPm25,
    'waqiTempC': waqiTempC,
    'waqiHumPct': waqiHumPct,
    'waqiWindKph': waqiWindKph,
    'waqiUpdatedAtMs': waqiUpdatedAtMs,
    'doaWaterDurationMin': doaWaterDurationMin,
    'doaWaterIntervalHr': doaWaterIntervalHr,
    'doaWaterAutoEnabled': doaWaterAutoEnabled,
  };

  static _SavedDevice fromJson(Map<String, dynamic> j) {
    final rawId = (j['id'] ?? '') as String;
    final storedThing = (j['thingName'] as String?)?.trim();
    final storedMdns = (j['mdnsHost'] as String?)?.trim();
    return _SavedDevice(
      id: rawId,
      brand: (j['brand'] ?? kDefaultDeviceBrand) as String,
      suffix: (j['suffix'] ?? '') as String,
      baseUrl: (j['baseUrl'] ?? 'http://192.168.4.1') as String,
      lastIp: (j['lastIp'] as String?)?.trim(),
      thingName: (storedThing != null && storedThing.isNotEmpty)
          ? storedThing
          : thingNameFromAny(rawId),
      mdnsHost: (storedMdns != null && storedMdns.isNotEmpty)
          ? storedMdns
          : mdnsHostFromAny(rawId),
      pairToken: (j['pairToken'] as String?)?.trim(),
      cloudLinked: (j['cloudLinked'] ?? false) == true,
      cloudEnabledLocal: (j['cloudEnabledLocal'] ?? false) == true,
      cloudRole: (j['cloudRole'] as String?)?.trim(),
      cloudSource: (j['cloudSource'] as String?)?.trim(),
      waqiName: (j['waqiName'] as String?)?.trim(),
      waqiLat: (j['waqiLat'] as num?)?.toDouble(),
      waqiLon: (j['waqiLon'] as num?)?.toDouble(),
      waqiCityName: (j['waqiCityName'] as String?)?.trim(),
      waqiAqi: (j['waqiAqi'] as num?)?.toDouble(),
      waqiPm25: (j['waqiPm25'] as num?)?.toDouble(),
      waqiTempC: (j['waqiTempC'] as num?)?.toDouble(),
      waqiHumPct: (j['waqiHumPct'] as num?)?.toDouble(),
      waqiWindKph: (j['waqiWindKph'] as num?)?.toDouble(),
      waqiUpdatedAtMs: (j['waqiUpdatedAtMs'] as num?)?.toInt(),
      doaWaterDurationMin: (j['doaWaterDurationMin'] as num?)?.toDouble(),
      doaWaterIntervalHr: (j['doaWaterIntervalHr'] as num?)?.toDouble(),
      doaWaterAutoEnabled: (j['doaWaterAutoEnabled'] as bool?),
    );
  }
}
