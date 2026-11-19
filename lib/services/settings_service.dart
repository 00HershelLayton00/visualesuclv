import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_service.dart';

class SettingsService extends ChangeNotifier {
  SettingsService(this._preferences)
    : _themeMode = _readTheme(_preferences),
      _backgroundChecks = _preferences.getBool(_backgroundKey) ?? true;

  static const String _themeKey = 'theme_mode';
  static const String _backgroundKey = 'background_checks';
  static const String _recentSearchesKey = 'recent_searches';

  final SharedPreferences _preferences;
  ThemeMode _themeMode;
  bool _backgroundChecks;

  ThemeMode get themeMode => _themeMode;
  bool get backgroundChecks => _backgroundChecks;
  List<String> get recentSearches =>
      _preferences.getStringList(_recentSearchesKey) ?? const [];

  Future<void> addRecentSearch(String query) async {
    final value = query.trim();
    if (value.length < 2) return;
    final list = List<String>.of(recentSearches)
      ..removeWhere((item) => item.toLowerCase() == value.toLowerCase())
      ..insert(0, value);
    if (list.length > 8) list.removeRange(8, list.length);
    await _preferences.setStringList(_recentSearchesKey, list);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    await _preferences.remove(_recentSearchesKey);
    notifyListeners();
  }

  static ThemeMode _readTheme(SharedPreferences preferences) {
    switch (preferences.getString(_themeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _preferences.setString(_themeKey, mode.name);
    notifyListeners();
  }

  Future<void> setBackgroundChecks(bool enabled) async {
    _backgroundChecks = enabled;
    await _preferences.setBool(_backgroundKey, enabled);
    if (enabled) {
      await BackgroundService.enable();
    } else {
      await BackgroundService.disable();
    }
    notifyListeners();
  }
}
