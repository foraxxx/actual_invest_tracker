
import 'package:flutter/material.dart';

import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_forecast_service.dart';
import '../services/value_forecast_engine.dart';
import '../services/value_forecast_service.dart';

/// Окно прогноза стоимости портфеля — когда выплат нет и переключать не на
/// что. Иначе прогноз стоимости открывается в общем окне «Прогноз».
void showValueForecastSheet(BuildContext context) {
  var years = ValueForecastService.defaultHorizon;
  showAppSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                title: 'Прогноз стоимости',
                subtitle: valueForecastSubtitle,
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(height: 14),
              ValueForecastBody(years: years, onYears: (v) => setSheet(() => years = v)),
            ],
          ),
        ),
      ),
    ),
  );
}

const valueForecastSubtitle = 'Три сценария для текущего портфеля';

/// Пояснение к прогнозу стоимости — за значком ⓘ.
List<(String, String)> valueForecastInfo() {
  final m = ValueForecastService.assumptions;
  String p(double? v) => v == null ? '—' : '${(v * 100).round()}%';
  return [
    ('Что считаем', 'только бумаги, которые уже лежат в портфеле. Новые покупки и планы не учитываются.'),
    ('Акции', 'в среднем дорожают на ${Fmt.pct(m.stockMedianGrowthPct).replaceAll('+', '')} в год, '
        'но год на год не приходится — цена может отклоняться примерно на ${(m.stockVolatility * 100).round()}%. '
        'Откуда цифры: ${m.source}.'),
    ('Облигации', 'приносят купоны, а при погашении возвращают номинал. Эти деньги снова вкладываются — '
        'под ${p(m.reinvestYield[ForecastScenario.pessimistic])} в плохом сценарии, '
        '${p(m.reinvestYield[ForecastScenario.realistic])} в среднем и '
        '${p(m.reinvestYield[ForecastScenario.optimistic])} в хорошем.'),
    ('Выплаты', 'дивиденды и купоны после налога сразу докупают ту же бумагу.'),
    ('Сценарии', 'плохой — рынок растёт слабо, средний — как обычно бывало раньше, хороший — лучше обычного. '
        '«Все» показывает три линии сразу.'),
  ];
}

String yearsLabel(int n) => _yearsLabel(n);

String _yearsLabel(int n) {
  if (n % 10 == 1 && n % 100 != 11) return '$n год';
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) return '$n года';
  return '$n лет';
}

