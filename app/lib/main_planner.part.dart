part of 'main.dart';

// Planner akışını merkezi toplar:
// - Plan ekleme/kaydetme
// - Cihaza saat senkronu
// - Çakışma kontrolü
extension _HomeScreenPlanner on _HomeScreenState {
  void _addPlan() async {
    final created = await showModalBottomSheet<_PlanItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: _PlanEditor(
            i18n: widget.i18n,
            isDoa: _isDoaDevice,
            overlaps: (cand) => _wouldOverlapWith(cand),
          ),
        ),
      ),
    );
    if (created != null) {
      if (_wouldOverlapWith(created)) {
        _showSnack(t.t('overlap_exists'));
        return;
      }
      _safeSetState(() => _plans.add(created));
      _trySavePlans(applyNow: false);
    }
  }

  Future<void> _savePlansToDevice({bool applyNow = true}) async {
    final body = {'plans': _plans.map((e) => e.toJson()).toList()};
    await _send(body);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('plans', jsonEncode(body['plans']));
    } catch (_) {}

    if (applyNow) {
      if (_appliedStartMin.length != _plans.length) {
        _appliedStartMin = List<int>.filled(_plans.length, -1);
      } else {
        for (var i = 0; i < _appliedStartMin.length; i++) {
          _appliedStartMin[i] = -1;
        }
      }
      _autoAfterNoPlanSent = false;
      debugPrint('[PLANNER] Force evaluate after Save');
      _evaluatePlans(force: true);
    }
  }

  Future<void> _syncTimeFromPhone() async {
    final epoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    const tzTR = 'EET-2EEST,M3.5.0/3,M10.5.0/4';
    await _send({'setTimeEpoch': epoch, 'tz': tzTR});
  }

  bool _hasOverlappingEnabledPlans() {
    final intervals = <List<int>>[];
    for (final p in _plans) {
      if (!p.enabled) continue;
      final startMin = p.start.hour * 60 + p.start.minute;
      final endMin = p.end.hour * 60 + p.end.minute;
      if (startMin == endMin) {
        intervals.add([0, 1440]);
        continue;
      }
      if (startMin < endMin) {
        intervals.add([startMin, endMin]);
      } else {
        intervals.add([startMin, 1440]);
        intervals.add([0, endMin]);
      }
    }
    if (intervals.length <= 1) return false;
    intervals.sort((a, b) => a[0].compareTo(b[0]));
    var curEnd = intervals.first[1];
    for (var i = 1; i < intervals.length; i++) {
      final s = intervals[i][0];
      final e = intervals[i][1];
      if (s < curEnd) return true;
      curEnd = e;
    }
    return false;
  }

  Future<void> _trySavePlans({bool applyNow = true}) async {
    if (_hasOverlappingEnabledPlans()) {
      _showSnack(t.t('overlap_exists'));
      return;
    }
    await _savePlansToDevice(applyNow: applyNow);
  }

  void _evaluatePlans({bool force = false}) {
    final now = DateTime.now();
    final recentSwitch =
        _lastActiveDeviceSwitchAt != null &&
        now.difference(_lastActiveDeviceSwitchAt!) <
            const Duration(seconds: 20);
    final recentMismatch =
        _lastEndpointMismatchAt != null &&
        now.difference(_lastEndpointMismatchAt!) < const Duration(seconds: 12);
    if (!force && (recentSwitch || recentMismatch)) {
      debugPrint(
        '[PLANNER] skip: transport stabilizing '
        '(recentSwitch=$recentSwitch recentMismatch=$recentMismatch)',
      );
      return;
    }

    // Planner should only drive the device for OWNER sessions.
    // For USER/GUEST, running plan logic causes command overrides (e.g. auto humidity
    // being set back on every poll) and breaks expected manual control behavior.
    if (!_isOwnerRole()) {
      if (_plannerWasActive || _autoAfterNoPlanSent || _manualOverride) {
        _plannerWasActive = false;
        _autoAfterNoPlanSent = false;
        _manualOverride = false;
      }
      debugPrint(
        '[PLANNER] skip: non-owner role=${(state?.authRole ?? '').toUpperCase()}',
      );
      return;
    }

    // Do not attempt to evaluate or send commands while disconnected
    if (!_canControlDevice) {
      debugPrint('[PLANNER] skip: not connected');
      return;
    }
    // If no plans at all, or all are disabled, switch to AUTO once and stop touching anything else
    final bool hasAnyEnabledPlan = _plans.any((p) => p.enabled);
    if (!hasAnyEnabledPlan) {
      if (!_autoAfterNoPlanSent) {
        if (!_networkAutoPollingAllowed) {
          debugPrint('[PLANNER] AUTO suppressed until network polling opt-in');
          return;
        }
        debugPrint('[PLANNER] No enabled plans; triggering AUTO once');
        _autoAfterNoPlanSent = true;
        _plannerWasActive = false; // reset planner activity state
        // Only change mode, leave lights/ion/RGB as-is
        Future.microtask(() => _send({'mode': 5}, promptForQr: false));
      }
      return; // nothing else to evaluate
    }

    // There are enabled plans; evaluate current activity window(s)
    if (_appliedStartMin.length != _plans.length) {
      _appliedStartMin = List<int>.filled(_plans.length, -1);
    }

    final curMin = now.hour * 60 + now.minute;
    bool anyActive = false;

    debugPrint('[PLANNER] now=${now.toIso8601String()} curMin=$curMin');

    // If user manually changed mode/fan during an active plan, do not auto-apply
    // anything until the active window ends (unless force==true from Planner refresh)
    if (_manualOverride && !force) {
      // Detect if any plan is currently active; if so, skip applying
      bool activeExists = false;
      for (final p in _plans) {
        if (!p.enabled) continue;
        final startMin = p.start.hour * 60 + p.start.minute;
        final endMin = p.end.hour * 60 + p.end.minute;
        final bool active = (startMin <= endMin)
            ? (curMin >= startMin && curMin < endMin)
            : (curMin >= startMin || curMin < endMin);
        if (active) {
          activeExists = true;
          break;
        }
      }
      if (activeExists) {
        debugPrint(
          '[PLANNER] manualOverride=true => skipping auto apply during active window',
        );
        return; // don't touch anything now
      } else {
        // no active plan -> clear override so next window can apply as usual
        _manualOverride = false;
      }
    }

    for (var i = 0; i < _plans.length; i++) {
      final p = _plans[i];
      if (!p.enabled) continue;

      final startMin = p.start.hour * 60 + p.start.minute;
      final endMin = p.end.hour * 60 + p.end.minute;
      final bool active = (startMin <= endMin)
          ? (curMin >= startMin && curMin < endMin)
          : (curMin >= startMin || curMin < endMin); // spans midnight

      if (active) anyActive = true;

      debugPrint(
        '[PLANNER] plan#$i enabled=${p.enabled} start=$startMin end=$endMin active=$active',
      );

      // Apply only for ACTIVE plans:
      // - normal durumda sadece planın başlangıç dakikasında
      // - force=true (kaydetme/düzenleme) olduğunda ise, aktif pencere
      //   içindeyse hemen uygula
      final bool shouldApply =
          active &&
          (force || (curMin == startMin && _appliedStartMin[i] != curMin));
      if (!shouldApply) continue;

      // İlk kez bir plan uygulanıyorsa mevcut durumu snapshot olarak al
      if (!_plannerWasActive && !_hasPrePlanSnapshot && state != null) {
        _hasPrePlanSnapshot = true;
        _prePlanMode = state!.mode;
        _prePlanFanPercent = state!.fanPercent;
        _prePlanLightOn = state!.lightOn;
        _prePlanIonOn = state!.ionOn;
        _prePlanRgbOn = state!.rgbOn;
        _prePlanAutoHumEnabled = _autoHumEnabled;
        _prePlanAutoHumTarget = _autoHumTarget;
        debugPrint('[PLANNER] snapshot pre-plan state captured');
      }

      _appliedStartMin[i] = curMin;
      _plannerWasActive = true; // a plan is currently driving
      _autoAfterNoPlanSent = false; // allow future AUTO trigger after plan ends

      final payload = {
        'mode': p.mode,
        'fanPercent': p.fanPercent,
        'lightOn': p.lightOn,
        'ionOn': p.ionOn,
        'rgb': {'on': p.rgbOn},
      };
      if (_isDoaDevice) {
        // Doa profilinde manuel sulama veya nem-bazlı otomasyon aktifken
        // planner sulama alanlarına dokunmamalı; aksi halde kullanıcı ayarı ezilir.
        final bool plannerCanDriveDoaWatering =
            !_doaManualWaterOn && !_doaHumAutoEnabled;
        if (plannerCanDriveDoaWatering) {
          payload['waterAutoEnabled'] = p.autoHumEnabled ? 1 : 0;
        }
        payload['autoHumEnabled'] = 0;
      } else {
        payload['autoHumEnabled'] = p.autoHumEnabled ? 1 : 0;
        payload['autoHumTarget'] = p.autoHumTarget;
      }

      // UI tarafında da otomatik nem ayarlarını aktif plana göre güncelle
      if (mounted) {
        _safeSetState(() {
          _autoHumEnabled = p.autoHumEnabled;
          _autoHumTarget = p.autoHumTarget.toDouble();
        });
      }

      // Clean kapalıyken fan asla dönmemeli
      if (!(state?.cleanOn ?? false)) {
        payload['fanPercent'] = 0;
      }

      debugPrint(
        '[PLANNER] applying plan#$i (force=$force) payload=${jsonEncode(payload)}',
      );
      Future.microtask(() => _send(payload, promptForQr: false));
    }

    // Transition: if previously a plan was active but now none is active,
    // restore user's pre-plan profile if we have a snapshot; otherwise use
    // a safe default (AUTO + ionizer on).
    if (!anyActive && _plannerWasActive) {
      debugPrint(
        '[PLANNER] all plans inactive now; restoring pre-plan or default profile',
      );
      _plannerWasActive = false; // prevent repeated triggers
      _autoAfterNoPlanSent = true; // don't keep forcing AUTO
      _manualOverride = false; // clear manual override at window end

      Map<String, dynamic> payload;
      if (_hasPrePlanSnapshot && _prePlanMode != null) {
        payload = {
          'mode': _prePlanMode,
          if (_prePlanFanPercent != null) 'fanPercent': _prePlanFanPercent,
          if (_prePlanLightOn != null) 'lightOn': _prePlanLightOn,
          if (_prePlanIonOn != null) 'ionOn': _prePlanIonOn,
          'rgb': {'on': _prePlanRgbOn ?? false},
        };
        if (mounted) {
          _safeSetState(() {
            if (_prePlanAutoHumEnabled != null) {
              _autoHumEnabled = _prePlanAutoHumEnabled!;
            }
            if (_prePlanAutoHumTarget != null) {
              _autoHumTarget = _prePlanAutoHumTarget!;
            }
          });
        }
        debugPrint(
          '[PLANNER] restoring snapshot payload=${jsonEncode(payload)}',
        );
      } else {
        payload = {
          'mode': 5, // FAN_AUTO
          'lightOn': false,
          'ionOn': true,
          'rgb': {'on': false},
        };
        debugPrint('[PLANNER] no snapshot; using default AUTO profile');
      }

      _hasPrePlanSnapshot = false;
      _prePlanMode = null;
      _prePlanFanPercent = null;
      _prePlanLightOn = null;
      _prePlanIonOn = null;
      _prePlanRgbOn = null;
      _prePlanAutoHumEnabled = null;
      _prePlanAutoHumTarget = null;

      Future.microtask(() => _send(payload, promptForQr: false));
    }

    // If any plan is currently active, make sure we can auto-trigger later when it ends
    if (anyActive) {
      _plannerWasActive = true;
      _autoAfterNoPlanSent = false;
    }
  }
}
