import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../screens/ticker_detail_screen.dart';
import '../services/appearance_service.dart';

/// Строка в списке под календарём: одна выплата или одна сделка.
class CalendarLine {
  /// Дата, если известна. Для ожидаемых выплат без объявленной даты — null.
  final DateTime? date;
  final String title;
  final String amount;

  /// Серым — ещё не случилось (ожидаемая выплата).
  final bool muted;

  /// Цвет суммы, например красный у продажи.
  final Color? amountColor;

  /// Бумага: нажатие на строку открывает её карточку.
  final String? ticker;

  const CalendarLine({
    required this.title,
    required this.amount,
    this.date,
    this.muted = false,
    this.amountColor,
    this.ticker,
  });
}

/// Один месяц календаря.
class CalendarMonth {
  final DateTime month;

  /// Число, по которому считается яркость клетки. Знак выбирает цвет:
  /// положительное — основной, отрицательное — оранжевый.
  final double value;

  /// Главная надпись клетки — сумма целиком, например «≈18 427 ₽».
  final String main;

  /// Мелкие строки под суммой, например «куплено 84 200». Цвет — по желанию.
  final List<(String, Color?)> captions;

  /// Клетка-прогноз: обведена пунктиром.
  final bool forecast;

  /// Месяц целиком ожидаемый — в широкой раскладке подписывается «прогноз».
  final bool onlyForecast;

  /// Что написать в заголовке списка, например «4 выплаты».
  final String summary;
  final List<CalendarLine> lines;

  const CalendarMonth({
    required this.month,
    required this.value,
    required this.main,
    this.captions = const [],
    this.forecast = false,
    this.onlyForecast = false,
    this.summary = '',
    this.lines = const [],
  });

  bool get isEmpty => value.abs() < 0.005 && lines.isEmpty;
  String get key => '${month.year}-${month.month.toString().padLeft(2, '0')}';
}

/// Календарь из 12 месяцев: чем больше сумма, тем ярче клетка.
///
/// Общий для выплат (главная, прогноз, итоги года) и для сделок (итоги
/// года). Нажатие на месяц выделяет его и показывает под сеткой каждую
/// выплату или сделку отдельной строкой; повторное нажатие снимает выбор.
///
/// Ничего не обрезается: ни названия месяцев, ни суммы. Если текст не
/// помещается в клетку, он немного уменьшается. Раскладка — 3 или 2 столбца,
/// по настройке в «Оформлении».
class MonthCalendar extends StatefulWidget {
  final List<CalendarMonth> months;

  /// Основной цвет клеток.
  final Color color;

  const MonthCalendar({super.key, required this.months, this.color = AppColors.positive});

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  String? _selectedKey;

