part of 'main.dart';

extension _HomeScreenPollingPart on _HomeScreenState {
  Duration _nextPollDelay() {
    final now = DateTime.now();
    if (_pollFastUntil != null && now.isBefore(_pollFastUntil!)) {
      return kPollFastInterval;
    }
    if (_bleControlMode) return kPollFastInterval;
    final authRole = (state?.authRole ?? '').trim().toUpperCase();
    final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
    final nonOwnerKnown =
        authRole == 'USER' ||
        authRole == 'GUEST' ||
        cloudRole == 'USER' ||
        cloudRole == 'GUEST';
    if (connected && nonOwnerKnown) return const Duration(seconds: 2);
    if (connected) return kPollStableInterval;
    return kPollNormalInterval;
  }

  void _markPollFast([Duration window = kPollFastWindowAfterSend]) {
    _pollFastUntil = DateTime.now().add(window);
  }

  void _scheduleNextPoll(int generation, {bool immediate = false}) {
    if (!mounted || _backgroundSuspended) return;
    if (generation != _pollGeneration) return;
    final delay = immediate ? Duration.zero : _nextPollDelay();
    _poller = Timer(delay, () async {
      if (!mounted || _backgroundSuspended) return;
      if (generation != _pollGeneration) return;
      if (_pollTickInFlight) {
        _scheduleNextPoll(generation);
        return;
      }
      _pollTickInFlight = true;
      debugPrint('[PLANNER] Poll tick at ${DateTime.now().toIso8601String()}');
      try {
        if (_bleControlMode) {
          if (!mounted) return;
          // ignore: invalid_use_of_protected_member
          setState(() {
            connected = true;
          });
          try {
            debugPrint('[PLANNER] Evaluating plans (connected=$connected)');
            _evaluatePlans();
          } catch (e, st) {
            debugPrint('[PLANNER] _evaluatePlans threw: $e');
            debugPrint(st.toString());
          }
          return;
        }
        final s = await _fetchStateSmart();
        if (!mounted) return;
        if (s != null) {
          final pathConnected = _isControlPathConnectedNow();
          // ignore: invalid_use_of_protected_member
          setState(() {
            state = s;
            _syncAutoHumControlsFromState(s);
            connected = pathConnected;
            _lastUpdate = DateTime.now();
            _pushHistorySample(s);
          });
          _cacheActiveRuntimeHealth(
            localOk: !_cloudReady(DateTime.now()),
            cloudOk: _cloudReady(DateTime.now()),
          );
          if (_isOwnerRole() && _cloudEnabledEffective() && _cloudLoggedIn()) {
            final now = DateTime.now();
            final shouldRefreshOwnerAux =
                _cloudOwnerAuxPolledAt == null ||
                now.difference(_cloudOwnerAuxPolledAt!) >
                    const Duration(seconds: 30);
            if (shouldRefreshOwnerAux) {
              _cloudOwnerAuxPolledAt = now;
              unawaited(_refreshCloudMembers());
              unawaited(_refreshCloudInvites());
              unawaited(_refreshCloudIntegrations());
              unawaited(_autoCloudAclRecovery(reason: 'owner_poll'));
            }
          }
        } else {
          if (_shouldKeepConnectedOnNullState()) {
            if (!connected) {
              // ignore: invalid_use_of_protected_member
              setState(() {
                connected = true;
              });
            }
            debugPrint(
              '[NET] keeping connected=true while transport is stabilizing',
            );
          } else {
            // ignore: invalid_use_of_protected_member
            setState(() {
              connected = false;
            });
            unawaited(_connectionTick());
          }
        }
        try {
          debugPrint('[PLANNER] Evaluating plans (connected=$connected)');
          _evaluatePlans();
        } catch (e, st) {
          debugPrint('[PLANNER] _evaluatePlans threw: $e');
          debugPrint(st.toString());
        }
      } finally {
        _pollTickInFlight = false;
        if (mounted && !_backgroundSuspended && generation == _pollGeneration) {
          _scheduleNextPoll(generation);
        }
      }
    });
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = null;
    _pollTickInFlight = false;
    _pollGeneration += 1;
    _scheduleNextPoll(_pollGeneration, immediate: true);
  }

