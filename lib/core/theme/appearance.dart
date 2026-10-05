import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme choice (system / light / dark, like the moon toggle on usekago.net)
/// and the OLED black option for the dark theme. Saved between launches.
class Appearance {
  const Appearance({this.mode = ThemeMode.system, this.pureBlack = false});
  final ThemeMode mode;
  final bool pureBlack;

  Appearance copyWith({ThemeMode? mode, bool? pureBlack}) => Appearance(
      mode: mode ?? this.mode, pureBlack: pureBlack ?? this.pureBlack);
}

class AppearanceNotifier extends StateNotifier<Appearance> {
  AppearanceNotifier() : super(const Appearance()) {
    _load();
  }

  static const _modeKey = 'kago.theme.mode';
  static const _blackKey = 'kago.theme.pureBlack';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_modeKey);
      state = Appearance(
        mode: ThemeMode.values.firstWhere((value) => value.name == name,
            orElse: () => ThemeMode.system),
        pureBlack: prefs.getBool(_blackKey) ?? false,
      );
    } catch (_) {
      // Storage unavailable: keep the defaults.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    try {
      await (await SharedPreferences.getInstance())
          .setString(_modeKey, mode.name);
    } catch (_) {}
  }

  Future<void> setPureBlack(bool value) async {
    state = state.copyWith(pureBlack: value);
    try {
      await (await SharedPreferences.getInstance()).setBool(_blackKey, value);
    } catch (_) {}
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceNotifier, Appearance>(
        (ref) => AppearanceNotifier());
