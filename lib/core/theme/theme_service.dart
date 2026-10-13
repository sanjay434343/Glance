import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeService extends StateNotifier<ThemeMode> {
  ThemeService() : super(ThemeMode.system);

  void toggleTheme() {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
    } else if (state == ThemeMode.light) {
      state = ThemeMode.system;
    } else {
      state = ThemeMode.dark;
    }
  }

  void setTheme(ThemeMode mode) {
    state = mode;
  }
}

final themeServiceProvider = StateNotifierProvider<ThemeService, ThemeMode>((ref) {
  return ThemeService();
});
