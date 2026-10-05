import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/l10n/l10n.dart';
import 'package:kago_vpn/core/l10n/strings_en.dart';

/// Every `tr('…')` text in lib/ must have an English translation with the
/// same `{placeholders}`, so no Russian leaks into the English interface.
void main() {
  final pattern = RegExp(r"(?<![\w.])tr\(\s*'((?:[^'\\]|\\.)*)'");
  final placeholders = RegExp(r'\{(\w+)\}');

  String unescape(String source) => source
      .replaceAll(r'\n', '\n')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\\', r'\');

  final keys = <String>{
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File &&
          file.path.endsWith('.dart') &&
          !file.path.contains('l10n'))
        for (final match in pattern.allMatches(file.readAsStringSync()))
          unescape(match.group(1)!),
  };

  test('lib uses translatable texts', () {
    expect(keys.length, greaterThan(300));
  });

  test('every text has an English translation', () {
    final missing = keys.where((key) => !stringsEn.containsKey(key)).toList();
    expect(missing, isEmpty);
  });

  test('translations keep the same placeholders', () {
    for (final entry in stringsEn.entries) {
      Set<String> names(String text) =>
          placeholders.allMatches(text).map((m) => m.group(1)!).toSet();
      expect(names(entry.value), names(entry.key), reason: entry.key);
    }
  });

  test('tr switches language and fills placeholders', () {
    addTearDown(() => L10n.use('ru'));
    L10n.use('en');
    expect(tr('Настройки'), 'Settings');
    expect(tr('Здравствуйте, {name}', <String, Object?>{'name': 'So'}),
        'Hello, So');
    L10n.use('ru');
    expect(tr('Настройки'), 'Настройки');
    expect(formatLongDate(DateTime(2099, 11, 15, 12)), '15 ноября 2099 г.');
  });
}
