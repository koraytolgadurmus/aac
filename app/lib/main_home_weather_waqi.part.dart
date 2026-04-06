part of 'main.dart';

extension _HomeScreenWeatherWaqiPart on _HomeScreenState {
  Future<void> _loadWeather() async {
    try {
      final activeIdAtStart = _activeDeviceId;
      final waqiLoc = _waqiLocation;
      if (waqiLoc == null) return;
      final info = await _weatherApi.fetchWaqi(
        lat: waqiLoc.lat,
        lon: waqiLoc.lon,
      );
      if (info != null &&
          mounted &&
          _isSameDeviceId(_activeDeviceId, activeIdAtStart)) {
        await _cacheActiveDeviceWaqiInfo(info, forcePersist: true);
        // ignore: invalid_use_of_protected_member
        setState(() {
          _waqiInstantInfo = info;
          _waqiInstantDeviceId = activeIdAtStart;
        });
      }
    } catch (e) {
      debugPrint('[WAQI] fetch error: $e');
    }
  }

  Future<void> _saveWaqiPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('waqi_location');
      await p.setString(
        'waqi_recent_locations',
        jsonEncode(
          _waqiRecent
              .map((e) => {'name': e.name, 'lat': e.lat, 'lon': e.lon})
              .toList(),
        ),
      );
    } catch (e) {
      debugPrint('[WAQI] save prefs error: $e');
    }
  }

  Future<void> _openWaqiPicker() async {
    if (!mounted) return;
    Timer? debounce;
    final selected = await showModalBottomSheet<WaqiLocation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final searchCtl = TextEditingController();
        List<WaqiLocation> results = [];
        bool searching = false;
        String? error;

        Future<void> doSearch(
          String q,
          void Function(void Function()) setS,
        ) async {
          final trimmed = q.trim();
          if (trimmed.isEmpty) {
            setS(() {
              results = [];
              error = null;
              searching = false;
            });
            return;
          }
          setS(() {
            searching = true;
            error = null;
          });
          try {
            final list = await _weatherApi.searchWaqiStations(trimmed);
            setS(() {
              results = list;
            });
          } catch (e) {
            setS(() {
              error = e.toString();
            });
          } finally {
            setS(() {
              searching = false;
            });
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'WAQI istasyonu seç',
                        style: TextStyle(
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchCtl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Şehir, ilçe veya istasyon adı',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (q) {
                      debounce?.cancel();
                      debounce = Timer(
                        const Duration(milliseconds: 400),
                        () => doSearch(q, setS),
                      );
                    },
                    onSubmitted: (q) => doSearch(q, setS),
                  ),
                  const SizedBox(height: 12),
                  if (_waqiRecent.isNotEmpty) ...[
                    Text(
                      'Son aranan WAQI istasyonları',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _waqiRecent
                          .map(
                            (loc) => InputChip(
                              label: Text(loc.name),
                              onPressed: () => Navigator.of(ctx).pop(loc),
                              onDeleted: () {
                                // ignore: invalid_use_of_protected_member
                                setState(() {
                                  _waqiRecent = _waqiRecent
                                      .where(
                                        (e) =>
                                            e.lat != loc.lat ||
                                            e.lon != loc.lon ||
                                            e.name != loc.name,
                                      )
                                      .toList();
                                });
                                _saveWaqiPrefs();
                                setS(() {});
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (searching) const LinearProgressIndicator(),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ],
                  Flexible(
                    child: results.isEmpty && !searching
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Sonuç bulunamadı. Lütfen farklı bir isim deneyin.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final loc = results[i];
                              return ListTile(
                                leading: const Icon(Icons.location_city),
                                title: Text(loc.name),
                                subtitle: Text(
                                  'Lat: ${loc.lat.toStringAsFixed(3)}, Lon: ${loc.lon.toStringAsFixed(3)}',
                                ),
                                onTap: () => Navigator.of(ctx).pop(loc),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (selected != null) {
      final activeIdAtSelection = _activeDeviceId;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _waqiLocation = selected;
        _waqiRecent = [
          selected,
          ..._waqiRecent.where(
            (e) =>
                e.lat != selected.lat ||
                e.lon != selected.lon ||
                e.name != selected.name,
          ),
        ].take(5).toList();
      });
      final idx = _indexOfDeviceByIdLike(activeIdAtSelection);
      if (idx != -1) {
        _devices[idx].waqiName = selected.name;
        _devices[idx].waqiLat = selected.lat;
        _devices[idx].waqiLon = selected.lon;
        await _saveDevicesToPrefs();
      }
      await _saveWaqiPrefs();
      try {
        final instant = await _weatherApi.fetchWaqi(
          lat: selected.lat,
          lon: selected.lon,
        );
        if (instant != null &&
            mounted &&
            _activeDeviceId == activeIdAtSelection) {
          await _cacheActiveDeviceWaqiInfo(instant, forcePersist: true);
          // ignore: invalid_use_of_protected_member
          setState(() {
            _waqiInstantInfo = instant;
            _waqiInstantDeviceId = _activeDeviceId;
          });
        }
      } catch (_) {}
      final sent = await _send({
        'waqi': {
          'name': selected.name,
          'lat': selected.lat,
          'lon': selected.lon,
        },
      });
      if (sent) {
        try {
          final refreshed = await _fetchStateSmart(force: true);
          if (refreshed != null && mounted) {
            // ignore: invalid_use_of_protected_member
            setState(() => state = refreshed);
          }
        } catch (_) {}
      }
    }
  }
}