  @override
  void didUpdateWidget(covariant MonthCalendar old) {
    super.didUpdateWidget(old);
    // Сменился год — выбранного месяца в сетке больше нет.
    if (_selectedKey != null && !widget.months.any((c) => c.key == _selectedKey)) {
      _selectedKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.months;
    final maxValue = months.fold(0.0, (m, c) => math.max(m, c.value.abs()));
    final twoColumns = AppearanceService.payoutCalendar == PayoutCalendarStyle.twoColumns;
    // Месяцы из двух разных лет (прогноз на 12 месяцев): у первой клетки и у
    // января дописываем год, иначе «январь» непонятно какого года.
    final spansYears = months.isNotEmpty && months.first.month.year != months.last.month.year;
    // Одинаковое число мелких строк во всех клетках — иначе клетки одного
    // ряда получились бы разной высоты.
    final captionLines = months.fold(0, (m, c) => math.max(m, c.captions.length));

    Widget cell(int index, bool wide) {
      if (index >= months.length) return const SizedBox.shrink();
      final c = months[index];
      return _MonthCell(
        data: c,
        ratio: maxValue <= 0 ? 0 : c.value.abs() / maxValue,
        color: c.value < 0 ? AppColors.warning : widget.color,
        wide: wide,
        withYear: spansYears && (index == 0 || c.month.month == 1),
        captionLines: captionLines,
        selected: c.key == _selectedKey,
        onTap: () => setState(() => _selectedKey = _selectedKey == c.key ? null : c.key),
      );
    }

    final rows = <Widget>[];
    if (twoColumns) {
      // Два столбца по полгода: слева январь–июнь, справа июль–декабрь.
      final half = (months.length / 2).ceil();
      for (int r = 0; r < half; r++) {
        rows.add(_row([cell(r, true), cell(r + half, true)]));
      }
    } else {
      for (int r = 0; r * 3 < months.length; r++) {
        rows.add(_row([for (int c = 0; c < 3; c++) cell(r * 3 + c, false)]));
      }
    }

    CalendarMonth? selected;
    for (final c in months) {
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
          child: selected == null
              ? const SizedBox(width: double.infinity)
              : _details(context, selected),
        ),
      ],
    );
  }

  Widget _row(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${Fmt.monthShort(d.month)}';

  Widget _details(BuildContext context, CalendarMonth m) {
    final title = Fmt.monthTitle(m.key);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.summary.isEmpty ? title : '$title · ${m.summary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              HiddenAmount.forText(
                m.main,
                fontSize: 13,
                child: Text(m.main, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (m.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('Ничего нет', style: TextStyle(fontSize: 11.5, color: context.dim)),
            ),
          for (int i = 0; i < m.lines.length; i++) _line(context, m.lines[i], first: i == 0),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, CalendarLine l, {required bool first}) {
    final dim = context.dim;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: context.hairline, width: 0.6)),
      ),
      child: Row(
        children: [
          // Дата — только если известна. У ожидаемых выплат даты нет, и
          // название начинается сразу от края: «≈» уже стоит у суммы.
          if (l.date != null)
            SizedBox(
              width: 46,
              child: Text(
                _date(l.date!),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dim),
              ),
            ),
          Expanded(
            child: Text(
              l.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: l.muted ? dim : null),
            ),
          ),
          const SizedBox(width: 8),
          HiddenAmount.forText(
            l.amount,
            fontSize: 12,
            child: Text(
              l.amount,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: l.muted ? dim : l.amountColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (l.ticker == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        AppPageRoute(builder: (_) => TickerDetailScreen(ticker: l.ticker!)),
      ),
      child: row,
    );
  }
}

class _MonthCell extends StatelessWidget {
  final CalendarMonth data;
  final double ratio;
  final Color color;
  final bool wide;
  final bool withYear;
  final int captionLines;
  final bool selected;
  final VoidCallback onTap;

  const _MonthCell({
    required this.data,
    required this.ratio,
    required this.color,
    required this.wide,
    required this.withYear,
    required this.captionLines,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = context.isDark ? Colors.white.withOpacity(0.03) : AppColors.lightSurfaceHigh;
    final bg = data.isEmpty ? empty : color.withOpacity(0.08 + 0.42 * ratio.clamp(0.0, 1.0));
    final yy = (data.month.year % 100).toString().padLeft(2, '0');
    // Полное название месяца в обеих раскладках: «сентябрь», а не «сен».
    final monthName = Fmt.monthTitle(data.key).split(' ').first.toLowerCase();
    final label = '$monthName${withYear ? ' $yy' : ''}${wide && data.onlyForecast ? ' · прогноз' : ''}';

    Widget body = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: selected ? Border.all(color: color, width: 1.6) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSingleLineText(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.dim),
          ),
          const SizedBox(height: 2),
          HiddenAmount.forText(
            data.main,
            fontSize: wide ? 14 : 13,
            child: AdaptiveSingleLineText(
              data.main,
              style: TextStyle(
                fontSize: wide ? 14 : 13,
                fontWeight: FontWeight.w700,
                color: data.isEmpty ? context.dim : null,
              ),
            ),
          ),
          for (int i = 0; i < captionLines; i++)
            AdaptiveSingleLineText(
              i < data.captions.length ? data.captions[i].$1 : ' ',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: (i < data.captions.length ? data.captions[i].$2 : null) ?? context.dim,
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
                    color: color.withOpacity(data.forecast ? 0.55 : 0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (data.forecast && !selected) {
      body = CustomPaint(
        foregroundPainter: _DashedBorderPainter(color: color.withOpacity(0.75)),
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
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)).deflate(0.5);
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
