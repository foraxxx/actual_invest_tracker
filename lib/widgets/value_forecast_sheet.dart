import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_forecast_service.dart';
import '../services/value_forecast_engine.dart';
import '../services/value_forecast_service.dart';

/// Окно прогноза стоимости портфеля.
void showValueForecastSheet(BuildContext context) {
  showAppSheet(context: context, builder: (_) => const _ValueForecastSheet());
}

String _yearsLabel(int n) {
  if (n % 10 == 1 && n % 100 != 11) return '$n год';
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) return '$n года';
  return '$n лет';
}

String _scenarioLabel(ForecastScenario s) {
  switch (s) {
    case ForecastScenario.pessimistic:
      return 'Пессимист.';
    case ForecastScenario.realistic:
      return 'Реалист.';
    case ForecastScenario.optimistic:
      return 'Оптимист.';
  }
}

Color _scenarioColor(ForecastScenario s) {
  switch (s) {
    case ForecastScenario.pessimistic:
      return AppColors.negative;
    case ForecastScenario.realistic:
      return AppColors.info;
    case ForecastScenario.optimistic:
      return AppColors.positive;
  }
}

class _ValueForecastSheet extends StatefulWidget {
  const _ValueForecastSheet();

  @override
  State<_ValueForecastSheet> createState() => _ValueForecastSheetState();
}

class _ValueForecastSheetState extends State<_ValueForecastSheet> {
  int _years = ValueForecastService.defaultHorizon;
  ForecastScenario _scenario = ForecastScenario.realistic;

  @override
  void initState() {
    super.initState();
    ValueForecastService.version.addListener(_refresh);
    PayoutForecastService.version.addListener(_refresh);
    // История индекса уточняет сценарии акций, а график купонов нужен для
    // облигаций. Пока их нет, прогноз строится по тому, что есть, и сам
    // пересчитается, когда данные приедут.
    ValueForecastService.loadMarketHistory();
    if (!PayoutForecastService.hasData) PayoutForecastService.refresh();
  }

  @override
  void dispose() {
    ValueForecastService.version.removeListener(_refresh);
    PayoutForecastService.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final results = ValueForecastService.compute(_years);
    final maturities = ValueForecastService.maturities(_years);
    final selected = results[_scenario]!;
    final b = selected.breakdown;
    final market = ValueForecastService.assumptions;
    final endDate = selected.points.last.date;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: 'Прогноз стоимости',
              subtitle: 'Три сценария для текущего портфеля',
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 14),
            PillTabs<int>(
              values: ValueForecastService.horizons,
              selected: _years,
              labelOf: _yearsLabel,
              onChanged: (v) => setState(() => _years = v),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 180,
                    child: CustomPaint(
                      painter: _ForecastChartPainter(
                        series: {for (final e in results.entries) e.key: e.value.points},
                        selected: _scenario,
                        maturities: maturities,
                        grid: context.hairline,
                        dotColor: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('сейчас', style: TextStyle(fontSize: 10.5, color: context.dim)),
                      const Spacer(),
                      Text(
                        '${Fmt.monthShort(endDate.month)} ${endDate.year}',
                        style: TextStyle(fontSize: 10.5, color: context.dim),
                      ),
                    ],
                  ),
                  if (maturities.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // Пунктир — граница, после которой облигация больше не
                    // считается по своему графику, а деньги от неё идут под
                    // допущение. Правее неё прогноз заметно менее точен.
                    Text(
                      'Пунктир — погашение облигаций. Дальше деньги от них '
                      'вкладываются под допущенную доходность.',
                      style: TextStyle(fontSize: 10.5, color: context.dim, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SegmentedToggle<ForecastScenario>(
              values: ForecastScenario.values,
              selected: _scenario,
              labelOf: _scenarioLabel,
              colorOf: _scenarioColor,
              onChanged: (v) => setState(() => _scenario = v),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  _row(context, 'Сейчас', Fmt.money(b.start)),
                  if (b.coupons.abs() >= 1) _delta(context, 'Купоны', b.coupons),
                  if (b.bondsToPar.abs() >= 1) _delta(context, 'Облигации к номиналу', b.bondsToPar),
                  if (b.stockGrowth.abs() >= 1) _delta(context, 'Рост акций', b.stockGrowth),
                  if (b.dividends.abs() >= 1) _delta(context, 'Дивиденды', b.dividends),
                  if (b.reinvestment.abs() >= 1) _delta(context, 'Эффект реинвестирования', b.reinvestment),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: context.hairline),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Через ${_yearsLabel(_years)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '≈${Fmt.money(b.end)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _scenarioColor(_scenario),
                            ),
                          ),
                          if (b.start > 0)
                            Text(
                              Fmt.pct((b.end / b.start - 1) * 100),
                              style: TextStyle(fontSize: 11, color: context.dim),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InfoBanner(
              icon: Icons.tune_rounded,
              color: AppColors.info,
              text: 'Акции: медианный рост ${Fmt.pct(market.stockMedianGrowthPct)} в год, '
                  'разброс ${(market.stockVolatility * 100).round()}% — ${market.source}. '
                  'Коридор между крайними сценариями — это 80% вероятных исходов по этой модели. '
                  'Деньги после погашения облигаций: '
                  '${_pct(market.reinvestYield[ForecastScenario.pessimistic])} / '
                  '${_pct(market.reinvestYield[ForecastScenario.realistic])} / '
                  '${_pct(market.reinvestYield[ForecastScenario.optimistic])} годовых. '
                  'Купоны и дивиденды вкладываются в ту же бумагу, суммы до налогов.',
            ),
            const SizedBox(height: 10),
            const InfoBanner(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              text: 'Это расчёт по допущениям, а не предсказание. Облигации '
                  'считаются почти точно по графику выплат, акции — по поведению '
                  'индекса в прошлом, которое не обязано повториться.',
            ),
          ],
        ),
      ),
    );
  }

  static String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.dim))),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _delta(BuildContext context, String label, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.dim))),
            Text(
              Fmt.signedMoney(value),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: value >= 0 ? AppColors.positive : AppColors.negative,
              ),
            ),
          ],
        ),
      );
}

