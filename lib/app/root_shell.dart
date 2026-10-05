import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/app_providers.dart';
import '../core/theme/kago_theme.dart';
import '../features/connections/connections_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/proxies/proxies_screen.dart';
import '../features/settings/settings_screen.dart';

class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  // Each tab repaints on its own, so an animation on one never repaints others.
  static const _screens = <Widget>[
    RepaintBoundary(child: DashboardScreen()),
    RepaintBoundary(child: ProxiesScreen()),
    RepaintBoundary(child: ConnectionsScreen()),
    RepaintBoundary(child: SettingsScreen()),
  ];
  static const _destinations = <NavigationDestination>[
    NavigationDestination(
        icon: Icon(Icons.space_dashboard_outlined),
        selectedIcon: Icon(Icons.space_dashboard),
        label: 'Главная'),
    NavigationDestination(
        icon: Icon(Icons.hub_outlined),
        selectedIcon: Icon(Icons.hub),
        label: 'Серверы'),
    NavigationDestination(
        icon: Icon(Icons.swap_horiz_rounded),
        selectedIcon: Icon(Icons.swap_horiz_rounded),
        label: 'Трафик'),
    NavigationDestination(
        icon: Icon(Icons.tune_rounded),
        selectedIcon: Icon(Icons.tune_rounded),
        label: 'Настройки'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(subscriptionUsageRefresherProvider);
    final index = ref.watch(rootTabIndexProvider);
    void select(int value) =>
        ref.read(rootTabIndexProvider.notifier).state = value;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return _ExitGuard(child: _buildShell(context, ref, index, select, wide));
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
              backgroundColor: KaGoColors.canvas,
              leading: const Padding(
                  padding: EdgeInsets.only(top: 18, bottom: 34),
                  child: _BrandMark()),
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    selectedIcon: Icon(Icons.space_dashboard),
                    label: Text('Главная')),
                NavigationRailDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: Text('Серверы')),
                NavigationRailDestination(
                    icon: Icon(Icons.swap_horiz_rounded),
                    selectedIcon: Icon(Icons.swap_horiz_rounded),
                    label: Text('Трафик')),
                NavigationRailDestination(
                    icon: Icon(Icons.tune_rounded),
                    selectedIcon: Icon(Icons.tune_rounded),
                    label: Text('Настройки')),
              ],
            ),
          if (wide) const VerticalDivider(width: 1, color: KaGoColors.border),
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
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
            color: KaGoColors.brand, borderRadius: BorderRadius.circular(14)),
        child: const Center(
            child: Text('K',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900))),
      );
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

/// On desktop, closing the window must not leave mihomo running with the Windows
/// system proxy still pointing at it. Stops the core (which restores the proxy)
/// before the app exits, with a hard time limit so closing never hangs.
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
    if (Platform.isAndroid || Platform.isIOS) return;
    _listener = AppLifecycleListener(onExitRequested: () async {
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
  Widget build(BuildContext context) => widget.child;
}
