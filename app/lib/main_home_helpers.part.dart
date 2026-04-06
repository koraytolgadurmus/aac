part of 'main.dart';

extension _HomeScreenHelpersPart on _HomeScreenState {
  bool _effectiveOwnerExists() {
    if (_cloudCommandEligibleForActive() && _cloudOwnerExistsOverride != null) {
      return _cloudOwnerExistsOverride!;
    }
    return state?.ownerExists == true;
  }

  bool _isOwnerRole() {
    final localRole = (state?.authRole ?? '').toUpperCase();
    if (localRole == 'OWNER') return true;
    final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
    if (_cloudLoggedIn() && cloudRole == 'OWNER') return true;
    return false;
  }

  bool _authRoleKnown(String? role) {
    final r = (role ?? '').trim().toUpperCase();
    if (r.isEmpty) return false;
    if (r == 'UNKNOWN' || r == 'BILINMIYOR') return false;
    return true;
  }

  String _authRoleLabel() {
    final role = (state?.authRole ?? '').toUpperCase();
    if (role.isEmpty || role == 'UNKNOWN') return 'Bilinmiyor';
    if (role == 'OWNER') return 'Owner';
    if (role == 'USER') return 'User';
    if (role == 'GUEST') return 'Guest';
    if (role == 'SETUP') return 'Setup';
    return role;
  }

  String _cloudStateLabel() {
    final s = _effectiveCloudStateUpper();
    if (s.isEmpty || s == 'UNKNOWN') return 'Bilinmiyor';
    if (s == 'DISABLED' || s == 'OFF') return 'Kapalı';
    if (s == 'SETUP_REQUIRED') return 'Kurulum Gerekli';
    if (s == 'PROVISIONING') return 'Provisioning';
    if (s == 'LINKED') return 'Bağlı (Link)';
    if (s == 'CONNECTED') return 'Bağlı';
    if (s == 'DEGRADED') return 'Sorunlu';
    return s;
  }

  String _cloudReasonLabel(String reasonRaw) {
    final r = reasonRaw.trim().toLowerCase();
    if (r.isEmpty) return '';
    if (r == 'cloud_init') return 'Cloud başlatılıyor';
    if (r == 'user_disabled') return 'Kullanıcı cloud kapattı';
    if (r == 'no_endpoint') return 'Cloud endpoint ayarlı değil';
    if (r == 'no_wifi') return 'Wi-Fi bağlı değil';
    if (r == 'fs_fail') return 'Dosya sistemi erişim hatası';
    if (r == 'needs_provisioning') return 'Provisioning gerekiyor';
    if (r == 'tls_config') return 'TLS yapılandırılıyor';
    if (r == 'no_root_ca') return 'Root CA eksik';
    if (r == 'tls_fail') return 'TLS yükleme hatası';
    if (r == 'tls_ready') return 'TLS hazır';
    if (r == 'no_time') return 'Cihaz saati senkron değil';
    if (r == 'mqtt_connected' || r == 'mqtt_loop') return 'MQTT bağlı';
    if (r == 'mqtt_connect_fail') return 'MQTT bağlantı hatası';
    return reasonRaw.trim();
  }

  String _boolDebugLabel(bool? v) {
    if (v == null) return '-';
    return v ? 'EVET' : 'HAYIR';
  }

  String _stringOrDash(String? v) {
    final s = (v ?? '').trim();
    return s.isEmpty ? '-' : s;
  }

  String _formatDebugTime(DateTime? dt) {
    if (dt == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(dt);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} (${_formatElapsedShortMs(diff.inMilliseconds)})';
  }

