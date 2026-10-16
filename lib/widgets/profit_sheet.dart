import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/fields.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/profit_breakdown_service.dart';

const _periods = [
  PeriodFilter.month1,
  PeriodFilter.month3,
  PeriodFilter.month6,
  PeriodFilter.year1,
  PeriodFilter.all,
];

String _tabLabel(PeriodFilter f) => switch (f) {
      PeriodFilter.month1 => '1 мес',
      PeriodFilter.month3 => '3 мес',
      PeriodFilter.month6 => '6 мес',
      PeriodFilter.year1 => 'Год',
      PeriodFilter.all => 'Всё',
    };

String _periodText(PeriodFilter f) => switch (f) {
      PeriodFilter.month1 => 'за месяц',
      PeriodFilter.month3 => 'за 3 месяца',
      PeriodFilter.month6 => 'за полгода',
      PeriodFilter.year1 => 'за год',
      PeriodFilter.all => 'за всё время',
    };

/// Окно «Из чего прибыль»: по нажатию на плитку «Прибыль» на главной.
/// Открывается на том периоде, что выбран на графике.
Future<void> showProfitSheet(BuildContext context, PeriodFilter initial) {
  var period = initial;
  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final b = ProfitBreakdownService.forPeriod(period);
        final change = AnalyticsService.portfolioChangeForPeriod(period);
        final now = DateTime.now();
        final from = b.from;
        final subtitle = from == null
            ? _periodText(period)
            : period == PeriodFilter.all
                ? '${_periodText(period)} · с ${Fmt.date(from)}'
                : '${_periodText(period)} · ${Fmt.date(from)} — ${Fmt.date(now)}';

        // Полоса долей — только из того, что дало плюс.
        final parts = <(String, double, Color)>[
          ('Рост цен', b.priceGrowth, AppColors.info),
          ('Купоны', b.coupons, AppColors.positive),
          ('Дивиденды', b.dividends, AppColors.gold),
        ];
        final plusTotal = parts.fold(0.0, (s, p) => s + (p.$2 > 0 ? p.$2 : 0));

        Widget line(String label, double value, Color dot, {bool showShare = false}) {
          final share = showShare && value > 0 && plusTotal > 0 ? '${(value / plusTotal * 100).round()}%' : null;
          final text = Fmt.signedMoney(value);
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 9),
                Text(label, style: const TextStyle(fontSize: 13.5)),
                if (share != null) ...[
                  const SizedBox(width: 6),
                  Text(share, style: TextStyle(fontSize: 12.5, color: ctx.dim)),
                ],
                const Spacer(),
                HiddenAmount.forText(
                  text,
                  fontSize: 13.5,
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.pnl(value)),
                  ),
                ),
              ],
            ),
          );
        }

        Widget plate(String title, double value, String hint) => Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 11.5, color: ctx.dim)),
                    const SizedBox(height: 3),
                    HiddenAmount.forText(
                      Fmt.money(value),
                      fontSize: 15,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Fmt.signedMoney(value),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(hint, style: TextStyle(fontSize: 10.5, color: ctx.dim)),
                  ],
                ),
              ),
            );

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: 'Из чего прибыль',
                  subtitle: subtitle,
                  trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ),
                const SizedBox(height: 12),
                SegmentedToggle<PeriodFilter>(
                  values: _periods,
                  selected: period,
                  labelOf: _tabLabel,
                  onChanged: (f) => setSheet(() => period = f),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: HiddenAmount.forText(
                        Fmt.signedMoney(b.total),
                        fontSize: 26,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            Fmt.signedMoney(b.total),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppColors.pnl(b.total),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (change != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          Fmt.pct(change.changePct),
                          style: TextStyle(fontSize: 12.5, color: ctx.dim),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (plusTotal > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          for (final p in parts)
                            if (p.$2 > 0)
                              Expanded(
                                flex: (p.$2 / plusTotal * 1000).round().clamp(1, 1000),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  color: p.$3,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                line('Рост цен', b.priceGrowth, AppColors.info, showShare: true),
                if (b.coupons.abs() > 0.5) line('Купоны', b.coupons, AppColors.positive, showShare: true),
                if (b.dividends.abs() > 0.5) line('Дивиденды', b.dividends, AppColors.gold, showShare: true),
                if (b.feesAndAccrued.abs() > 0.5) line('Комиссии и НКД', -b.feesAndAccrued, AppColors.negative),
                if (b.tax > 0.5) line('Налог с выплат', -b.tax, AppColors.negative),
                Divider(height: 14, color: ctx.hairline),
                const SizedBox(height: 4),
                Row(
                  children: [
                    plate('Уже в кармане', b.inPocket, 'продажи и выплаты'),
                    const SizedBox(width: 8),
                    plate('На бумаге', b.onPaper, 'рост того, что держите'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Купоны и дивиденды — до налога, налог показан отдельно. «Рост цен» включает результат '
                  'продаж. НКД, уплаченный при покупке облигаций, брокер записывает вместе с комиссией — '
                  'он возвращается в ближайшем купоне.',
                  style: TextStyle(fontSize: 11, height: 1.4, color: ctx.dim),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
