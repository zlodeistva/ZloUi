import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../models.dart';
import '../store.dart';
import 'account_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
    required this.onSettingsChanged,
  });

  final AppStore store;
  final Session session;
  final ValueChanged<Session> onSessionUpdated;
  final VoidCallback onLogout;
  final VoidCallback onSettingsChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _assistChannel = MethodChannel('zloui/assist');

  int _index = 0;

  /// Fires when the app is launched as the digital assistant.
  final _assistSignal = ValueNotifier<AssistRequest>(const AssistRequest(0));

  @override
  void initState() {
    super.initState();
    _assistChannel.setMethodCallHandler((call) async {
      if (call.method == 'assist') _onAssist(call.arguments as String?);
    });
    _assistChannel
        .invokeMethod<Object>('consumeLaunch')
        .then((launched) {
          if (launched is Map && launched['assist'] == true) {
            _onAssist(launched['chatId'] as String?);
          }
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _assistChannel.setMethodCallHandler(null);
    _assistSignal.dispose();
    super.dispose();
  }

  void _onAssist(String? chatId) {
    if (!mounted) return;
    setState(() => _index = 0);
    _assistSignal.value = AssistRequest(_assistSignal.value.id + 1, chatId);
  }

  Future<void> _logout() async {
    await widget.store.clearSession();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final s = Strings.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          ChatScreen(
            store: widget.store,
            session: widget.session,
            onSessionUpdated: widget.onSessionUpdated,
            onUnauthorized: _logout,
            assistSignal: _assistSignal,
          ),
          SettingsScreen(
            store: widget.store,
            onChanged: widget.onSettingsChanged,
            asTab: true,
          ),
          AccountScreen(session: widget.session, onLogout: _logout),
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                FocusScope.of(context).unfocus();
                setState(() => _index = value);
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.chat_bubble_outline),
                  selectedIcon: const Icon(Icons.chat_bubble),
                  label: s.t('chat'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: s.t('settings'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_circle_outlined),
                  selectedIcon: const Icon(Icons.account_circle),
                  label: s.t('account'),
                ),
              ],
            ),
    );
  }
}
