import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/cbr_service.dart';
import '../services/online_settings_service.dart';
import '../services/real_return_service.dart';

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

String realReturnPeriodText(PeriodFilter f) => switch (f) {
      PeriodFilter.month1 => 'за месяц',
      PeriodFilter.month3 => 'за 3 месяца',
      PeriodFilter.month6 => 'за полгода',
      PeriodFilter.year1 => 'за год',
      PeriodFilter.all => 'за всё время',
    };

const _months = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

const _monthsShort = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

const _portfolioColor = AppColors.positive;
const _inflationColor = AppColors.warning;
const _keyRateColor = AppColors.info;

/// «+3.4 п.п.» — разница двух процентов.
String formatPoints(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)} п.п.';

String _pct(double v) => '${v.toStringAsFixed(1)}%';

/// Ключевую ставку показываем с сотыми — так её публикует Банк России.
String _rate(double v) => '${v.toStringAsFixed(2)}%';

/// «данные Банка России за сентябрь 2026».
String cbrSourceText() {
  final last = CbrService.lastInflation;
  if (last == null) return 'Инфляция и ключевая ставка — Банк России';
  return 'Инфляция и ключевая ставка — Банк России, данные за ${_months[last.month - 1]} ${last.year}';
}

/// Окно «Против инфляции»: три линии в процентах за год — доходность
/// портфеля, инфляция и ключевая ставка.
Future<void> showRealReturnSheet(BuildContext context, PeriodFilter initial) {
  return showAppSheet(
    context: context,
    builder: (ctx) => _RealReturnSheet(initial: initial),
  );
}

class _RealReturnSheet extends StatefulWidget {
  final PeriodFilter initial;

  const _RealReturnSheet({required this.initial});

  @override
  State<_RealReturnSheet> createState() => _RealReturnSheetState();
}

class _RealReturnSheetState extends State<_RealReturnSheet> {
  late PeriodFilter _period = widget.initial;
  int? _touched;

  // Расчёт проходит по истории счёта месяц за месяцем — не повторяем его на
  // каждое движение пальца по графику.
  RealReturn? _result;
  bool _stale = true;

  @override
  void initState() {
    super.initState();
    CbrService.version.addListener(_refresh);
    CbrService.error.addListener(_refresh);
  }

