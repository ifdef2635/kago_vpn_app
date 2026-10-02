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

  static const _screens = <Widget>[
    DashboardScreen(),
    ProxiesScreen(),
    ConnectionsScreen(),
    SettingsScreen(),
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
    final index = ref.watch(rootTabIndexProvider);
    void select(int value) =>
        ref.read(rootTabIndexProvider.notifier).state = value;
    final wide = MediaQuery.sizeOf(context).width >= 760;
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
          Expanded(child: IndexedStack(index: index, children: _screens)),
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
            color: KaGoColors.accent.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(14)),
        child: const Center(
            child: Text('K',
                style: TextStyle(
                    color: KaGoColors.accent,
                    fontSize: 25,
                    fontWeight: FontWeight.w900))),
      );
}
