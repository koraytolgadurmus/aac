part of 'main.dart';

extension _HomeScreenProvisioningUiPart on _HomeScreenState {
  Future<void> sendMtlsConfig(String cert, String key, String ca) async {
    final cmd = _bleCtrlCmdChar;
    if (cmd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('BLE bağlı değil veya komut kanalı hazır değil.'),
        ),
      );
      return;
    }
    try {
      final payload = jsonEncode(<String, dynamic>{
        'cmd': 'set_mtls',
        'certPem': cert,
        'keyPem': key,
        'caPem': ca,
      });
      await cmd.write(
        utf8.encode(payload),
        withoutResponse: !cmd.properties.write,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sertifikalar gönderildi! Cihaz yeniden bağlanmalı.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  void _showProvisioningDialog() {
    final certCtl = TextEditingController();
    final keyCtl = TextEditingController();
    final caCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Provision Device (Manual)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: certCtl,
                decoration: const InputDecoration(labelText: 'Certificate PEM'),
                maxLines: 3,
              ),
              TextField(
                controller: keyCtl,
                decoration: const InputDecoration(labelText: 'Private Key PEM'),
                maxLines: 3,
              ),
              TextField(
                controller: caCtl,
                decoration: const InputDecoration(labelText: 'Root CA PEM'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              sendMtlsConfig(
                certCtl.text.trim(),
                keyCtl.text.trim(),
                caCtl.text.trim(),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _bleSsidPicker() async {
    if (_bleBusy) {
      _showSnack('BLE busy...');
      return;
    }
    _bleBusy = true;

    StreamSubscription<List<ScanResult>>? scanSub;
    StreamSubscription<List<int>>? localNotifySub;
    BluetoothDevice? target;
    BluetoothCharacteristic? provChar;
    BluetoothCharacteristic? infoChar;
    BluetoothCharacteristic? cmdChar;
    final ssids = <String>{};

    Future<void> cleanup() async {
      try {
        _bleReadTimer?.cancel();
      } catch (_) {}
      _bleReadTimer = null;

      try {
        _blePollCmdTimer?.cancel();
      } catch (_) {}
      _blePollCmdTimer = null;

      try {
        await notifySub?.cancel();
      } catch (_) {}
      notifySub = null;

      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      try {
        await scanSub?.cancel();
      } catch (_) {}
      scanSub = null;
    }

    try {
      final bleReady = await _ensureBluetoothOnWithUi();
      if (!bleReady) {
        await cleanup();
        return;
      }

      try {
        final connected = FlutterBluePlus.connectedDevices;
        for (final d in connected) {
          if (isKnownBleName(d.platformName)) {
            target = d;
            break;
          }
        }
      } catch (_) {
        target = null;
      }

      if (target == null) {
        final collected = <ScanResult>[];
        scanSub = FlutterBluePlus.scanResults.listen((batch) {
          for (final r in batch) {
            if (!collected.any(
              (e) => e.device.remoteId.str == r.device.remoteId.str,
            )) {
              collected.add(r);
              debugPrint(
                '[BLE][SSID] seen: id=${r.device.remoteId.str} name=${r.device.platformName} adv=${r.advertisementData.advName}',
              );
            }
          }
        });
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
        await Future.delayed(const Duration(seconds: 5));
        await FlutterBluePlus.stopScan();
        await scanSub?.cancel();

        ScanResult? hit;
        for (final r in collected) {
          final name = r.device.platformName;
          final adv = r.advertisementData.advName;
          if (isKnownBleName(name) || isKnownBleName(adv)) {
            hit = r;
            break;
          }
        }
        if (hit == null) {
          _showSnack('Yakında uyumlu BLE cihazı bulunamadı.');
          await cleanup();
          _bleBusy = false;
          return;
        }
        target = hit.device;
      }

      try {
        await target.connect(timeout: const Duration(seconds: 8));
      } catch (_) {}

      final services = await target.discoverServices();
      BluetoothService? prefSvc;
      try {
        prefSvc = services.firstWhere((s) => _guidEq(s.uuid, kSvcUuidHint));
      } catch (_) {
        prefSvc = null;
      }
      Iterable<BluetoothCharacteristic> scanChars(
        Iterable<BluetoothService> ss,
      ) sync* {
        for (final s in ss) {
          for (final c in s.characteristics) {
            yield c;
          }
        }
      }

      final scope = prefSvc != null ? [prefSvc] : services;
      for (final c in scanChars(scope)) {
        final canWrite =
            c.properties.write || c.properties.writeWithoutResponse;
        final canNotify = c.properties.notify;
        debugPrint(
          '[BLE][SSID] char ${c.uuid.str} write=${c.properties.write} writeNR=${c.properties.writeWithoutResponse} notify=${c.properties.notify}',
        );
        if (provChar == null &&
            (_guidEq(c.uuid, kProvCharUuidHint) || canWrite)) {
          provChar = c;
        }
        if (infoChar == null &&
            (_guidEq(c.uuid, kInfoCharUuidHint) || canNotify)) {
          infoChar = c;
        }
        if (cmdChar == null &&
            !_guidEq(c.uuid, kProvCharUuidHint) &&
            !_guidEq(c.uuid, kInfoCharUuidHint) &&
            (c.properties.write || c.properties.writeWithoutResponse)) {
          cmdChar = c;
        }
      }

      provChar ??= _firstWhereOrNull<BluetoothCharacteristic>(
        scanChars(scope),
        (c) => c.properties.write || c.properties.writeWithoutResponse,
      );
      if (provChar == null) {
        _showSnack('BLE WRITE karakteristiği bulunamadı.');
        await cleanup();
        _bleBusy = false;
        return;
      }
      infoChar ??= _firstWhereOrNull<BluetoothCharacteristic>(
        scanChars(scope),
        (c) => c.properties.notify,
      );
      if (infoChar == null) {
        _showSnack('BLE NOTIFY karakteristiği bulunamadı.');
        await cleanup();
        _bleBusy = false;
        return;
      }
      if (cmdChar == null) {
        cmdChar = _firstWhereOrNull<BluetoothCharacteristic>(
          scanChars(scope),
          (c) =>
              !_guidEq(c.uuid, provChar!.uuid) &&
              !_guidEq(c.uuid, infoChar!.uuid) &&
              (c.properties.write || c.properties.writeWithoutResponse),
        );
        cmdChar ??= provChar;
      }

      await infoChar.setNotifyValue(true);

      final StringBuffer buf = StringBuffer();
      int depth = 0;
      bool inStr = false;
      bool esc = false;
      localNotifySub = infoChar.lastValueStream.listen((data) {
        try {
          final chunk = utf8.decode(data, allowMalformed: true);
          for (int i = 0; i < chunk.length; i++) {
            final ch = chunk[i];
            buf.write(ch);
            if (esc) {
              esc = false;
              continue;
            }
            if (inStr) {
              if (ch == '\\') {
                esc = true;
              } else if (ch == '"') {
                inStr = false;
              }
              continue;
            }
            if (ch == '"') {
              inStr = true;
            } else if (ch == '{') {
              depth++;
            } else if (ch == '}') {
              depth = (depth - 1).clamp(0, 1 << 20);
              if (depth == 0) {
                final jsonStr = buf.toString();
                buf.clear();
                try {
                  final obj = jsonDecode(jsonStr);
                  if (obj is Map) {
                    final aps = obj['aps'] ?? obj['scan'] ?? obj['wifi_scan'];
                    if (aps is List) {
                      for (final e in aps) {
                        if (e is Map) {
                          final s = e['ssid'];
                          if (s is String && s.trim().isNotEmpty) {
                            ssids.add(s.trim());
                          }
                        }
                      }
                    }
                    final single = obj['ssid'];
                    if (single is String && single.trim().isNotEmpty) {
                      ssids.add(single.trim());
                    }
                    final wifi = obj['wifi'];
                    if (wifi is Map && wifi['aps'] is List) {
                      for (final e in (wifi['aps'] as List)) {
                        if (e is Map) {
                          final s = e['ssid'];
                          if (s is String && s.trim().isNotEmpty) {
                            ssids.add(s.trim());
                          }
                        }
                      }
                    }
                  }
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      });

      final cmds = [
        {'scan': 'wifi'},
        {'wifi': 'scan'},
        {'cmd': 'scan_wifi'},
        {'get': 'wifi_scan'},
        {'scan_wifi': true},
      ];

      Future<void> writeCmd(Map<String, dynamic> cmd) async {
        final payload = Map<String, dynamic>.from(cmd);
        final prov = provChar;
        final cmdCharRef = cmdChar;
        final isProv =
            prov != null &&
            cmdCharRef != null &&
            _guidEq(cmdCharRef.uuid, prov.uuid);
        final body = jsonEncode(payload);
        final supportsNoResp =
            cmdChar?.properties.writeWithoutResponse ?? false;
        final supportsWithResp = cmdChar?.properties.write ?? false;

        Future<bool> tryWrite(bool withoutResponse) async {
          try {
            await cmdChar!.write(
              utf8.encode(body),
              withoutResponse: withoutResponse,
            );
            debugPrint(
              '[BLE][SSID] requested scan via write${withoutResponse ? ' (no resp)' : ''}: $body',
            );
            return true;
          } catch (e) {
            debugPrint('[BLE][SSID] write error (noResp=$withoutResponse): $e');
            return false;
          }
        }

        bool attempted = false;

        if (!isProv && supportsNoResp) {
          attempted = true;
          if (await tryWrite(true)) return;
        }

        if (supportsWithResp || isProv) {
          attempted = true;
          if (await tryWrite(false)) return;
        }

        if (!attempted) {
          debugPrint(
            '[BLE][SSID] write skipped: characteristic has no writable property',
          );
        }
      }

      for (final cmd in cmds) {
        await writeCmd(cmd);
        await Future.delayed(const Duration(milliseconds: 600));
      }

      for (int i = 0; i < 3; i++) {
        await writeCmd({'get': 'status'});
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await Future.delayed(const Duration(seconds: 2));

      try {
        await localNotifySub.cancel();
      } catch (_) {}
      localNotifySub = null;
      try {
        _bleReadTimer?.cancel();
      } catch (_) {}
      _bleReadTimer = null;

      List<String> list = ssids.toList();
      if (list.isEmpty) {
        debugPrint(
          '[BLE][SSID] BLE scan empty, trying AP portal scan as fallback',
        );
        try {
          if (!mounted) return;
          await _scanWifiNetworks(context, TextEditingController());
        } catch (e) {
          debugPrint('[BLE][SSID] AP fallback scan error: $e');
        }
      }

      list = ssids.toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (list.isEmpty) {
        _showSnack('Wi-Fi ağları bulunamadı');
        await cleanup();
        _bleBusy = false;
        return;
      }

      if (!mounted) return;
      if (context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = list[i];
                  return ListTile(
                    leading: const Icon(Icons.wifi),
                    title: Text(
                      s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      final nav = Navigator.of(ctx);
                      try {
                        final p = await SharedPreferences.getInstance();
                        await p.setString('last_ssid', s);
                        await Clipboard.setData(ClipboardData(text: s));
                        _showSnack('${t.literal('SSID seçildi')}: $s');
                      } catch (_) {}
                      if (nav.canPop()) {
                        nav.pop();
                      }
                    },
                  );
                },
              ),
            );
          },
        );
      }

      await cleanup();
      _bleBusy = false;
    } catch (e, st) {
      debugPrint('[BLE][SSID] picker error: $e');
      debugPrint(st.toString());
      try {
        await cleanup();
      } catch (_) {}
      _bleBusy = false;
      _showSnack(t.t('command_failed'));
    }
  }
}
