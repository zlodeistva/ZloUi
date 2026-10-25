import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.asTab = false,
  });

  final AppStore store;
  final VoidCallback onChanged;

  /// No back button when shown as a bottom navigation tab.
  final bool asTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const _assistChannel = MethodChannel('zloui/assist');

  bool _isAssistant = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAssistant();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAssistant();
  }

  Future<void> _refreshAssistant() async {
    if (!Platform.isAndroid) return;
    try {
      final value = await _assistChannel.invokeMethod<bool>(
        'isDefaultAssistant',
      );
      if (mounted) setState(() => _isAssistant = value == true);
    } catch (_) {}
  }

  Future<void> _openAssistantSettings() async {
    try {
      await _assistChannel.invokeMethod<void>('openAssistantSettings');
    } catch (_) {}
  }

  static const _palette = [
    Color(0xFF7C5CFF),
    Color(0xFF2563EB),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF64748B),
  ];

  Future<void> _setLanguage(String code) async {
    await widget.store.saveLanguage(code);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await widget.store.saveThemeMode(mode);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _setSystemColor(bool value) async {
    await widget.store.saveUseSystemColor(value);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _setAccent(Color color) async {
    await widget.store.saveAccentColor(color);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('settings')),
        automaticallyImplyLeading: !widget.asTab,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionTitle(title: s.t('language')),
          RadioGroup<String>(
            groupValue: widget.store.language,
            onChanged: (value) {
              if (value != null) _setLanguage(value);
            },
            child: Column(
              children: [
                RadioListTile<String>(value: 'ru', title: Text(s.t('russian'))),
                RadioListTile<String>(value: 'en', title: Text(s.t('english'))),
              ],
            ),
          ),
          const Divider(),
          _SectionTitle(title: s.t('theme')),
          RadioGroup<ThemeMode>(
            groupValue: widget.store.themeMode,
            onChanged: (value) {
              if (value != null) _setThemeMode(value);
            },
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text(s.t('themeSystem')),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text(s.t('themeLight')),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text(s.t('themeDark')),
                ),
              ],
            ),
          ),
          const Divider(),
          _SectionTitle(title: s.t('colorSource')),
          SwitchListTile(
            value: widget.store.useSystemColor,
            onChanged: _setSystemColor,
            title: Text(s.t('systemColor')),
            subtitle: Text(s.t('systemColorHint')),
            secondary: const Icon(Icons.auto_awesome),
          ),
          if (!widget.store.useSystemColor) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                s.t('accentColor'),
                style: theme.textTheme.labelLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final color in _palette)
                    _ColorDot(
                      color: color,
                      selected:
                          widget.store.accentColor.toARGB32() ==
                          color.toARGB32(),
                      onTap: () => _setAccent(color),
                    ),
                ],
              ),
            ),
          ],
          if (Platform.isAndroid) ...[
            const Divider(),
            _SectionTitle(title: s.t('assistantSettings')),
            ListTile(
              leading: const Icon(Icons.assistant_outlined),
              title: Text(
                _isAssistant
                    ? s.t('assistantSettingsOn')
                    : s.t('assistantSettingsOpen'),
              ),
              subtitle: Text(s.t('assistantSettingsHint')),
              trailing: _isAssistant
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : const Icon(Icons.chevron_right),
              onTap: _openAssistantSettings,
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}
