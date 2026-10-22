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

/// Столбики по годам: сумма над столбиком, сверху процент, снизу год. У
/// каждого года один цельный столбик высотой в сумму за год, под годом точки
/// по числу выплат. С [selectable] нажатие в любом месте колонки года
/// перебирает его выплаты по очереди: часть столбика, которая приходится на
/// выбранную выплату, и её точка становятся золотыми, а над годом — её дата,
/// доходность и сумма. После последней выплаты нажатие снимает выбор.
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

  /// Следующая выплата этого года, после последней — снять выбор.
  void _tap(int year) {
    if (!widget.selectable || widget.bars[year].parts.isEmpty) return;
    final sel = _selected;
    final next = sel != null && sel.$1 == year ? sel.$2 + 1 : 0;
    setState(() => _selected = next < widget.bars[year].parts.length ? (year, next) : null);
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    // Масштаб — по сумме за год: столбики выплат и контур года в одних
    // единицах, поэтому рост и падение по годам видно сразу.
    final max = bars.map((b) => b.total).fold(0.0, math.max);
    final hasNotes = bars.any((b) => b.note != null) || widget.selectable;
    final hasDots = bars.any((b) => b.parts.length > 1);
    return LayoutBuilder(builder: (context, box) {
      final scroll = bars.length > _visible;
      final slot = scroll ? box.maxWidth / _visible : box.maxWidth / bars.length;
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < bars.length; i++) SizedBox(width: slot, child: _bar(context, i, max, hasNotes, hasDots)),
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

  Widget _bar(BuildContext context, int index, double max, bool hasNotes, bool hasDots) {
    final b = widget.bars[index];
    final dim = context.dim;
    final sel = _selected;
    final selPart = sel != null && sel.$1 == index ? sel.$2 : null;
    final selectedHere = selPart == null ? null : b.parts[selPart];
    final future = b.isFuture;

    final note = selectedHere != null ? selectedHere.selectedNote : b.note;
    final top = selectedHere != null ? selectedHere.selectedTop : b.top;
    final value = selectedHere != null ? selectedHere.value : b.total;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (hasNotes)
          // Подпись не шире своей колонки: длинная уменьшается, а не
          // наезжает на соседние годы.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              note ?? '',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: 9, color: selectedHere != null ? _gold : dim),
            ),
          ),
        Text(
          top ?? '',
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: selectedHere != null
                ? _gold
                : future
                    ? dim
                    : (b.topColor ?? AppColors.positive),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.format(value),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selectedHere != null ? _gold : (future ? dim : null),
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: widget.barHeight,
          child: FractionallySizedBox(
            widthFactor: 0.62,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _column(b, max, selPart),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text('${b.year}', style: TextStyle(fontSize: 10, color: dim)),
        if (hasDots)
          SizedBox(
            height: 10,
            child: b.parts.length > 1 ? _dots(b.parts.length, selPart) : null,
          ),
      ],
    );
    if (!widget.selectable) return column;
    // Вся колонка года — одна большая кнопка: попадать в столбик не нужно.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(index),
      child: column,
    );
  }

  /// Цельный столбик года. Соседние выплаты одного вида сливаются в один
  /// кусок; выбранная выплата — отдельный золотой кусок на своём месте
  /// (снизу самая ранняя).
  Widget _column(YearBar b, double max, int? selPart) {
    if (b.parts.isEmpty || b.total <= 0 || max <= 0) {
      return Container(
        height: 2,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.5),
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }
    final full = math.max(2.0, widget.barHeight * b.total / max);
    // Куски снизу вверх: (вид, сумма, выбран ли).
    final pieces = <(BarKind, double, bool)>[];
    for (int i = 0; i < b.parts.length; i++) {
      final p = b.parts[i];
      final on = i == selPart;
      if (!on && pieces.isNotEmpty && !pieces.last.$3 && pieces.last.$1 == p.kind) {
        pieces[pieces.length - 1] = (p.kind, pieces.last.$2 + p.value, false);
      } else {
        pieces.add((p.kind, p.value, on));
      }
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5), bottom: Radius.circular(2)),
      child: SizedBox(
        width: double.infinity,
        height: full,
        child: Column(
          children: [
            for (final piece in pieces.reversed)
              SizedBox(
                width: double.infinity,
                height: full * piece.$2 / b.total,
                child: _fill(piece.$1, piece.$3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fill(BarKind kind, bool on) {
    final color = on ? _gold : widget.color;
    // Ширина и высота заданы снаружи: без них заливка и штриховка, у
    // которых нет своего размера, сжимаются в ноль.
    if (kind == BarKind.paid) return ColoredBox(color: color);
    return CustomPaint(painter: _Stripes(color, faint: kind == BarKind.forecast && !on));
  }

  /// Точки под годом — по числу выплат, выбранная золотая и крупнее.
  Widget _dots(int count, int? selected) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          Container(
            width: i == selected ? 7 : 5,
            height: i == selected ? 7 : 5,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == selected ? _gold : context.dim.withOpacity(0.55),
            ),
          ),
      ],
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
