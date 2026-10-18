import 'package:flutter/material.dart';

import '../design/nav_bar.dart';
import '../design/page_tour.dart';
import 'budget_screen.dart';
import 'portfolios_screen.dart';
import 'settings_screen.dart';

/// Стартовый экран: портфели, бюджет и настройки. Бюджет и настройки общие
/// для всех портфелей, поэтому живут здесь, а не внутри портфеля.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  static final _key = GlobalKey<_RootScreenState>();

  static Widget create() => RootScreen(key: _key);

  /// Открыть настройки из любого места: закрывает открытые поверх экраны и
  /// переключает на вкладку «Настройки».
  static void goToSettings(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _key.currentState?._select(2);
  }

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with SingleTickerProviderStateMixin {
  int _index = 0;

  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);

  final _screens = const [
    PortfoliosScreen(),
    BudgetScreen(),
    SettingsScreen(),
  ];

  static const _items = [
    NavItem(icon: Icons.folder_open_outlined, activeIcon: Icons.folder_rounded, label: 'Портфели'),
    NavItem(icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet, label: 'Бюджет'),
    NavItem(icon: Icons.tune_outlined, activeIcon: Icons.tune, label: 'Настройки'),
  ];

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _fade.forward(from: 0.35);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
        child: IndexedStack(
          index: _index,
          children: [
            for (int i = 0; i < _screens.length; i++)
              TickerMode(
                enabled: i == _index,
                child: TourVisibility(visible: i == _index, child: _screens[i]),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AuroraNavBar(items: _items, index: _index, onChanged: _select),
    );
  }
}
