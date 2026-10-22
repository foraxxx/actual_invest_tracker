import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/format.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';

/// Подпись суммы над точкой: «48,3 тыс», «1,2 млн».
String payoutYearLabel(double v) {
  final abs = v.abs();
  String one(double x) => x.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '');
  if (abs >= 1000000) return '${one(v / 1000000)} млн';
  if (abs >= 100000) return '${(v / 1000).round()} тыс';
  if (abs >= 1000) return '${one(v / 1000)} тыс';
  return Fmt.group(v);
}

/// Выплаты по годам: линия с точками. Нажатие на точку или год выбирает
/// год. Текущий год ещё идёт — его точка полая, линия к ней пунктиром.
class PayoutYearsChart extends StatelessWidget {
  /// Год → получено за год. Годы по возрастанию.
  final List<(int, double)> years;
  final int selected;

  /// Год, который ещё не закончился.
  final int? partialYear;
  final ValueChanged<int> onSelect;
  final Color color;

  const PayoutYearsChart({
    super.key,
    required this.years,
    required this.selected,
    required this.onSelect,
    this.partialYear,
    this.color = AppColors.positive,
  });

  static const double height = 156;
  static const double _side = 22;

  double _x(int i, double width) {
    if (years.length == 1) return width / 2;
    return _side + i * (width - _side * 2) / (years.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppearanceService.revealed,
      builder: (context, _, __) => LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              var best = 0;
              var bestDist = double.infinity;
              for (int i = 0; i < years.length; i++) {
                final dist = (d.localPosition.dx - _x(i, width)).abs();
                if (dist < bestDist) {
                  bestDist = dist;
                  best = i;
                }
              }
              if (years.isEmpty || years[best].$1 == selected) return;
              HapticFeedback.selectionClick();
              onSelect(years[best].$1);
            },
            child: CustomPaint(
              size: Size(width, height),
              painter: _YearsPainter(
                years: years,
                selected: selected,
                partialYear: partialYear,
                color: color,
                dim: context.dim,
                text: Theme.of(context).colorScheme.onSurface,
                grid: context.hairline,
                surface: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
                hideAmounts: AppearanceService.amountsHidden,
                xOf: (i) => _x(i, width),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _YearsPainter extends CustomPainter {
  final List<(int, double)> years;
  final int selected;
  final int? partialYear;
  final Color color;
  final Color dim;
  final Color text;
  final Color grid;
  final Color surface;
  final bool hideAmounts;
  final double Function(int) xOf;

  _YearsPainter({
    required this.years,
    required this.selected,
    required this.partialYear,
    required this.color,
    required this.dim,
    required this.text,
    required this.grid,
    required this.surface,
    required this.hideAmounts,
    required this.xOf,
  });

  static const double _top = 30;
  static const double _bottom = 30;

  void _text(Canvas canvas, String s, Offset center, TextStyle style, {double maxRight = double.infinity}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    var dx = center.dx - tp.width / 2;
    if (dx + tp.width > maxRight) dx = maxRight - tp.width;
    if (dx < 0) dx = 0;
    tp.paint(canvas, Offset(dx, center.dy - tp.height / 2));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 5, double gap = 4}) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (years.isEmpty) return;
    final maxV = years.fold(0.0, (m, e) => math.max(m, e.$2));
    final top = _top;
    final bottom = size.height - _bottom;
    double yOf(double v) => maxV <= 0 ? bottom : bottom - (bottom - top) * (v / (maxV * 1.08));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = bottom - (bottom - top) * f;
      canvas.drawLine(Offset(xOf(0) - 8, y), Offset(xOf(years.length - 1) + 8, y), gridPaint);
    }

    final points = [for (int i = 0; i < years.length; i++) Offset(xOf(i), yOf(years[i].$2))];
    final partialIndex = partialYear == null ? -1 : years.indexWhere((e) => e.$1 == partialYear);
    // Сплошная часть — полные годы. Последний неполный год — пунктиром.
    final solidEnd = partialIndex == years.length - 1 && years.length > 1 ? years.length - 2 : years.length - 1;

    if (solidEnd >= 1) {
      final area = Path()..moveTo(points[0].dx, bottom);
      for (int i = 0; i <= solidEnd; i++) {
        area.lineTo(points[i].dx, points[i].dy);
      }
      area
        ..lineTo(points[solidEnd].dx, bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top),
            Offset(0, bottom),
            [color.withOpacity(0.20), color.withOpacity(0.0)],
          ),
      );
      final line = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i <= solidEnd; i++) {
        line.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    if (solidEnd < years.length - 1) {
      _dashed(
        canvas,
        points[solidEnd],
        points[years.length - 1],
        Paint()
          ..color = color
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    for (int i = 0; i < years.length; i++) {
      final p = points[i];
      final isSel = years[i].$1 == selected;
      final partial = i == partialIndex;
      if (isSel) {
        _dashed(
          canvas,
          Offset(p.dx, p.dy + 8),
          Offset(p.dx, bottom),
          Paint()
            ..color = color.withOpacity(0.45)
            ..strokeWidth = 1,
          dash: 2,
          gap: 3,
        );
        canvas.drawCircle(p, 11, Paint()..color = color.withOpacity(0.2));
      }
      final r = isSel ? 6.0 : 4.2;
      canvas.drawCircle(p, r, Paint()..color = partial ? surface : color);
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );

      if (!hideAmounts) {
        _text(
          canvas,
          payoutYearLabel(years[i].$2),
          Offset(p.dx, p.dy - 15),
          TextStyle(
            fontSize: isSel ? 11 : 9.5,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
            color: isSel ? text : dim,
          ),
          maxRight: size.width,
        );
      }

      // Подпись года; выбранный — в «таблетке».
      final yearStyle = TextStyle(
        fontSize: 11.5,
        fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
        color: isSel ? color : dim,
      );
      final labelCenter = Offset(p.dx, bottom + 17);
      if (isSel) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: labelCenter, width: 46, height: 22), const Radius.circular(11)),
          Paint()..color = color.withOpacity(0.18),
        );
      }
      _text(canvas, '${years[i].$1}', labelCenter, yearStyle, maxRight: size.width);
    }
  }

  @override
  bool shouldRepaint(covariant _YearsPainter old) =>
      old.years != years ||
      old.selected != selected ||
      old.partialYear != partialYear ||
      old.color != color ||
      old.dim != dim ||
      old.text != text ||
      old.hideAmounts != hideAmounts ||
      old.surface != surface;
}
