import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppStore {
  AppStore._(this._prefs);

  static const _baseUrlKey = 'base_url';
  static const _tokenKey = 'token';
  static const _emailKey = 'email';
  static const _nameKey = 'name';
  static const _userIdKey = 'user_id';
  static const _avatarKey = 'avatar_url';
  static const _modelKey = 'model';
  static const _languageKey = 'language';
  static const _languageSetKey = 'language_user_set';
  static const _themeModeKey = 'theme_mode';
  static const _useSystemColorKey = 'use_system_color';
  static const _accentKey = 'accent_color';

  final SharedPreferences _prefs;

  static Future<AppStore> load() async {
    return AppStore._(await SharedPreferences.getInstance());
  }

  String get baseUrl => _prefs.getString(_baseUrlKey) ?? '';

  String get model => _prefs.getString(_modelKey) ?? '';

  String get language {
    final saved = _prefs.getString(_languageKey);
    if (_prefs.getBool(_languageSetKey) == true &&
        (saved == 'ru' || saved == 'en')) {
      return saved!;
    }
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return code == 'ru' ? 'ru' : 'en';
  }

  ThemeMode get themeMode {
    switch (_prefs.getString(_themeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  bool get useSystemColor => _prefs.getBool(_useSystemColorKey) ?? true;

  Color get accentColor => Color(_prefs.getInt(_accentKey) ?? 0xFF7C5CFF);

  Session? get session {
    final token = _prefs.getString(_tokenKey);
    final email = _prefs.getString(_emailKey);
    if (token == null || token.isEmpty || email == null || email.isEmpty) {
      return null;
    }
    return Session(
      baseUrl: baseUrl,
      token: token,
      email: email,
      name: _prefs.getString(_nameKey) ?? email,
      userId: _prefs.getString(_userIdKey) ?? '',
      avatarUrl: _prefs.getString(_avatarKey) ?? '',
    );
  }

  Future<void> saveSession(Session session) async {
    await _prefs.setString(_baseUrlKey, session.baseUrl);
    await _prefs.setString(_tokenKey, session.token);
    await _prefs.setString(_emailKey, session.email);
    await _prefs.setString(_nameKey, session.name);
    await _prefs.setString(_userIdKey, session.userId);
    await _prefs.setString(_avatarKey, session.avatarUrl);
  }

  Future<void> saveBaseUrl(String url) => _prefs.setString(_baseUrlKey, url);

  Future<void> saveModel(String model) => _prefs.setString(_modelKey, model);

  Future<void> saveLanguage(String code) async {
    await _prefs.setBool(_languageSetKey, true);
    await _prefs.setString(_languageKey, code);
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeModeKey, switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });

  Future<void> saveUseSystemColor(bool value) =>
      _prefs.setBool(_useSystemColorKey, value);

  Future<void> saveAccentColor(Color color) =>
      _prefs.setInt(_accentKey, color.toARGB32());

  Future<void> clearSession() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_emailKey);
    await _prefs.remove(_nameKey);
    await _prefs.remove(_userIdKey);
    await _prefs.remove(_avatarKey);
    await _prefs.remove(_modelKey);
  }
}