  List<MapEntry<String, String>> _cloudDiagnosticsRows() {
    final active = _activeDevice;
    final id6 = _deviceId6ForMqtt();
    final canonical = _activeCanonicalDeviceId;
    final localState = state;
    final localReason = (localState?.cloudStateReason ?? '').trim();
    final activeListed =
        id6 != null && id6.isNotEmpty && _cloudApiDeviceIds.contains(id6);
    final listedIds = _cloudApiDeviceIds.isEmpty
        ? '-'
        : _cloudApiDeviceIds.join(', ');
    return <MapEntry<String, String>>[
      MapEntry('Aktif cihaz', _stringOrDash(active?.displayName)),
      MapEntry('Aktif cihaz ID', _stringOrDash(active?.id)),
      MapEntry('Canonical ID', _stringOrDash(canonical)),
      MapEntry('MQTT/Cloud ID6', _stringOrDash(id6)),
      MapEntry('Thing name', _stringOrDash(active?.thingName)),
      MapEntry(
        'Base URL',
        _stringOrDash(
          active != null ? _preferredDisplayBaseUrlForDevice(active) : null,
        ),
      ),
      MapEntry('Last IP', _stringOrDash(active?.lastIp)),
      MapEntry(
        'Pair token',
        (active?.pairToken ?? '').trim().isEmpty ? 'YOK' : 'VAR',
      ),
      MapEntry('Cloud linked', _boolDebugLabel(active?.cloudLinked)),
      MapEntry('Cloud role(list)', _stringOrDash(active?.cloudRole)),
      MapEntry('Cloud source(list)', _stringOrDash(active?.cloudSource)),
      MapEntry('Auth role(state)', _authRoleLabel()),
      MapEntry('Owner exists(local)', _boolDebugLabel(localState?.ownerExists)),
      MapEntry(
        'Owner setup(local)',
        _boolDebugLabel(localState?.ownerSetupDone),
      ),
      MapEntry(
        'Owner override(cloud)',
        _boolDebugLabel(_cloudOwnerExistsOverride),
      ),
      MapEntry('Claim(local)', _boolDebugLabel(localState?.cloudClaimed)),
      MapEntry('Cloud enabled(app)', _boolDebugLabel(_cloudUserEnabledLocal)),
      MapEntry(
        'Cloud enabled(device)',
        _boolDebugLabel(localState?.cloudEnabled),
      ),
      MapEntry('Cloud effective', _boolDebugLabel(_cloudEnabledEffective())),
      MapEntry(
        'Cloud cmd eligible',
        _boolDebugLabel(_cloudCommandEligibleForActive()),
      ),
      MapEntry('Cloud state(device)', _stringOrDash(localState?.cloudState)),
      MapEntry('Cloud state(api)', _stringOrDash(_cloudApiState)),
      MapEntry('Cloud reason(device)', _stringOrDash(localReason)),
      MapEntry('Cloud reason(api)', _stringOrDash(_cloudApiStateReason)),
      MapEntry(
        'MQTT connected',
        _boolDebugLabel(localState?.cloudMqttConnected),
      ),
      MapEntry('MQTT state', _stringOrDash(localState?.cloudMqttState)),
      MapEntry('MQTT code', '${localState?.cloudMqttStateCode ?? 0}'),
      MapEntry('Cloud devices(api)', _cloudApiDeviceCount?.toString() ?? '-'),
      MapEntry('Active in cloud list', _boolDebugLabel(activeListed)),
      MapEntry('Cloud listed IDs', listedIds),
      MapEntry('Members fetched', _formatDebugTime(_cloudMembersFetchedAt)),
      MapEntry('Members count', _cloudMembers?.length.toString() ?? '-'),
      MapEntry('Members err', _stringOrDash(_cloudMembersErr)),
      MapEntry('Invites fetched', _formatDebugTime(_cloudInvitesFetchedAt)),
      MapEntry('Invites count', _cloudInvites?.length.toString() ?? '-'),
      MapEntry('Invites err', _stringOrDash(_cloudInvitesErr)),
      MapEntry(
        'Capabilities fetched',
        _formatDebugTime(_cloudCapabilitiesFetchedAt),
      ),
      MapEntry('Cap schema', _stringOrDash(_cloudCapabilitiesSchema)),
      MapEntry('Cap source', _stringOrDash(_cloudCapabilitiesSource)),
      MapEntry('Last cloud ok', _formatDebugTime(_lastCloudOkAt)),
      MapEntry('Cloud fail until', _formatDebugTime(_cloudFailUntil)),
      MapEntry('Cloud prefer until', _formatDebugTime(_cloudPreferUntil)),
      MapEntry('Cloud login email', _stringOrDash(_cloudUserEmail)),
    ];
  }

