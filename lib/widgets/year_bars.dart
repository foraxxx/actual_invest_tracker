import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Вид части столбика.
enum BarKind { paid, announced, forecast }

/// Одна выплата внутри года — свой узкий столбик.
class BarPart {
  final double value;
  final BarKind kind;

  /// Что показать над годом, когда нажали на этот столбик.
  final String? selectedTop;
  final String? selectedNote;

  const BarPart(this.value, {this.kind = BarKind.paid, this.selectedTop, this.selectedNote});
}

/// Один год на графике выплат.
class YearBar {
  final int year;
  final List<BarPart> parts;

  /// Процент над столбиком и его цвет.
  final String? top;
  final Color? topColor;

  /// Подпись над процентом: «объявлено», «прогноз».
  final String? note;

  const YearBar({required this.year, required this.parts, this.top, this.topColor, this.note});

  double get total => parts.fold(0.0, (s, p) => s + p.value);
  bool get isFuture => parts.isNotEmpty && parts.every((p) => p.kind != BarKind.paid);
}

/// Столбики по годам: сумма над столбиком, сверху процент, снизу год. Если в
/// году несколько выплат — столько же узких столбиков рядом. С [selectable]
/// на столбик можно нажать: над годом появится эта выплата.
/// Больше шести лет — график листается, открывается на последних годах.
class YearBars extends StatefulWidget {
  final List<YearBar> bars;
  final String Function(double) format;
  final double barHeight;
  final Color color;
  final bool selectable;

  const YearBars({
    super.key,
    required this.bars,
    required this.format,
    this.barHeight = 60,
    this.color = AppColors.info,
    this.selectable = false,
  });

  @override
  State<YearBars> createState() => _YearBarsState();
}

class _YearBarsState extends State<YearBars> {
  static const _visible = 6;
  static const _gold = AppColors.gold;

  /// Выбранная выплата: (индекс года, индекс выплаты).
  (int, int)? _selected;

  @override
  void didUpdateWidget(YearBars old) {
    super.didUpdateWidget(old);
    if (old.bars.length != widget.bars.length) _selected = null;
  }

  void _tap(int year, int part) {
    if (!widget.selectable) return;
    setState(() => _selected = _selected == (year, part) ? null : (year, part));
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    final max = bars.expand((b) => b.parts).map((p) => p.value).fold(0.0, math.max);
    final hasNotes = bars.any((b) => b.note != null) || widget.selectable;
    return LayoutBuilder(builder: (context, box) {
      final scroll = bars.length > _visible;
      final slot = scroll ? box.maxWidth / _visible : box.maxWidth / bars.length;
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < bars.length; i++) SizedBox(width: slot, child: _bar(context, i, max, hasNotes)),
        ],
      );
      final body = GestureDetector(
        // Нажатие мимо столбиков снимает выбор.
        behavior: HitTestBehavior.translucent,
        onTap: _selected == null ? null : () => setState(() => _selected = null),
        child: row,
      );
      if (!scroll) return body;
      return ShaderMask(
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
          child: body,
        ),
      );
    });
  }

  Widget _bar(BuildContext context, int index, double max, bool hasNotes) {
    final b = widget.bars[index];
    final dim = context.dim;
    final sel = _selected;
    final selectedHere = sel != null && sel.$1 == index ? b.parts[sel.$2] : null;
    final future = b.isFuture;

    final note = selectedHere != null ? selectedHere.selectedNote : b.note;
    final top = selectedHere != null ? selectedHere.selectedTop : b.top;
    final value = selectedHere != null ? selectedHere.value : b.total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (hasNotes)
          Text(
            note ?? '',
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: TextStyle(fontSize: 9, color: selectedHere != null ? _gold : dim),
          ),
        Text(
          top ?? '',
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: future && selectedHere == null ? dim : (b.topColor ?? AppColors.positive),
          ),
        ),
        Text(
          widget.format(value),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selectedHere != null ? _gold : (future ? dim : null),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: widget.barHeight,
          child: FractionallySizedBox(
            widthFactor: 0.76,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int p = 0; p < b.parts.length; p++) ...[
                  if (p > 0) const SizedBox(width: 3),
                  Expanded(child: _part(index, p, b.parts[p], max)),
                ],
                if (b.parts.isEmpty || b.total <= 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text('${b.year}', style: TextStyle(fontSize: 10, color: dim)),
      ],
    );
  }

  Widget _part(int year, int index, BarPart p, double max) {
    final h = max <= 0 ? 2.0 : math.max(2.0, widget.barHeight * p.value / max);
    final sel = _selected;
    final on = sel == (year, index);
    final faded = sel != null && !on;
    const radius = BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(2));
    final bar = Container(
      height: h,
      // Ширина обязательна: без неё заливка и штриховка, у которых нет своего
      // размера, сжимаются в ноль и столбик пропадает.
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: on ? Border.all(color: _gold, width: 2) : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: p.kind == BarKind.paid
            ? ColoredBox(color: widget.color)
            : CustomPaint(painter: _Stripes(widget.color, faint: p.kind == BarKind.forecast)),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.selectable ? () => _tap(year, index) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: faded ? 0.45 : 1,
        // Нажимать удобно по всей высоте колонки, а не только по столбику.
        child: Container(height: widget.barHeight, alignment: Alignment.bottomCenter, child: bar),
      ),
    );
  }
}

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
