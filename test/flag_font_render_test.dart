import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled flag font really draws a colour flag for regional-indicator
/// pairs (Windows has none of its own). The font is used only on Windows; the
/// macOS test engine does not draw it through a fallback (checked on Windows
/// and Linux).
void main() {
  test('flag font draws the German flag in colour', skip: Platform.isMacOS,
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes =
        File('assets/fonts/TwemojiCountryFlags.ttf').readAsBytesSync();
    await (FontLoader('KagoFlags')
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
        .load();
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 40))
      ..pushStyle(ui.TextStyle(
          fontFamily: 'NoSuchFont', fontFamilyFallback: const ['KagoFlags']))
      ..addText('\u{1F1E9}\u{1F1EA}');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 200));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawParagraph(paragraph, Offset.zero);
    final image = await recorder.endRecording().toImage(80, 60);
    final data = (await image.toByteData())!;
    var red = 0, yellow = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i), g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2), a = data.getUint8(i + 3);
      if (a < 200) continue;
      if (r > 180 && g < 80 && b < 80) red++;
      if (r > 200 && g > 160 && b < 80) yellow++;
    }
    expect(red, greaterThan(20));
    expect(yellow, greaterThan(20));
  });
}
