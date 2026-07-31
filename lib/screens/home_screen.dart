import 'package:flutter/material.dart';
import '../design/nav_bar.dart';
import '../services/appearance_service.dart';
import '../services/moex_sync_service.dart';
import '../design/page_tour.dart';
import 'dashboard_screen.dart';
import 'purchases_screen.dart';
import 'incomes_screen.dart';
import 'plans_screen.dart';
import 'market_screen.dart';
import 'settings_screen.dart';

/// Каркас приложения внутри портфеля: шесть вкладок в IndexedStack (чтобы
/// каждая сохраняла своё состояние — фильтры, позицию прокрутки) плюс
/// собственная анимированная навигация внизу.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Переключает на вкладку настроек из любого места внутри каркаса —
  /// нужно, например, экрану «Биржа», когда загрузка котировок выключена.
  static void goToSettings(BuildContext context) {
    context.findAncestorStateOfType<_HomeScreenState>()?._select(_settingsIndex);
  }

  static const _settingsIndex = 5;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _index = AppearanceService.startTab;

  @override
  void initState() {
    super.initState();
    MoexSyncService.instance.setMarketVisible(_index == 1);
  }

  /// Короткое проявление контента при смене вкладки: IndexedStack сам по
  /// себе переключается мгновенно, и без этой анимации переход выглядит
  /// «дёрганым» рядом с плавно едущей навигацией.
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);

  final _screens = const [
    DashboardScreen(),
    MarketScreen(),
    PurchasesScreen(),
    IncomesScreen(),
    PlansScreen(),
    SettingsScreen(),
  ];

  static const _items = [
    NavItem(icon: Icons.donut_large_outlined, activeIcon: Icons.donut_large, label: 'Портфель'),
    NavItem(icon: Icons.show_chart_rounded, activeIcon: Icons.show_chart_rounded, label: 'Биржа'),
    NavItem(icon: Icons.swap_horiz_outlined, activeIcon: Icons.swap_horiz, label: 'Сделки'),
    NavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments, label: 'Выплаты'),
    NavItem(icon: Icons.flag_outlined, activeIcon: Icons.flag, label: 'Планы'),
    NavItem(icon: Icons.tune_outlined, activeIcon: Icons.tune, label: 'Настройки'),
  ];

  @override
  void dispose() {
    MoexSyncService.instance.setMarketVisible(false);
    _fade.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    MoexSyncService.instance.setMarketVisible(i == 1);
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
            // Вкладки строятся все сразу, поэтому каждая должна знать, открыта
            // ли она: обучение запускается по факту захода, а не сборки.
            for (int i = 0; i < _screens.length; i++)
              TickerMode(
                enabled: i == _index,
                child: TourVisibility(visible: i == _index, child: _screens[i]),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AuroraNavBar(
        items: _items,
        index: _index,
        onChanged: _select,
      ),
    );
  }
}

/// Отступ снизу для списков внутри вкладок: под плавающей кнопкой действия
/// контент не должен «прятаться».
const double kListBottomPadding = 96;
