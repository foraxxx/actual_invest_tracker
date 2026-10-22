import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
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
  final manual = CbrService.manualInflation;
  if (last == null && manual != null) {
    return 'Ключевая ставка — Банк России; инфляция ${manual.toStringAsFixed(2)}% указана вручную';
  }
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

  /// true — «В годовых», false — «С начала периода» (по умолчанию).
  /// Выбор запоминается.
  bool _annualMode = AppearanceService.ui('inflationMode') == 'annual';

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
    } else if (!CbrService.hasInflation) {
      text = 'Инфляцию с сайта Банка России получить не удалось. Можно указать её вручную — '
          'годовую, как её публикуют в новостях, — и сравнение заработает.';
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
        if (!CbrService.hasInflation) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _askInflation(ctx),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Указать инфляцию вручную'),
            ),
          ),
        ],
      ],
    );
  }

  /// Ввод инфляции вручную — запасной путь, если сайт Банка России
  /// недоступен или поменял вёрстку.
  Future<void> _askInflation(BuildContext ctx) async {
    final controller = TextEditingController(text: CbrService.manualInflation?.toStringAsFixed(2) ?? '');
    final value = await showDialog<double?>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Инфляция за год'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Рост цен за последние 12 месяцев, в процентах. Используется, только пока с сайта '
              'Банка России данные получить не удаётся.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(suffixText: '%', hintText: 'например, 6.5'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(dctx, double.tryParse(controller.text.replaceAll(',', '.').trim())),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    // Контроллер не освобождаем сразу: поле ещё видно, пока окно закрывается.
    if (value != null && value > -50 && value < 100) {
      await CbrService.setManualInflation(value);
    }
  }

  List<Widget> _content(BuildContext ctx, RealReturn r) {
    final ahead = r.vsInflation >= 0;
    final points = r.points;
    final touched = _touched != null && _touched! < points.length ? points[_touched!] : null;
    final annualMode = _annualMode;
    final hasAnnualLine = points.any((p) => p.portfolio != null);
    final hasEarly = points.any((p) => p.portfolioEarly != null);
    final lastKey = CbrService.keyRateAt(r.to);
    final lastInfl = CbrService.lastInflation?.inflation;
    final last = r.last;

    Widget legend(Color color, String title, String sub, String value, {bool dashed = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 3,
                child: CustomPaint(painter: _LegendLinePainter(color, dashed)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13)),
                    Text(sub, style: TextStyle(fontSize: 11, color: ctx.dim)),
                  ],
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
              ],
            ],
          ),
        );

    Widget summaryRow(String label, String value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: ctx.dim))),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );

    String signed(double? v) => v == null ? '—' : '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';

    Widget modeChip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: on ? ctx.accent.withOpacity(0.18) : Colors.transparent,
                border: Border.all(color: on ? ctx.accent : ctx.hairline),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? ctx.accent : null),
              ),
            ),
          ),
        );

    void setMode(bool annual) {
      if (annual == _annualMode) return;
      setState(() => _annualMode = annual);
      AppearanceService.setUi('inflationMode', annual ? 'annual' : 'cumulative');
    }

    final dateLabel = touched == null
        ? null
        : r.weekly
            ? (annualMode ? 'Неделя ${_dayMonth(touched.date)}' : 'К ${_dayMonth(touched.date)}')
            : '${_capitalized(_months[touched.date.month - 1])} ${touched.date.year}';

    final unitSuffix = r.annual ? ' годовых' : '';
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
                '${ahead ? 'портфель обогнал инфляцию' : 'портфель отстал от инфляции'}\n'
                '${Fmt.pct(r.portfolioPct, decimals: 2)} против ${Fmt.pct(r.inflationPct, decimals: 2)}'
                '${r.annual ? ' в год' : ' за период'}',
                style: TextStyle(fontSize: 12.5, height: 1.3, color: ctx.dim),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          modeChip('С начала периода', !annualMode, () => setMode(false)),
          modeChip('В годовых', annualMode, () => setMode(true)),
        ],
      ),
      const SizedBox(height: 10),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        radius: AppRadius.sm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              annualMode
                  ? '% годовых, ${r.weekly ? 'по неделям' : 'по месяцам'}'
                  : '% с ${Fmt.date(r.from)}, ${r.weekly ? 'по неделям' : 'по месяцам'}',
              style: TextStyle(fontSize: 11, color: ctx.dim),
            ),
            const SizedBox(height: 6),
            // Подсказка с разглядываемой датой. Место под неё занято всегда,
            // чтобы график не прыгал, когда палец касается его.
            SizedBox(
              height: 36,
              child: touched == null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Проведите пальцем по графику, чтобы увидеть значения',
                          style: TextStyle(fontSize: 11, color: ctx.dim)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(dateLabel!, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 10,
                          children: annualMode
                              ? [
                                  if (touched.portfolio != null)
                                    _tip('Портфель', touched.portfolio, _portfolioColor)
                                  else if (touched.portfolioEarly != null)
                                    _tip('С начала', touched.portfolioEarly, _portfolioColor, signedValue: true),
                                  _tip('Инфляция', touched.inflation, _inflationColor),
                                  _tip('Ставка', touched.keyRate, _keyRateColor, rate: true),
                                ]
                              : [
                                  _tip('Портфель', touched.cumPortfolio, _portfolioColor, signedValue: true),
                                  _tip('Цены', touched.cumInflation, _inflationColor, signedValue: true),
                                  _tip('Вклад', touched.cumDeposit, _keyRateColor, signedValue: true),
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
                        annual: annualMode,
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
                  Text(_axisLabel(points.first.date, r.weekly), style: TextStyle(fontSize: 10.5, color: ctx.dim)),
                  const Spacer(),
                  Text(_axisLabel(points.last.date, r.weekly), style: TextStyle(fontSize: 10.5, color: ctx.dim)),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (annualMode) ...[
        legend(_portfolioColor, 'Портфель', 'за последние 12 месяцев, в пересчёте на год',
            r.portfolio12m == null ? '—' : _pct(r.portfolio12m!)),
        if (hasEarly)
          legend(
              _portfolioColor,
              'Портфель с начала',
              '${hasAnnualLine ? 'до ${_monthGen(points.firstWhere((p) => p.portfolio != null).date)}' : 'пока истории меньше полугода'}: '
                  'заработок с первой сделки, без пересчёта на год',
              '',
              dashed: true),
        legend(_inflationColor, 'Инфляция', 'рост цен за последние 12 месяцев',
            lastInfl == null ? '—' : _pct(lastInfl)),
        legend(_keyRateColor, 'Ключевая ставка', 'на сегодня', lastKey == null ? '—' : _rate(lastKey)),
      ] else ...[
        legend(_portfolioColor, 'Портфель', 'сколько заработал с начала периода', signed(last?.cumPortfolio)),
        legend(_inflationColor, 'Инфляция', 'на сколько подорожали цены', signed(last?.cumInflation)),
        legend(_keyRateColor, 'Вклад под ключевую ставку', 'сколько принёс бы вклад', signed(last?.cumDeposit)),
      ],
      const SizedBox(height: 8),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        radius: AppRadius.sm,
        child: Column(
          children: annualMode
              ? [
                  summaryRow('Портфель ${realReturnPeriodText(_period)}',
                      '${Fmt.pct(r.portfolioPct, decimals: 2)}${r.annual ? unitSuffix : ''}', AppColors.pnl(r.portfolioPct)),
                  if (!r.annual && r.portfolioPerYear != null)
                    summaryRow('То же в пересчёте на год', '≈ ${Fmt.pct(r.portfolioPerYear!, decimals: 2)}',
                        AppColors.pnl(r.portfolioPerYear!)),
                  summaryRow('Инфляция за тот же период',
                      '${Fmt.pct(r.inflationPct, decimals: 2)}${r.annual ? ' в год' : ''}', _inflationColor),
                  if (r.keyRateAvg != null)
                    summaryRow('Ключевая ставка в среднем', _rate(r.keyRateAvg!), _keyRateColor),
                ]
              : [
                  if (lastKey != null) summaryRow('Ключевая ставка сейчас', _rate(lastKey), _keyRateColor),
                  if (r.keyRateAvg != null)
                    summaryRow('В среднем за период', _rate(r.keyRateAvg!), _keyRateColor),
                  if (lastInfl != null)
                    summaryRow('Инфляция за последние 12 месяцев', _pct(lastInfl), _inflationColor),
                ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        annualMode
            ? 'Все линии — в процентах за год, их можно сравнивать напрямую. Зелёная выше оранжевой — '
                'портфель в это время обгонял рост цен. '
                '${hasEarly ? 'Пунктир — заработок с первой сделки, пока истории меньше полугода: его нельзя сравнивать с годовыми линиями. ' : ''}'
                'Доходность портфеля считается без влияния пополнений и выводов.'
            : 'Все линии начинаются с нуля в первый день периода. Зелёная выше оранжевой — портфель обгоняет '
                'рост цен; выше синей — обгоняет вклад под ключевую ставку. Пополнения и выводы заработком не считаются.',
        style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
      ),
    ];
  }

  Widget _tip(String label, double? v, Color color, {bool rate = false, bool signedValue = false}) {
    String text;
    if (v == null) {
      text = '—';
    } else if (rate) {
      text = _rate(v);
    } else if (signedValue) {
      text = '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}%';
    } else {
      text = _pct(v);
    }
    return Text('$label $text', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color));
  }
}

