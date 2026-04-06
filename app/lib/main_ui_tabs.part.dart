part of 'main.dart';

extension _HomeScreenUiTabsPart on _HomeScreenState {
  Widget _buildDashboardImpl() {
    return _buildHomeTab();
  }

  Widget _buildSensorsImpl() {
    final s = state;
    final allZero = (s?.rpm ?? 0) == 0;
    final hasEnv = _hasEnvSignal(s);
    final ts = _lastUpdate == null
        ? '--'
        : _lastUpdate!.toLocal().toIso8601String().substring(11, 19);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.update, size: 18),
              const SizedBox(width: 6),
              Text('${t.t('last_update')}: ' + ts),
              const SizedBox(width: 12),
              _dot(_canControlDevice ? Colors.green : Colors.red),
              const SizedBox(width: 6),
              Text(_canControlDevice ? t.t('status_ok') : t.t('status_off')),
            ],
          ),
          if (_canControlDevice && allZero && !hasEnv)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                t.t('sensor_zero_hint'),
                style: TextStyle(color: Colors.amber.shade700),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 3 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _sensorCard(
                  title: 'PM2.5',
                  unit: 'µg/m³',
                  value: s?.pm25,
                  history: _pm25History,
                  icon: Icons.blur_on,
                  lineColor: Colors.greenAccent,
                  onTap: () => _openSensorDetails(
                    title: 'PM2.5',
                    unit: 'µg/m³',
                    icon: Icons.blur_on,
                    history: _pm25History,
                    lineColor: Colors.greenAccent,
                  ),
                ),
                _sensorCard(
                  title: 'Humidity',
                  unit: '%',
                  value: s?.hum,
                  history: _humHistory,
                  icon: Icons.water_drop,
                  lineColor: Colors.redAccent,
                  onTap: () => _openSensorDetails(
                    title: 'Humidity',
                    unit: '%',
                    icon: Icons.water_drop,
                    history: _humHistory,
                    lineColor: Colors.redAccent,
                  ),
                ),
                _sensorCard(
                  title: 'Temp',
                  unit: '°C',
                  value: s?.tempC,
                  history: _tempHistory,
                  icon: Icons.thermostat,
                  lineColor: Colors.lightGreenAccent,
                  onTap: () => _openSensorDetails(
                    title: 'Temp',
                    unit: '°C',
                    icon: Icons.thermostat,
                    history: _tempHistory,
                    lineColor: Colors.lightGreenAccent,
                  ),
                ),
                _sensorCard(
                  title: 'VOC index',
                  unit: '',
                  value: s?.vocIndex,
                  history: _vocHistory,
                  icon: Icons.science_outlined,
                  lineColor: Colors.tealAccent,
                  onTap: () => _openSensorDetails(
                    title: 'VOC index',
                    unit: '',
                    icon: Icons.science_outlined,
                    history: _vocHistory,
                    lineColor: Colors.tealAccent,
                  ),
                ),
                _sensorCard(
                  title: 'NOx index',
                  unit: '',
                  value: s?.noxIndex,
                  history: _noxHistory,
                  icon: Icons.cloud_outlined,
                  lineColor: Colors.orangeAccent,
                  onTap: () => _openSensorDetails(
                    title: 'NOx index',
                    unit: '',
                    icon: Icons.cloud_outlined,
                    history: _noxHistory,
                    lineColor: Colors.orangeAccent,
                  ),
                ),
                _sensorCard(
                  title: 'RPM',
                  unit: 'RPM',
                  value: (s?.rpm ?? 0).toDouble(),
                  history: _rpmHistory,
                  icon: Icons.air,
                  lineColor: Colors.greenAccent,
                  decimals: 0,
                  onTap: () => _openSensorDetails(
                    title: 'RPM',
                    unit: 'RPM',
                    icon: Icons.air,
                    history: _rpmHistory,
                    lineColor: Colors.greenAccent,
                    decimals: 0,
                  ),
                ),
                _sensorCard(
                  title: 'AI Temp',
                  unit: '°C',
                  value: s?.aiTempC,
                  history: _aiTempHistory,
                  icon: Icons.thermostat_auto,
                  lineColor: Colors.lightBlueAccent,
                  onTap: () => _openSensorDetails(
                    title: 'AI Temp',
                    unit: '°C',
                    icon: Icons.thermostat_auto,
                    history: _aiTempHistory,
                    lineColor: Colors.lightBlueAccent,
                  ),
                ),
                _sensorCard(
                  title: 'AI Hum',
                  unit: '%',
                  value: s?.aiHum,
                  history: _aiHumHistory,
                  icon: Icons.water_drop_outlined,
                  lineColor: Colors.cyanAccent,
                  onTap: () => _openSensorDetails(
                    title: 'AI Hum',
                    unit: '%',
                    icon: Icons.water_drop_outlined,
                    history: _aiHumHistory,
                    lineColor: Colors.cyanAccent,
                  ),
                ),
                _sensorCard(
                  title: 'AI Press',
                  unit: 'hPa',
                  value: s?.aiPressure,
                  history: _aiPressHistory,
                  icon: Icons.speed,
                  lineColor: Colors.purpleAccent,
                  onTap: () => _openSensorDetails(
                    title: 'AI Press',
                    unit: 'hPa',
                    icon: Icons.speed,
                    history: _aiPressHistory,
                    lineColor: Colors.purpleAccent,
                  ),
                ),
                _sensorCard(
                  title: 'AI Gas',
                  unit: 'kΩ',
                  value: s?.aiGasKOhm,
                  history: _aiGasHistory,
                  icon: Icons.local_fire_department_outlined,
                  lineColor: Colors.amberAccent,
                  onTap: () => _openSensorDetails(
                    title: 'AI Gas',
                    unit: 'kΩ',
                    icon: Icons.local_fire_department_outlined,
                    history: _aiGasHistory,
                    lineColor: Colors.amberAccent,
                  ),
                ),
                _sensorCard(
                  title: 'IAQ',
                  unit: '',
                  value: s?.aiIaq,
                  history: _aiIaqHistory,
                  icon: Icons.dashboard_outlined,
                  lineColor: Colors.blueAccent,
                  onTap: () => _openSensorDetails(
                    title: 'IAQ',
                    unit: '',
                    icon: Icons.dashboard_outlined,
                    history: _aiIaqHistory,
                    lineColor: Colors.blueAccent,
                  ),
                ),
                _sensorCard(
                  title: 'CO₂ eq',
                  unit: 'ppm',
                  value: s?.aiCo2Eq,
                  history: _aiCo2History,
                  icon: Icons.co2_outlined,
                  lineColor: Colors.lightGreenAccent,
                  onTap: () => _openSensorDetails(
                    title: 'CO₂ eq',
                    unit: 'ppm',
                    icon: Icons.co2_outlined,
                    history: _aiCo2History,
                    lineColor: Colors.lightGreenAccent,
                  ),
                ),
                _sensorCard(
                  title: 'bVOC eq',
                  unit: 'ppm',
                  value: s?.aiBVocEq,
                  history: _aiBVocHistory,
                  icon: Icons.blur_circular_outlined,
                  lineColor: Colors.pinkAccent,
                  onTap: () => _openSensorDetails(
                    title: 'bVOC eq',
                    unit: 'ppm',
                    icon: Icons.blur_circular_outlined,
                    history: _aiBVocHistory,
                    lineColor: Colors.pinkAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorCard({
    required String title,
    required String unit,
    required double? value,
    required List<_HistoryPoint> history,
    required IconData icon,
    required Color lineColor,
    int decimals = 2,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    String valueText;
    if (value == null) {
      valueText = '--';
    } else if (decimals == 0) {
      valueText = value.toStringAsFixed(0);
    } else {
      valueText = value.toStringAsFixed(decimals);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                unit.isEmpty ? valueText : '$valueText $unit',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SensorTrendPainter(
                    history,
                    domainStart: () {
                      if (history.isEmpty) {
                        final now = DateTime.now();
                        return now.subtract(const Duration(minutes: 1));
                      }
                      if (history.length >= 2) return history.first.time;
                      return history.first.time.subtract(
                        const Duration(minutes: 1),
                      );
                    }(),
                    domainEnd: () {
                      if (history.isEmpty) {
                        return DateTime.now();
                      }
                      if (history.length >= 2) return history.last.time;
                      return history.first.time.add(const Duration(minutes: 1));
                    }(),
                    lineColor: lineColor,
                    gridColor: theme.dividerColor.withValues(alpha: 0.4),
                    useIndexX: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSensorDetails({
    required String title,
    required String unit,
    required IconData icon,
    required List<_HistoryPoint> history,
    required Color lineColor,
    int decimals = 2,
  }) async {
    if (!mounted) return;

    // Varsayılan olarak ekranda biriken history'yi kullan; fakat
    // mümkünse ESP32'den /api/history çekip bu sensör için birleşik
    // (RAM + daily) geçmişle değiştir.
    List<_HistoryPoint> effectiveHistory = history;
    try {
      final hJson = await api.fetchHistory();
      if (hJson != null) {
        effectiveHistory = _historyFromApi(hJson, title, history);
      }
    } catch (_) {
      // Sessizce düş; en azından mevcut history ile devam ederiz.
    }
    if (!mounted || effectiveHistory.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        _SensorHistoryRange range = _SensorHistoryRange.last3h;

        // Seçili zaman aralığına göre history'i [domainStart, domainEnd]
        // penceresine filtrele.
        List<_HistoryPoint> _filteredRaw(
          DateTime domainStart,
          DateTime domainEnd,
        ) {
          if (effectiveHistory.length < 2) return effectiveHistory;
          final list = effectiveHistory
              .where(
                (p) =>
                    !p.time.isBefore(domainStart) && p.time.isBefore(domainEnd),
              )
              .toList(growable: false);
          return list.isEmpty ? history : list;
        }

        List<_HistoryPoint> _bucketed(
          List<_HistoryPoint> src,
          DateTime domainStart,
        ) {
          if (src.length < 2) return src;

          // Son 3 saat görünümünde ham noktaları kullan; zaman ekseni
          // zaten sabit bir pencereye ayarlı ve örnek sayısı düşük.
          if (range == _SensorHistoryRange.last3h) {
            return src;
          }
          Duration bucket;
          switch (range) {
            case _SensorHistoryRange.last3h:
              bucket = const Duration(minutes: 5);
              break;
            case _SensorHistoryRange.day:
              bucket = const Duration(hours: 1);
              break;
            case _SensorHistoryRange.week:
              bucket = const Duration(hours: 3);
              break;
            case _SensorHistoryRange.month:
              bucket = const Duration(hours: 12);
              break;
          }
          if (bucket.inMinutes <= 0) return src;

          // Eğer elimizdeki veri seçilen bucket süresinden daha kısa bir
          // zaman aralığını kapsıyorsa, bucket'lama yerine ham noktaları
          // kullan; aksi halde tek bir kovaya düşüp sadece nokta görünür.
          final span = src.last.time.difference(src.first.time).abs();
          if (span < bucket) return src;

          final buckets = <int, double>{};
          final counts = <int, int>{};
          for (final p in src) {
            final diff = p.time.difference(domainStart);
            if (diff.isNegative) continue;
            final minutes = diff.inMinutes;
            final idx = (minutes / bucket.inMinutes).floor();
            buckets[idx] = (buckets[idx] ?? 0) + p.value;
            counts[idx] = (counts[idx] ?? 0) + 1;
          }
          if (buckets.isEmpty) return src;

          final result = <_HistoryPoint>[];
          buckets.forEach((idx, sum) {
            final c = counts[idx] ?? 1;
            final t = domainStart.add(
              Duration(minutes: idx * bucket.inMinutes),
            );
            result.add(_HistoryPoint(t, sum / c));
          });
          result.sort((a, b) => a.time.compareTo(b.time));
          return result;
        }

        String formatValue(double v) =>
            decimals == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(decimals);

        return StatefulBuilder(
          builder: (ctx, setS) {
            // Seçilen aralığa göre sabit bir zaman penceresi tanımla
            final now = DateTime.now();
            late DateTime domainStart;
            late DateTime domainEnd;
            switch (range) {
              case _SensorHistoryRange.last3h:
                domainEnd = now;
                domainStart = now.subtract(const Duration(hours: 3));
                break;
              case _SensorHistoryRange.day:
                // Gün görünümünde x eksenini günün 00–24 saatleri
                // üzerine sabitliyoruz.
                final todayMidnight = DateTime(now.year, now.month, now.day);
                domainStart = todayMidnight;
                domainEnd = todayMidnight.add(const Duration(days: 1));
                break;
              case _SensorHistoryRange.week:
                domainEnd = now;
                domainStart = now.subtract(const Duration(days: 7));
                break;
              case _SensorHistoryRange.month:
                domainEnd = now;
                domainStart = now.subtract(const Duration(days: 30));
                break;
            }

            final raw = _filteredRaw(domainStart, domainEnd);
            final points = _bucketed(raw, domainStart);
            final latest = raw.isNotEmpty ? raw.last.value : null;
            double? minVal;
            double? maxVal;
            if (raw.isNotEmpty) {
              minVal = raw.first.value;
              maxVal = raw.first.value;
              for (final p in raw) {
                if (p.value < minVal!) minVal = p.value;
                if (p.value > maxVal!) maxVal = p.value;
              }
            }
            final valueText = latest == null
                ? '--'
                : formatValue(latest) + (unit.isEmpty ? '' : ' $unit');

            Widget rangeChip(_SensorHistoryRange r, String label) {
              final selected = range == r;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setS(() => range = r),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      valueText,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (minVal != null && maxVal != null)
                      Text(
                        'Min: ${formatValue(minVal)}  ·  Max: ${formatValue(maxVal)}',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Card(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: CustomPaint(
                            painter: _SensorTrendPainter(
                              points,
                              domainStart: domainStart,
                              domainEnd: domainEnd,
                              lineColor: lineColor,
                              gridColor: Theme.of(
                                ctx,
                              ).dividerColor.withValues(alpha: 0.4),
                              // Detay görünümünde X ekseni gerçek zamana göre
                              // ölçeklensin ki Son 3 saat / Gün / Hafta / Ay
                              // gerçekten farklı pencereler göstersin.
                              useIndexX: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (range == _SensorHistoryRange.day)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: List.generate(
                            24,
                            (i) => Expanded(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (range == _SensorHistoryRange.last3h)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: List.generate(4, (i) {
                            final frac = i / 3;
                            final t = domainStart.add(
                              Duration(
                                milliseconds:
                                    ((domainEnd
                                                .difference(domainStart)
                                                .inMilliseconds) *
                                            frac)
                                        .round(),
                              ),
                            );
                            final label = t.hour.toString().padLeft(2, '0');
                            return Expanded(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9),
                              ),
                            );
                          }),
                        ),
                      )
                    else if (range == _SensorHistoryRange.week ||
                        range == _SensorHistoryRange.month)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: List.generate(
                            range == _SensorHistoryRange.week ? 7 : 8,
                            (i) {
                              final t = domainStart.add(Duration(days: i));
                              final label =
                                  '${t.day.toString().padLeft(2, '0')}';
                              return Expanded(
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 9),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        rangeChip(
                          _SensorHistoryRange.last3h,
                          t.t('history_last3h'),
                        ),
                        rangeChip(_SensorHistoryRange.day, t.t('history_day')),
                        rangeChip(
                          _SensorHistoryRange.week,
                          t.t('history_week'),
                        ),
                        rangeChip(
                          _SensorHistoryRange.month,
                          t.t('history_month'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWaqiCardImpl() {
    final st = state;

    // ESP32'nin city alanından PM2.5 alıp AQI hesapla
    final instant = _isSameDeviceId(_waqiInstantDeviceId, _activeDeviceId)
        ? _waqiInstantInfo
        : null;
    final cityAqi = st?.cityAqi ?? 0.0;
    final pm25 = (st?.cityPm25 ?? 0) > 0
        ? st!.cityPm25
        : ((instant?.pm25 ?? 0) > 0 ? instant!.pm25! : 0.0);
    final instantAqi = (instant?.aqi ?? 0).toDouble();
    final selectedWaqiName = (_waqiLocation?.name ?? '').trim();
    final hasCity =
        (st?.cityName.isNotEmpty ?? false) ||
        (instant?.city.trim().isNotEmpty ?? false) ||
        selectedWaqiName.isNotEmpty;
    final hasData = pm25 > 0 || cityAqi > 0 || instantAqi > 0;
    final aqi = cityAqi > 0
        ? cityAqi.clamp(0.0, 500.0)
        : (instantAqi > 0
              ? instantAqi.clamp(0.0, 500.0)
              : (pm25 > 0 ? _pm25ToAqi(pm25).clamp(0.0, 500.0) : 0.0));

    String aqiLabel;
    Color levelColor;
    String subtitle;

    if (!hasData) {
      // Henüz WAQI verisi yok; kullanıcıya konum seçmesini veya verinin
      // beklenmekte olduğunu göster.
      levelColor = Colors.grey.shade400;
      aqiLabel = hasCity
          ? 'Dış hava verisi bekleniyor'
          : 'WAQI için şehir seçin';
      subtitle = (st?.cityName.isNotEmpty ?? false)
          ? st!.cityName
          : ((instant?.city.trim().isNotEmpty ?? false)
                ? instant!.city.trim()
                : (selectedWaqiName.isNotEmpty
                      ? selectedWaqiName
                      : 'Şehir / istasyon seçmek için dokunun'));
    } else {
      String aqiLabelKey;
      if (aqi <= 50) {
        aqiLabelKey = 'aqi_level_good';
        levelColor = Colors.green.shade600;
      } else if (aqi <= 100) {
        aqiLabelKey = 'aqi_level_moderate';
        levelColor = Colors.yellow.shade700;
      } else if (aqi <= 150) {
        aqiLabelKey = 'aqi_level_sensitive';
        levelColor = Colors.orange.shade700;
      } else if (aqi <= 200) {
        aqiLabelKey = 'aqi_level_unhealthy';
        levelColor = Colors.red.shade700;
      } else if (aqi <= 300) {
        aqiLabelKey = 'aqi_level_very_unhealthy';
        levelColor = Colors.purple.shade700;
      } else {
        aqiLabelKey = 'aqi_level_hazardous';
        levelColor = const Color(0xFF4B2E2E); // kestane rengi
      }
      aqiLabel = t.t(aqiLabelKey);
      subtitle = (st?.cityName.isNotEmpty ?? false)
          ? st!.cityName
          : ((instant?.city.trim().isNotEmpty ?? false)
                ? instant!.city.trim()
                : (selectedWaqiName.isNotEmpty ? selectedWaqiName : 'WAQI'));
    }

    // PM2.5 ve hava durumu metriklerini tek satırda (gerekirse kayarak)
    // göstereceğimiz küçük etiketler listesi
    final metricWidgets = <Widget>[];

    if (hasData) {
      // PM2.5 bilgisini metriklerin yanında göster
      if (pm25 > 0) {
        metricWidgets.add(
          Text(
            'PM2.5: ${pm25.toStringAsFixed(1)} µg/m³',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }

      final cityTemp = (st?.cityTempC ?? 0) != 0
          ? st!.cityTempC
          : (instant?.tempC ?? 0);
      final cityHum = (st?.cityHum ?? 0) != 0
          ? st!.cityHum
          : (instant?.humidity ?? 0);
      final cityWind = (st?.cityWindKph ?? 0) != 0
          ? st!.cityWindKph
          : (instant?.windKph ?? 0);

      if (cityTemp != 0) {
        metricWidgets.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.thermostat,
                size: 14,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 2),
              Text(
                '${cityTemp.toStringAsFixed(1)}°C',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      }
      if (cityHum != 0) {
        metricWidgets.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.water_drop,
                size: 14,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 2),
              Text(
                '%${cityHum.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      }
      if (cityWind != 0) {
        metricWidgets.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.air,
                size: 14,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 2),
              Text(
                '${cityWind.toStringAsFixed(1)} km/h',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      }
    }

    final hasMetrics = metricWidgets.isNotEmpty;

    Widget buildSubtitleAndWarning() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            aqiLabel,
            style: TextStyle(fontWeight: FontWeight.w600, color: levelColor),
          ),
        ],
      );
    }

    Widget buildMetricsRow() {
      return Wrap(spacing: 12, runSpacing: 4, children: metricWidgets);
    }

    return InkWell(
      onTap: _openWaqiPicker,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_city, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(child: buildSubtitleAndWarning()),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: hasData ? 0.9 : 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    hasData ? 'AQI ${aqi.round()}' : 'WAQI',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (hasMetrics) buildMetricsRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeHeaderImpl() {
    final st = state;
    final quality = _aqHistory.isNotEmpty ? _aqHistory.last.value : 0.0;
    final q = quality.clamp(0, 100);
    final qualityInt = q.round();

    String labelKey;
    if (qualityInt >= 85) {
      labelKey = 'aqi_bucket_excellent';
    } else if (qualityInt >= 70) {
      labelKey = 'aqi_bucket_good';
    } else if (qualityInt >= 45) {
      labelKey = 'aqi_bucket_moderate';
    } else {
      labelKey = 'aqi_bucket_poor';
    }
    final label = t.t(labelKey);

    List<Color> progressColors;
    if (qualityInt >= 70) {
      progressColors = [Colors.green.shade700, Colors.greenAccent];
    } else if (qualityInt >= 40) {
      progressColors = [Colors.orange.shade700, Colors.yellowAccent];
    } else {
      progressColors = [Colors.red.shade700, Colors.redAccent];
    }

    final appearance = CircularSliderAppearance(
      startAngle: 150,
      angleRange: 240,
      size: 220,
      customWidths: CustomSliderWidths(trackWidth: 10, progressBarWidth: 10),
      customColors: CustomSliderColors(
        trackColor: Colors.grey.withValues(alpha: 0.25),
        progressBarColors: progressColors,
        dotColor: Colors.white,
        hideShadow: true,
      ),
      infoProperties: InfoProperties(
        modifier: (double _) => qualityInt.toString(),
        mainLabelStyle: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
        ),
        bottomLabelText: label,
        bottomLabelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: progressColors.last,
        ),
      ),
    );

    return Column(
      children: [
        SleekCircularSlider(
          appearance: appearance,
          min: 0,
          max: 100,
          initialValue: q.toDouble(),
        ),
        const SizedBox(height: 10),
        _buildHomeInsight(st),
      ],
    );
  }

  Widget _buildHomeInsightImpl(DeviceState? st) {
    if (st == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    String title;
    switch (st.fanReason) {
      case 'odor_cleanup':
        title = t.t('home_fan_odor');
        break;
      case 'health':
        title = t.t('home_fan_health');
        break;
      default:
        title = t.t('home_fan_manual');
        break;
    }

    final metrics = <String>[
      'Fan ${st.fanPercent}%',
      '${t.t('rpm')} ${st.rpm}',
      if (st.pm25 > 0.05) 'PM2.5 ${st.pm25.toStringAsFixed(1)}',
      if (st.vocIndex > 0.5) 'VOC ${st.vocIndex.round()}',
      if (st.noxIndex > 0.5) 'NOx ${st.noxIndex.round()}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.22,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                st.odorBoostActive ? Icons.air : Icons.monitor_heart_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            metrics.join('  ·  '),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTrendStripImpl() {
    final hasAny = _aqHistory.length >= 2 || _cityAqHistory.length >= 2;
    if (!hasAny) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      // Detayda yine PM2.5 geçmişini gösteriyoruz; bu ekran küçük bir
      // "iç vs dış hava kalitesi" özet şeridi gibi davranıyor.
      onTap: () => _openSensorDetails(
        title: 'PM2.5',
        unit: 'µg/m³',
        icon: Icons.blur_on,
        history: _pm25History.isNotEmpty ? _pm25History : _aqHistory,
        lineColor: Colors.tealAccent,
      ),
      child: SizedBox(
        height: 40,
        width: double.infinity,
        child: CustomPaint(
          painter: _HomeTrendStripPainter(
            home: _aqHistory,
            city: _cityAqHistory,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTileNewImpl({
    required String label,
    String? subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    bool boldTitle = false,
  }) {
    final theme = Theme.of(context);
    final bool isOn = value && enabled;
    final Color iconColor = isOn
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    final Color titleColor = isOn
        ? theme.colorScheme.onSurface
        : theme.textTheme.bodyMedium?.color ??
              theme.colorScheme.onSurface.withValues(alpha: 0.85);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: icon != null ? Icon(icon, size: 20, color: iconColor) : null,
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: boldTitle ? FontWeight.w600 : FontWeight.normal,
            color: titleColor,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
        trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
  }

  Widget _buildFanCleanTileImpl(DeviceState st, bool canControl) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool on = st.masterOn;
    final int mode = st.mode;
    String modeLabel;
    switch (mode) {
      case 0:
        modeLabel = t.t('sleep');
        break;
      case 4:
        modeLabel = t.t('turbo');
        break;
      case 3:
        modeLabel = t.t('high');
        break;
      case 2:
        modeLabel = t.t('med');
        break;
      case 1:
      default:
        modeLabel = t.t('auto');
        break;
    }

    Widget fanIcon() {
      final baseColor = isDark
          ? Colors.white
          : theme.colorScheme.primary.withValues(alpha: 0.9);
      final base = SvgPicture.asset(
        'assets/icons/fan.svg',
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(
          baseColor.withValues(alpha: on ? 1 : 0.6),
          BlendMode.srcIn,
        ),
      );
      if (!on) {
        if (_fanSpinCtrl.isAnimating) _fanSpinCtrl.stop();
        return base;
      }
      if (!_fanSpinCtrl.isAnimating) {
        _fanSpinCtrl.repeat();
      }
      return RotationTransition(turns: _fanSpinCtrl, child: base);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -3),
            minVerticalPadding: 0,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: fanIcon(),
            title: Text(
              t.t('fan_clean_title'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        modeLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _fanExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Switch(
                  value: on,
                  onChanged: canControl
                      ? (v) async {
                          if (v) {
                            await _send({
                              'masterOn': true,
                              'cleanOn': true,
                              'fanPercent': 35,
                            });
                          } else {
                            final ok = await _send({
                              'masterOn': false,
                              'cleanOn': false,
                              'ionOn': false,
                            });
                            if (ok && mounted && !_isDoaDevice) {
                              _safeSetState(() {
                                _autoHumEnabled = false;
                              });
                            }
                          }
                        }
                      : null,
                ),
              ],
            ),
            onTap: () => _safeSetState(() => _fanExpanded = !_fanExpanded),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Column(
                children: [
                  _fanModeButton(t.t('auto'), 5, mode),
                  _fanModeButton(t.t('turbo'), 4, mode),
                  _fanModeButton(t.t('high'), 3, mode),
                  _fanModeButton(t.t('med'), 2, mode),
                  _fanModeButton(t.t('low'), 1, mode),
                ],
              ),
            ),
            crossFadeState: _fanExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _fanModeButton(String label, int modeValue, int currentMode) {
    final selected = modeValue == currentMode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primary.withAlpha(180)
                : Colors.black.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            side: BorderSide(
              color: selected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          onPressed: () =>
              _send({'mode': modeValue, 'masterOn': true, 'cleanOn': true}),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: selected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrameLightTileImpl(DeviceState? st, bool canControl) {
    final rgbOn = st?.rgbOn ?? false;
    final theme = Theme.of(context);
    final Color iconColor = rgbOn
        ? theme.colorScheme.primary
        : theme.iconTheme.color?.withValues(alpha: 0.7) ??
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -3),
            minVerticalPadding: 0,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              Icons.local_fire_department_outlined,
              size: 22,
              color: iconColor,
            ),
            title: Text(
              t.t('flame'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _frameExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Switch(
                  value: rgbOn,
                  onChanged: canControl
                      ? (v) => _send({
                          'rgb': {'on': v},
                        })
                      : null,
                ),
              ],
            ),
            onTap: () => _safeSetState(() => _frameExpanded = !_frameExpanded),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: _rgbPalette(st),
            ),
            crossFadeState: _frameExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTogglesImpl() {
    final st = state;
    final canControl = _canControlDevice;

    return Column(
      children: [
        const SizedBox(height: 4),
        if (st != null) _buildFanCleanTile(st, canControl),
        _buildAutoHumidityTile(),
        _buildToggleTileNew(
          label: t.t('ion'),
          value: st?.ionOn ?? false,
          enabled: canControl,
          onChanged: (v) => _send({'ionOn': v}),
          icon: Icons.bubble_chart_outlined,
          boldTitle: true,
        ),
        _buildToggleTileNew(
          label: t.t('light'),
          value: st?.lightOn ?? false,
          enabled: canControl,
          onChanged: (v) => _send({'lightOn': v}),
          icon: Icons.light_mode_outlined,
          boldTitle: true,
        ),
        _buildFrameLightTile(st, canControl),
      ],
    );
  }

  bool _hasEnvSignal(DeviceState? s) {
    if (s == null) return false;
    if ((s.envSeq ?? 0) > 0) return true;
    if (s.tempC.abs() > 0.01) return true;
    if (s.hum.abs() > 0.01) return true;
    if (s.pm25.abs() > 0.01) return true;
    if (s.vocIndex.abs() > 0.01) return true;
    if (s.noxIndex.abs() > 0.01) return true;
    return false;
  }

  Widget _buildHomeTabImpl() {
    final hum = _humHistory.isNotEmpty ? _humHistory.last.value : 0.0;
    final temp = _tempHistory.isNotEmpty ? _tempHistory.last.value : 0.0;
    final aqScore = _aqHistory.isNotEmpty
        ? _aqHistory.last.value.clamp(0, 100)
        : 100.0;
    final severity = ((100.0 - aqScore) / 100.0).clamp(0.0, 1.0);
    final particleCount = (10 + severity * 50).round();
    final hasEnv = _hasEnvSignal(state);

    return Stack(
      children: [
        Positioned.fill(child: _HomeDustLayer(intensity: particleCount)),
        ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          children: [
            _buildWaqiCard(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHomeHeader(),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHomeTrendStrip(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.water_drop_outlined, size: 14),
                  const SizedBox(width: 4),
                  Text('${hum.toStringAsFixed(1)} %'),
                  const SizedBox(width: 16),
                  const Icon(Icons.thermostat, size: 14),
                  const SizedBox(width: 4),
                  Text('${temp.toStringAsFixed(1)} °C'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (!_canControlDevice)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: Colors.amber.withValues(alpha: 0.2),
                  child: ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(t.t('device_not')),
                    subtitle: Text(t.t('device_not_hint')),
                    onTap: () => _tryConnect(),
                    trailing: TextButton(
                      onPressed: () => _tryConnect(),
                      child: Text(t.t('connect')),
                    ),
                  ),
                ),
              ),
            if (_canControlDevice && (state?.rpm ?? 0) == 0 && !hasEnv)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: Colors.amber.withValues(alpha: 0.2),
                  child: ListTile(
                    leading: const Icon(Icons.sensor_door_outlined),
                    title: Text(t.t('sensor_zero_title')),
                    subtitle: Text(t.t('sensor_zero_hint')),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHomeToggles(),
            ),
          ],
        ),
      ],
    );
  }

  // Aday plan mevcut etkin planlarla çakışıyor mu? (gece aşımı destekli)
  bool _wouldOverlapWith(_PlanItem candidate, {int? exceptIndex}) {
    final intervals = <List<int>>[];

    // Mevcut etkin planları topla (exceptIndex hariç)
    for (var i = 0; i < _plans.length; i++) {
      if (i == exceptIndex) continue;
      final p = _plans[i];
      if (!p.enabled) continue;
      final s = p.start.hour * 60 + p.start.minute;
      final e = p.end.hour * 60 + p.end.minute;
      if (s == e) {
        intervals.add([0, 1440]);
        continue;
      }
      if (s < e) {
        intervals.add([s, e]);
      } else {
        intervals.add([s, 1440]);
        intervals.add([0, e]);
      }
    }

    // Aday plan etkinse onu da ekle
    if (candidate.enabled) {
      final s = candidate.start.hour * 60 + candidate.start.minute;
      final e = candidate.end.hour * 60 + candidate.end.minute;
      if (s == e) {
        intervals.add([0, 1440]);
      } else if (s < e) {
        intervals.add([s, e]);
      } else {
        intervals.add([s, 1440]);
        intervals.add([0, e]);
      }
    }

    if (intervals.length <= 1) return false;
    intervals.sort((a, b) => a[0].compareTo(b[0]));
    var curEnd = intervals.first[1];
    for (var i = 1; i < intervals.length; i++) {
      final s = intervals[i][0];
      final e = intervals[i][1];
      if (s < curEnd) return true; // çakışma
      curEnd = e;
    }
    return false;
  }

  Widget _buildPlannerImpl() {
    final s = state;
    final hasAlert = (s?.filterAlert ?? false) || (lastFilterMsg == 'BAD');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                widget.i18n.t('planner'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                tooltip: widget.i18n.t('refresh'),
                onPressed: () async {
                  unawaited(_connectionTick(force: true));
                  final canForceBle =
                      state?.pairingWindowActive == true ||
                      state?.softRecoveryActive == true ||
                      state?.apSessionActive == true;
                  unawaited(_autoConnectBleIfNeeded(force: canForceBle));
                  final st = await _fetchStateSmart();
                  if (st != null && mounted) {
                    _safeSetState(() {
                      state = st;
                      _syncAutoHumControlsFromState(st);
                      _pushHistorySample(st);
                    });
                  }
                  // User explicitly requested a refresh: evaluate once without continuous forcing
                  _evaluatePlans(force: true);
                },
                icon: const Icon(Icons.refresh),
              ),
              TextButton.icon(
                onPressed: _syncTimeFromPhone,
                icon: const Icon(Icons.access_time_filled),
                label: Text(widget.i18n.t('sync_time')),
              ),
              FilledButton.icon(
                onPressed: _addPlan,
                icon: const Icon(Icons.add),
                label: Text(widget.i18n.t('add_plan')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasAlert)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(widget.i18n.t('filter_alert_title')),
                subtitle: Text(widget.i18n.t('filter_alert_subtitle')),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _plans.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_busy, size: 64),
                        const SizedBox(height: 12),
                        Text(widget.i18n.t('no_plan')),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _plans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _plans[index];
                      final timeText =
                          _fmtTod(item.start) + ' – ' + _fmtTod(item.end);
                      final modeNames = [
                        t.t('sleep'),
                        t.t('low'),
                        t.t('med'),
                        t.t('high'),
                        t.t('turbo'),
                        t.t('auto'),
                      ];

                      final base = item.mode == 5
                          ? modeNames[item.mode]
                          : '${modeNames[item.mode]}  %${_pctForMode(item.mode)}';

                      final extras = [
                        if (item.lightOn) '💡',
                        if (item.ionOn) '🧪',
                        if (item.rgbOn) '🔥',
                      ].join(' ');
                      final subtitle = extras.isEmpty ? base : '$base  $extras';

                      return Card(
                        child: ListTile(
                          leading: Switch(
                            value: item.enabled,
                            onChanged: (v) {
                              if (v) {
                                final cand = _plans[index];
                                final tmp = _PlanItem(
                                  enabled: true,
                                  start: cand.start,
                                  end: cand.end,
                                  mode: cand.mode,
                                  fanPercent: cand.fanPercent,
                                  lightOn: cand.lightOn,
                                  ionOn: cand.ionOn,
                                  rgbOn: cand.rgbOn,
                                  autoHumEnabled: cand.autoHumEnabled,
                                  autoHumTarget: cand.autoHumTarget,
                                );
                                if (_wouldOverlapWith(
                                  tmp,
                                  exceptIndex: index,
                                )) {
                                  _showSnack(t.t('overlap_exists'));
                                  return; // engelle
                                }
                              }
                              _safeSetState(() => _plans[index].enabled = v);
                              _trySavePlans();
                            },
                          ),
                          title: Text(timeText),
                          subtitle: Text(subtitle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  final edited =
                                      await showModalBottomSheet<_PlanItem>(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (ctx) => _PlanEditor(
                                          i18n: widget.i18n,
                                          isDoa: _isDoaDevice,
                                          initial: item,
                                          overlaps: (cand) => _wouldOverlapWith(
                                            cand,
                                            exceptIndex: index,
                                          ),
                                        ),
                                      );
                                  if (edited != null) {
                                    if (_wouldOverlapWith(
                                      edited,
                                      exceptIndex: index,
                                    )) {
                                      _showSnack(t.t('overlap_exists'));
                                      return; // düzenlemeyi uygulatma
                                    }
                                    _safeSetState(() => _plans[index] = edited);
                                    _trySavePlans();
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  _safeSetState(() => _plans.removeAt(index));
                                  _trySavePlans();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoHumidityTileImpl() {
    final theme = Theme.of(context);
    final canControl = _canControlDevice;
    final isDoa = _isDoaDevice;
    final s = state;
    final effectiveAutoHumEnabled = isDoa
        ? (s?.waterAutoEnabled ?? _doaWaterAutoEnabled)
        : (s?.autoHumEnabled ?? _autoHumEnabled);
    final effectiveAutoHumTarget =
        (s?.autoHumTarget.toDouble() ?? _autoHumTarget)
            .clamp(30.0, 70.0)
            .toDouble();
    final target = effectiveAutoHumTarget.round();
    final double? humDoa = (s != null && !s.dhtHum.isNaN) ? s.dhtHum : null;

    final Color chipColor = effectiveAutoHumEnabled
        ? theme.colorScheme.primary
        : theme.disabledColor;

    final labelColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
    final hintColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7) ??
        labelColor.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -3),
            minVerticalPadding: 0,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              isDoa ? Icons.local_florist : Icons.water_drop_outlined,
              size: 22,
              color: effectiveAutoHumEnabled
                  ? chipColor
                  : theme.iconTheme.color?.withValues(alpha: 0.7),
            ),
            title: Text(
              isDoa ? t.t('watering_auto_title') : t.t('auto_humidity'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isDoa
                        ? '${_doaWaterDurationMin.round()} ${t.t('watering_minutes_suffix')} · ${_doaWaterIntervalHr.round()} ${t.t('watering_hours_suffix')}'
                        : '$target%',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: chipColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  effectiveAutoHumEnabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: effectiveAutoHumEnabled
                        ? theme.colorScheme.primary
                        : hintColor,
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: effectiveAutoHumEnabled,
                  onChanged: canControl
                      ? (v) async {
                          _manualOverride = true;
                          final ok = isDoa
                              ? await _sendDoaWateringConfig(enabled: v)
                              : await _sendArtAutoHumidityConfig(enabled: v);
                          if (!ok) return;
                          if (mounted) {
                            _safeSetState(() {
                              if (isDoa) {
                                _doaWaterAutoEnabled = v;
                              } else {
                                _autoHumEnabled = v;
                              }
                            });
                          }
                          if (isDoa) {
                            await _persistDoaWatering();
                          }
                        }
                      : null,
                ),
              ],
            ),
            onTap: () =>
                _safeSetState(() => _autoHumExpanded = !_autoHumExpanded),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 4,
                bottom: 8,
              ),
              child: isDoa
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          t.t('watering_duration_label'),
                          style: TextStyle(
                            fontSize: 13,
                            color: labelColor.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_doaWaterDurationMin.round()} ${t.t('watering_minutes_suffix')}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: chipColor,
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            min: 1,
                            max: 30,
                            divisions: 29,
                            value: _doaWaterDurationMin.clamp(1, 30),
                            label:
                                '${_doaWaterDurationMin.round()} ${t.t('watering_minutes_suffix')}',
                            onChanged: (v) {
                              _safeSetState(() => _doaWaterDurationMin = v);
                            },
                            onChangeEnd: (v) async {
                              _doaWaterDurationMin = v;
                              await _persistDoaWatering();
                              await _sendDoaWateringConfig();
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.t('watering_interval_label'),
                          style: TextStyle(
                            fontSize: 13,
                            color: labelColor.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_doaWaterIntervalHr.round()} ${t.t('watering_hours_suffix')}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: chipColor,
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            min: 1,
                            max: 48,
                            divisions: 47,
                            value: _doaWaterIntervalHr.clamp(1, 48),
                            label:
                                '${_doaWaterIntervalHr.round()} ${t.t('watering_hours_suffix')}',
                            onChanged: (v) {
                              _safeSetState(() => _doaWaterIntervalHr = v);
                            },
                            onChangeEnd: (v) async {
                              _doaWaterIntervalHr = v;
                              await _persistDoaWatering();
                              await _sendDoaWateringConfig();
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.t('watering_hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: hintColor),
                        ),
                        if (humDoa != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'DHT11: ${humDoa.toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 11, color: hintColor),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.t('watering_auto_hum'),
                              style: TextStyle(
                                fontSize: 13,
                                color: labelColor.withValues(alpha: 0.9),
                              ),
                            ),
                            Switch(
                              value: _doaHumAutoEnabled,
                              onChanged: canControl
                                  ? (v) {
                                      _safeSetState(() {
                                        _doaHumAutoEnabled = v;
                                      });
                                      _sendDoaHumAutoConfig(v);
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.t('watering_manual'),
                              style: TextStyle(
                                fontSize: 13,
                                color: labelColor.withValues(alpha: 0.9),
                              ),
                            ),
                            Switch(
                              value: _doaManualWaterOn,
                              onChanged: canControl
                                  ? (v) {
                                      _safeSetState(
                                        () => _doaManualWaterOn = v,
                                      );
                                      _sendDoaManualWater(v);
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$target%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: chipColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            min: 30,
                            max: 70,
                            divisions: 40,
                            value: effectiveAutoHumTarget,
                            onChanged: canControl
                                ? (v) {
                                    _manualOverride = true;
                                    _safeSetState(() => _autoHumTarget = v);
                                  }
                                : null,
                            onChangeEnd: (canControl && effectiveAutoHumEnabled)
                                ? (_) {
                                    _manualOverride = true;
                                    _sendArtAutoHumidityConfig();
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.t('auto_humidity_recommended'),
                          style: TextStyle(fontSize: 11, color: hintColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.t('auto_humidity_hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: hintColor),
                        ),
                      ],
                    ),
            ),
            crossFadeState: _autoHumExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  String _fmtTodImpl(TimeOfDay t) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String? _normalizeBaseUrl(String raw) => _normalizeBaseUrlImpl(raw);

  Future<bool> _applyProvisionedBaseUrl(String raw, {bool showSnack = true}) =>
      _applyProvisionedBaseUrlImpl(raw, showSnack: showSnack);

  Future<void> _openBleManageAndProvision() => _openBleManageAndProvisionImpl();

  Future<String?> _pairTokenForBleSheet(String? id6) =>
      _pairTokenForBleSheetImpl(id6);

  Future<void> _clearPairTokenForBleSheet(String? id6) =>
      _clearPairTokenForBleSheetImpl(id6);

  Future<void> _resetPairTokenForActiveDevice() =>
      _resetPairTokenForActiveDeviceImpl();

  Future<void> _factoryResetActiveDevice() => _factoryResetActiveDeviceImpl();

  Future<bool> _tryClaimOwnerOverAp({
    required String user,
    required String pass,
  }) => _tryClaimOwnerOverApImpl(user: user, pass: pass);

  Future<bool> _refreshOwnerStateFromDevice() =>
      _refreshOwnerStateFromDeviceImpl();

  Future<bool> _isBluetoothReadyForAutoClaim() =>
      _isBluetoothReadyForAutoClaimImpl();

  Future<bool> _finalizeOwnerClaimAfterQr({
    required String? id6,
    required String? setupUser,
    required String? setupPass,
  }) => _finalizeOwnerClaimAfterQrImpl(
    id6: id6,
    setupUser: setupUser,
    setupPass: setupPass,
  );

  Future<bool> _ensureLocalOwnerClaimAfterProvision({
    String? idHint,
    String? setupUserHint,
    String? setupPassHint,
    String source = 'ble_provision',
  }) => _ensureLocalOwnerClaimAfterProvisionImpl(
    idHint: idHint,
    setupUserHint: setupUserHint,
    setupPassHint: setupPassHint,
    source: source,
  );

  Future<bool> _claimViaCloudWithSecret({
    required String id6,
    required String claimSecret,
    bool allowRecoveryPrompt = true,
  }) => _claimViaCloudWithSecretImpl(
    id6: id6,
    claimSecret: claimSecret,
    allowRecoveryPrompt: allowRecoveryPrompt,
  );

  Future<void> _openManualClaimSecretRecovery() =>
      _openManualClaimSecretRecoveryImpl();

  Future<void> _retryOwnerClaimFlow() => _retryOwnerClaimFlowImpl();

  // AP ile yönetim: Wi-Fi AP'ye bağlıyken yerel kontrolü başlat.
  Future<void> _toggleApControl() => _toggleApControlImpl();

  Future<void> _openApProvision() => _openApProvisionImpl();

  Future<void> _toggleBleControl({
    bool interactive = true,
    bool preserveActiveDevice = false,
    bool allowUnownedWithoutSetupCreds = false,
  }) => _toggleBleControlImpl(
    interactive: interactive,
    preserveActiveDevice: preserveActiveDevice,
    allowUnownedWithoutSetupCreds: allowUnownedWithoutSetupCreds,
  );

  Future<void> _bleEnsureOwnerAuthed({String? targetId6}) =>
      _bleEnsureOwnerAuthedImpl(targetId6: targetId6);

  String? _extractId6FromBleName(String? name) =>
      _extractId6FromBleNameImpl(name);

  Future<bool> _bleSendJson(Map<String, dynamic> body) =>
      _bleSendJsonImpl(body);
}