class _ForecastChartPainter extends CustomPainter {
  final Map<ForecastScenario, List<ForecastPoint>> series;
  final ForecastScenario selected;
  final List<DateTime> maturities;
  final Color grid;
  final Color dotColor;

  _ForecastChartPainter({
    required this.series,
    required this.selected,
    required this.maturities,
    required this.grid,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.values.expand((s) => s).toList();
    if (all.length < 2) return;

    var minV = all.map((p) => p.value).reduce(math.min);
    var maxV = all.map((p) => p.value).reduce(math.max);
    final pad = (maxV - minV).abs() * 0.06 + 1;
    minV -= pad;
    maxV += pad;

    final first = all.map((p) => p.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = all.map((p) => p.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final span = last.difference(first).inDays.toDouble();
    if (span <= 0) return;

    double x(DateTime d) => d.difference(first).inDays / span * size.width;
    double y(double v) => size.height - (v - minV) / (maxV - minV) * size.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);

    // Пунктир на датах погашения облигаций.
    final dash = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final m in maturities) {
      final mx = x(m);
      for (double yy = 0; yy < size.height; yy += 7) {
        canvas.drawLine(Offset(mx, yy), Offset(mx, math.min(yy + 3.5, size.height)), dash);
      }
    }

    // Невыбранные сценарии — приглушённо, выбранный — поверх и толще.
    final order = [
      ...ForecastScenario.values.where((s) => s != selected),
      selected,
    ];
    for (final s in order) {
      final points = series[s];
      if (points == null || points.length < 2) continue;
      final path = Path()..moveTo(x(points.first.date), y(points.first.value));
      for (final p in points.skip(1)) {
        path.lineTo(x(p.date), y(p.value));
      }
      final isSel = s == selected;
      canvas.drawPath(
        path,
        Paint()
          ..color = _scenarioColor(s).withOpacity(isSel ? 1 : 0.35)
          ..strokeWidth = isSel ? 2.6 : 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final start = series[selected]?.first;
    if (start != null) {
      canvas.drawCircle(Offset(x(start.date), y(start.value)), 3.5, Paint()..color = dotColor);
    }
  }

  @override
  bool shouldRepaint(covariant _ForecastChartPainter old) =>
      old.selected != selected || old.series != series || old.maturities != maturities || old.grid != grid;
}
