import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AdminLTE / Bootstrap palette mapped to hex. ITFlow's web UI applies these
/// via `accent-<name>` on the `<body>`. Falls back to indigo seed (the app's
/// default brand color) when the name is unknown.
const Color _defaultSeed = Color(0xFF4F46E5);

const Map<String, Color> adminLteAccents = {
  'pink': Color(0xFFE83E8C),
  'fuchsia': Color(0xFFF012BE),
  'red': Color(0xFFDC3545),
  'danger': Color(0xFFDC3545),
  'maroon': Color(0xFFD81B60),
  'orange': Color(0xFFFF851B),
  'yellow': Color(0xFFFFC107),
  'warning': Color(0xFFFFC107),
  'olive': Color(0xFF3D9970),
  'lime': Color(0xFF01FF70),
  'green': Color(0xFF28A745),
  'success': Color(0xFF28A745),
  'teal': Color(0xFF39CCCC),
  'cyan': Color(0xFF17A2B8),
  'info': Color(0xFF17A2B8),
  'lightblue': Color(0xFF3C8DBC),
  'blue': Color(0xFF007BFF),
  'primary': Color(0xFF007BFF),
  'navy': Color(0xFF001F3F),
  'indigo': Color(0xFF6610F2),
  'purple': Color(0xFF6F42C1),
  'black': Color(0xFF000000),
  'gray-dark': Color(0xFF343A40),
  'gray': Color(0xFF6C757D),
  'white': Color(0xFFFFFFFF),
};

Color colorForAccent(String? name) {
  if (name == null) return _defaultSeed;
  return adminLteAccents[name.toLowerCase()] ?? _defaultSeed;
}

class AppSettings {
  final String? displayName;
  final String accentMode; // 'auto' | 'manual'
  final String? manualAccentColor; // key from adminLteAccents
  final String? cachedInstanceAccent; // last scraped from ITFlow
  final String? cachedInstanceName; // company_name from agent <title>
  final String themeMode; // 'system' | 'light' | 'dark' | 'oled'

  const AppSettings({
    this.displayName,
    this.accentMode = 'auto',
    this.manualAccentColor,
    this.cachedInstanceAccent,
    this.cachedInstanceName,
    this.themeMode = 'system',
  });

  /// User override > scraped company name > "ITFlow".
  String get effectiveTitle {
    final override = displayName?.trim();
    if (override != null && override.isNotEmpty) return override;
    final scraped = cachedInstanceName?.trim();
    if (scraped != null && scraped.isNotEmpty) return scraped;
    return 'ITFlow';
  }

  Color get effectiveSeedColor {
    if (accentMode == 'manual') return colorForAccent(manualAccentColor);
    return colorForAccent(cachedInstanceAccent);
  }

  AppSettings copyWith({
    String? displayName,
    String? accentMode,
    String? manualAccentColor,
    String? cachedInstanceAccent,
    String? cachedInstanceName,
    String? themeMode,
    bool clearDisplayName = false,
  }) =>
      AppSettings(
        displayName: clearDisplayName
            ? null
            : (displayName ?? this.displayName),
        accentMode: accentMode ?? this.accentMode,
        manualAccentColor: manualAccentColor ?? this.manualAccentColor,
        cachedInstanceAccent:
            cachedInstanceAccent ?? this.cachedInstanceAccent,
        cachedInstanceName: cachedInstanceName ?? this.cachedInstanceName,
        themeMode: themeMode ?? this.themeMode,
      );
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _kDisplayName = 'pref.displayName';
  static const _kAccentMode = 'pref.accentMode';
  static const _kManual = 'pref.manualAccentColor';
  static const _kCached = 'pref.cachedInstanceAccent';
  static const _kCachedName = 'pref.cachedInstanceName';
  static const _kThemeMode = 'pref.themeMode';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  @override
  Future<AppSettings> build() async {
    final p = await _prefs();
    return AppSettings(
      displayName: p.getString(_kDisplayName),
      accentMode: p.getString(_kAccentMode) ?? 'auto',
      manualAccentColor: p.getString(_kManual),
      cachedInstanceAccent: p.getString(_kCached),
      cachedInstanceName: p.getString(_kCachedName),
      themeMode: p.getString(_kThemeMode) ?? 'system',
    );
  }

  Future<void> setCachedInstanceName(String name) async {
    final p = await _prefs();
    await p.setString(_kCachedName, name);
    final current = state.value ?? const AppSettings();
    state = AsyncValue.data(current.copyWith(cachedInstanceName: name));
  }

  Future<void> setThemeMode(String mode) async {
    final p = await _prefs();
    await p.setString(_kThemeMode, mode);
    final current = state.value ?? const AppSettings();
    state = AsyncValue.data(current.copyWith(themeMode: mode));
  }

  Future<void> setDisplayName(String? name) async {
    final p = await _prefs();
    final v = (name ?? '').trim();
    if (v.isEmpty) {
      await p.remove(_kDisplayName);
    } else {
      await p.setString(_kDisplayName, v);
    }
    final current = state.value ?? const AppSettings();
    state = AsyncValue.data(
        current.copyWith(displayName: v.isEmpty ? null : v, clearDisplayName: v.isEmpty));
  }

  Future<void> setAccentMode(String mode) async {
    final p = await _prefs();
    await p.setString(_kAccentMode, mode);
    final current = state.value ?? const AppSettings();
    state = AsyncValue.data(current.copyWith(accentMode: mode));
  }

  Future<void> setManualAccent(String? color) async {
    final p = await _prefs();
    if (color == null) {
      await p.remove(_kManual);
    } else {
      await p.setString(_kManual, color);
    }
    final current = state.value ?? const AppSettings();
    state = AsyncValue.data(current.copyWith(manualAccentColor: color));
  }

  Future<void> setCachedInstanceAccent(String color) async {
    final p = await _prefs();
    await p.setString(_kCached, color);
    final current = state.value ?? const AppSettings();
    state = AsyncValue.data(current.copyWith(cachedInstanceAccent: color));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
        AppSettingsNotifier.new);
