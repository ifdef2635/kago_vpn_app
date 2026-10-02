import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/app_providers.dart';
import '../core/theme/kago_theme.dart';
import 'root_shell.dart';

class KaGoApp extends ConsumerWidget {
  const KaGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'KaGo VPN',
        debugShowCheckedModeBanner: false,
        theme: KaGoTheme.dark(pureBlack: ref.watch(pureBlackProvider)),
        home: const RootShell(),
      );
}
