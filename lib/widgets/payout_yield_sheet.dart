import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/payout_calendar_service.dart';
import '../services/payout_yield_service.dart';
import 'ticker_avatar.dart';
import 'year_bars.dart';

/// Процент с запятой: «10,9%».
String yieldPct(double v) => '${Fmt.group(v, decimals: 1)}%';

/// Окно «Доходность выплат»: сколько процентов в год вложенные деньги
/// приносят выплатами — в целом, по годам и по каждой бумаге.
Future<void> showPayoutYieldSheet(BuildContext context) =>
    showAppSheet<void>(context: context, builder: (_) => const _PayoutYieldSheet());

class _PayoutYieldSheet extends StatefulWidget {
  const _PayoutYieldSheet();

  @override
  State<_PayoutYieldSheet> createState() => _PayoutYieldSheetState();
}

class _PayoutYieldSheetState extends State<_PayoutYieldSheet> {
  PayoutKind _kind = PayoutKind.all;
  bool _all = false;

  static const _labels = {
    PayoutKind.all: 'Все бумаги',
    PayoutKind.dividends: 'Дивиденды',
    PayoutKind.coupons: 'Купоны',
  };

  void _info() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Как считается'),
        content: const Text(
          'К средней цене — выплаты за последние 12 месяцев (после налога, как пришли на счёт), '
          'делённые на деньги, потраченные на бумаги, которые их принесли.\n\n'
          'К текущей цене — те же выплаты к тому, сколько эти бумаги стоят сейчас.\n\n'
          'За прошлый год — выплаты календарного года к деньгам, вложенным в эти бумаги на его конец.\n\n'
          'Красным «к текущей» отмечены бумаги, которые сейчас выгоднее, чем были у вас при покупке.\n\n'
          'Рост цены сюда не входит — он учтён в общей доходности на главной.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = PayoutYieldService.summary(_kind);
    final years = s.byYear.keys.toList()..sort();
    final now = DateTime.now().year;
    final rows = _all ? s.rows : s.rows.take(6).toList();
    final maxYield = s.rows.isEmpty ? 1.0 : s.rows.first.toCost;
    final hidden = AppearanceService.amountsHidden;
    String money(double v) => hidden ? '••• ₽' : Fmt.money(v);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: 'Доходность выплат',
              subtitle: 'Сколько процентов в год приносят ваши деньги',
              trailing: IconButton(icon: const Icon(Icons.info_outline_rounded), onPressed: _info),
            ),
            const SizedBox(height: 6),
            SegmentedToggle<PayoutKind>(
              values: PayoutKind.values,
              selected: _kind,
              labelOf: (k) => _labels[k]!,
              onChanged: (k) => setState(() {
                _kind = k;
                _all = false;
              }),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('К средней цене, за 12 месяцев', style: TextStyle(fontSize: 12, color: context.dim)),
                  const SizedBox(height: 4),
                  Text(
                    s.toCost == null ? '—' : yieldPct(s.toCost!),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.positive),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.income <= 0
                        ? 'За 12 месяцев выплат не было'
                        : '${money(s.income)} выплат на ${money(s.cost)} вложенных',
                    style: TextStyle(fontSize: 12.5, color: context.dim),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _mini(context, 'К текущей цене', s.toValue == null ? '—' : yieldPct(s.toValue!))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _mini(
                          context,
                          'За ${s.lastYearNumber} год',
                          s.lastYear == null ? '—' : yieldPct(s.lastYear!),
                          color: AppColors.positive,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (years.isNotEmpty) ...[
              _caption(context, 'ВЫПЛАТЫ ПО ГОДАМ, ₽'),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YearBars(
                      color: AppColors.positive,
                      format: (v) => hidden ? '•••' : Fmt.group(v),
                      bars: [
                        for (int i = 0; i < years.length; i++)
                          YearBar(
                            year: years[i],
                            parts: [BarPart(s.byYear[years[i]]!)],
                            top: _growth(years, i, s.byYear, now),
                            topColor: _growthColor(years, i, s.byYear),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Пришло на счёт после налога. $now — по сегодня, поэтому без сравнения',
                      style: TextStyle(fontSize: 11, color: context.dim),
                    ),
                  ],
                ),
              ),
            ],
            _caption(context, 'ПО БУМАГАМ — К СРЕДНЕЙ ЦЕНЕ'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              child: Column(
                children: [
                  if (s.rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text('Выплат за 12 месяцев пока нет', style: TextStyle(color: context.dim)),
                    ),
                  for (final r in rows) _row(context, r, maxYield),
                  if (!_all && s.rows.length > 6)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _all = true),
                        child: Text('Показать все ${s.rows.length} ›'),
                      ),
                    ),
                  if (s.without.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Без выплат за 12 месяцев: ${s.without.take(6).join(', ')}'
                              '${s.without.length > 6 ? ' и ещё ${s.without.length - 6}' : ''} — не входят в расчёт',
                              style: TextStyle(fontSize: 11.5, color: context.dim),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _growth(List<int> years, int i, Map<int, double> by, int now) {
    if (i == 0 || years[i] >= now) return null;
    final prev = by[years[i - 1]] ?? 0;
    if (prev <= 0 || years[i - 1] != years[i] - 1) return null;
    final g = (by[years[i]]! / prev - 1) * 100;
    return '${g >= 0 ? '+' : '−'}${Fmt.group(g.abs(), decimals: 0)}%';
  }

  Color? _growthColor(List<int> years, int i, Map<int, double> by) {
    if (i == 0) return null;
    final prev = by[years[i - 1]] ?? 0;
    return (by[years[i]] ?? 0) >= prev ? AppColors.positive : AppColors.negative;
  }

  Widget _caption(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.dim)),
      );

  Widget _mini(BuildContext context, String label, String value, {Color? color}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
          borderRadius: AppRadius.all(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: context.dim)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  Widget _row(BuildContext context, PayoutYieldRow r, double maxYield) {
    final better = r.toValue > r.toCost + 0.05;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          TickerAvatar(ticker: r.ticker, size: 34, glow: false),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.ticker, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(
                  PayoutCalendarService.nameOf(r.ticker),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.dim),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: maxYield <= 0 ? 0 : (r.toCost / maxYield).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: context.dim.withOpacity(0.15),
                    color: AppColors.positive,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                yieldPct(r.toCost),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.positive),
              ),
              Text(
                'к текущей ${yieldPct(r.toValue)}',
                style: TextStyle(fontSize: 11, color: better ? AppColors.negative : context.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
