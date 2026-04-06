part of 'main.dart';

// Unified device model parsed from cloud/local/BLE payloads.
class DeviceState {
  bool masterOn, lightOn, cleanOn, ionOn;
  bool autoHumEnabled;
  int autoHumTarget; // 30..70
  int mode, fanPercent;
  int indoorScore;
  int r, g, b;
  bool rgbOn;
  int rgbBrightness; // 0..100
  double tempC;
  double hum;
  double dhtTempC;
  double dhtHum;
  bool? waterAutoEnabled;
  int? waterDurationMin;
  int? waterIntervalMin;
  bool? waterManual;
  bool? waterHumAutoEnabled;
  double pm25;
  double vocIndex;
  double noxIndex;
  // BME688 (AI) classic channels
  double aiTempC;
  double aiHum;
  double aiPressure;
  double aiGasKOhm;
  double aiIaq;
  double aiCo2Eq;
  double aiBVocEq;
  int? envSeq;
  int rpm;
  String fanReason;
  bool odorBoostActive;
  List<int> calibRPM;
  bool filterAlert;
  // OTA
  bool otaAvailable;
  String otaNewVersion;
  bool otaPending;
  String otaJobId;
  bool otaRequiresUserApproval;
  String fwVersion;
  String otaFirmwareUrl;
  String otaSha256;
  String otaMinVersion;
  String deviceProduct;
  String deviceHwRev;
  String deviceBoardRev;
  String deviceFwChannel;
  String networkApSsid;
  String networkMdnsHost;
  // Dış ortam (şehir) hava durumu / hava kalitesi
  double cityAqi;
  double cityPm25;
  double cityTempC;
  double cityHum;
  double cityWindKph;
  String cityName;
  String cityDesc;
  // Owner / davet durumu
  bool ownerSetupDone;
  bool ownerExists;
  bool joinActive;
  bool pairingWindowActive;
  bool apSessionActive;
  bool softRecoveryActive;
  int softRecoveryRemainingSec;
  String authRole;
  List<InvitedUser> invitedUsers;
  // Cloud
  bool cloudEnabled;
  bool cloudMqttConnected;
  String cloudMqttState;
  int cloudMqttStateCode;
  String cloudState;
  int cloudStateCode;
  String cloudStateReason;
  String cloudIotEndpoint;
  int cloudStateUpdatedAtMs;
  int cloudStateSinceMs;
  int cloudLastDesiredPingMs;
  int cloudLastDesiredClientTsMs;
  int sampleTsMs;
  bool cloudClaimed;
  DeviceState({
    required this.masterOn,
    required this.lightOn,
    required this.cleanOn,
    required this.ionOn,
    required this.autoHumEnabled,
    required this.autoHumTarget,
    required this.mode,
    required this.fanPercent,
    required this.indoorScore,
    required this.r,
    required this.g,
    required this.b,
    required this.rgbOn,
    required this.rgbBrightness,
    required this.tempC,
    required this.hum,
    required this.dhtTempC,
    required this.dhtHum,
    this.waterAutoEnabled,
    this.waterDurationMin,
    this.waterIntervalMin,
    this.waterManual,
    this.waterHumAutoEnabled,
    required this.pm25,
    required this.vocIndex,
    required this.noxIndex,
    required this.aiTempC,
    required this.aiHum,
    required this.aiPressure,
    required this.aiGasKOhm,
    required this.aiIaq,
    required this.aiCo2Eq,
    required this.aiBVocEq,
    this.envSeq,
    required this.rpm,
    required this.fanReason,
    required this.odorBoostActive,
    required this.calibRPM,
    required this.filterAlert,
    required this.cityAqi,
    required this.cityPm25,
    required this.cityTempC,
    required this.cityHum,
    required this.cityWindKph,
    required this.cityName,
    required this.cityDesc,
    required this.otaAvailable,
    required this.otaNewVersion,
    required this.otaPending,
    required this.otaJobId,
    required this.otaRequiresUserApproval,
    required this.fwVersion,
    required this.otaFirmwareUrl,
    required this.otaSha256,
    required this.otaMinVersion,
    required this.deviceProduct,
    required this.deviceHwRev,
    required this.deviceBoardRev,
    required this.deviceFwChannel,
    required this.networkApSsid,
    required this.networkMdnsHost,
    required this.ownerSetupDone,
    required this.ownerExists,
    required this.joinActive,
    required this.pairingWindowActive,
    required this.apSessionActive,
    required this.softRecoveryActive,
    required this.softRecoveryRemainingSec,
    required this.authRole,
    required this.invitedUsers,
    required this.cloudEnabled,
    required this.cloudMqttConnected,
    required this.cloudMqttState,
    required this.cloudMqttStateCode,
    required this.cloudState,
    required this.cloudStateCode,
    required this.cloudStateReason,
    required this.cloudIotEndpoint,
    required this.cloudStateUpdatedAtMs,
    required this.cloudStateSinceMs,
    required this.cloudLastDesiredPingMs,
    required this.cloudLastDesiredClientTsMs,
    required this.sampleTsMs,
    required this.cloudClaimed,
  });

