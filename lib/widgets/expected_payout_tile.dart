import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/income.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
import '../services/dividend_history_service.dart';
import '../services/dividend_tax_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/storage_service.dart';
import 'income_sheet.dart';

/// Ближайшая выплата по бумаге в карточке.
///
/// До даты — «Ожидается · выплата»: дата слева, сколько на одну бумагу и
/// справа одной строкой, сколько придёт на счёт. После даты (дивиденд — после
/// отсечки, купон — после даты купона), пока выплата не записана, блок
/// спрашивает «Выплата пришла?»: одна кнопка записывает ожидаемую сумму,
/// вторая открывает форму, где сумму и налог можно поправить.
class ExpectedPayoutTile extends StatelessWidget {
  final String ticker;
  final String name;
  final ExpectedPayout payout;

  /// Дата прошла — ждём подтверждения.
  final bool confirm;
  final VoidCallback onChanged;

  const ExpectedPayoutTile({
    super.key,
    required this.ticker,
    required this.name,
    required this.payout,
    required this.confirm,
    required this.onChanged,
  });

  /// Что показать для акции: ждущая подтверждения выплата или ближайшая
  /// объявленная. null — показывать нечего.
  static (ExpectedPayout, bool)? forStock(String ticker) {
    final h = DividendHistoryService.of(ticker);
    if (h == null) return null;
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    // Отсечка прошла не больше 45 дней назад, а выплата ещё не записана.
    DividendRecord? passed;
    for (final r in h.records) {
      if (r.forecast || !r.date.isBefore(day) || day.difference(r.date).inDays > 45) continue;
      if (passed == null || r.date.isAfter(passed.date)) passed = r;
    }
    if (passed != null && !_recorded(ticker, passed.date, IncomeType.dividend)) {
      final units = DividendTaxService.sharesAtCutoff(ticker, passed.date);
      if (units > 0) {
        return (ExpectedPayout(perUnit: passed.amount, units: units, date: passed.date, isBond: false), true);
      }
    }
    final next = h.nextAnnounced;
    if (next == null) return null;
    final units = AnalyticsService.currentHoldings()[ticker]?.qty ?? 0;
    return (ExpectedPayout(perUnit: next.amount, units: units, date: next.date, isBond: false), false);
  }

  /// То же для облигации — по графику купонов с биржи.
  static (ExpectedPayout, bool)? forBond(String ticker) {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final coupons = PayoutForecastService.payoutsFor(ticker)
        .where((p) => p.kind == 'Купон' && p.amount > 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    // Купон прошёл не больше 30 дней назад и не записан.
    for (final c in coupons.reversed) {
      if (!c.date.isBefore(day)) continue;
      if (day.difference(c.date).inDays > 30) break;
      if (_recorded(ticker, c.date, IncomeType.coupon)) break;
      final atDay = DateTime(c.date.year, c.date.month, c.date.day, 23, 59, 59);
      final units = AnalyticsService.holdingsAt(date: atDay)[ticker]?.qty ?? 0;
      if (units > 0) {
        return (ExpectedPayout(perUnit: c.amount, units: units, date: c.date, isBond: true), true);
      }
      break;
    }
    for (final c in coupons) {
      if (c.date.isBefore(day)) continue;
      final units = AnalyticsService.currentHoldings()[ticker]?.qty ?? 0;
      return (ExpectedPayout(perUnit: c.amount, units: units, date: c.date, isBond: true), false);
    }
    return null;
  }

  /// Есть ли уже записанная выплата этого вида с даты [from] (за день до —
  /// на случай записи «задним числом»).
  static bool _recorded(String ticker, DateTime from, IncomeType type) {
    final since = from.subtract(const Duration(days: 1));
    return StorageService.incomes.any((i) =>
        i.type == type && i.ticker.toUpperCase() == ticker.toUpperCase() && !i.date.isBefore(since));
  }

  @override
  Widget build(BuildContext context) {
    final hidden = AppearanceService.amountsHidden;
    final p = payout;
    final net = p.net(defaultTaxRate(p.isBond));
    final color = confirm ? AppColors.warning : AppColors.info;
    final month = Fmt.dateLong(p.date).split(' ')[1];
    final unit = p.isBond ? 'облигацию' : 'акцию';
    final amountText = hidden ? '••• ₽' : '≈ ${Fmt.money(net)}';

    final dateBox = Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text('${p.date.day}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.05)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(month, style: TextStyle(fontSize: 10, color: context.dim))),
        ],
      ),
    );

    // Слева дата, справа подпись и сумма на бумагу — каждая своей строкой
    // во всю ширину, поэтому ничего не обрезается. «Получите» — отдельной
    // строкой внизу: даже сумма в миллионы помещается одинаково.
    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        dateBox,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                confirm
                    ? (p.isBond ? 'Купон выплачен · проверьте' : 'Отсечка прошла · ждём на счёт')
                    : (p.date.year == DateTime.now().year
                        ? 'Ожидается · выплата'
                        : 'Ожидается · выплата в ${p.date.year} году'),
                style: TextStyle(fontSize: 12, color: confirm ? AppColors.warning : context.dim),
              ),
              const SizedBox(height: 2),
              Text(
                confirm ? 'Выплата пришла?' : '${plainNumber(p.perUnit)} ₽ на $unit',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
    final total = p.units <= 0
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    confirm
                        ? 'Ожидалось · ${Fmt.qty(p.units)} шт'
                        : 'Получите · ${Fmt.qty(p.units)} шт${p.isBond ? '' : ', после налога'}',
                    style: TextStyle(fontSize: 12.5, color: context.dim),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  amountText,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: confirm ? null : AppColors.positive,
                  ),
                ),
              ],
            ),
          );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
        borderRadius: AppRadius.all(AppRadius.sm),
        border: confirm ? Border.all(color: AppColors.warning.withOpacity(0.35)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (total != null) total,
          if (confirm) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'Пришло',
                    onPressed: () async {
                      await confirmExpectedPayout(
                        ticker: ticker,
                        name: name,
                        expected: p,
                        // Дивиденд приходит в среднем через две недели после
                        // отсечки, купон — в день купона.
                        paidDate: p.isBond ? p.date : p.date.add(const Duration(days: 14)),
                      );
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GradientButton(
                    label: 'Другая сумма',
                    secondary: true,
                    onPressed: () async {
                      final paid = p.isBond ? p.date : p.date.add(const Duration(days: 14));
                      await showAddIncomeSheet(
                        context,
                        ticker: ticker,
                        name: name,
                        isBond: p.isBond,
                        initialDate: paid,
                        initialAmount: (net * 100).round() / 100,
                        title: 'Выплата пришла',
                      );
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
