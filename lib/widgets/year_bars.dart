import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Один год на графике выплат.
class YearBar {
  final int year;

  /// Уже выплачено — сплошная часть.
  final double paid;

  /// Объявлено компанией — заштрихованная часть.
  final double announced;

  /// Прогноз аналитиков — бледная штриховка с рамкой.
  final double forecast;

  /// Процент над столбиком и его цвет.
  final String? top;
  final Color? topColor;

  /// Подпись над процентом: «объявлено», «прогноз».
  final String? note;

  const YearBar({
    required this.year,
    this.paid = 0,
    this.announced = 0,
    this.forecast = 0,
    this.top,
    this.topColor,
    this.note,
  });

  double get total => paid + announced + forecast;
  bool get isFuture => paid <= 0 && (announced > 0 || forecast > 0);
}

/// Столбики по годам: сумма над столбиком, сверху процент, снизу год.
/// Больше шести лет — график листается, открывается на последних годах.
class YearBars extends StatelessWidget {
  final List<YearBar> bars;
  final String Function(double) format;
  final double barHeight;
  final Color color;

  const YearBars({
    super.key,
    required this.bars,
    required this.format,
    this.barHeight = 60,
    this.color = AppColors.info,
  });

  static const _visible = 6;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final max = bars.map((b) => b.total).fold(0.0, math.max);
    final hasNotes = bars.any((b) => b.note != null);
    final total = barHeight + 16 + 14 + 15 + (hasNotes ? 12 : 0);
    return LayoutBuilder(builder: (context, box) {
      final scroll = bars.length > _visible;
      final slot = scroll ? box.maxWidth / _visible : box.maxWidth / bars.length;
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [for (final b in bars) SizedBox(width: slot, child: _bar(context, b, max, hasNotes))],
      );
      if (!scroll) return SizedBox(height: total, child: row);
      return SizedBox(
        height: total,
        child: ShaderMask(
          // Затемнение у левого края — там есть более ранние годы.
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.transparent, Colors.black],
            stops: [0, 0.09],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            physics: const BouncingScrollPhysics(),
            child: row,
          ),
        ),
      );
    });
  }

  Widget _bar(BuildContext context, YearBar b, double max, bool hasNotes) {
    double h(double v) => max <= 0 ? 0 : barHeight * v / max;
    final dim = context.dim;
    final future = b.isFuture;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (hasNotes)
          SizedBox(
            height: 12,
            child: Text(b.note ?? '', style: TextStyle(fontSize: 9, color: dim)),
          ),
        SizedBox(
          height: 14,
          child: Text(
            b.top ?? '',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: future ? dim : (b.topColor ?? dim)),
          ),
        ),
        Text(
          format(b.total),
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: future ? dim : null,
          ),
        ),
        const SizedBox(height: 2),
        FractionallySizedBox(
          widthFactor: 0.72,
          child: Column(
            children: [
              if (b.forecast > 0) _part(h(b.forecast), _Pattern.faint, top: true, bottom: b.paid + b.announced <= 0),
              if (b.announced > 0) _part(h(b.announced), _Pattern.striped, top: b.forecast <= 0, bottom: b.paid <= 0),
              if (b.paid > 0) _part(h(b.paid), _Pattern.solid, top: b.forecast + b.announced <= 0, bottom: true),
              if (b.total <= 0)
                Container(
                  height: 2,
                  decoration: BoxDecoration(color: color.withOpacity(0.5), borderRadius: BorderRadius.circular(1)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text('${b.year}', style: TextStyle(fontSize: 10, color: dim)),
      ],
    );
  }

  Widget _part(double height, _Pattern p, {required bool top, required bool bottom}) {
    final radius = BorderRadius.vertical(
      top: Radius.circular(top ? 5 : 0),
      bottom: Radius.circular(bottom ? 2 : 0),
    );
    return SizedBox(
      height: math.max(height, 2),
      width: double.infinity,
      child: ClipRRect(
        borderRadius: radius,
        child: p == _Pattern.solid
            ? ColoredBox(color: color)
            : CustomPaint(painter: _Stripes(color, faint: p == _Pattern.faint)),
      ),
    );
  }
}

enum _Pattern { solid, striped, faint }

class _Stripes extends CustomPainter {
  final Color color;
  final bool faint;
  _Stripes(this.color, {required this.faint});

  @override
  void paint(Canvas canvas, Size size) {
    if (!faint) canvas.drawRect(Offset.zero & size, Paint()..color = color.withOpacity(0.22));
    final p = Paint()
      ..color = color.withOpacity(faint ? 0.35 : 0.75)
      ..strokeWidth = faint ? 1.4 : 3;
    final step = faint ? 7.0 : 8.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    if (faint) {
      canvas.drawRect(
        (Offset.zero & size).deflate(0.5),
        Paint()
          ..color = color.withOpacity(0.55)
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes old) => old.color != color || old.faint != faint;
}
