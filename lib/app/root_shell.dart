import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/desktop/windows_tray.dart';
import '../core/network/android_vpn_events.dart';
import '../core/network/anonymous_mode.dart';
import '../core/network/app_providers.dart';
import '../core/theme/app_widgets.dart';
import '../core/theme/kago_theme.dart';
import '../features/account/account_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/guest/guest_telegram.dart';
import '../features/proxies/proxies_screen.dart';
import '../features/proxies/proxy_mode.dart';
import '../features/settings/settings_screen.dart';
import '../features/update/update_flow.dart';
import '../core/l10n/l10n.dart';

class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  // Each tab repaints on its own, so an animation on one never repaints others.
  static const _screens = <Widget>[
    RepaintBoundary(child: DashboardScreen()),
    RepaintBoundary(child: ProxiesScreen()),
    RepaintBoundary(child: AccountScreen()),
    RepaintBoundary(child: SettingsScreen()),
  ];
  static List<NavigationDestination> get _destinations =>
      <NavigationDestination>[
        NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            selectedIcon: const Icon(Icons.space_dashboard),
            label: tr('Главная')),
        NavigationDestination(
            icon: const Icon(Icons.hub_outlined),
            selectedIcon: const Icon(Icons.hub),
            label: tr('Серверы')),
        NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: tr('Кабинет')),
        NavigationDestination(
            icon: const Icon(Icons.tune_rounded),
            selectedIcon: const Icon(Icons.tune_rounded),
            label: tr('Настройки')),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(subscriptionUsageRefresherProvider);
    ref.watch(subscriptionAutoUpdaterProvider);
    ref.watch(proxyModeSyncProvider);
    if (Platform.isAndroid) {
      // The VPN service outlives the UI and the tile starts it without the
      // UI: which profile runs comes from the service.
      ref.listen(androidVpnEventProvider, (_, next) {
        final event = next.valueOrNull;
        final config = event?['config'];
        if (event?['state'] != 'connected' || config is! String) return;
        ref.read(guestModeActiveProvider.notifier).state =
            config == GuestTelegram.configName;
        ref.read(anonymousActiveProvider.notifier).state =
            config == AnonymousMode.configName;
      });
    }
    final index = ref.watch(rootTabIndexProvider);
    void select(int value) =>
        ref.read(rootTabIndexProvider.notifier).state = value;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return _ExitGuard(
        child: UpdatePrompt(
            child: _buildShell(context, ref, index, select, wide)));
  }

  Widget _buildShell(BuildContext context, WidgetRef ref, int index,
      void Function(int) select, bool wide) {
    return Scaffold(
      body: SafeArea(
        child: Row(children: <Widget>[
          if (wide)
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              backgroundColor: context.kago.surface,
              leading: const Padding(
                  padding: EdgeInsets.only(top: 18, bottom: 34),
                  child: _BrandMark()),
              destinations: <NavigationRailDestination>[
                NavigationRailDestination(
                    icon: const Icon(Icons.space_dashboard_outlined),
                    selectedIcon: const Icon(Icons.space_dashboard),
                    label: Text(tr('Главная'))),
                NavigationRailDestination(
                    icon: const Icon(Icons.hub_outlined),
                    selectedIcon: const Icon(Icons.hub),
                    label: Text(tr('Серверы'))),
                NavigationRailDestination(
                    icon: const Icon(Icons.person_outline_rounded),
                    selectedIcon: const Icon(Icons.person_rounded),
                    label: Text(tr('Кабинет'))),
                NavigationRailDestination(
                    icon: const Icon(Icons.tune_rounded),
                    selectedIcon: const Icon(Icons.tune_rounded),
                    label: Text(tr('Настройки'))),
              ],
            ),
          if (wide) VerticalDivider(width: 1, color: context.kago.border),
          Expanded(
              child: _TabTransition(
                  index: index,
                  child: IndexedStack(index: index, children: _screens))),
        ]),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: select,
              destinations: _destinations,
            ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => const KagoLogo(size: 42);
}

/// Fades and slightly lifts the content whenever the selected tab changes. The
/// tabs stay mounted inside the IndexedStack (their state is kept); only the
/// container animates. Motion is time-based, so it stays smooth at any refresh
/// rate, and it is skipped when the system asks for reduced motion.
class _TabTransition extends StatefulWidget {
  const _TabTransition({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<double> _opacity =
      Tween<double>(begin: .25, end: 1).animate(_curve);
  late final Animation<Offset> _offset =
      Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero)
          .animate(_curve);

  @override
  void didUpdateWidget(_TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child));
}

/// On desktop, quitting must not leave mihomo running with the system proxy
/// still pointing at it: the core is stopped (which restores the proxy) before
/// the app exits, with a hard time limit so quitting never hangs. On Windows
/// the window's close button hides it to the tray ([WindowsTray]) and the
/// app quits from the tray menu. Also tracks whether the app is on screen
/// (appForegroundProvider).
class _ExitGuard extends ConsumerStatefulWidget {
  const _ExitGuard({required this.child});
  final Widget child;

  @override
  ConsumerState<_ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends ConsumerState<_ExitGuard> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    // Window visible (focused or not) counts as foreground; minimized or in
    // the background pauses screen-only polling (appForegroundProvider).
    void onState(AppLifecycleState state) {
      ref.read(appForegroundProvider.notifier).state =
          state == AppLifecycleState.resumed ||
              state == AppLifecycleState.inactive;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      _listener = AppLifecycleListener(onStateChange: onState);
      return;
    }
    // A time zone left by the anonymous profile after a crash.
    unawaited(WindowsTimeZone.restore());
    // Windows: closing the window hides it to the tray; «Выход» in the tray
    // menu (or Windows shutting down) stops the core, then the app ends.
    unawaited(WindowsTray.attach(
        connected: ref.read(vpnActiveProvider),
        onQuit: () async {
          await ref.read(mihomoProcessProvider).stop();
          ref.read(desktopCoreRunningProvider.notifier).state = false;
        }));
    _listener = AppLifecycleListener(
        onStateChange: onState,
        onExitRequested: () async {
          try {
            await ref
                .read(mihomoProcessProvider)
                .stop()
                .timeout(const Duration(seconds: 6));
          } catch (_) {
            // Exit anyway; a stale proxy is repaired at the next start.
          }
          return AppExitResponse.exit;
        });
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      ref.listen(vpnActiveProvider, (_, connected) {
        unawaited(WindowsTray.setConnected(connected));
      });
    }
    return widget.child;
  }
}
