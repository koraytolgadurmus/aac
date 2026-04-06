part of 'main.dart';

class WaqiLocation {
  const WaqiLocation({
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String name;
  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon};

  factory WaqiLocation.fromJson(Map<String, dynamic> j) {
    return WaqiLocation(
      name: (j['name'] ?? '') as String,
      lat: (j['lat'] as num).toDouble(),
      lon: (j['lon'] as num).toDouble(),
    );
  }
}

class WaqiInfo {
  const WaqiInfo({
    required this.city,
    required this.aqi,
    this.pm25,
    this.pm10,
    this.time,
    this.tempC,
    this.humidity,
    this.windKph,
    this.dominantPol,
  });

  final String city;
  final double aqi; // 0..500
  final double? pm25; // µg/m³
  final double? pm10; // µg/m³
  final DateTime? time;
  final double? tempC; // °C
  final double? humidity; // %
  final double? windKph; // km/h
  final String? dominantPol;
}

class WeatherLocation {
  final String name;
  final String? state;
  final String? country;
  final double lat;
  final double lon;

  WeatherLocation({
    required this.name,
    required this.lat,
    required this.lon,
    this.state,
    this.country,
  });

  String displayName(String fallback) {
    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (state != null && state!.isNotEmpty && !parts.contains(state)) {
      parts.add(state!);
    }
    if (country != null && country!.isNotEmpty) parts.add(country!);
    if (parts.isEmpty) return fallback;
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'state': state,
    'country': country,
    'lat': lat,
    'lon': lon,
  };

  factory WeatherLocation.fromJson(Map<String, dynamic> j) {
    return WeatherLocation(
      name: (j['name'] ?? '') as String,
      state: j['state'] as String?,
      country: j['country'] as String?,
      lat: (j['lat'] as num).toDouble(),
      lon: (j['lon'] as num).toDouble(),
    );
  }
}

class OpenWeatherApi {
  // WAQI token must be injected at build time.
  static const String _waqiToken = String.fromEnvironment(
    'WAQI_API_TOKEN',
    defaultValue: 'REPLACE_WITH_WAQI_TOKEN',
  );

  Future<List<WaqiLocation>> searchWaqiStations(String keyword) async {
    if (_waqiToken == 'REPLACE_WITH_WAQI_TOKEN') return const [];
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.parse(
      'https://api.waqi.info/search/?token=$_waqiToken&keyword=${Uri.encodeQueryComponent(trimmed)}',
    );
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final obj = jsonDecode(r.body);
        if (obj is Map<String, dynamic> && obj['status'] == 'ok') {
          final data = obj['data'];
          if (data is List) {
            final out = <WaqiLocation>[];
            for (final item in data) {
              if (item is! Map) continue;
              final m = item.cast<String, dynamic>();
              final station = m['station'];
              if (station is! Map) continue;
              final name = (station['name'] ?? '') as String;
              final geo = station['geo'];
              if (geo is List && geo.length >= 2) {
                final latRaw = geo[0];
                final lonRaw = geo[1];
                if (latRaw is num && lonRaw is num) {
                  out.add(
                    WaqiLocation(
                      name: name,
                      lat: latRaw.toDouble(),
                      lon: lonRaw.toDouble(),
                    ),
                  );
                }
              }
            }
            return out;
          }
        }
      }
    } catch (e) {
      debugPrint('[WAQI] search error: $e');
    }
    return const [];
  }

  Future<WaqiInfo?> fetchWaqi({
    required double lat,
    required double lon,
  }) async {
    if (_waqiToken == 'REPLACE_WITH_WAQI_TOKEN') return null;
    final uri = Uri.parse(
      'https://api.waqi.info/feed/geo:$lat;$lon/?token=$_waqiToken',
    );
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final obj = jsonDecode(r.body);
        if (obj is Map<String, dynamic> && obj['status'] == 'ok') {
          final data = obj['data'];
          if (data is Map<String, dynamic>) {
            final rawAqi = data['aqi'];
            if (rawAqi is num) {
              final aqi = rawAqi.toDouble().clamp(0.0, 500.0);
              final cityObj = data['city'];
              String cityName = '';
              if (cityObj is Map && cityObj['name'] is String) {
                cityName = cityObj['name'] as String;
              }
              double? pm25;
              double? pm10;
              double? tempC;
              double? humidity;
              double? windKph;
              final iaqi = data['iaqi'];
              if (iaqi is Map) {
                final pm25Map = iaqi['pm25'];
                if (pm25Map is Map && pm25Map['v'] is num) {
                  pm25 = (pm25Map['v'] as num).toDouble();
                }
                final pm10Map = iaqi['pm10'];
                if (pm10Map is Map && pm10Map['v'] is num) {
                  pm10 = (pm10Map['v'] as num).toDouble();
                }
                final tMap = iaqi['t'];
                if (tMap is Map && tMap['v'] is num) {
                  tempC = (tMap['v'] as num).toDouble();
                }
                final hMap = iaqi['h'];
                if (hMap is Map && hMap['v'] is num) {
                  humidity = (hMap['v'] as num).toDouble();
                }
                final wMap = iaqi['w'];
                if (wMap is Map && wMap['v'] is num) {
                  final wMs = (wMap['v'] as num).toDouble();
                  windKph = wMs * 3.6;
                }
              }
              DateTime? t;
              final timeObj = data['time'];
              if (timeObj is Map && timeObj['s'] is String) {
                t = DateTime.tryParse(timeObj['s'] as String);
              }
              String? domPol;
              final dom = data['dominentpol'];
              if (dom is String && dom.isNotEmpty) {
                domPol = dom;
              }
              return WaqiInfo(
                city: cityName,
                aqi: aqi,
                pm25: pm25,
                pm10: pm10,
                time: t,
                tempC: tempC,
                humidity: humidity,
                windKph: windKph,
                dominantPol: domPol,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WAQI] fetchWaqi error: $e');
    }
    return null;
  }

  Future<List<WeatherLocation>> searchCities(
    String query, {
    String langCode = 'tr',
  }) async {
    // OpenWeather city search is intentionally disabled; WAQI picker is used.
    return const [];
  }
}
