import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/payout_calendar_service.dart';
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

/// Строки окна. Каждая раскрывается списком бумаг.
enum _Part { price, coupons, dividends, fees, tax }

/// Окно «Из чего прибыль»: по нажатию на плитку «Прибыль» на главной.
/// Открывается на том периоде, что выбран на графике. Нажатие на строку
/// раскрывает под ней все бумаги этой части — за выбранный период.
Future<void> showProfitSheet(BuildContext context, PeriodFilter initial) {
  var period = initial;
  _Part? open;
  // Список проданных бумаг под раскрытой частью — свёрнут, пока не нажали.
  var soldOpen = false;
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
        final parts = <(_Part, double, Color)>[
          (_Part.price, b.priceGrowth, AppColors.info),
          (_Part.coupons, b.coupons, AppColors.positive),
          (_Part.dividends, b.dividends, AppColors.gold),
        ];
        final plusTotal = parts.fold(0.0, (s, p) => s + (p.$2 > 0 ? p.$2 : 0));

        Widget line(_Part part, String label, double value, Color dot, Map<String, double> byTicker,
            {bool showShare = false, bool expense = false}) {
          final share = showShare && value > 0 && plusTotal > 0 ? '${(value / plusTotal * 100).round()}%' : null;
          final shown = expense ? -value : value;
          final text = Fmt.signedMoney(shown);
          final isOpen = open == part;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setSheet(() {
                  open = isOpen ? null : part;
                  soldOpen = false;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? (ctx.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.pnl(shown)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isOpen ? Icons.expand_less_rounded : Icons.chevron_right_rounded,
                        size: 18,
                        color: ctx.dim,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: isOpen
                    ? _tickers(ctx, byTicker, dot,
                        expense: expense,
                        soldOpen: soldOpen,
                        onToggleSold: () => setSheet(() => soldOpen = !soldOpen))
                    : const SizedBox(width: double.infinity),
              ),
            ],
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: 'Из чего прибыль',
                  subtitle: subtitle,
                  trailing: IconButton(
                    icon: const Icon(Icons.info_outline_rounded),
                    tooltip: 'Как считается',
                    onPressed: () => _showHowSheet(ctx),
                  ),
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
                        child: Text(Fmt.pct(change.changePct), style: TextStyle(fontSize: 12.5, color: ctx.dim)),
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
                                // Раскрытая часть ярче, остальные приглушены.
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 150),
                                  opacity: open == null || open == p.$1 ? 1 : 0.3,
                                  child: Container(margin: const EdgeInsets.symmetric(horizontal: 1), color: p.$3),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                line(_Part.price, 'Рост цен', b.priceGrowth, AppColors.info, b.priceByTicker, showShare: true),
                if (b.coupons.abs() > 0.5)
                  line(_Part.coupons, 'Купоны', b.coupons, AppColors.positive, b.couponsByTicker, showShare: true),
                if (b.dividends.abs() > 0.5)
                  line(_Part.dividends, 'Дивиденды', b.dividends, AppColors.gold, b.dividendsByTicker,
                      showShare: true),
                if (b.feesAndAccrued.abs() > 0.5)
                  line(_Part.fees, 'Комиссии и НКД', b.feesAndAccrued, AppColors.negative, b.feesByTicker,
                      expense: true),
                if (b.tax > 0.5)
                  line(_Part.tax, 'Налог с выплат', b.tax, AppColors.negative, b.taxByTicker, expense: true),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Все бумаги части: название, полоска относительно самой крупной и сумма.
Widget _tickers(
  BuildContext ctx,
  Map<String, double> byTicker,
  Color color, {
  required bool expense,
  required bool soldOpen,
  required VoidCallback onToggleSold,
}) {
  final items = byTicker.entries.where((e) => e.value.abs() >= 0.5).toList()
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  if (items.isEmpty) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 2, 8, 10),
      child: Text('За этот период ничего нет', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
    );
  }
  // Сначала то, что лежит в портфеле сейчас; проданное — отдельной
  // плашкой ниже, чтобы не мешало.
  final held = AnalyticsService.currentHoldings().keys.map((t) => t.toUpperCase()).toSet();
  final current = [for (final e in items) if (held.contains(e.key.toUpperCase())) e];
  final sold = [for (final e in items) if (!held.contains(e.key.toUpperCase())) e];
  final maxAbs = items.fold(0.0, (m, e) => math.max(m, e.value.abs()));

  Widget row(MapEntry<String, double> e, {bool dimmed = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                PayoutCalendarService.nameOf(e.key),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: dimmed ? ctx.dim : null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: maxAbs <= 0 ? 0 : e.value.abs() / maxAbs,
                  minHeight: 6,
                  backgroundColor: ctx.hairline,
                  // Бумага, которая в этой части дала минус, — красным.
                  valueColor: AlwaysStoppedAnimation(
                    (!expense && e.value < 0 ? AppColors.negative : color).withOpacity(dimmed ? 0.55 : 1),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: HiddenAmount.forText(
                Fmt.money(e.value),
                fontSize: 12.5,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    Fmt.signedMoney(expense ? -e.value : e.value),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pnl(expense ? -e.value : e.value),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  final soldTotal = sold.fold(0.0, (s, e) => s + e.value);
  final soldText = Fmt.signedMoney(expense ? -soldTotal : soldTotal);
  return Padding(
    padding: const EdgeInsets.fromLTRB(27, 2, 8, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in current) row(e),
        if (sold.isNotEmpty) ...[
          if (current.isNotEmpty) const SizedBox(height: 2),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleSold,
            child: Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 15, color: ctx.dim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Уже нет в портфеле · ${sold.length} ${Fmt.papers(sold.length)}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ctx.dim),
                    ),
                  ),
                  HiddenAmount.forText(
                    soldText,
                    fontSize: 12.5,
                    child: Text(
                      soldText,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pnl(expense ? -soldTotal : soldTotal),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(soldOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: ctx.dim),
                ],
              ),
            ),
          ),
          if (soldOpen)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(children: [for (final e in sold) row(e, dimmed: true)]),
            ),
        ],
      ],
    ),
  );
}

/// Окно «Как считается» — пояснения, чтобы не загромождать окно прибыли.
Future<void> _showHowSheet(BuildContext context) {
  Widget part(String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$title — ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: text),
          ]),
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      );
  return showAppSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Как считается',
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 12),
            part('Рост цен',
                'насколько подорожали или подешевели бумаги за период, вместе с результатом продаж.'),
            part('Купоны и дивиденды', 'полученные выплаты до налога.'),
            part('Комиссии и НКД',
                'брокер записывает их одной суммой. Уплаченный при покупке облигации НКД возвращается '
                    'в ближайшем купоне.'),
            part('Налог с выплат', 'удержанный с купонов и дивидендов, если он был.'),
            Text(
              'Все строки вместе дают прибыль сверху. Нажмите на строку — покажу, какие бумаги её дали.',
              style: TextStyle(fontSize: 12, height: 1.4, color: ctx.dim),
            ),
          ],
        ),
      ),
    ),
  );
}
