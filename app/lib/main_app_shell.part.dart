part of 'main.dart';

// Application shell and first-run bootstrap.
// Kept separate so product variants can share transport/core code
// while replacing only top-level app boot experience.
class ArtAirCleanerApp extends StatefulWidget {
  const ArtAirCleanerApp({super.key});
  @override
  State<ArtAirCleanerApp> createState() => _ArtAirCleanerAppState();
}

class _ArtAirCleanerAppState extends State<ArtAirCleanerApp> {
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.dark);
  final ValueNotifier<String> _lang = ValueNotifier('tr');
  final ValueNotifier<bool> _langReady = ValueNotifier(false);

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapApp());
    });
  }

  Future<void> _bootstrapApp() async {
    await _ensureLanguageSelected();
    await _loadInitialTheme();
    _langReady.value = true;
  }

  Future<void> _ensureLanguageSelected() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('lang');
    final supported = I18n.supported.keys.toList();

    if (saved != null && supported.contains(saved)) {
      _lang.value = saved;
      return;
    }

    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    final choice = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) {
        final entries = I18n.supported.entries.toList();
        return AlertDialog(
          title: Text(I18n(_lang.value).t('dialog_title')),
          content: SizedBox(
            width: 360,
            height: 360,
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final code = entries[i].key;
                final name = entries[i].value;
                return ListTile(
                  title: Text(name),
                  trailing: Text(code.toUpperCase()),
                  onTap: () => Navigator.pop(dCtx, code),
                );
              },
            ),
          ),
        );
      },
    );

    if (choice != null && supported.contains(choice)) {
      await p.setString('lang', choice);
      _lang.value = choice;
    }
  }

  Future<void> _loadInitialTheme() async {
    final p = await SharedPreferences.getInstance();
    final themeStr = p.getString('theme_mode');
    if (themeStr == 'light') {
      _themeMode.value = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode.value = ThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _lang,
      builder: (_, code, __) {
        final i18n = I18n(code);
        return ValueListenableBuilder<bool>(
          valueListenable: _langReady,
          builder: (_, ready, __) {
            return Directionality(
              textDirection: I18n(code).isRTL
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: _themeMode,
                builder: (_, mode, __) {
                  return MaterialApp(
                    navigatorKey: _navKey,
                    title: i18n.t('title'),
                    themeMode: mode,
                    theme: ThemeData(
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal,
                        brightness: Brightness.light,
                      ),
                      useMaterial3: true,
                    ),
                    darkTheme: ThemeData(
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal,
                        brightness: Brightness.dark,
                      ),
                      useMaterial3: true,
                    ),
                    home: ready
                        ? HomeScreen(
                            i18n: i18n,
                            onThemeChanged: (m) => _themeMode.value = m,
                            onLanguageChanged: (c) async {
                              _lang.value = c;
                              final p = await SharedPreferences.getInstance();
                              await p.setString('lang', c);
                            },
                          )
                        : const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
