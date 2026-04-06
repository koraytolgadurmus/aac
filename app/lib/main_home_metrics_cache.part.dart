part of 'main.dart';

extension _HomeScreenMetricsCacheExt on _HomeScreenState {
  int _pctForMode(int mode) {
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
        return state?.fanPercent ?? 35;
    }
  }

  double _pm25ToAqi(double pm25) {
    if (pm25 <= 0 || pm25.isNaN) return 0;
    double c = pm25;
    double cLow, cHigh;
    double iLow, iHigh;
    if (c <= 12.0) {
      cLow = 0.0;
      cHigh = 12.0;
      iLow = 0.0;
      iHigh = 50.0;
    } else if (c <= 35.4) {
      cLow = 12.1;
      cHigh = 35.4;
      iLow = 51.0;
      iHigh = 100.0;
    } else if (c <= 55.4) {
      cLow = 35.5;
      cHigh = 55.4;
      iLow = 101.0;
      iHigh = 150.0;
    } else if (c <= 150.4) {
      cLow = 55.5;
      cHigh = 150.4;
      iLow = 151.0;
      iHigh = 200.0;
    } else if (c <= 250.4) {
      cLow = 150.5;
      cHigh = 250.4;
      iLow = 201.0;
      iHigh = 300.0;
    } else if (c <= 500.4) {
      cLow = 250.5;
      cHigh = 500.4;
      iLow = 301.0;
      iHigh = 500.0;
    } else {
      return 500.0;
    }
    final ratio = (c - cLow) / (cHigh - cLow);
    return (iHigh - iLow) * ratio + iLow;
  }

  double _aqiToPercent(double aqi) {
    if (aqi <= 0 || aqi.isNaN) return 100.0;
    if (aqi >= 500.0) return 0.0;
    final p = 100.0 - (aqi / 5.0);
    if (p < 0) return 0.0;
    if (p > 100) return 100.0;
    return p;
  }

  WaqiInfo? _waqiInfoFromDeviceCache(_SavedDevice dev) {
    final city = (dev.waqiCityName ?? '').trim();
    final aqi = (dev.waqiAqi ?? 0).toDouble();
    final pm25 = dev.waqiPm25;
    final tempC = dev.waqiTempC;
    final humidity = dev.waqiHumPct;
    final windKph = dev.waqiWindKph;
    final hasAny =
        city.isNotEmpty ||
        aqi > 0 ||
        (pm25 != null && pm25 > 0) ||
        (tempC != null && tempC != 0) ||
        (humidity != null && humidity != 0) ||
        (windKph != null && windKph != 0);
    if (!hasAny) return null;
    final fallbackAqi = (pm25 != null && pm25 > 0) ? _pm25ToAqi(pm25) : 0.0;
    return WaqiInfo(
      city: city,
      aqi: aqi > 0 ? aqi : fallbackAqi,
      pm25: pm25,
      tempC: tempC,
      humidity: humidity,
      windKph: windKph,
    );
  }

  int _indexOfDeviceByIdLike(String? rawId) {
    final id = (rawId ?? '').trim();
    if (id.isEmpty) return -1;
    final exact = _devices.indexWhere((d) => d.id == id);
    if (exact != -1) return exact;
    final canonical = canonicalizeDeviceId(id);
    if (canonical == null || canonical.isEmpty) return -1;
    return _devices.indexWhere((d) => canonicalizeDeviceId(d.id) == canonical);
  }

  int _indexOfActiveDevice() => _indexOfDeviceByIdLike(_activeDeviceId);

  bool _isSameDeviceId(String? a, String? b) {
    final aa = (a ?? '').trim();
    final bb = (b ?? '').trim();
    if (aa.isEmpty || bb.isEmpty) return aa == bb;
    if (aa == bb) return true;
    final ca = canonicalizeDeviceId(aa);
    final cb = canonicalizeDeviceId(bb);
    return ca != null && cb != null && ca == cb;
  }

  Future<void> _cacheActiveDeviceWaqiInfo(
    WaqiInfo info, {
    bool forcePersist = true,
  }) async {
    final idx = _indexOfActiveDevice();
    if (idx == -1) return;
    final dev = _devices[idx];
    var changed = false;
    final city = info.city.trim();
    if (city.isNotEmpty && dev.waqiCityName != city) {
      dev.waqiCityName = city;
      changed = true;
    }
    if (info.aqi > 0 &&
        (dev.waqiAqi == null || (dev.waqiAqi! - info.aqi).abs() > 0.01)) {
      dev.waqiAqi = info.aqi;
      changed = true;
    }
    if (info.pm25 != null &&
        info.pm25! > 0 &&
        (dev.waqiPm25 == null || (dev.waqiPm25! - info.pm25!).abs() > 0.01)) {
      dev.waqiPm25 = info.pm25;
      changed = true;
    }
    if (info.tempC != null &&
        (dev.waqiTempC == null ||
            (dev.waqiTempC! - info.tempC!).abs() > 0.01)) {
      dev.waqiTempC = info.tempC;
      changed = true;
    }
    if (info.humidity != null &&
        (dev.waqiHumPct == null ||
            (dev.waqiHumPct! - info.humidity!).abs() > 0.01)) {
      dev.waqiHumPct = info.humidity;
      changed = true;
    }
    if (info.windKph != null &&
        (dev.waqiWindKph == null ||
            (dev.waqiWindKph! - info.windKph!).abs() > 0.01)) {
      dev.waqiWindKph = info.windKph;
      changed = true;
    }
    dev.waqiUpdatedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (changed || forcePersist) {
      await _saveDevicesToPrefs();
    }
  }

  void _cacheActiveDeviceWaqiSnapshot(
    DeviceState st, {
    bool forcePersist = false,
  }) {
    final idx = _indexOfActiveDevice();
    if (idx == -1) return;
    final dev = _devices[idx];
    final cityName = st.cityName.trim();
    final hasAny =
        cityName.isNotEmpty ||
        st.cityAqi > 0 ||
        st.cityPm25 > 0 ||
        st.cityTempC != 0 ||
        st.cityHum != 0 ||
        st.cityWindKph != 0;
    if (!hasAny) return;

    var changed = false;
    if (cityName.isNotEmpty && dev.waqiCityName != cityName) {
      dev.waqiCityName = cityName;
      changed = true;
    }
    if (st.cityAqi > 0 &&
        (dev.waqiAqi == null || (dev.waqiAqi! - st.cityAqi).abs() > 0.01)) {
      dev.waqiAqi = st.cityAqi;
      changed = true;
    }
    if (st.cityPm25 > 0 &&
        (dev.waqiPm25 == null || (dev.waqiPm25! - st.cityPm25).abs() > 0.01)) {
      dev.waqiPm25 = st.cityPm25;
      changed = true;
    }
    if (st.cityTempC != 0 &&
        (dev.waqiTempC == null ||
            (dev.waqiTempC! - st.cityTempC).abs() > 0.01)) {
      dev.waqiTempC = st.cityTempC;
      changed = true;
    }
    if (st.cityHum != 0 &&
        (dev.waqiHumPct == null ||
            (dev.waqiHumPct! - st.cityHum).abs() > 0.01)) {
      dev.waqiHumPct = st.cityHum;
      changed = true;
    }
    if (st.cityWindKph != 0 &&
        (dev.waqiWindKph == null ||
            (dev.waqiWindKph! - st.cityWindKph).abs() > 0.01)) {
      dev.waqiWindKph = st.cityWindKph;
      changed = true;
    }
    if (!changed) return;
    dev.waqiUpdatedAtMs = DateTime.now().millisecondsSinceEpoch;
    _waqiInstantInfo = _waqiInfoFromDeviceCache(dev);
    _waqiInstantDeviceId = dev.id;

    final now = DateTime.now();
    final shouldPersist =
        forcePersist ||
        _lastWaqiSnapshotPersistAt == null ||
        now.difference(_lastWaqiSnapshotPersistAt!) >
            const Duration(seconds: 45);
    if (shouldPersist) {
      _lastWaqiSnapshotPersistAt = now;
      unawaited(_saveDevicesToPrefs());
    }
  }

  void _pushHistorySample(DeviceState st) {
    _cacheActiveDeviceWaqiSnapshot(st);
    final now = DateTime.now();

    final indoorPercent = st.indoorScore.toDouble().clamp(0.0, 100.0);
    double? outdoorPercent;
    if (st.cityPm25 > 0) {
      final outdoorAqi = _pm25ToAqi(st.cityPm25);
      outdoorPercent = _aqiToPercent(outdoorAqi);
    }

    void push(List<_HistoryPoint> list, double v) {
      list.add(_HistoryPoint(now, v));
      if (list.length > _HomeScreenState._maxHistoryPoints) {
        list.removeAt(0);
      }
    }

    push(_aqHistory, indoorPercent);
    if (outdoorPercent != null) {
      push(_cityAqHistory, outdoorPercent);
    }
    push(_humHistory, st.hum);
    push(_tempHistory, st.tempC);
    push(_pm25History, st.pm25);
    push(_rpmHistory, st.rpm.toDouble());
    push(_vocHistory, st.vocIndex);
    push(_noxHistory, st.noxIndex);
    push(_aiTempHistory, st.aiTempC);
    push(_aiHumHistory, st.aiHum);
    push(_aiPressHistory, st.aiPressure);
    push(_aiGasHistory, st.aiGasKOhm);
    if (st.aiIaq > 0) {
      push(_aiIaqHistory, st.aiIaq);
    }
    if (st.aiCo2Eq > 0) {
      push(_aiCo2History, st.aiCo2Eq);
    }
    if (st.aiBVocEq > 0) {
      push(_aiBVocHistory, st.aiBVocEq);
    }
  }

  List<_HistoryPoint> _historyFromApi(
    Map<String, dynamic> j,
    String metricTitle,
    List<_HistoryPoint> fallback,
  ) {
    final Map<String, dynamic> root;
    if (j['home'] is Map<String, dynamic>) {
      root = j['home'] as Map<String, dynamic>;
    } else {
      root = j;
    }

    final out = <_HistoryPoint>[];
    String key;
    switch (metricTitle) {
      case 'PM2.5':
        key = 'pm2_5';
        break;
      case 'Humidity':
        key = 'hum';
        break;
      case 'AI Hum':
        key = 'aiHumPct';
        break;
      case 'Temp':
      case 'AI Temp':
        key = 'tempC';
        break;
      case 'VOC index':
        key = 'vocIndex';
        break;
      case 'NOx index':
        key = 'noxIndex';
        break;
      case 'RPM':
        key = 'rpm';
        break;
      case 'AI Press':
        key = 'aiPressure';
        break;
      case 'AI Gas':
        key = 'aiGasKOhm';
        break;
      case 'IAQ':
        key = 'aiIaq';
        break;
      case 'CO₂ eq':
        key = 'aiCo2Eq';
        break;
      case 'bVOC eq':
        key = 'aiBVocEq';
        break;
      default:
        return fallback;
    }

    void addList(dynamic src, {bool daily = false}) {
      if (src is! List) return;
      for (final e in src) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final ts = (m['ts'] ?? m['day']);
        if (ts is! num) continue;
        final v = m[key];
        if (v is! num) continue;
        var dt = DateTime.fromMillisecondsSinceEpoch(
          ts.toInt() * 1000,
          isUtc: true,
        ).toLocal();
        if (daily && m.containsKey('day')) {
          dt = dt.add(const Duration(hours: 12));
        }
        out.add(_HistoryPoint(dt, v.toDouble()));
      }
    }

    addList(root['short'], daily: false);
    addList(root['daily'], daily: true);

    if (out.isEmpty) return fallback;
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}
