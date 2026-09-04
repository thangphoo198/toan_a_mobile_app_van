import 'package:flutter/material.dart';
import '../services/prefs_service.dart';

class ThemeProvider extends ChangeNotifier {
  final PrefsService prefs;
  ThemeProvider({required this.prefs}) {
    _load();
  }

  ThemeMode mode = ThemeMode.system;

  Future<void> _load() async {
    final raw = await prefs.getThemeMode();
    mode = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    await prefs.setThemeMode(switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