  IconData _cloudStateIcon() {
    final s = _effectiveCloudStateUpper();
    if (s == 'CONNECTED') return Icons.cloud_done;
    if (s == 'LINKED') return Icons.link;
    if (s == 'PROVISIONING') return Icons.sync;
    if (s == 'SETUP_REQUIRED') return Icons.settings_suggest;
    if (s == 'DEGRADED') return Icons.cloud_off;
    if (s == 'DISABLED' || s == 'OFF') return Icons.cloud_off;
    return Icons.cloud_queue;
  }

  Color _cloudStateChipColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _effectiveCloudStateUpper();
    if (s == 'CONNECTED') return cs.primaryContainer;
    if (s == 'LINKED') return cs.secondaryContainer;
    if (s == 'PROVISIONING' || s == 'SETUP_REQUIRED')
      return cs.tertiaryContainer;
    if (s == 'DEGRADED') return cs.errorContainer;
    return cs.surfaceContainerHighest;
  }

  String _formatElapsedShortMs(int ms) {
    if (ms <= 0) return '';
    final d = Duration(milliseconds: ms);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}dk';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      if (m == 0) return '${d.inHours}sa';
      return '${d.inHours}sa ${m}dk';
    }
    return '${d.inDays}g';
  }

  String _shortUserId(String id) {
    final s = id.trim();
    if (s.length <= 10) return s;
    return '${s.substring(0, 6)}…${s.substring(s.length - 4)}';
  }

  bool _cloudLoggedIn() {
    return _cloudIdToken != null && _cloudIdToken!.isNotEmpty;
  }

  bool _cloudInvitesSupported() => _cloudFeatureInvites ?? true;
  bool _cloudOtaJobsSupported() => _cloudFeatureOtaJobs ?? true;
  bool _cloudShadowStateSupported() => _cloudFeatureShadowState ?? true;

  String _haEntityPart(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) return 'x';
    final norm = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final collapsed = norm.replaceAll(RegExp(r'_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'x' : trimmed;
  }

  List<String> _haEntityPreview(Map<String, dynamic> capabilities, String id6) {
    final devicePart = _haEntityPart(id6.isEmpty ? 'device' : id6);
    final base = 'aac_$devicePart';
    final out = <String>[];
    final seen = <String>{};

    bool supported(dynamic v) {
      if (v is bool) return v;
      if (v is Map) return v['supported'] == true;
      return false;
    }

    void addEntity(String domain, String key) {
      final safeKey = _haEntityPart(key);
      final entity = '$domain.${base}_$safeKey';
      if (seen.add(entity)) out.add(entity);
    }

    final switches = (capabilities['switches'] is Map)
        ? Map<String, dynamic>.from(capabilities['switches'] as Map)
        : const <String, dynamic>{};
    for (final e in switches.entries) {
      if (supported(e.value)) addEntity('switch', e.key);
    }

    final controls = (capabilities['controls'] is Map)
        ? Map<String, dynamic>.from(capabilities['controls'] as Map)
        : const <String, dynamic>{};
    for (final e in controls.entries) {
      if (!supported(e.value)) continue;
      final key = e.key.toLowerCase();
      if (key.contains('mode')) {
        addEntity('select', e.key);
      } else {
        addEntity('number', e.key);
      }
    }

    final sensors = (capabilities['sensors'] is Map)
        ? Map<String, dynamic>.from(capabilities['sensors'] as Map)
        : const <String, dynamic>{};
    for (final e in sensors.entries) {
      if (supported(e.value)) addEntity('sensor', e.key);
    }

    return out;
  }

  String _haDiscoveryPayloadDraft(
    Map<String, dynamic> capabilities,
    String id6,
  ) {
    final devicePart = _haEntityPart(id6.isEmpty ? 'device' : id6);
    final base = '${kDefaultDeviceProductSlug}_$devicePart';
    final stateTopic = '${kDefaultDeviceProductSlug}/$devicePart/state';
    final cmdTopic = '${kDefaultDeviceProductSlug}/$devicePart/cmd';
    final desiredTopic = cloudShadowDesiredTopicForId6(devicePart);
    final entities = <Map<String, dynamic>>[];

    bool supported(dynamic v) {
      if (v is bool) return v;
      if (v is Map) return v['supported'] == true;
      return false;
    }

    final switches = (capabilities['switches'] is Map)
        ? Map<String, dynamic>.from(capabilities['switches'] as Map)
        : const <String, dynamic>{};
    for (final e in switches.entries) {
      if (!supported(e.value)) continue;
      final key = _haEntityPart(e.key);
      entities.add({
        'platform': 'mqtt',
        'domain': 'switch',
        'name': '$kDefaultManufacturer ${e.key}',
        'unique_id': '${base}_$key',
        'state_topic': stateTopic,
        'command_topic': cmdTopic,
        'state_path': e.key,
        'command_key': e.key,
      });
    }

    final controls = (capabilities['controls'] is Map)
        ? Map<String, dynamic>.from(capabilities['controls'] as Map)
        : const <String, dynamic>{};
    for (final e in controls.entries) {
      if (!supported(e.value)) continue;
      final key = _haEntityPart(e.key);
      final isMode = e.key.toLowerCase().contains('mode');
      entities.add({
        'platform': 'mqtt',
        'domain': isMode ? 'select' : 'number',
        'name': '$kDefaultManufacturer ${e.key}',
        'unique_id': '${base}_$key',
        'state_topic': stateTopic,
        'command_topic': isMode ? cmdTopic : desiredTopic,
        'state_path': e.key,
        'command_key': e.key,
      });
    }

    final sensors = (capabilities['sensors'] is Map)
        ? Map<String, dynamic>.from(capabilities['sensors'] as Map)
        : const <String, dynamic>{};
    for (final e in sensors.entries) {
      if (!supported(e.value)) continue;
      final key = _haEntityPart(e.key);
      entities.add({
        'platform': 'mqtt',
        'domain': 'sensor',
        'name': '$kDefaultManufacturer ${e.key}',
        'unique_id': '${base}_$key',
        'state_topic': stateTopic,
        'state_path': e.key,
      });
    }

    final out = <String, dynamic>{
      'schemaVersion': _cloudCapabilitiesSchema ?? 'v1',
      'deviceId': id6,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'topics': {
        'state': stateTopic,
        'cmd': cmdTopic,
        'shadowDesired': desiredTopic,
      },
      'entities': entities,
    };
    return const JsonEncoder.withIndent('  ').convert(out);
  }

  List<Map<String, dynamic>> _haDiscoveryEntities(
    Map<String, dynamic> capabilities,
    String id6,
  ) {
    final devicePart = _haEntityPart(id6.isEmpty ? 'device' : id6);
    final base = '${kDefaultDeviceProductSlug}_$devicePart';
    final stateTopic = '${kDefaultDeviceProductSlug}/$devicePart/state';
    final cmdTopic = '${kDefaultDeviceProductSlug}/$devicePart/cmd';
    final desiredTopic = cloudShadowDesiredTopicForId6(devicePart);
    final entities = <Map<String, dynamic>>[];

    bool supported(dynamic v) {
      if (v is bool) return v;
      if (v is Map) return v['supported'] == true;
      return false;
    }

    final switches = (capabilities['switches'] is Map)
        ? Map<String, dynamic>.from(capabilities['switches'] as Map)
        : const <String, dynamic>{};
    for (final e in switches.entries) {
      if (!supported(e.value)) continue;
      final key = _haEntityPart(e.key);
      entities.add({
        'platform': 'mqtt',
        'domain': 'switch',
        'name': '$kDefaultManufacturer ${e.key}',
        'unique_id': '${base}_$key',
        'state_topic': stateTopic,
        'command_topic': cmdTopic,
        'state_path': e.key,
        'command_key': e.key,
      });
    }

    final controls = (capabilities['controls'] is Map)
        ? Map<String, dynamic>.from(capabilities['controls'] as Map)
        : const <String, dynamic>{};
    for (final e in controls.entries) {
      if (!supported(e.value)) continue;
      final key = _haEntityPart(e.key);
      final isMode = e.key.toLowerCase().contains('mode');
      entities.add({
        'platform': 'mqtt',
        'domain': isMode ? 'select' : 'number',
        'name': '$kDefaultManufacturer ${e.key}',
        'unique_id': '${base}_$key',
        'state_topic': stateTopic,
        'command_topic': isMode ? cmdTopic : desiredTopic,
        'state_path': e.key,
        'command_key': e.key,
      });
    }

    final sensors = (capabilities['sensors'] is Map)
        ? Map<String, dynamic>.from(capabilities['sensors'] as Map)
        : const <String, dynamic>{};
    for (final e in sensors.entries) {
      if (!supported(e.value)) continue;
      final key = _haEntityPart(e.key);
      entities.add({
        'platform': 'mqtt',
        'domain': 'sensor',
        'name': '$kDefaultManufacturer ${e.key}',
        'unique_id': '${base}_$key',
        'state_topic': stateTopic,
        'state_path': e.key,
      });
    }
    return entities;
  }

  List<Map<String, dynamic>> _haDiscoveryConfigMessages(
    Map<String, dynamic> capabilities,
    String id6,
  ) {
    final devicePart = _haEntityPart(id6.isEmpty ? 'device' : id6);
    final entities = _haDiscoveryEntities(capabilities, id6);
    final out = <Map<String, dynamic>>[];
    for (final e in entities) {
      final domain = (e['domain'] ?? '').toString();
      final uniqueId = (e['unique_id'] ?? '').toString();
      final stateTopic = (e['state_topic'] ?? '').toString();
      final statePath = (e['state_path'] ?? '').toString();
      if (domain.isEmpty || uniqueId.isEmpty || stateTopic.isEmpty) continue;

      final payload = <String, dynamic>{
        'name': e['name'],
        'unique_id': uniqueId,
        'state_topic': stateTopic,
        'value_template': '{{ value_json.$statePath }}',
        'device': {
          'identifiers': [devicePart],
          'name': '$kDefaultManufacturer $devicePart',
          'manufacturer': kDefaultManufacturer,
          'model': kDefaultDeviceBrand,
        },
      };
      final commandTopic = (e['command_topic'] ?? '').toString();
      final commandKey = (e['command_key'] ?? '').toString();
      if (commandTopic.isNotEmpty && commandKey.isNotEmpty) {
        payload['command_topic'] = commandTopic;
        payload['command_template'] = '{"$commandKey": {{ value | tojson }} }';
      }
      out.add({
        'topic': 'homeassistant/$domain/$uniqueId/config',
        'payload': payload,
      });
    }
    return out;
  }

  String _haDiscoveryConfigMessagesText(
    Map<String, dynamic> capabilities,
    String id6,
  ) {
    final messages = _haDiscoveryConfigMessages(capabilities, id6);
    return _haConfigMessagesToText(messages);
  }

  String _haConfigMessagesToText(List<dynamic> messages) {
    final enc = const JsonEncoder.withIndent('  ');
    final b = StringBuffer();
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (msg is! Map) continue;
      final topic = (msg['topic'] ?? '').toString();
      final payload = (msg['payload'] is Map)
          ? Map<String, dynamic>.from(msg['payload'] as Map)
          : <String, dynamic>{};
      if (i > 0) b.writeln('\n---');
      b.writeln('topic: $topic');
      b.writeln('payload:');
      b.writeln(enc.convert(payload));
    }
    return b.toString().trim();
  }

  Future<String> _saveTextDraft(
    String filePrefix,
    String id6,
    String text, {
    String ext = 'txt',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeId = _haEntityPart(id6.isEmpty ? 'device' : id6);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${dir.path}/$filePrefix'
      '_$safeId'
      '_$ts.$ext',
    );
    await file.writeAsString(text, flush: true);
    return file.path;
  }

  Future<String> _saveHaDiscoveryPayloadDraft(
    Map<String, dynamic> capabilities,
    String id6,
  ) async {
    final payload = _haDiscoveryPayloadDraft(capabilities, id6);
    return _saveTextDraft('ha_discovery', id6, payload, ext: 'json');
  }

  Future<Map<String, dynamic>?> _fetchHaConfigFromCloud(String id6) async {
    if (!_cloudLoggedIn() || id6.isEmpty) return null;
    await _cloudRefreshIfNeeded();
    return cloudApi.fetchHaConfig(id6, const Duration(seconds: 8));
  }

  String? _haConfigTextFromResponse(Map<String, dynamic>? remote) {
    final msgs = remote?['messages'];
    if (msgs is! List || msgs.isEmpty) return null;
    return _haConfigMessagesToText(msgs);
  }

  String? _normalizeCloudEndpointForDevice(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^https://', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^mqtts://', caseSensitive: false), '');
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    s = s.trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == 'your_aws_iot_endpoint') return null;
    final colon = s.lastIndexOf(':');
    if (colon > 0) {
      final port = s.substring(colon + 1);
      if (port.isNotEmpty && int.tryParse(port) != null) {
        s = s.substring(0, colon).trim();
      }
    }
    return s.isEmpty ? null : s;
  }

  void _applyCloudFeaturesFromMe(Map<String, dynamic>? me) {
    if (me == null) return;
    final rawCloud = me['_cloud'] ?? me['cloud'];
    if (rawCloud is! Map) return;
    final cloud = Map<String, dynamic>.from(rawCloud);
    final rawState = (cloud['state'] ?? '').toString().trim();
    if (rawState.isNotEmpty) _cloudApiState = rawState;
    final rawReason = (cloud['reason'] ?? cloud['stateReason'] ?? '')
        .toString()
        .trim();
    if (rawReason.isNotEmpty) _cloudApiStateReason = rawReason;
    final rawEndpoint =
        (cloud['iotEndpoint'] ??
                cloud['endpoint'] ??
                cloud['awsIotEndpoint'] ??
                '')
            .toString()
            .trim();
    final normalizedEndpoint = _normalizeCloudEndpointForDevice(rawEndpoint);
    if (normalizedEndpoint != null && normalizedEndpoint.isNotEmpty) {
      _cloudIotEndpoint = normalizedEndpoint;
    }
    final rawDeviceCount = cloud['deviceCount'];
    if (rawDeviceCount is num) {
      _cloudApiDeviceCount = rawDeviceCount.toInt();
    } else if (rawDeviceCount is String) {
      _cloudApiDeviceCount =
          int.tryParse(rawDeviceCount.trim()) ?? _cloudApiDeviceCount;
    }
    final rawFeatures = cloud['features'];
    if (rawFeatures is! Map) return;
    final f = Map<String, dynamic>.from(rawFeatures);
    bool? asBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == '1' || s == 'true' || s == 'yes') return true;
        if (s == '0' || s == 'false' || s == 'no') return false;
      }
      return null;
    }

    _cloudFeatureInvites = asBool(f['invites']) ?? _cloudFeatureInvites;
    _cloudFeatureOtaJobs = asBool(f['otaJobs']) ?? _cloudFeatureOtaJobs;
    _cloudFeatureShadowDesired =
        asBool(f['shadowDesired']) ?? _cloudFeatureShadowDesired;
    _cloudFeatureShadowState =
        asBool(f['shadowState']) ?? _cloudFeatureShadowState;
    _cloudFeatureShadowAclSync =
        asBool(f['shadowAclSync']) ?? _cloudFeatureShadowAclSync;
    _cloudFeaturesFetchedAt = DateTime.now();
  }
}
