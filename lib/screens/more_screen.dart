import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/budget_service.dart';
import '../services/goal_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/portfolio_service.dart';
import '../widgets/goal_widgets.dart';
import '../widgets/payout_forecast_sheet.dart';
import 'annual_report_screen.dart';
import 'budget_screen.dart';
import 'settings_screen.dart';

/// Вкладка «Ещё»: портфели, бюджет, выплаты, цель, итоги года и настройки —
/// всё, что не помещается в четыре основные вкладки, одним списком.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  /// Экраны бюджета и настроек сделаны как вкладки и своей стрелки «назад»
  /// не имеют — добавляем её сверху.
  static void _push(BuildContext context, Widget screen, {bool withBack = true}) => Navigator.push(
        context,
        AppPageRoute(
          builder: (_) => withBack
              ? Scaffold(appBar: AppBar(toolbarHeight: 44), body: screen)
              : screen,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<int>(
          valueListenable: BudgetService.version,
          builder: (context, _, __) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 6, 4, 16),
                child: Text('Ещё', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              ),
              _group(context, [
                _row(
                  context,
                  icon: Icons.folder_open_outlined,
                  title: 'Портфели',
                  value: PortfolioService.active.name,
                  // Список портфелей — стартовый экран приложения.
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ]),
              _group(context, [
                _row(context,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Бюджет',
                    value: _budgetValue(),
                    onTap: () => _push(context, const BudgetScreen())),
                _row(context,
                    icon: Icons.payments_outlined,
                    title: 'Выплаты',
                    value: _payoutValue(),
                    onTap: () => showPayoutForecastSheet(context)),
                _row(context,
                    icon: Icons.flag_outlined,
                    title: 'Цель',
                    value: GoalService.current == null ? 'не задана' : '',
                    onTap: () => GoalService.current == null
                        ? showGoalEditSheet(context)
                        : showGoalDetailsSheet(context)),
                _row(context,
                    icon: Icons.auto_awesome_outlined,
                    title: 'Итоги года',
                    onTap: () => _push(context, const AnnualReportScreen(), withBack: false)),
              ]),
              _group(context, [
                _row(context,
                    icon: Icons.tune_outlined,
                    title: 'Настройки',
                    value: 'данные, оформление, виджет',
                    onTap: () => _push(context, const SettingsScreen())),
              ]),
              const SizedBox(height: 8),
              Center(
                child: Text('Данные хранятся только на телефоне',
                    style: TextStyle(fontSize: 12, color: context.dim)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _budgetValue() {
    if (!BudgetService.started) return '';
    final now = DateTime.now();
    final v = BudgetService.view(now.year, now.month);
    if (!v.filled || v.plannedTotal <= 0.5) return '';
    if (AppearanceService.amountsHidden) return '•••';
    return '${Fmt.group(v.doneTotal)} / ${Fmt.group(v.plannedTotal)}';
  }

  String _payoutValue() {
    if (AppearanceService.amountsHidden) return '';
    final total = PayoutForecastService.portfolioForecast().total;
    return total > 0 ? '≈ ${Fmt.group(total)}' : '';
  }

  Widget _group(BuildContext context, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: context.hairline),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String value = '',
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.all(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: context.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
              ),
              child: Icon(icon, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
            if (value.isNotEmpty)
              Flexible(
                child: Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: context.dim)),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
          ],
        ),
      ),
    );
  }
}