String _scenarioLabel(ForecastScenario s) {
  switch (s) {
    case ForecastScenario.pessimistic:
      return 'Плохой';
    case ForecastScenario.realistic:
      return 'Средний';
    case ForecastScenario.optimistic:
      return 'Хороший';
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

/// Содержимое прогноза стоимости: срок, график, сценарии и разбор итога.
/// Срок хранит родитель — он нужен и карточке-итогу в окне «Прогноз».
class ValueForecastBody extends StatefulWidget {
  final int years;
  final ValueChanged<int> onYears;

  const ValueForecastBody({super.key, required this.years, required this.onYears});

  @override
  State<ValueForecastBody> createState() => _ValueForecastBodyState();
}

class _ValueForecastBodyState extends State<ValueForecastBody> {
  int get _years => widget.years;
  ForecastScenario _scenario = ForecastScenario.realistic;

  /// «Все» — три сценария на одном графике.
  bool _all = true;

  @override
  void initState() {
    super.initState();
    ValueForecastService.version.addListener(_refresh);
    PayoutForecastService.version.addListener(_refresh);
    // История индекса уточняет сценарии акций, а график купонов нужен для
    // облигаций. Пока их нет, прогноз строится по тому, что есть, и сам
    // пересчитается, когда данные приедут.
    ValueForecastService.loadMarketHistory();
    // Без условия «кэш пуст»: облигации из планов могли остаться без графика
    // выплат, даже когда для позиций портфеля он уже загружен. Свежие записи
    // refresh пропускает, так что лишнего трафика это не даёт.
    PayoutForecastService.refresh();
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
    final bundle = ValueForecastService.build(_years);
    final results = bundle.results;
    final selected = results[_all ? ForecastScenario.realistic : _scenario]!;
    final b = selected.breakdown;
    final points = selected.points;
    final color = _scenarioColor(_scenario);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('через ${_yearsLabel(_years)} · ${_all ? 'средний сценарий' : '${_scenarioLabel(_scenario).toLowerCase()} сценарий'}',
            style: TextStyle(fontSize: 12.5, color: context.dim)),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            Text('≈ ${Fmt.money(b.end)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            if (b.start > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(Fmt.pct((b.end / b.start - 1) * 100),
                    style: TextStyle(fontSize: 13, color: AppColors.pnl(b.end - b.start))),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Интерактивная линия: палец по графику — сумма на дату.
        if (_all && points.length >= 2) ...[
          MultiLineChart(
            height: 180,
            series: [
              for (final sc in ForecastScenario.values.reversed)
                ChartSeries(
                  label: _scenarioLabel(sc).toLowerCase(),
                  values: [for (final p in results[sc]!.points) p.value],
                  color: _scenarioColor(sc),
                  dashed: sc != ForecastScenario.realistic,
                ),
            ],
            dateOf: (i) => '${Fmt.monthShort(points[i].date.month)} ${points[i].date.year}',
            format: (v) => Fmt.money(v),
            startLabel: 'сейчас',
            endLabel: '${Fmt.monthShort(points.last.date.month)} ${points.last.date.year}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final sc in ForecastScenario.values)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_scenarioLabel(sc), style: TextStyle(fontSize: 11, color: context.dim)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(Fmt.money(results[sc]!.breakdown.end),
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _scenarioColor(sc))),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ] else if (points.length >= 2)
          Sparkline(
            values: [for (final p in points) p.value],
            color: color,
            height: 160,
            tooltipBuilder: (i, v) => '${Fmt.monthShort(points[i].date.month)} ${points[i].date.year}\n${Fmt.money(v)}',
          ),
        if (!_all) const SizedBox(height: 4),
        if (!_all) Row(
          children: [
            Text('сейчас', style: TextStyle(fontSize: 10.5, color: context.dim)),
            const Spacer(),
            if (points.isNotEmpty)
              Text('${Fmt.monthShort(points.last.date.month)} ${points.last.date.year}',
                  style: TextStyle(fontSize: 10.5, color: context.dim)),
          ],
        ),
        const SizedBox(height: 12),
        PillTabs<int>(
          values: ValueForecastService.horizons,
          selected: _years,
          labelOf: _yearsLabel,
          onChanged: widget.onYears,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        SegmentedToggle<ForecastScenario?>(
          values: const [null, ...ForecastScenario.values],
          selected: _all ? null : _scenario,
          labelOf: (v) => v == null ? 'Все' : _scenarioLabel(v),
          onChanged: (v) => setState(() {
            _all = v == null;
            if (v != null) _scenario = v;
          }),
          height: 40,
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            children: [
              _row(context, 'Сейчас', Fmt.money(b.start)),
              if (b.stockGrowth.abs() >= 1) _delta(context, 'Рост акций', b.stockGrowth),
              if ((b.dividends + b.coupons).abs() >= 1) _delta(context, 'Дивиденды и купоны', b.dividends + b.coupons),
              if (b.bondsToPar.abs() >= 1) _delta(context, 'Облигации к номиналу', b.bondsToPar),
              if (b.reinvestment.abs() >= 1) _delta(context, 'Реинвестирование', b.reinvestment),
            ],
          ),
        ),
      ],
    );
  }


  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.dim))),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _delta(BuildContext context, String label, double value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.dim))),
            Text(
              Fmt.signedMoney(value),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color ?? (value >= 0 ? AppColors.positive : AppColors.negative),
              ),
            ),
          ],
        ),
      );

}