String _capitalized(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const _monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _dayMonth(DateTime d) => '${d.day} ${_monthsGen[d.month - 1]}';

/// «до июля» — название месяца в родительном падеже.
String _monthGen(DateTime d) => _monthsGen[d.month - 1];

String _axisLabel(DateTime d, bool weekly) =>
    weekly ? '${d.day} ${_monthsShort[d.month - 1]}' : '${_monthsShort[d.month - 1]} ${d.year}';

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;

  _LegendLinePainter(this.color, this.dashed);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(size.width, x + 3), y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter old) => old.color != color || old.dashed != dashed;
}

/// Плавная линия через точки без «перелётов» выше и ниже соседних значений
/// (монотонная кубическая интерполяция).
Path _smoothPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) return path;
  if (pts.length == 2) {
    path.lineTo(pts[1].dx, pts[1].dy);
    return path;
  }
  final n = pts.length;
  final dx = List<double>.generate(n - 1, (i) => pts[i + 1].dx - pts[i].dx);
  final slope = List<double>.generate(n - 1, (i) => dx[i] == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx[i]);
  final m = List<double>.filled(n, 0);
  m[0] = slope[0];
  m[n - 1] = slope[n - 2];
  for (int i = 1; i < n - 1; i++) {
    m[i] = slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2;
  }
  for (int i = 0; i < n - 1; i++) {
    if (slope[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / slope[i];
    final b = m[i + 1] / slope[i];
    final h = a * a + b * b;
    if (h > 9) {
      final t = 3 / math.sqrt(h);
      m[i] = t * a * slope[i];
      m[i + 1] = t * b * slope[i];
    }
  }
  for (int i = 0; i < n - 1; i++) {
    final h = dx[i] / 3;
    path.cubicTo(
      pts[i].dx + h,
      pts[i].dy + m[i] * h,
      pts[i + 1].dx - h,
      pts[i + 1].dy - m[i + 1] * h,
      pts[i + 1].dx,
      pts[i + 1].dy,
    );
  }
  return path;
}

/// Линии графика. «С начала периода» — портфель, рост цен и вклад, все
/// плавные. «В годовых» — ставка ступеньками (её меняют скачком), инфляция и
/// портфель плавно, начало истории портфеля — пунктиром.
class _RatesPainter extends CustomPainter {
  final List<ReturnPoint> points;
  final bool annual;
  final int? touched;
  final Color grid;
  final Color label;

  _RatesPainter({
    required this.points,
    required this.annual,
    required this.touched,
    required this.grid,
    required this.label,
  });

  List<(double? Function(ReturnPoint), Color, double, bool, bool)> get _series => annual
      ? [
          ((p) => p.keyRate, _keyRateColor, 2.0, true, false),
          ((p) => p.inflation, _inflationColor, 2.0, false, false),
          ((p) => p.portfolioEarly, _portfolioColor, 2.0, false, true),
          ((p) => p.portfolio, _portfolioColor, 2.6, false, false),
        ]
      : [
          ((p) => p.cumDeposit, _keyRateColor, 2.0, false, false),
          ((p) => p.cumInflation, _inflationColor, 2.0, false, false),
          ((p) => p.cumPortfolio, _portfolioColor, 2.6, false, false),
        ];

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final series = _series;
    final values = <double>[
      for (final s in series)
        for (final p in points)
          if (s.$1(p) != null) s.$1(p)!,
    ];
    if (values.isEmpty) return;
    var lo = math.min(0.0, values.reduce(math.min));
    var hi = math.max(0.0, values.reduce(math.max));
    final pad = math.max(1.0, (hi - lo) * 0.08);
    if (lo < 0) lo -= pad;
    hi += pad;
    final n = points.length;
    double x(int i) => n == 1 ? size.width / 2 : i * size.width / (n - 1);
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    // Сетка: 0% и круглые значения.
    final range = hi - lo;
    final step = range > 30 ? 10.0 : (range > 12 ? 5.0 : (range > 5 ? 2.0 : 1.0));
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (double g = (lo / step).ceil() * step; g <= hi; g += step) {
      final yy = y(g);
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), gridPaint);
      final text = annual || g <= 0 ? '${g.round()}%' : '+${g.round()}%';
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: 9, color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, yy - tp.height - 1));
    }

    for (final s in series) {
      final pick = s.$1;
      final paint = Paint()
        ..color = s.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.$3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      // Непрерывные участки без пропусков рисуются отдельно.
      var run = <Offset>[];
      void flush() {
        if (run.isEmpty) return;
        final Path path;
        if (s.$4) {
          path = Path()..moveTo(run.first.dx, run.first.dy);
          for (int i = 1; i < run.length; i++) {
            path.lineTo(run[i].dx, run[i - 1].dy);
            path.lineTo(run[i].dx, run[i].dy);
          }
        } else {
          path = _smoothPath(run);
        }
        if (s.$5) {
          for (final metric in path.computeMetrics()) {
            for (double d = 0; d < metric.length; d += 8) {
              canvas.drawPath(metric.extractPath(d, math.min(metric.length, d + 4)), paint);
            }
          }
        } else {
          canvas.drawPath(path, paint);
        }
        run = <Offset>[];
      }

      for (int i = 0; i < n; i++) {
        final v = pick(points[i]);
        if (v == null) {
          flush();
          continue;
        }
        run.add(Offset(x(i), y(v)));
      }
      flush();
    }

    final t = touched;
    if (t != null && t < n) {
      final tx = x(t);
      final dash = Paint()
        ..color = label.withOpacity(0.7)
        ..strokeWidth = 1;
      for (double yy = 0; yy < size.height; yy += 5) {
        canvas.drawLine(Offset(tx, yy), Offset(tx, math.min(size.height, yy + 2.5)), dash);
      }
      for (final s in series) {
        final v = s.$1(points[t]);
        if (v != null) canvas.drawCircle(Offset(tx, y(v)), 4, Paint()..color = s.$2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RatesPainter old) =>
      old.points != points || old.touched != touched || old.annual != annual || old.grid != grid;
}
