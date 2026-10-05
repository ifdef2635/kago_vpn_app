import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/appearance.dart';
import '../core/theme/kago_theme.dart';
import 'root_shell.dart';

class KaGoApp extends ConsumerWidget {
  const KaGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    return MaterialApp(
      title: 'KaGo VPN',
      debugShowCheckedModeBanner: false,
      theme: KaGoTheme.light(),
      darkTheme: KaGoTheme.dark(pureBlack: appearance.pureBlack),
      themeMode: appearance.mode,
      home: const RootShell(),
    );
  }
}
