import 'dart:ui' show PlatformDispatcher;

import 'strings_en.dart';

/// App languages. Russian is the source language: the Russian text itself is
/// the key, so untranslated strings fall back to it. Add a language by adding
/// a map like [stringsEn] and listing it here.
abstract final class L10n {
  static const supported = <String>['ru', 'en'];
  static const _tables = <String, Map<String, String>>{'en': stringsEn};

  /// Languages whose speakers usually read Russian better than English.
  static const _russianFallback = <String>{'ru', 'uk', 'be', 'kk', 'ky', 'uz'};

  static String _current = 'ru';
  static String get current => _current;

  /// [choice] is `system`, or a language code from [supported].
  static String resolve(String choice) {
    if (supported.contains(choice)) return choice;
    final system = PlatformDispatcher.instance.locale.languageCode;
    if (supported.contains(system)) return system;
    return _russianFallback.contains(system) ? 'ru' : 'en';
  }

  static void use(String language) =>
      _current = supported.contains(language) ? language : 'ru';

  static String translate(String ru) => _tables[_current]?[ru] ?? ru;
}

/// Translates [ru] into the current language and fills `{name}` placeholders.
String tr(String ru, [Map<String, Object?> args = const <String, Object?>{}]) {
  var text = L10n.translate(ru);
  args.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
  return text;
}
