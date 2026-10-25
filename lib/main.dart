import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme.dart';
import 'assistant_overlay.dart';
import 'l10n.dart';
import 'models.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.load();
  runApp(ZloUiApp(store: store));
}

/// Entrypoint of the floating assistant window (AssistantActivity).
@pragma('vm:entry-point')
Future<void> assistantMain() => runAssistant();

class ZloUiApp extends StatefulWidget {
  const ZloUiApp({super.key, required this.store});

  final AppStore store;

  @override
  State<ZloUiApp> createState() => _ZloUiAppState();
}

class _ZloUiAppState extends State<ZloUiApp> {
  Session? _session;
  late String _language;
  late ThemeMode _themeMode;
  late bool _useSystemColor;
  late Color _accent;

  @override
  void initState() {
    super.initState();
    _session = widget.store.session;
    _readSettings();
  }

  void _readSettings() {
    _language = widget.store.language;
    _themeMode = widget.store.themeMode;
    _useSystemColor = widget.store.useSystemColor;
    _accent = widget.store.accentColor;
  }

  void _onSettingsChanged() {
    setState(_readSettings);
  }

  void _onSessionUpdated(Session session) {
    setState(() => _session = session);
  }

  @override
  Widget build(BuildContext context) {
    final useDynamic = _useSystemColor;

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: 'ZloUi',
          debugShowCheckedModeBanner: false,
          locale: Locale(_language),
          supportedLocales: Strings.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: _themeMode,
          theme: appThemeFor(
            brightness: Brightness.light,
            useSystemColor: useDynamic,
            accent: _accent,
            dynamicScheme: lightDynamic,
          ),
          darkTheme: appThemeFor(
            brightness: Brightness.dark,
            useSystemColor: useDynamic,
            accent: _accent,
            dynamicScheme: darkDynamic,
          ),
          home: _session == null
              ? LoginScreen(
                  store: widget.store,
                  onLoggedIn: (session) => setState(() => _session = session),
                )
              : HomeShell(
                  key: ValueKey(_session!.token),
                  store: widget.store,
                  session: _session!,
                  onSessionUpdated: _onSessionUpdated,
                  onSettingsChanged: _onSettingsChanged,
                  onLogout: () => setState(() => _session = null),
                ),
        );
      },
    );
  }
}