  Future<void> _connectionTick({bool force = false}) async {
    if (_transportRecoveryBlocked(reason: 'connection_tick')) return;
    if (_connTickInFlight) return;
    if (!_networkAutoPollingAllowed) {
      debugPrint('[NET] connectionTick suppressed until user opt-in');
      return;
    }
    final now = DateTime.now();
    final next = _connNextTryAt;
    if (!force && next != null && now.isBefore(next)) return;
    _connTickInFlight = true;
    try {
      final activeCloudId6 = _deviceId6ForMqtt();
      final cloudMembershipStale =
          _cloudDevicesFetchedAt == null ||
          now.difference(_cloudDevicesFetchedAt!) > const Duration(seconds: 12);
      final activeMissingFromCloudList =
          activeCloudId6 != null &&
          activeCloudId6.isNotEmpty &&
          !_cloudApiDeviceIds.contains(activeCloudId6);
      if (_cloudLoggedIn() &&
          _cloudUserEnabledLocal &&
          activeCloudId6 != null &&
          activeCloudId6.isNotEmpty &&
          (_cloudDeviceSyncFuture == null) &&
          (cloudMembershipStale || activeMissingFromCloudList)) {
        unawaited(
          _syncCloudDevices(
            autoSelectIfNeeded: false,
            showSnack: false,
            force: true,
          ),
        );
      }
      if (_cloudBringupNeeded()) {
        unawaited(
          _ensureCloudReadyForActiveDevice(force: force, showSnack: false),
        );
      }
      final localFresh =
          !_localDnsFailActive &&
          !_localUnreachableActive &&
          _lastLocalOkAt != null &&
          now.difference(_lastLocalOkAt!) < const Duration(seconds: 12);
      if (_apStickyActive()) {
        await _maybeSwitchToApBaseUrlIfReachable();
      }
      final any = connected || _bleControlMode || localFresh;
      if (any && !force) {
        _connBackoffSeconds = 2;
        _connNextTryAt = now.add(const Duration(seconds: 10));
        return;
      }

      final anyAfterPrimary =
          connected ||
          _bleControlMode ||
          (_lastLocalOkAt != null &&
              now.difference(_lastLocalOkAt!) < const Duration(seconds: 12));
      if (!anyAfterPrimary) {
        if (_apStickyActive()) {
          await _maybeSwitchToApBaseUrlIfReachable();
        }
        final baseHost = Uri.tryParse(api.baseUrl)?.host ?? '';
        if (baseHost.endsWith('.local')) {
          await _maybeSwitchToApBaseUrlIfReachable();
          _useFallbackIpIfAny('local-probe');
        }
        if (!_localDnsFailActive && !_localUnreachableActive) {
          final okLocal = await _probeInfoReachable(api.baseUrl);
          if (!okLocal) {
            await _maybeFixLocalBaseViaMdns();
            await _maybeSwitchToApBaseUrlIfReachable();
          }
        } else {
          await _maybeFixLocalBaseViaMdns();
          await _maybeSwitchToApBaseUrlIfReachable();
        }
      }

      final anyFinal =
          connected ||
          _bleControlMode ||
          (_lastLocalOkAt != null &&
              DateTime.now().difference(_lastLocalOkAt!) <
                  const Duration(seconds: 12));
      if (anyFinal) {
        _connBackoffSeconds = 2;
        _connNextTryAt = now.add(const Duration(seconds: 10));
      } else {
        _connBackoffSeconds = (_connBackoffSeconds * 2).clamp(2, 60);
        _connNextTryAt = now.add(Duration(seconds: _connBackoffSeconds));
      }
    } catch (e, st) {
      debugPrint('[NET] _connectionTick error: $e');
      debugPrint(st.toString());
    } finally {
      _connTickInFlight = false;
    }
  }

