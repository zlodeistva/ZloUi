import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme.dart';
import 'l10n.dart';
import 'screens/chat_screen.dart';
import 'store.dart';

/// Starts the floating assistant window (called from the entrypoint in main.dart).
Future<void> runAssistant() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.load();
  runApp(AssistantApp(store: store));
}

/// The assistant window is the same chat as in the app in a compact form, so
/// models, tools, images, markdown and questions behave identically.
class AssistantApp extends StatelessWidget {
  const AssistantApp({super.key, required this.store});

  static const _channel = MethodChannel('zloui/assist');

  final AppStore store;

  void _close() => SystemNavigator.pop();

  Future<void> _openApp(String? chatId) async {
    try {
      await _channel.invokeMethod<void>('openApp', chatId);
    } catch (_) {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ThemeData theme(Brightness brightness, Object? dynamic) => appThemeFor(
          brightness: brightness,
          useSystemColor: store.useSystemColor,
          accent: store.accentColor,
          dynamicScheme: dynamic,
        );
        final session = store.session;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(store.language),
          supportedLocales: Strings.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: store.themeMode,
          theme: theme(Brightness.light, lightDynamic),
          darkTheme: theme(Brightness.dark, darkDynamic),
          home: session == null
              ? _LoginRequired(onClose: _close)
              : ChatScreen(
                  store: store,
                  session: session,
                  onSessionUpdated: (_) {},
                  onUnauthorized: _close,
                  assistantMode: true,
                  onAssistantClose: _close,
                  onAssistantOpenApp: _openApp,
                ),
        );
      },
    );
  }
}

class _LoginRequired extends StatelessWidget {
  const _LoginRequired({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.4),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    Strings.of(context).t('assistantLoginFirst'),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
