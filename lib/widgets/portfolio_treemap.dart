import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/tokens.dart';

/// Одна бумага на карте портфеля.
class TreemapItem {
  final String ticker;
  final String label;
  final double value;
  final double pnlPct;

  /// Группа для раскладки «по типам» — например «Акции».
  final String group;

  const TreemapItem({
    required this.ticker,
    required this.label,
    required this.value,
    required this.pnlPct,
    this.group = '',
  });
}

/// Раскладка «squarified»: прямоугольники как можно ближе к квадратам, чтобы
/// подписи помещались. Значения должны быть отсортированы по убыванию.
///
/// Вынесена отдельно и не зависит от виджетов — её проверяют тесты: сумма
/// площадей равна площади поля, плитки не выходят за его края.
List<Rect> squarify(List<double> values, Rect rect) {
  final total = values.fold(0.0, (a, b) => a + b);
  if (values.isEmpty || total <= 0 || rect.width <= 0 || rect.height <= 0) {
    return List.filled(values.length, Rect.zero);
  }
  final scale = rect.width * rect.height / total;
  final areas = values.map((v) => math.max(0.0, v) * scale).toList();
  final result = <Rect>[];
  var free = rect;
  var i = 0;
  while (i < areas.length) {
    final side = math.min(free.width, free.height);
    final row = <double>[areas[i]];
    var j = i + 1;
    while (j < areas.length && _worst([...row, areas[j]], side) <= _worst(row, side)) {
      row.add(areas[j]);
      j++;
    }
    final rowSum = row.fold(0.0, (a, b) => a + b);
    if (free.width >= free.height) {
      // Ряд встаёт столбцом у левого края.
      final w = free.height <= 0 ? 0.0 : rowSum / free.height;
      var y = free.top;
      for (final a in row) {
        final h = w <= 0 ? 0.0 : a / w;
        result.add(Rect.fromLTWH(free.left, y, w, h));
        y += h;
      }
      free = Rect.fromLTRB(math.min(free.left + w, free.right), free.top, free.right, free.bottom);
    } else {
      // Ряд встаёт строкой у верхнего края.
      final h = free.width <= 0 ? 0.0 : rowSum / free.width;
      var x = free.left;
      for (final a in row) {
        final w = h <= 0 ? 0.0 : a / h;
        result.add(Rect.fromLTWH(x, free.top, w, h));
        x += w;
      }
      free = Rect.fromLTRB(free.left, math.min(free.top + h, free.bottom), free.right, free.bottom);
    }
    i = j;
  }
  return result;
}

/// Насколько вытянут худший прямоугольник ряда: 1 — квадрат.
double _worst(List<double> row, double side) {
  if (side <= 0) return double.infinity;
  var sum = 0.0;
  var hi = 0.0;
  var lo = double.infinity;
  for (final a in row) {
    sum += a;
    if (a > hi) hi = a;
    if (a < lo) lo = a;
  }
  if (sum <= 0 || lo <= 0) return double.infinity;
  final s2 = sum * sum;
  final w2 = side * side;
  return math.max(w2 * hi / s2, s2 / (w2 * lo));
}

/// Карта портфеля: плитка — бумага, размер — доля, цвет — прибыль.
class PortfolioTreemap extends StatelessWidget {
  final List<TreemapItem> items;

  /// Раскладывать сперва по группам (типам бумаг), потом бумаги внутри.
  final bool grouped;
  final double height;
  final void Function(String ticker) onTap;

  const PortfolioTreemap({
    super.key,
    required this.items,
    required this.onTap,
    this.grouped = false,
    this.height = 240,
  });

  static const double _gap = 2;
  static const double _groupHeader = 18;

  @override
  Widget build(BuildContext context) {
    final list = items.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = list.fold(0.0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, c) {
              final field = Rect.fromLTWH(0, 0, c.maxWidth, height);
              final tiles = <Widget>[];
              if (!grouped) {
                final rects = squarify(list.map((e) => e.value).toList(), field);
                for (int i = 0; i < list.length; i++) {
                  tiles.add(_tile(context, list[i], rects[i]));
                }
              } else {
                // Порядок групп — как в составе портфеля: по первому появлению
                // в исходном списке (экран передаёт акции раньше облигаций).
                final order = <String>[];
                for (final e in items) {
                  if (!order.contains(e.group)) order.add(e.group);
                }
                final groups = [
                  for (final g in order)
                    (name: g, items: list.where((e) => e.group == g).toList()),
                ].where((g) => g.items.isNotEmpty).toList()
                  ..sort((a, b) => _sum(b.items).compareTo(_sum(a.items)));
                final groupRects = squarify(groups.map((g) => _sum(g.items)).toList(), field);
                for (int gi = 0; gi < groups.length; gi++) {
                  final g = groups[gi];
                  final r = groupRects[gi].deflate(_gap);
                  final share = total <= 0 ? 0 : _sum(g.items) / total * 100;
                  final withHeader = r.height > _groupHeader + 24 && r.width > 50;
                  if (withHeader) {
                    tiles.add(Positioned.fromRect(
                      rect: Rect.fromLTWH(r.left + 2, r.top, r.width - 2, _groupHeader),
                      child: Text(
                        '${g.name} · ${share.toStringAsFixed(0)}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.dim),
                      ),
                    ));
                  }
                  final inner = withHeader
                      ? Rect.fromLTRB(r.left, r.top + _groupHeader, r.right, r.bottom)
                      : r;
                  final rects = squarify(g.items.map((e) => e.value).toList(), inner);
                  for (int i = 0; i < g.items.length; i++) {
                    tiles.add(_tile(context, g.items[i], rects[i]));
                  }
                }
              }
              return Stack(children: tiles);
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Размер — доля в портфеле, цвет — прибыль с покупки. Нажмите на плитку, чтобы открыть бумагу.',
          style: TextStyle(fontSize: 10.5, height: 1.35, color: context.dim),
        ),
      ],
    );
  }

  static double _sum(List<TreemapItem> list) => list.fold(0.0, (s, e) => s + e.value);

  Widget _tile(BuildContext context, TreemapItem item, Rect rect) {
    final r = rect.deflate(_gap / 2);
    if (r.width <= 0 || r.height <= 0) return const SizedBox.shrink();
    // Насыщенность растёт с величиной прибыли и упирается в ±20%: иначе одна
    // бумага с +80% сделала бы все остальные бледными.
    final strength = (item.pnlPct.abs() / 20).clamp(0.0, 1.0);
    final base = AppColors.pnl(item.pnlPct);
    final color = base.withOpacity(0.16 + 0.5 * strength);
    final showLabel = r.width >= 34 && r.height >= 26;
    final showPct = r.width >= 44 && r.height >= 42;

    return Positioned.fromRect(
      rect: r,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(item.ticker),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
          child: showLabel
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                    if (showPct)
                      Text(
                        Fmt.pct(item.pnlPct),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}