  factory DeviceState.fromJson(Map<String, dynamic> j) {
    // Support legacy flat JSON, structured /status, and compact BLE payloads (short keys).
    Map<String, dynamic> status = (j['status'] is Map<String, dynamic>)
        ? (j['status'] as Map<String, dynamic>)
        : <String, dynamic>{};
    Map<String, dynamic> fan = (j['fan'] is Map<String, dynamic>)
        ? (j['fan'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final filter = (j['filter'] is Map<String, dynamic>)
        ? j['filter'] as Map<String, dynamic>
        : <String, dynamic>{};
    final ui = (j['ui'] is Map<String, dynamic>)
        ? j['ui'] as Map<String, dynamic>
        : <String, dynamic>{};
    Map<String, dynamic> env = (j['env'] is Map<String, dynamic>)
        ? (j['env'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final city = (j['city'] is Map<String, dynamic>)
        ? j['city'] as Map<String, dynamic>
        : <String, dynamic>{};
    final network = (j['network'] is Map<String, dynamic>)
        ? j['network'] as Map<String, dynamic>
        : <String, dynamic>{};
    final capabilities = (j['capabilities'] is Map<String, dynamic>)
        ? j['capabilities'] as Map<String, dynamic>
        : <String, dynamic>{};
    final meta = (j['meta'] is Map<String, dynamic>)
        ? j['meta'] as Map<String, dynamic>
        : const <String, dynamic>{};
    Map<String, dynamic> owner = (j['owner'] is Map<String, dynamic>)
        ? (j['owner'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    Map<String, dynamic> join = (j['join'] is Map<String, dynamic>)
        ? (j['join'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    final auth = (j['auth'] is Map<String, dynamic>)
        ? j['auth'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final claim = (j['claim'] is Map<String, dynamic>)
        ? j['claim'] as Map<String, dynamic>
        : const <String, dynamic>{};
    Map<String, dynamic> cloud = (j['cloud'] is Map<String, dynamic>)
        ? (j['cloud'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    // Compact BLE format:
    // o: owner {sd, ho, pw}, j: join {a, ap}, s: status {m,l,c,i,mo,fp}, e: env {t,h,p,v,n}, f: fan {r}
    if (j['s'] is Map<String, dynamic>) {
      final s = j['s'] as Map<String, dynamic>;
      status = <String, dynamic>{
        'masterOn': s['m'],
        'lightOn': s['l'],
        'cleanOn': s['c'],
        'ionOn': s['i'],
        'mode': s['mo'],
        'fanPercent': s['fp'],
      };
    }
    if (j['e'] is Map<String, dynamic>) {
      final e = j['e'] as Map<String, dynamic>;
      env = <String, dynamic>{
        'tempC': e['t'],
        'humPct': e['h'],
        'pm2_5': e['p'],
        'vocIndex': e['v'],
        'noxIndex': e['n'],
      };
    }
    if (j['a'] is Map<String, dynamic>) {
      final a = j['a'] as Map<String, dynamic>;
      env = <String, dynamic>{
        ...env,
        'aiTempC': a['t'],
        'aiHumPct': a['h'],
        'aiPressure': a['p'],
        'aiGasKOhm': a['g'],
        'aiIaq': a['i'],
        'aiCo2Eq': a['c'],
        'aiBVocEq': a['b'],
      };
    }
    if (j['f'] is Map<String, dynamic>) {
      final f = j['f'] as Map<String, dynamic>;
      fan = <String, dynamic>{'rpm': f['r']};
    }
    if (j['o'] is Map<String, dynamic>) {
      final o = j['o'] as Map<String, dynamic>;
      owner = <String, dynamic>{
        'setupDone': o['sd'],
        'hasOwner': o['ho'],
        'pairingWindowActive': o['pw'],
        'softRecoveryActive': o['sr'],
        'softRecoveryRemainingSec': o['srs'],
      };
    }
    if (j['j'] is Map<String, dynamic>) {
      final jj = j['j'] as Map<String, dynamic>;
      join = <String, dynamic>{
        'active': jj['a'],
        'apSessionActive': jj['ap'],
        'softRecoveryActive': jj['sr'],
        'softRecoveryRemainingSec': jj['srs'],
      };
    }

    bool readBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return false;
    }

    bool? readOptionalBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return null;
    }

    double readDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    int readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    int? readOptionalInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final masterOn = readBool(status['masterOn'] ?? j['masterOn']);
    final lightOn = readBool(status['lightOn'] ?? j['lightOn']);
    final cleanOn = readBool(status['cleanOn'] ?? j['cleanOn']);
    final ionOn = readBool(status['ionOn'] ?? j['ionOn']);
    final autoHumEnabled = readBool(
      status['autoHumEnabled'] ?? env['autoHumEnabled'] ?? j['autoHumEnabled'],
    );
    final autoHumTargetRaw = readInt(
      status['autoHumTarget'] ??
          env['autoHumTarget'] ??
          j['autoHumTarget'] ??
          55,
    );
    final autoHumTarget = autoHumTargetRaw.clamp(30, 70);
    final waterAutoEnabled = readOptionalBool(
      status['waterAutoEnabled'] ??
          env['waterAutoEnabled'] ??
          j['waterAutoEnabled'],
    );
    final waterDurationMin = readOptionalInt(
      status['waterDurationMin'] ??
          env['waterDurationMin'] ??
          j['waterDurationMin'],
    );
    final waterIntervalMin = readOptionalInt(
      status['waterIntervalMin'] ??
          env['waterIntervalMin'] ??
          j['waterIntervalMin'],
    );
    final waterManual = readOptionalBool(
      status['waterManual'] ?? env['waterManual'] ?? j['waterManual'],
    );
    final waterHumAutoEnabled = readOptionalBool(
      status['waterHumAutoEnabled'] ??
          env['waterHumAutoEnabled'] ??
          j['waterHumAutoEnabled'],
    );

    final mode = readInt(status['mode'] ?? j['mode'] ?? 1);
    final fanPercent = readInt(
      status['fanPercent'] ?? fan['targetPct'] ?? j['fanPercent'] ?? 35,
    );

    final rgbMap = (j['rgb'] is Map<String, dynamic>)
        ? j['rgb'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final r = readInt(ui['rgbR'] ?? rgbMap['r'] ?? 0);
    final g = readInt(ui['rgbG'] ?? rgbMap['g'] ?? 0);
    final b = readInt(ui['rgbB'] ?? rgbMap['b'] ?? 0);
    final rgbOn = readBool(ui['rgbOn'] ?? rgbMap['on'] ?? false);
    final rgbBrightness = readInt(
      ui['rgbBrightness'] ?? rgbMap['brightness'] ?? 100,
    );

    final tempC = readDouble(
      j['tempC'] ??
          env['tempC'] ??
          env['temperature'] ??
          env['temp'] ??
          j['temperature'] ??
          j['temp'],
    );
    final hum = readDouble(
      j['hum'] ??
          env['hum'] ??
          env['humPct'] ??
          env['humidity'] ??
          j['humidity'] ??
          j['humPct'],
    );
    final dhtTempC = readDouble(env['dhtTempC']);
    final dhtHum = readDouble(env['dhtHumPct']);
    final airQuality = (j['airQuality'] is Map<String, dynamic>)
        ? j['airQuality'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final pm25 = readDouble(
      j['pm25'] ??
          j['pm2_5'] ??
          env['pm2_5'] ??
          env['pm25'] ??
          env['pm'] ??
          j['pm'],
    );
    final vocIndex = readDouble(j['vocIndex'] ?? env['vocIndex']);
    final noxIndex = readDouble(j['noxIndex'] ?? env['noxIndex']);

    final aiTempC = readDouble(env['aiTempC']);
    final aiHum = readDouble(env['aiHumPct']);
    final aiPressure = readDouble(env['aiPressure']);
    final aiGasKOhm = readDouble(env['aiGasKOhm']);
    final aiIaq = readDouble(env['aiIaq']);
    final aiCo2Eq = readDouble(env['aiCo2Eq']);
    final aiBVocEq = readDouble(env['aiBVocEq']);

    final rpm = readInt(j['rpm'] ?? fan['rpm'] ?? 0);
    final indoorScore = readInt(
      airQuality['score'] ?? j['aqScore'] ?? j['airScore'] ?? 100,
    ).clamp(0, 100);
    final fanReason = (fan['reason'] ?? '').toString().trim();
    final odorBoostActive = readBool(
      fan['odorBoostActive'] ?? env['odorBoostActive'] ?? false,
    );
    final envSeq = readOptionalInt(
      env['seq'] ??
          env['sampleCount'] ??
          env['sample_count'] ??
          env['sample'] ??
          env['seqNo'],
    );

    final calibRPM =
        (j['calibRPM'] as List?)?.map((e) => readInt(e ?? 0)).toList() ??
        List<int>.filled(9, 0);

    final filterAlert = readBool(filter['alert'] ?? j['filterAlert']);

    final ota = (j['ota'] is Map<String, dynamic>)
        ? j['ota'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final cloudOta = (cloud['ota'] is Map<String, dynamic>)
        ? cloud['ota'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final otaAvailable = readBool(ota['available'] ?? false);
    final otaPending = readBool(cloudOta['pending'] ?? false);
    final otaJobId = (cloudOta['jobId'] ?? cloudOta['job_id'] ?? '')
        .toString()
        .trim();
    final otaRequiresUserApproval = readBool(
      cloudOta['requiresUserApproval'] ??
          cloudOta['requires_user_approval'] ??
          true,
    );
    final otaNewVersion = (cloudOta['version'] ?? ota['newVersion'] ?? '')
        .toString()
        .trim();
    final otaFirmwareUrl =
        (ota['firmwareUrl'] ?? ota['url'] ?? ota['fwUrl'] ?? '')
            .toString()
            .trim();
    final otaSha256 = (ota['sha256'] ?? ota['hash'] ?? '').toString().trim();
    final otaMinVersion = (ota['minVersion'] ?? ota['min_version'] ?? '')
        .toString()
        .trim();
    final dynamic rawFw =
        j['fwVersion'] ?? meta['fwVersion'] ?? ota['currentVersion'];
    final fwVersion = (rawFw is String && rawFw.isNotEmpty)
        ? rawFw
        : (otaNewVersion.isNotEmpty ? otaNewVersion : 'unknown');
    final deviceProduct =
        (meta['product'] ??
                capabilities['deviceProduct'] ??
                j['deviceProduct'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final deviceHwRev =
        (meta['hwRev'] ??
                capabilities['hwRev'] ??
                j['hwRev'] ??
                j['hardwareRev'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final deviceBoardRev =
        (meta['boardRev'] ??
                capabilities['boardRev'] ??
                j['boardRev'] ??
                j['board'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final deviceFwChannel =
        (meta['fwChannel'] ??
                capabilities['fwChannel'] ??
                j['fwChannel'] ??
                j['channel'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final networkApSsid = (network['apSsid'] ?? '').toString().trim();
    final networkMdnsHost = (network['mdnsHost'] ?? '').toString().trim();

    // Şehir / dış ortam bilgileri (eskiden ESP32 tarafındaki OpenWeather entegrasyonu)
    final cityAqi = readDouble(city['aqi']);
    final cityPm25 = readDouble(city['pm2_5']);
    final cityTempC = readDouble(city['tempC']);
    final cityHum = readDouble(city['humPct']);
    final cityWindKph = readDouble(city['windKph']);
    final cityName = (city['name'] ?? '').toString();
    final cityDesc = (city['desc'] ?? '').toString();

    final ownerSetupDone = readBool(
      owner['setupDone'] ??
          owner['ownerSetupDone'] ??
          owner['setup_done'] ??
          owner['done'],
    );
    final ownerExists = readBool(
      owner['hasOwner'] ??
          owner['ownerExists'] ??
          owner['exists'] ??
          owner['owner'],
    );
    final joinActive = (join['active'] is bool)
        ? join['active'] as bool
        : false;
    final pairingWindowActive = (owner['pairingWindowActive'] is bool)
        ? owner['pairingWindowActive'] as bool
        : false;
    final apSessionActive = (join['apSessionActive'] is bool)
        ? join['apSessionActive'] as bool
        : false;
    final hasSoftRecoveryFlag =
        owner.containsKey('softRecoveryActive') ||
        join.containsKey('softRecoveryActive');
    final softRecoveryActive = hasSoftRecoveryFlag
        ? readBool(
            join['softRecoveryActive'] ?? owner['softRecoveryActive'] ?? false,
          )
        : (pairingWindowActive || apSessionActive);
    final softRecoveryRemainingSec = readInt(
      join['softRecoveryRemainingSec'] ??
          owner['softRecoveryRemainingSec'] ??
          0,
    ).clamp(0, 86400);
    final authRole = (auth['role'] ?? '').toString();
    final invitedUsers = (j['users'] is List)
        ? (j['users'] as List)
              .whereType<Map>()
              .map((e) => InvitedUser.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <InvitedUser>[];

    final cloudEnabled = readBool(
      cloud['enabled'] ?? cloud['cloudEnabled'] ?? false,
    );
    final cloudMqttConnected = readBool(cloud['mqttConnected'] ?? false);
    final cloudMqttState = (cloud['mqttState'] ?? '').toString();
    final cloudMqttStateCode = readInt(cloud['mqttStateCode'] ?? 0);
    final cloudState = (cloud['state'] ?? cloudMqttState).toString();
    final cloudStateCode = readInt(cloud['stateCode'] ?? cloudMqttStateCode);
    final cloudStateReason = (cloud['stateReason'] ?? '').toString();
    final cloudIotEndpoint = (cloud['iotEndpoint'] ?? cloud['endpoint'] ?? '')
        .toString()
        .trim();
    final cloudStateUpdatedAtMs = readInt(
      cloud['stateUpdatedAtMs'] ??
          cloud['updatedAtMs'] ??
          j['stateUpdatedAtMs'] ??
          j['updatedAtMs'] ??
          0,
    );
    final cloudStateSinceMs = readInt(cloud['stateSinceMs'] ?? 0);
    final cloudDebug = (cloud['debug'] is Map<String, dynamic>)
        ? (cloud['debug'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    final cloudLastDesiredPingMs = readInt(
      cloudDebug['lastDesiredPingMs'] ?? cloud['lastDesiredPingMs'] ?? 0,
    );
    final cloudLastDesiredClientTsMs = readInt(
      cloudDebug['lastDesiredClientTsMs'] ??
          cloud['lastDesiredClientTsMs'] ??
          0,
    );
    final sampleTsMs = readInt(
      meta['ts_ms'] ?? meta['tsMs'] ?? j['ts_ms'] ?? 0,
    );
    final cloudClaimed = readBool(claim['claimed'] ?? false);

    return DeviceState(
      masterOn: masterOn,
      lightOn: lightOn,
      cleanOn: cleanOn,
      ionOn: ionOn,
      autoHumEnabled: autoHumEnabled,
      autoHumTarget: autoHumTarget,
      mode: mode,
      fanPercent: fanPercent,
      indoorScore: indoorScore,
      r: r,
      g: g,
      b: b,
      rgbOn: rgbOn,
      rgbBrightness: rgbBrightness,
      tempC: tempC,
      hum: hum,
      dhtTempC: dhtTempC,
      dhtHum: dhtHum,
      waterAutoEnabled: waterAutoEnabled,
      waterDurationMin: waterDurationMin,
      waterIntervalMin: waterIntervalMin,
      waterManual: waterManual,
      waterHumAutoEnabled: waterHumAutoEnabled,
      pm25: pm25,
      vocIndex: vocIndex,
      noxIndex: noxIndex,
      aiTempC: aiTempC,
      aiHum: aiHum,
      aiPressure: aiPressure,
      aiGasKOhm: aiGasKOhm,
      aiIaq: aiIaq,
      aiCo2Eq: aiCo2Eq,
      aiBVocEq: aiBVocEq,
      envSeq: envSeq,
      rpm: rpm,
      fanReason: fanReason.isEmpty ? 'manual' : fanReason,
      odorBoostActive: odorBoostActive,
      calibRPM: calibRPM,
      filterAlert: filterAlert,
      cityAqi: cityAqi,
      cityPm25: cityPm25,
      cityTempC: cityTempC,
      cityHum: cityHum,
      cityWindKph: cityWindKph,
      cityName: cityName,
      cityDesc: cityDesc,
      otaAvailable: otaAvailable,
      otaNewVersion: otaNewVersion,
      otaPending: otaPending,
      otaJobId: otaJobId,
      otaRequiresUserApproval: otaRequiresUserApproval,
      fwVersion: fwVersion,
      otaFirmwareUrl: otaFirmwareUrl,
      otaSha256: otaSha256,
      otaMinVersion: otaMinVersion,
      deviceProduct: deviceProduct,
      deviceHwRev: deviceHwRev,
      deviceBoardRev: deviceBoardRev,
      deviceFwChannel: deviceFwChannel,
      networkApSsid: networkApSsid,
      networkMdnsHost: networkMdnsHost,
      ownerSetupDone: ownerSetupDone,
      ownerExists: ownerExists,
      joinActive: joinActive,
      pairingWindowActive: pairingWindowActive,
      apSessionActive: apSessionActive,
      softRecoveryActive: softRecoveryActive,
      softRecoveryRemainingSec: softRecoveryRemainingSec,
      authRole: authRole.isEmpty ? 'UNKNOWN' : authRole,
      invitedUsers: invitedUsers,
      cloudEnabled: cloudEnabled,
      cloudMqttConnected: cloudMqttConnected,
      cloudMqttState: cloudMqttState,
      cloudMqttStateCode: cloudMqttStateCode,
      cloudState: cloudState,
      cloudStateCode: cloudStateCode,
      cloudStateReason: cloudStateReason,
      cloudIotEndpoint: cloudIotEndpoint,
      cloudStateUpdatedAtMs: cloudStateUpdatedAtMs,
      cloudStateSinceMs: cloudStateSinceMs,
      cloudLastDesiredPingMs: cloudLastDesiredPingMs,
      cloudLastDesiredClientTsMs: cloudLastDesiredClientTsMs,
      sampleTsMs: sampleTsMs,
      cloudClaimed: cloudClaimed,
    );
  }
}
