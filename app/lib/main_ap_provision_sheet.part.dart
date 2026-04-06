part of 'main.dart';

class ApProvisionResult {
  const ApProvisionResult({
    required this.success,
    required this.message,
    this.ip,
    this.showReconnectHint = false,
  });
  final bool success;
  final String message;
  final String? ip;
  final bool showReconnectHint;
}

class ApProvisionSheet extends StatefulWidget {
  const ApProvisionSheet({
    super.key,
    required this.onProvision,
    this.onScanWifi,
    this.brandLabel = '',
  });

  final Future<ApProvisionResult> Function(String ssid, String pass)
  onProvision;
  final Future<void> Function(
    BuildContext context,
    TextEditingController controller,
  )?
  onScanWifi;
  final String brandLabel;

  @override
  State<ApProvisionSheet> createState() => _ApProvisionSheetState();
}

class _ApProvisionSheetState extends State<ApProvisionSheet> {
  final TextEditingController _ssidCtl = TextEditingController();
  final TextEditingController _pwdCtl = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _autoScanOnce = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_prefillLastSsid);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_autoScanOnce) return;
      _autoScanOnce = true;
      final scan = widget.onScanWifi;
      if (scan == null) return;
      if (_ssidCtl.text.trim().isNotEmpty) return;
      try {
        await scan(context, _ssidCtl);
      } catch (_) {}
    });
  }

  Future<void> _prefillLastSsid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_ssid');
      if (last != null && last.trim().isNotEmpty) {
        _ssidCtl.text = last.trim();
        debugPrint('[AP][UI] Prefilled SSID from last_ssid="$last"');
      }
    } catch (e) {
      debugPrint('[AP][UI] Prefill SSID error: $e');
    }
  }

  @override
  void dispose() {
    _ssidCtl.dispose();
    _pwdCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedBrand = widget.brandLabel.trim();
    final apBrand = normalizedBrand.isNotEmpty
        ? normalizedBrand
        : kDefaultDeviceBrand;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi_tethering, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'AP ile Kurulum',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1. Telefondaki Wi-Fi ayarlarından "${apBrand}_AP_XXXX" ağına bağlanın.',
              ),
              const SizedBox(height: 4),
              const Text(
                '2. Ev ağınızı seçip şifresini girin. Kurulum tamamlanınca cihazın IP adresi otomatik kaydedilecektir.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ssidCtl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Wi-Fi SSID',
                  prefixIcon: const Icon(Icons.wifi),
                  suffixIcon: IconButton(
                    tooltip: 'Ağları tara',
                    icon: const Icon(Icons.wifi_find),
                    onPressed: () async {
                      final scan = widget.onScanWifi;
                      if (scan != null) {
                        await scan(context, _ssidCtl);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwdCtl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi Şifre',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final ssid = _ssidCtl.text.trim();
                        if (ssid.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Lütfen Wi-Fi SSID girin'),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          _busy = true;
                          _status = null;
                        });
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('last_ssid', ssid);
                          } catch (_) {}
                          final res = await widget.onProvision(
                            ssid,
                            _pwdCtl.text,
                          );
                          if (!mounted) return;
                          if (res.success) {
                            navigator.pop(res);
                          } else {
                            setState(() => _status = res.message);
                            messenger.showSnackBar(
                              SnackBar(content: Text(res.message)),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _busy = false);
                          }
                        }
                      },
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Kaydet ve Bağlan'),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(
                  _status!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
