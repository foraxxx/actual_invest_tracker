import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/payout_calendar_service.dart';

/// Календарь выплат: 12 клеток-месяцев, чем больше сумма — тем ярче клетка.
/// Прогноз обведён пунктиром. Нажатие на месяц выделяет его и показывает под
/// сеткой, сколько выплат и от каких бумаг; повторное нажатие снимает выбор.
///
/// Суммы пишутся целиком, с «₽». Если число не помещается в клетку, оно
/// немного уменьшается, но не обрезается. Раскладка — 3 или 2 столбца, по
/// настройке в «Оформлении».
class PayoutCalendar extends StatefulWidget {
  final List<PayoutMonthCell> cells;

  /// Сообщает экрану выбранный месяц (null — выбор снят). Экран «Выплаты»
  /// по нему фильтрует список.
  final ValueChanged<DateTime?>? onSelect;

  /// Выбранный месяц снаружи — например, когда экран сам сбросил фильтр.
  final DateTime? selected;

  const PayoutCalendar({super.key, required this.cells, this.onSelect, this.selected});

  @override
  State<PayoutCalendar> createState() => _PayoutCalendarState();
}

class _PayoutCalendarState extends State<PayoutCalendar> {
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.selected == null ? null : PayoutMonthCell.monthKey(widget.selected!);
  }

  @override
  void didUpdateWidget(covariant PayoutCalendar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _selectedKey = widget.selected == null ? null : PayoutMonthCell.monthKey(widget.selected!);
    }
    // Сменился год — выбранного месяца в сетке больше нет.
    if (_selectedKey != null && !widget.cells.any((c) => c.key == _selectedKey)) {
      _selectedKey = null;
    }
  }

  void _toggle(PayoutMonthCell cell) {
    final next = _selectedKey == cell.key ? null : cell.key;
    setState(() => _selectedKey = next);
    widget.onSelect?.call(next == null ? null : cell.month);
  }

  @override
  Widget build(BuildContext context) {
    final cells = widget.cells;
    final maxTotal = cells.fold(0.0, (m, c) => math.max(m, c.total));
    final twoColumns = AppearanceService.payoutCalendar == PayoutCalendarStyle.twoColumns;
    // Если клетки захватывают два года (прогноз на 12 месяцев), у января и у
    // первой клетки дописываем год, иначе «янв» непонятно какого года.
    final spansYears = cells.isNotEmpty && cells.first.month.year != cells.last.month.year;

    final rows = <Widget>[];
    if (twoColumns) {
      // Два столбца по полгода: слева январь–июнь, справа июль–декабрь —
      // читается сверху вниз, как обычный список месяцев.
      final half = (cells.length / 2).ceil();
      for (int r = 0; r < half; r++) {
        rows.add(_row([
          _cellAt(context, cells, r, maxTotal, spansYears, true),
          _cellAt(context, cells, r + half, maxTotal, spansYears, true),
        ]));
      }
    } else {
      for (int r = 0; r * 3 < cells.length; r++) {
        rows.add(_row([
          for (int c = 0; c < 3; c++) _cellAt(context, cells, r * 3 + c, maxTotal, spansYears, false),
        ]));
      }
    }

    PayoutMonthCell? selected;
    for (final c in cells) {
      if (c.key == _selectedKey) selected = c;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: selected == null ? const SizedBox(width: double.infinity) : _details(context, selected),
        ),
      ],
    );
  }

  Widget _row(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }

  Widget _cellAt(
    BuildContext context,
    List<PayoutMonthCell> cells,
    int index,
    double maxTotal,
    bool spansYears,
    bool wide,
  ) {
    if (index >= cells.length) return const SizedBox.shrink();
    final cell = cells[index];
    return _MonthCell(
      cell: cell,
      ratio: maxTotal <= 0 ? 0 : cell.total / maxTotal,
      wide: wide,
      withYear: spansYears && (index == 0 || cell.month.month == 1),
      selected: cell.key == _selectedKey,
      onTap: () => _toggle(cell),
    );
  }

  Widget _details(BuildContext context, PayoutMonthCell cell) {
    final title = Fmt.monthTitle(cell.key);
    final parts = <String>[
      if (cell.receivedCount > 0) '${cell.receivedCount} ${Fmt.payouts(cell.receivedCount)}',
      if (cell.received > 0 && cell.hasForecast) 'получено ${Fmt.money(cell.received)}',
      if (cell.hasForecast) 'ожидается ≈${Fmt.money(cell.expected)}',
    ];
    final tickers = cell.byTicker.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final names = tickers.map((e) => PayoutCalendarService.label(e.key)).toList();
    final who = names.isEmpty
        ? 'Выплат нет'
        : names.length <= 3
            ? names.join(', ')
            : '${names.take(3).join(', ')} и ещё ${names.length - 3}';
    final total = cell.isEmpty ? '—' : '${cell.hasForecast ? '≈' : ''}${Fmt.money(cell.total)}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  parts.isEmpty ? title : '$title · ${parts.join(' · ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              HiddenAmount.forText(
                total,
                fontSize: 13,
                child: Text(total, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            who,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.dim),
          ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final PayoutMonthCell cell;
  final double ratio;
  final bool wide;
  final bool withYear;
  final bool selected;
  final VoidCallback onTap;

  const _MonthCell({
    required this.cell,
    required this.ratio,
    required this.wide,
    required this.withYear,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final green = AppColors.positive;
    final empty = context.isDark ? Colors.white.withOpacity(0.03) : AppColors.lightSurfaceHigh;
    final bg = cell.isEmpty ? empty : green.withOpacity(0.08 + 0.42 * ratio.clamp(0.0, 1.0));
    final yy = (cell.month.year % 100).toString().padLeft(2, '0');
    final monthName = wide
        ? Fmt.monthTitle(cell.key).split(' ').first.toLowerCase()
        : Fmt.monthShort(cell.month.month);
    // «Прогноз» словом — только когда месяц целиком ожидаемый и есть место.
    final onlyForecast = cell.hasForecast && cell.received <= 0;
    final label = '$monthName${withYear ? ' $yy' : ''}${wide && onlyForecast ? ' · прогноз' : ''}';
    final amount = cell.isEmpty ? '—' : '${cell.hasForecast ? '≈' : ''}${Fmt.money(cell.total)}';

    Widget body = Container(
      padding: EdgeInsets.fromLTRB(8, 6, 8, wide ? 6 : 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: selected ? Border.all(color: green, width: 1.6) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.dim),
          ),
          const SizedBox(height: 2),
          HiddenAmount.forText(
            amount,
            fontSize: wide ? 14 : 13,
            child: AdaptiveSingleLineText(
              amount,
              style: TextStyle(
                fontSize: wide ? 14 : 13,
                fontWeight: FontWeight.w800,
                color: cell.isEmpty ? context.dim : null,
              ),
            ),
          ),
          if (wide) ...[
            const SizedBox(height: 4),
            // Полоска размера: сравнивать длины проще, чем оттенки.
            LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: c.maxWidth * ratio.clamp(0.0, 1.0),
                  height: 3,
                  decoration: BoxDecoration(
                    color: green.withOpacity(cell.hasForecast ? 0.55 : 0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (cell.hasForecast && !selected) {
      body = CustomPaint(
        foregroundPainter: _DashedBorderPainter(color: green.withOpacity(0.75)),
        child: body,
      );
    }

    return Pressable(onTap: onTap, scale: 0.97, child: body);
  }
}

/// Пунктирная рамка прогнозной клетки.
class _DashedBorderPainter extends CustomPainter {
  final Color color;

  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    ).deflate(0.5);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final next = math.min(d + 4, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
