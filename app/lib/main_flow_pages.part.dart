part of 'main.dart';

// Shared flow pages used by cloud/auth/setup journeys.
// These are intentionally UI-focused and stateless wrt transport logic.

class _AsyncLaunchPage extends StatefulWidget {
  const _AsyncLaunchPage({required this.title, required this.task});

  final String title;
  final Future<bool> Function() task;

  @override
  State<_AsyncLaunchPage> createState() => _AsyncLaunchPageState();
}

class _AsyncLaunchPageState extends State<_AsyncLaunchPage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await widget.task();
      if (!mounted) return;
      Navigator.of(context).pop(ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudConfirmInput {
  const _CloudConfirmInput({
    required this.action,
    required this.email,
    required this.code,
  });

  final String action;
  final String email;
  final String code;
}

class _CloudConfirmPage extends StatefulWidget {
  const _CloudConfirmPage({required this.initialEmail});

  final String initialEmail;

  @override
  State<_CloudConfirmPage> createState() => _CloudConfirmPageState();
}

class _CloudConfirmPageState extends State<_CloudConfirmPage> {
  late final TextEditingController _emailCtl;
  late final TextEditingController _codeCtl;

  @override
  void initState() {
    super.initState();
    _emailCtl = TextEditingController(text: widget.initialEmail);
    _codeCtl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  void _finish(String action) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _CloudConfirmInput(
        action: action,
        email: _emailCtl.text.trim(),
        code: _codeCtl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_lt(context, 'Cloud doğrulama'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _lt(context, 'E-posta'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _lt(context, 'Doğrulama kodu'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _finish('resend'),
              child: Text(_lt(context, 'Kodu yeniden gönder')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _finish('confirm'),
              child: Text(_lt(context, 'Doğrula')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudEmailPage extends StatefulWidget {
  const _CloudEmailPage({
    required this.title,
    required this.initialEmail,
    required this.submitLabel,
  });

  final String title;
  final String initialEmail;
  final String submitLabel;

  @override
  State<_CloudEmailPage> createState() => _CloudEmailPageState();
}

class _CloudEmailPageState extends State<_CloudEmailPage> {
  late final TextEditingController _emailCtl;

  @override
  void initState() {
    super.initState();
    _emailCtl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-posta',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop(_emailCtl.text.trim());
              },
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceOption {
  const _ChoiceOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.emphasized = false,
  });

  final String value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool emphasized;
}

class _ChoicePage extends StatelessWidget {
  const _ChoicePage({
    required this.title,
    this.description,
    required this.options,
  });

  final String title;
  final String? description;
  final List<_ChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if ((description ?? '').trim().isNotEmpty) ...[
              Text(description!.trim()),
              const SizedBox(height: 12),
            ],
            for (final option in options)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: option.icon != null ? Icon(option.icon) : null,
                  title: Text(option.title),
                  subtitle: option.subtitle != null
                      ? Text(option.subtitle!)
                      : null,
                  trailing: option.emphasized
                      ? const Icon(Icons.arrow_forward)
                      : null,
                  onTap: () => Navigator.of(context).pop(option.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextEntryPage extends StatefulWidget {
  const _TextEntryPage({
    required this.title,
    required this.submitLabel,
    required this.hintText,
    this.initialText = '',
    this.maxLines = 1,
  });

  final String title;
  final String submitLabel;
  final String hintText;
  final String initialText;
  final int maxLines;

  @override
  State<_TextEntryPage> createState() => _TextEntryPageState();
}

class _TextEntryPageState extends State<_TextEntryPage> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _ctl,
              maxLines: widget.maxLines,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: widget.hintText,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_ctl.text.trim()),
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteQrPage extends StatelessWidget {
  const _InviteQrPage({required this.role, required this.data});

  final String role;
  final String data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_lt(context, 'Kullanıcı davet QR kodu'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${_lt(context, 'Rol')}: $role',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                data,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