  Future<void> _autoConnectBleIfNeeded({bool force = false}) async {
    if (!mounted) return;
    if (_bleManageSheetOpen) return;
    if (!force && _transportRecoveryBlocked(reason: 'ble_auto_connect')) {
      return;
    }
    if (!force && !_autoBleReconnectEnabled) return;
    if (_bleControlMode || _bleCtrlConnecting || _bleBusy) return;
    if (_qrBleConnectDialogOpen || _qrBleConnectInFlight) return;

    final now = DateTime.now();
    final last = _bleAutoLastAttemptAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _bleAutoLastAttemptAt = now;

    bool shouldSkipBleAuto() {
      final st = state;
      final softRecovery = st?.softRecoveryActive == true;
      final pairingWindow = st?.pairingWindowActive == true;
      final apSession = st?.apSessionActive == true;
      final recoveryOpen = softRecovery || pairingWindow || apSession;
      final authRole = (st?.authRole ?? '').trim().toUpperCase();
      final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
      final ownerExists =
          st?.ownerExists == true ||
          _cloudOwnerExistsOverride == true ||
          authRole == 'OWNER' ||
          cloudRole == 'OWNER';
      final nonOwnerRole =
          authRole == 'USER' ||
          authRole == 'GUEST' ||
          cloudRole == 'USER' ||
          cloudRole == 'GUEST';
      final cloudStable =
          st?.cloudMqttConnected == true ||
          _cloudReady(DateTime.now()) ||
          _cloudHealthy(DateTime.now());

      if (ownerExists && !recoveryOpen) {
        debugPrint(
          '[BLE][AUTO] skip: owner device and recovery closed (soft=$softRecovery pair=$pairingWindow ap=$apSession)',
        );
        return true;
      }
      if (nonOwnerRole && !recoveryOpen) {
        debugPrint(
          '[BLE][AUTO] skip: non-owner role auth=$authRole cloud=$cloudRole',
        );
        return true;
      }
      if (cloudStable && !recoveryOpen) {
        debugPrint('[BLE][AUTO] skip: cloud transport already stable');
        return true;
      }
      return false;
    }

    if (shouldSkipBleAuto()) return;

    final activeId6 = _deviceId6ForMqtt();
    String? id6 = force ? activeId6 : null;
    id6 ??= await _getBleTargetId6FromPrefs();
    if (id6 == null) return;
    if (activeId6 != null && activeId6.isNotEmpty && activeId6 != id6) {
      debugPrint(
        '[BLE][AUTO] skip: target id6=$id6 does not match active id6=$activeId6',
      );
      return;
    }
    if (force &&
        activeId6 != null &&
        activeId6.isNotEmpty &&
        activeId6 == id6) {
      await _setBleTargetId6InPrefs(id6);
    }

    final pairToken = await _loadPairToken(canonicalizeDeviceId(id6) ?? id6);
    final hasPairToken = pairToken != null && pairToken.trim().isNotEmpty;
    final cached = await _loadBleSetupCredsForId6(id6);
    final recoveryOpenNow =
        state?.softRecoveryActive == true ||
        state?.pairingWindowActive == true ||
        state?.apSessionActive == true;
    if (!force && !hasPairToken && cached == null) return;
    if (force && !hasPairToken && cached == null) {
      if (!recoveryOpenNow) {
        debugPrint(
          '[BLE][AUTO] skip force connect: no pairToken/setupCreds and recovery closed (id6=$id6)',
        );
        return;
      }
      debugPrint(
        '[BLE][AUTO] force connect without pairToken/setupCreds (id6=$id6)',
      );
    }

    debugPrint('[BLE][AUTO] attempting auto connect (id6=$id6)');
    try {
      await _toggleBleControl(
        interactive: false,
        preserveActiveDevice: true,
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint('[BLE][AUTO] _toggleBleControl timeout');
          _bleCtrlConnecting = false;
          _bleBusy = false;
        },
      );
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          if (_bleControlMode) connected = true;
        });
      }
    } catch (e) {
      debugPrint('[BLE][AUTO] Auto connect error: $e');
      _bleCtrlConnecting = false;
      _bleBusy = false;
    }
  }

  Future<void> _updateActiveDeviceIdFromApi() async {
    if (_activeDeviceId != null && !_activeDeviceId!.startsWith('dev_')) {
      return;
    }

    try {
      final uri = Uri.parse('${api.baseUrl}/api/status');
      final response = await http
          .get(uri, headers: api.authHeaders())
          .timeout(kLocalHttpRequestTimeout);

      if (response.statusCode != 200) return;

      final j = jsonDecode(response.body) as Map<String, dynamic>;
      final meta = (j['meta'] is Map<String, dynamic>)
          ? (j['meta'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final apiDeviceId = (meta['deviceId'] ?? j['deviceId'] ?? '')
          .toString()
          .trim();

      if (apiDeviceId.isNotEmpty && !apiDeviceId.startsWith('dev_')) {
        await _updateActiveDeviceIdFromApiValue(apiDeviceId);
      }
    } catch (e) {
      debugPrint('[STATE] _updateActiveDeviceIdFromApi error: $e');
    }
  }

  Future<DeviceState?> _fetchStateSmart({bool force = false}) async {
    final fetchEpoch = _activeDeviceSwitchEpoch;
    final fetchDeviceId = _activeDeviceId;
    bool isStale() =>
        fetchEpoch != _activeDeviceSwitchEpoch ||
        fetchDeviceId != _activeDeviceId;
    if (!force &&
        !_bleControlMode &&
        _transportRecoveryBlocked(reason: 'fetch_state')) {
      return null;
    }
    final now = DateTime.now();
    final cloudId6 = _deviceId6ForMqtt();
    final cloudStateSupported = _cloudShadowStateSupported();
    final cloudEligible = _cloudCommandEligibleForActive();
    final cloudPossible =
        _cloudEnabledEffective() &&
        cloudEligible &&
        cloudStateSupported &&
        cloudId6 != null &&
        cloudId6.isNotEmpty;
    final currentHost = Uri.tryParse(api.baseUrl)?.host ?? '';
    final onSoftAp = currentHost == '192.168.4.1';
    final preferAp = _apStickyActive();
    if (!_networkAutoPollingAllowed && !_bleControlMode && !cloudPossible) {
      return null;
    }

    var localFresh = false;
    if (_lastLocalOkAt != null &&
        now.difference(_lastLocalOkAt!) < const Duration(seconds: 6)) {
      localFresh = true;
    }

    final cloudReady = _cloudReady(now);
    final cloudHealthy = _cloudHealthy(now);
    final cloudPrefer = _cloudPreferActive(now);
    final cloudStateMinInterval = _isOwnerRole()
        ? kCloudStateMinFetchInterval
        : const Duration(seconds: 6);
    if (!onSoftAp &&
        !localFresh &&
        cloudReady &&
        cloudEligible &&
        cloudStateSupported &&
        cloudId6 != null &&
        cloudId6.isNotEmpty &&
        (cloudHealthy || cloudPrefer || _lastCloudOkAt == null)) {
      if (!force &&
          _lastCloudStateFetchId6 == cloudId6 &&
          _lastCloudStateFetchAt != null &&
          now.difference(_lastCloudStateFetchAt!) < cloudStateMinInterval &&
          _lastStateFetchSource == 'cloud' &&
          state != null) {
        return state;
      }
      final refreshed = await _cloudRefreshIfNeeded();
      if (!_cloudAuthReady(now) && !refreshed) {
        _markCloudFail();
      } else {
        try {
          final cloudState = await cloudApi.fetchState(
            cloudId6,
            kCloudConnectTimeout,
          );
          if (cloudState != null) {
            if (isStale()) {
              debugPrint(
                '[STATE] stale cloud state dropped (start=$fetchDeviceId now=$_activeDeviceId)',
              );
              return null;
            }
            debugPrint(
              '[CLOUD][STATE] id6=$cloudId6 role=${cloudState.authRole} users=${cloudState.invitedUsers.length} owner=${cloudState.ownerExists} claimed=${cloudState.cloudClaimed}',
            );
            if (cloudState.cloudEnabled && !_cloudUserEnabledLocal) {
              await _autoEnableCloudLocalFlag(reason: 'device_cloud_enabled');
            }
            _localUnauthorizedHits = 0;
            _markCloudOk();
            _lastCloudStateFetchAt = DateTime.now();
            _lastCloudStateFetchId6 = cloudId6;
            _cloudOwnerExistsOverride = cloudState.ownerExists;
            _cloudOwnerSetupDoneOverride = cloudState.ownerSetupDone;
            await _maybeAutoClaimCloud(cloudId6, cloudState);
            final prev = state;
            if (prev != null) {
              final cloudHasExplicitRgb = _hasExplicitRgbState(
                cloudApi.lastFetchedStateCore,
              );
              if (!cloudHasExplicitRgb) {
                cloudState.rgbOn = prev.rgbOn;
                cloudState.r = prev.r;
                cloudState.g = prev.g;
                cloudState.b = prev.b;
                cloudState.rgbBrightness = prev.rgbBrightness;
              }
              if (cloudEligible &&
                  !cloudState.ownerExists &&
                  prev.ownerExists) {
                cloudState.ownerExists = true;
              }
              if (cloudEligible &&
                  !cloudState.ownerSetupDone &&
                  prev.ownerSetupDone) {
                cloudState.ownerSetupDone = true;
              }
              if (cloudEligible &&
                  cloudState.ownerExists == false &&
                  cloudState.cloudClaimed == true &&
                  prev.cloudClaimed == true) {
                cloudState.cloudClaimed = true;
              }
              if (cloudEligible &&
                  !_authRoleKnown(cloudState.authRole) &&
                  _authRoleKnown(prev.authRole)) {
                cloudState.authRole = prev.authRole;
              }
              if (cloudState.invitedUsers.isEmpty &&
                  prev.invitedUsers.isNotEmpty) {
                cloudState.invitedUsers = prev.invitedUsers;
              }
            }
            if (!_authRoleKnown(cloudState.authRole)) {
              final cachedRole = await _loadCloudRole(cloudId6);
              if (cachedRole != null && cachedRole.isNotEmpty) {
                cloudState.authRole = cachedRole;
                debugPrint(
                  '[CLOUD][STATE] role missing -> using cached role=$cachedRole',
                );
              }
            }
            if (cloudEligible &&
                !_authRoleKnown(cloudState.authRole) &&
                _ownerPrivD32 != null &&
                (cloudState.ownerExists || cloudState.ownerSetupDone)) {
              cloudState.authRole = 'OWNER';
            }
            if (cloudEligible &&
                !cloudState.ownerExists &&
                cloudState.cloudClaimed) {
              cloudState.cloudClaimed = true;
            }
            _lastStateFetchSource = 'cloud';
            return cloudState;
          }
          _markCloudFail();
        } catch (_) {
          _markCloudFail();
        }
      }
    }

    if (!preferAp && !_localDnsFailActive && !_localUnreachableActive) {
      final authRole = (state?.authRole ?? '').trim().toUpperCase();
      final cloudRole = (_activeDevice?.cloudRole ?? '').trim().toUpperCase();
      final nonOwnerKnown =
          authRole == 'USER' ||
          authRole == 'GUEST' ||
          cloudRole == 'USER' ||
          cloudRole == 'GUEST';
      if (!onSoftAp && nonOwnerKnown) {
        return null;
      }
      final ownedKnown =
          state?.ownerExists == true ||
          (cloudEligible && _cloudOwnerExistsOverride == true);
      if (ownedKnown && !api.hasSigningKey) {
        return null;
      }
      var allowLocalAttempt =
          localFresh || await _probeInfoReachable(api.baseUrl);
      if (!allowLocalAttempt &&
          !_baseHostLooksLikeIpv4(api.baseUrl) &&
          api.baseUrl.contains('.local')) {
        _useFallbackIpIfAny('local-probe');
        allowLocalAttempt = await _probeInfoReachable(api.baseUrl);
      }
      if (allowLocalAttempt) {
        try {
          final local = await api.fetchState();
          if (local != null) {
            if (isStale()) {
              debugPrint(
                '[STATE] stale local state dropped (start=$fetchDeviceId now=$_activeDeviceId)',
              );
              return null;
            }
            _captureLastIpForBaseInBackground(api.baseUrl);
            final host = Uri.tryParse(api.baseUrl)?.host ?? '';
            if (_baseHostLooksLikeIpv4(host)) {
              unawaited(_updateActiveDeviceLastIp(host));
            }
            _lastLocalOkAt = DateTime.now();
            _localUnauthorizedHits = 0;
            _localDnsFailUntil = null;
            _localUnreachableUntil = null;
            _cacheActiveRuntimeHealth(localOk: true);
            if ((_activeDeviceId == null ||
                    _activeDeviceId!.startsWith('dev_')) &&
                !_localUnreachableActive) {
              await _updateActiveDeviceIdFromApi();
              if (isStale()) {
                debugPrint(
                  '[STATE] stale local post-id-update dropped (start=$fetchDeviceId now=$_activeDeviceId)',
                );
                return null;
              }
            }
            final prev = state;
            if (_cloudEnabledEffective() &&
                cloudEligible &&
                prev != null &&
                prev.cloudClaimed &&
                !local.cloudClaimed) {
              local.cloudClaimed = true;
            }
            final endpointOk = await _endpointMatchesSelectedForState(
              transport: 'local',
              warnOnMismatch: false,
            );
            if (!endpointOk) {
              _lastStateFetchSource = 'none';
              return null;
            }
            _lastStateFetchSource = 'local';
            return local;
          }
          if (api.lastDnsFailure && !_baseHostLooksLikeIpv4(api.baseUrl)) {
            _markLocalDnsFailure();
          } else if ((api.lastErrCode ?? '').trim().toLowerCase() ==
              'unauthorized') {
            _handleUnauthorizedHit(source: 'local_fetch_null');
          }
        } catch (e) {
          debugPrint('[STATE] local HTTP state error: $e');
          if (_looksLikeDnsLookupFailure(e) &&
              !_baseHostLooksLikeIpv4(api.baseUrl)) {
            _markLocalDnsFailure();
          } else if (_looksLikeLocalUnreachable(e)) {
            _markLocalUnreachable();
          } else if ((api.lastErrCode ?? '').trim().toLowerCase() ==
              'unauthorized') {
            _handleUnauthorizedHit(source: 'local_fetch_throw');
          }
        }
      }
    }

    try {
      const apBase = 'http://192.168.4.1';
      final selectedId6 = _selectedId6ForGuard();
      final apEndpointId6 = await _probeApEndpointId6();
      final apReachable = apEndpointId6 != null || await _probeApReachable();
      if (apReachable &&
          selectedId6 != null &&
          selectedId6.isNotEmpty &&
          apEndpointId6 != null &&
          apEndpointId6.isNotEmpty &&
          apEndpointId6 != selectedId6) {
        debugPrint(
          '[STATE] skip AP fetch due to endpoint mismatch selected=$selectedId6 endpoint=$apEndpointId6',
        );
        _lastStateFetchSource = 'none';
        return null;
      }
      if (apReachable) {
        await _maybeSwitchToApBaseUrlIfReachable();
        if (api.baseUrl == apBase) {
          final apState = await api.fetchState();
          if (apState != null) {
            if (isStale()) {
              debugPrint(
                '[STATE] stale AP state dropped (start=$fetchDeviceId now=$_activeDeviceId)',
              );
              return null;
            }
            if ((_activeDeviceId == null ||
                _activeDeviceId!.startsWith('dev_'))) {
              await _updateActiveDeviceIdFromApi();
              if (isStale()) {
                debugPrint(
                  '[STATE] stale AP post-id-update dropped (start=$fetchDeviceId now=$_activeDeviceId)',
                );
                return null;
              }
            }
            _localUnauthorizedHits = 0;
            _lastLocalOkAt = DateTime.now();
            final endpointOk = await _endpointMatchesSelectedForState(
              transport: 'ap',
              warnOnMismatch: false,
            );
            if (!endpointOk) {
              _lastStateFetchSource = 'none';
              return null;
            }
            _lastStateFetchSource = 'ap';
            return apState;
          } else if ((api.lastErrCode ?? '').trim().toLowerCase() ==
              'unauthorized') {
            if (_localUnauthorizedHits >= 2) {
              unawaited(_handleInvalidQrToken(source: 'AP_HTTP_401'));
              api.clearLocalSession();
            }
            _handleUnauthorizedHit(
              source: 'ap_fetch_unauthorized',
              immediateRecovery: true,
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
