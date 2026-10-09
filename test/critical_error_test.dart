import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/theme/app_widgets.dart';

/// The only message at the bottom of the screen is a critical error, and it
/// leads to support with the technical details.
void main() {
  testWidgets('a critical error offers support and its details',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showCriticalError(
                        context, 'Не удалось подключиться.',
                        details: 'SocketException: errno 1225'),
                    child: const Text('go'))))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось подключиться.'), findsOneWidget);
    // The technical text is not in the message itself.
    expect(find.textContaining('errno'), findsNothing);

    await tester.tap(find.text('Поддержка'));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.data == 'SocketException: errno 1225'),
        findsOneWidget);
    expect(find.text('Написать'), findsOneWidget);
    expect(find.text('Копировать'), findsOneWidget);
  });
}
