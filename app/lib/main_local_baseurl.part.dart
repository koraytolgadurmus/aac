part of 'main.dart';

extension _HomeScreenLocalBaseUrlPart on _HomeScreenState {
  String? _normalizeBaseUrlImpl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://' + s;
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    var host = uri.host.replaceAll(RegExp(r'\.+$'), '');
    if (host.endsWith('.loca') && !host.endsWith('.local')) {
      host = '${host}l';
    }
    if (host.isEmpty || host == '0.0.0.0') return null;
    final ipv4 = RegExp(r'^\d+(\.\d+){3}$');
    final partialIpv4 = RegExp(r'^\d+(\.\d+){2}$');
    if (!ipv4.hasMatch(host) && partialIpv4.hasMatch(host)) return null;
    final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
    final port = (uri.hasPort && uri.port != 80 && uri.port != 443)
        ? ':${uri.port}'
        : '';
    return '$scheme://$host$port';
  }

  Future<bool> _applyProvisionedBaseUrlImpl(
    String raw, {
    bool showSnack = true,
  }) async {
    final rawNormalized = _normalizeBaseUrl(raw);
    final normalized = rawNormalized == null
        ? null
        : (_activeDevice != null
              ? _normalizedStoredBaseForDevice(_activeDevice!, rawNormalized)
              : _preferredStableLocalBaseUrl(rawNormalized));
    if (normalized == null) return false;

    final changed = normalized != baseUrl;
    if (normalized == 'http://192.168.4.1') {
      _markApSticky();
    } else if (!_baseHostLooksLikeIpv4(normalized)) {
      // Leaving AP towards non-IP local host; let sticky expire naturally.
    } else {
      _preferApUntil = null;
    }
    if (mounted) {
      _safeSetState(() {
        baseUrl = normalized;
        api.baseUrl = normalized;
        _urlCtl.text = normalized;
      });
    } else {
      baseUrl = normalized;
      api.baseUrl = normalized;
      _urlCtl.text = normalized;
    }

    final currentApiPair = (api.pairToken ?? '').trim();
    if (currentApiPair.isEmpty && _activeDeviceId != null) {
      final storedPair = await _loadPairToken(_activeDeviceId!);
      if (storedPair != null && storedPair.isNotEmpty) {
        api.setPairToken(storedPair);
        debugPrint('[BASEURL] Loaded pairToken for device $_activeDeviceId');
      } else {
        final device = _devices.firstWhere(
          (d) => d.id == _activeDeviceId,
          orElse: () =>
              _SavedDevice(id: '', brand: kDefaultDeviceBrand, baseUrl: ''),
        );
        if (device.pairToken != null && device.pairToken!.isNotEmpty) {
          api.setPairToken(device.pairToken);
          debugPrint('[BASEURL] Loaded pairToken from device list');
        }
      }
    } else if (_activeDeviceId != null) {
      debugPrint(
        '[BASEURL] Keeping existing API pairToken for $_activeDeviceId',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('baseUrl', normalized);
      await _updateActiveDeviceBaseUrl(normalized);
    } catch (_) {}

    _startPolling();

    if (showSnack && mounted) {
      final key = changed ? t.t('base_url_updated') : t.t('base_url_saved');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$key: $normalized')));
    }
    return true;
  }
}
