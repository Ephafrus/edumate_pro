import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Holds the user-configurable look & feel (seed colour + light/dark mode) and
/// persists it locally so it survives restarts and applies to guests too.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _load();
  }

  static const _seedKey = 'theme_seed';
  static const _modeKey = 'theme_mode';

  Color _seed = AppTheme.defaultSeed;
  ThemeMode _mode = ThemeMode.system;

  Color get seed => _seed;
  ThemeMode get mode => _mode;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final seedValue = prefs.getInt(_seedKey);
    if (seedValue != null) _seed = Color(seedValue);
    final modeIndex = prefs.getInt(_modeKey);
    if (modeIndex != null && modeIndex < ThemeMode.values.length) {
      _mode = ThemeMode.values[modeIndex];
    }
    notifyListeners();
  }

  Future<void> setSeed(Color color) async {
    _seed = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // ignore: deprecated_member_use  (kept for broad SDK compatibility)
    await prefs.setInt(_seedKey, color.value);
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, mode.index);
  }
}