  @override
  void dispose() {
    CbrService.version.removeListener(_refresh);
    CbrService.error.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _stale = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_stale) {
      _result = RealReturnService.forPeriod(_period);
      _stale = false;
    }
    final r = _result;
    final error = CbrService.error.value;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Против инфляции',
              subtitle: r == null
                  ? realReturnPeriodText(_period)
                  : '${realReturnPeriodText(_period)} · ${Fmt.date(r.from)} — ${Fmt.date(r.to)}',
            ),
            const SizedBox(height: 12),
            SegmentedToggle<PeriodFilter>(
              values: _periods,
              selected: _period,
              labelOf: _tabLabel,
              onChanged: (f) => setState(() {
                _period = f;
                _touched = null;
                _stale = true;
              }),
            ),
            const SizedBox(height: 16),
            if (r == null) _noData(context) else ..._content(context, r),
            const SizedBox(height: 14),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InfoBanner(
                  text: error,
                  icon: Icons.cloud_off_rounded,
                  color: AppColors.warning,
                  onTap: () => CbrService.refreshIfStale(force: true),
                ),
              ),
            Row(
              children: [
                Icon(Icons.account_balance_outlined, size: 14, color: context.dim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(cbrSourceText(), style: TextStyle(fontSize: 11.5, color: context.dim)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _noData(BuildContext ctx) {
    final String text;
    if (!CbrService.hasData && !OnlineSettingsService.enabled) {
      text = 'Чтобы сравнить портфель с инфляцией, включите в настройках загрузку данных из интернета: '
          'инфляцию и ключевую ставку приложение берёт у Банка России.';
    } else if (!CbrService.hasData) {
      text = 'Данные Банка России ещё не загружены. Проверьте интернет и попробуйте ещё раз.';
    } else {
      text = 'За этот период нет своих денег в портфеле — сравнивать не с чем.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: ctx.dim)),
        if (!CbrService.hasData && OnlineSettingsService.enabled) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => CbrService.refreshIfStale(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Загрузить'),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _content(BuildContext ctx, RealReturn r) {
    final ahead = r.vsInflation >= 0;
    final points = r.points;
    final touched = _touched != null && _touched! < points.length ? points[_touched!] : null;
    final hasPortfolioLine = points.any((p) => p.portfolio != null);
    final lastKey = CbrService.keyRateAt(r.to);
    final lastInfl = CbrService.lastInflation?.inflation;

    Widget legend(Color color, String title, String sub, double? value, {bool rate = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 3,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13)),
                    Text(sub, style: TextStyle(fontSize: 11, color: ctx.dim)),
                  ],
                ),
              ),
              Text(
                value == null ? '—' : (rate ? _rate(value) : _pct(value)),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
        );

    Widget summaryRow(String label, String value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: ctx.dim))),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        );

    final unitSuffix = r.annual ? ' годовых' : ' за период';
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatPoints(r.vsInflation),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.pnl(r.vsInflation)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                ahead ? 'портфель обогнал инфляцию' : 'портфель отстал от инфляции',
                style: TextStyle(fontSize: 12.5, color: ctx.dim),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        radius: AppRadius.sm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('% годовых, по месяцам', style: TextStyle(fontSize: 11, color: ctx.dim)),
            const SizedBox(height: 6),
            // Подсказка с разглядываемым месяцем. Место под неё занято всегда,
            // чтобы график не прыгал, когда палец касается его.
            SizedBox(
              height: 36,
              child: touched == null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Проведите пальцем по графику, чтобы увидеть месяц',
                          style: TextStyle(fontSize: 11, color: ctx.dim)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_capitalized(_months[touched.date.month - 1])} ${touched.date.year}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 10,
                          children: [
                            _tip('Портфель', touched.portfolio, _portfolioColor),
                            _tip('Инфляция', touched.inflation, _inflationColor),
                            _tip('Ставка', touched.keyRate, _keyRateColor, rate: true),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (ctx, c) {
                void pick(Offset p) {
                  if (points.length < 2) return;
                  final i = (p.dx / c.maxWidth * (points.length - 1)).round().clamp(0, points.length - 1);
                  if (i != _touched) setState(() => _touched = i);
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => pick(d.localPosition),
                  onHorizontalDragStart: (d) => pick(d.localPosition),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition),
                  child: SizedBox(
                    height: 180,
                    width: c.maxWidth,
                    child: CustomPaint(
                      painter: _RatesPainter(
                        points: points,
                        touched: _touched,
                        grid: ctx.hairline,
                        label: ctx.dim,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            if (points.isNotEmpty)
              Row(
                children: [
                  Text(_monthLabel(points.first.date), style: TextStyle(fontSize: 10.5, color: ctx.dim)),
                  const Spacer(),
                  Text(_monthLabel(points.last.date), style: TextStyle(fontSize: 10.5, color: ctx.dim)),
                ],
              ),
            if (!hasPortfolioLine) ...[
              const SizedBox(height: 6),
              Text(
                'Линия портфеля появится, когда у счёта будет хотя бы полгода истории: '
                'её значение — доходность за последние 12 месяцев в пересчёте на год.',
                style: TextStyle(fontSize: 11, height: 1.35, color: ctx.dim),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      legend(_portfolioColor, 'Портфель', 'доходность за последние 12 месяцев', r.portfolio12m),
      legend(_inflationColor, 'Инфляция', 'рост цен за последние 12 месяцев', lastInfl),
      legend(_keyRateColor, 'Ключевая ставка', 'на сегодня', lastKey, rate: true),
      const SizedBox(height: 8),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        radius: AppRadius.sm,
        child: Column(
          children: [
            summaryRow('Портфель ${realReturnPeriodText(_period)}', '${Fmt.pct(r.portfolioPct)}$unitSuffix',
                AppColors.pnl(r.portfolioPct)),
            summaryRow('Инфляция за тот же период', '${Fmt.pct(r.inflationPct)}${r.annual ? ' в год' : ''}',
                _inflationColor),
            if (r.keyRateAvg != null) summaryRow('Ключевая ставка в среднем', _rate(r.keyRateAvg!), _keyRateColor),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Все три линии — в процентах за год, поэтому их можно сравнивать напрямую. '
        'Зелёная выше оранжевой — портфель в это время обгонял рост цен. '
        'Доходность портфеля считается без влияния пополнений и выводов.',
        style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
      ),
    ];
  }

  Widget _tip(String label, double? v, Color color, {bool rate = false}) => Text(
        '$label ${v == null ? '—' : (rate ? _rate(v) : _pct(v))}',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      );
}

String _capitalized(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _monthLabel(DateTime d) => '${_monthsShort[d.month - 1]} ${d.year}';

/// Три линии: ставка ступеньками, инфляция и доходность портфеля.
class _RatesPainter extends CustomPainter {
  final List<ReturnPoint> points;
  final int? touched;
  final Color grid;
  final Color label;

  _RatesPainter({required this.points, required this.touched, required this.grid, required this.label});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final values = <double>[
      for (final p in points) ...[
        if (p.portfolio != null) p.portfolio!,
        if (p.inflation != null) p.inflation!,
        if (p.keyRate != null) p.keyRate!,
      ],
    ];
    if (values.isEmpty) return;
    var lo = math.min(0.0, values.reduce(math.min));
    var hi = values.reduce(math.max);
    final pad = math.max(1.0, (hi - lo) * 0.08);
    lo -= lo < 0 ? pad : 0;
    hi += pad;
    final n = points.length;
    double x(int i) => n == 1 ? size.width / 2 : i * size.width / (n - 1);
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    // Сетка: 0% и круглые значения через 5 или 10 пунктов.
    final step = hi - lo > 30 ? 10.0 : 5.0;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (double g = (lo / step).ceil() * step; g <= hi; g += step) {
      final yy = y(g);
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${g.round()}%', style: TextStyle(fontSize: 9, color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, yy - tp.height - 1));
    }

    void line(double? Function(ReturnPoint) pick, Color color, double width, {bool stepped = false}) {
      final path = Path();
      bool open = false;
      double? prevY;
      for (int i = 0; i < n; i++) {
        final v = pick(points[i]);
        if (v == null) {
          open = false;
          continue;
        }
        final px = x(i);
        final py = y(v);
        if (!open) {
          path.moveTo(px, py);
          open = true;
        } else if (stepped && prevY != null) {
          path.lineTo(px, prevY);
          path.lineTo(px, py);
        } else {
          path.lineTo(px, py);
        }
        prevY = py;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    line((p) => p.keyRate, _keyRateColor, 2, stepped: true);
    line((p) => p.inflation, _inflationColor, 2);
    line((p) => p.portfolio, _portfolioColor, 2.6);

    final t = touched;
    if (t != null && t < n) {
      final tx = x(t);
      final dash = Paint()
        ..color = label.withOpacity(0.7)
        ..strokeWidth = 1;
      for (double yy = 0; yy < size.height; yy += 5) {
        canvas.drawLine(Offset(tx, yy), Offset(tx, math.min(size.height, yy + 2.5)), dash);
      }
      for (final e in [
        (points[t].keyRate, _keyRateColor),
        (points[t].inflation, _inflationColor),
        (points[t].portfolio, _portfolioColor),
      ]) {
        final v = e.$1;
        if (v != null) canvas.drawCircle(Offset(tx, y(v)), 4, Paint()..color = e.$2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RatesPainter old) =>
      old.points != points || old.touched != touched || old.grid != grid;
}
