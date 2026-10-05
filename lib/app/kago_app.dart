import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/appearance.dart';
import '../core/theme/kago_theme.dart';
import 'root_shell.dart';

class KaGoApp extends ConsumerWidget {
  const KaGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final language = L10n.resolve(appearance.language);
    L10n.use(language);
    return MaterialApp(
      title: 'KaGo VPN',
      debugShowCheckedModeBanner: false,
      theme: KaGoTheme.light(),
      darkTheme: KaGoTheme.dark(pureBlack: appearance.pureBlack),
      themeMode: appearance.mode,
      locale: Locale(language),
      supportedLocales: <Locale>[
        for (final code in L10n.supported) Locale(code),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // A new key rebuilds every screen, so all texts switch language at once.
      home: RootShell(key: ValueKey<String>(language)),
    );
  }
}
