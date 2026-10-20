import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/home_widget_config.dart';

/// Что показывает виджет — те же расчёты, что делает сам виджет на
/// телефоне по снимку из приложения.
class WidgetViewData {
  final String title;
  final double value;
  final double? dayRub;
  final double? dayPct;
  final double profit;
  final double? profitPct;
  final DateTime updatedAt;
  final bool hidden;
  final List<double> chart;
  final List<Map<String, dynamic>> payouts;
  final Map<String, dynamic>? month;
  final List<Map<String, dynamic>> divs;
  final List<(String, double)> leaders;

  const WidgetViewData({
    required this.title,
    required this.value,
    required this.dayRub,
    required this.dayPct,
    required this.profit,
    required this.profitPct,
    required this.updatedAt,
    required this.hidden,
    required this.chart,
    required this.payouts,
    required this.month,
    required this.divs,
    required this.leaders,
  });

  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

  static WidgetViewData? from(Map<String, dynamic>? s) {
    if (s == null) return null;
    double dayRub = 0, dayBase = 0;
    var any = false;
    final leaders = <(String, double)>[];
    for (final p in (s['pos'] as List? ?? const [])) {
      final m = p as Map;
      final q = _d(m['q']), k = _d(m['k']), price = _d(m['p']);
      final prev = (m['c'] as num?)?.toDouble();
      if (prev == null || prev <= 0) continue;
      any = true;
      dayRub += q * (price - prev) * k;
      dayBase += q * prev * k;
      leaders.add(('${m['n'] ?? m['s']}', (price / prev - 1) * 100));
    }
    leaders.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
    final value = _d(s['value']);
    final profit = _d(s['profit']);
    final invested = value - profit;
    return WidgetViewData(
      title: '${s['title'] ?? 'Портфель'}',
      value: value,
      dayRub: any ? dayRub : null,
      dayPct: any && dayBase > 0 ? dayRub / dayBase * 100 : null,
      profit: profit,
      profitPct: invested > 1 ? profit / invested * 100 : null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((s['pricesAt'] as num?)?.toInt() ?? 0),
      hidden: s['hidden'] == true,
      chart: [
        for (final e in (s['chart'] as List? ?? const [])) _d((e as List)[1]),
        value,
      ],
      payouts: [for (final e in (s['pay'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)],
      month: s['month'] is Map ? Map<String, dynamic>.from(s['month'] as Map) : null,
      divs: [for (final e in (s['divs'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)],
      leaders: leaders.take(3).toList(),
    );
  }
}

const _months = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _money(double v) {
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${v < 0 ? '−' : ''}$b ₽';
}

String _pct(double v) => '${v.abs().toStringAsFixed(2).replaceAll('.', ',')}%';
String _date(int d) => '${d % 100} ${_months[d ~/ 100 % 100 - 1]}';
String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Превью виджета в конструкторе: та же раскладка и оформление, что на
/// рабочем столе, внутри пунктирного места, которое выделяет телефон.
class HomeWidgetPreview extends StatelessWidget {
  final WidgetSize size;
  final WidgetSizeConfig cfg;
  final WidgetStyle style;
  final WidgetViewData? data;

  const HomeWidgetPreview({
    super.key,
    required this.size,
    required this.cfg,
    required this.style,
    required this.data,
  });

  Color get _text => Color(0xFF000000 | style.text);
  Color get _dim => Color(0x94000000 | style.text);
  Color get _up => Color(0xFF000000 | style.up);
  Color get _down => Color(0xFF000000 | style.down);
  Color get _accent => Color(0xFF000000 | style.accent);

  double get _radius => switch (style.radius) { 'small' => 12.0, 'large' => 30.0, _ => 22.0 };

  @override
  Widget build(BuildContext context) {
    final w = size.previewWidth;
    final h = size.previewHeight;
    final cardW = w * cfg.width / 100;
    final cardH = cfg.fit ? null : h * cfg.height / 100;
    final shadow = switch (style.shadow) {
      'soft' => [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 10, spreadRadius: 0.5)],
      'strong' => [BoxShadow(color: Colors.black.withOpacity(0.75), blurRadius: 14, spreadRadius: 1.5)],
      _ => const <BoxShadow>[],
    };
    final borderColor = Color(style.borderColor | ((style.borderAlpha * 255 ~/ 100) << 24));
    final card = Container(
      width: cardW,
      height: cardH,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: size.rows == 1 ? 7 : 12),
      decoration: BoxDecoration(
        color: Color(style.bg | ((style.bgAlpha * 255 ~/ 100) << 24)),
        borderRadius: BorderRadius.circular(_radius),
        border: style.border == 'none' ? null : Border.all(color: borderColor, width: style.border == 'edge' ? 0.8 : 1),
        boxShadow: shadow,
      ),
      foregroundDecoration: style.border == 'edge'
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.035, 0.08],
                colors: [borderColor.withOpacity(math.min(1, borderColor.opacity * 2.5)), borderColor.withOpacity(0), Colors.transparent],
              ),
            )
          : null,
      child: DefaultTextStyle(
        style: TextStyle(color: _text, fontSize: 11, height: 1.2),
        child: data == null
            ? Center(child: Text('Данные готовятся…', style: TextStyle(color: _dim)))
            : _content(data!),
      ),
    );
    final align = switch (cfg.align) {
      'top' => Alignment.topCenter,
      'bottom' => Alignment.bottomCenter,
      _ => Alignment.center,
    };
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _DashedCell(),
        child: Align(alignment: align, child: card),
      ),
    );
  }

  // --- Части ---

  Widget _label(String t, {String? right}) => Row(
        children: [
          Expanded(
            child: Text(t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _dim)),
          ),
          if (right != null) Text(right, style: TextStyle(fontSize: 10.5, color: _dim)),
        ],
      );

  Widget _value(WidgetViewData d, double fs) => SizedBox(
        height: fs + 7,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(d.hidden ? '••• ••• ₽' : _money(d.value),
              style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ),
      );

  String _time(DateTime t) {
    final n = DateTime.now();
    if (t.year == n.year && t.month == n.month && t.day == n.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return _date(t.year * 10000 + t.month * 100 + t.day);
  }

  Widget _today(WidgetViewData d, {bool word = false}) {
    final r = d.dayRub;
    if (r == null) return Text('Нет цен с биржи', style: TextStyle(color: _dim, fontSize: 11));
    final up = r >= 0;
    final arrow = up ? '▲ ' : '▼ ';
    final pct = d.dayPct == null ? '' : _pct(d.dayPct!);
    final t = d.hidden ? '$arrow$pct' : '$arrow${_money(r.abs())}${pct.isEmpty ? '' : ' · $pct'}';
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: t),
        if (word) TextSpan(text: ' сегодня', style: TextStyle(color: _dim, fontWeight: FontWeight.w400)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: up ? _up : _down),
    );
  }

  Widget _total(WidgetViewData d) {
    final up = d.profit >= 0;
    final amount = d.hidden
        ? (d.profitPct == null ? '•••' : '${up ? '+' : '−'}${_pct(d.profitPct!)}')
        : '${up ? '+' : '−'}${_money(d.profit.abs())}';
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'за всё время '),
        TextSpan(text: amount, style: TextStyle(color: up ? _up : _down, fontWeight: FontWeight.w700)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: _dim),
    );
  }

  Widget _header(WidgetViewData d, {double fs = 21, bool todayWord = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(d.title, right: cfg.time ? _time(d.updatedAt) : null),
          _value(d, fs),
          if (cfg.today) _today(d, word: todayWord),
          if (cfg.total) Padding(padding: const EdgeInsets.only(top: 2), child: _total(d)),
        ],
      );

  Widget _bar(double p) => Container(
        height: 4,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: _dim.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: p.clamp(0.0, 1.0),
          child: Container(decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2))),
        ),
      );

  Widget _divider({bool vertical = false}) => vertical
      ? Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 12), color: _dim.withOpacity(0.2))
      : Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: _dim.withOpacity(0.2));

  /// Выплаты бюджета: текущая (с которой откладываем) и следующая.
  (Map<String, dynamic>?, Map<String, dynamic>?, List<Map<String, dynamic>>) _pays(WidgetViewData d) {
    final n = DateTime.now();
    final today = n.year * 10000 + n.month * 100 + n.day;
    final pays = [...d.payouts]..sort((a, b) => (a['d'] as int).compareTo(b['d'] as int));
    Map<String, dynamic>? current;
    for (final p in pays) {
      if ((p['d'] as int) <= today) current = p;
    }
    final upcoming = [for (final p in pays) if ((p['d'] as int) > today) p];
    return (current, upcoming.isEmpty ? null : upcoming.first, upcoming);
  }

  Widget _payTitle(Map<String, dynamic> p) => _label('${p['n']} ${_date(p['d'] as int)}');

  Widget _leftBlock(WidgetViewData d, Map<String, dynamic> p, {bool showOf = true, double fs = 15}) {
    final plan = WidgetViewData._d(p['plan']);
    final left = WidgetViewData._d(p['left']);
    if (plan <= 0.5) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _payTitle(p),
        Padding(padding: const EdgeInsets.only(top: 3), child: Text('ещё не распределено', style: TextStyle(color: _dim))),
      ]);
    }
    final done = ((plan - left) / plan).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _payTitle(p),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: d.hidden ? 'отложено ' : 'осталось ', style: TextStyle(color: _dim, fontSize: 10.5)),
              TextSpan(
                text: d.hidden ? '${(done * 100).round()}%' : _money(left),
                style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800),
              ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showOf && !d.hidden) Text('из ${_money(plan)}', style: TextStyle(color: _dim, fontSize: 10.5)),
        _bar(done),
      ],
    );
  }

  Widget _doneBlock(Map<String, dynamic> p, Map<String, dynamic>? next, {double fs = 15}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _payTitle(p),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('Всё отложено ✓',
                maxLines: 1, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: _up)),
          ),
          if (next != null)
            Text('дальше ${_lowerFirst('${next['n']}')} ${_date(next['d'] as int)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _dim, fontSize: 10.5)),
        ],
      );

  Widget _emptyBudget() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [_label('Бюджет'), Text('не заполнен', style: TextStyle(color: _dim))],
      );

  /// Ближайшая выплата бюджета одним блоком.
  Widget _budget(WidgetViewData d, {bool withNext = true, double fs = 15}) {
    final (current, next, _) = _pays(d);
    if (d.payouts.every((p) => WidgetViewData._d(p['plan']) <= 0.5)) return _emptyBudget();
    if (current != null && WidgetViewData._d(current['plan']) > 0.5) {
      if (WidgetViewData._d(current['left']) > 0.5) return _leftBlock(d, current, fs: fs);
      return _doneBlock(current, withNext ? next : null, fs: fs);
    }
    if (next != null) return _leftBlock(d, next, fs: fs);
    return _emptyBudget();
  }

  /// Правая колонка 4×2: текущая выплата, следующая и итог месяца.
  Widget _budgetColumn(WidgetViewData d) {
    final (current, next, upcoming) = _pays(d);
    Map<String, dynamic>? second = next;
    Widget first;
    if (current != null && WidgetViewData._d(current['plan']) > 0.5) {
      first = WidgetViewData._d(current['left']) > 0.5
          ? _leftBlock(d, current, fs: 13)
          : _doneBlock(current, null, fs: 13);
    } else if (next != null) {
      first = _leftBlock(d, next, fs: 13);
      second = upcoming.length > 1 ? upcoming[1] : null;
    } else {
      first = _emptyBudget();
      second = null;
    }
    final m = d.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        first,
        if (second != null) ...[const SizedBox(height: 10), _leftBlock(d, second, fs: 13)],
        if (m != null) ...[
          cfg.fit ? const SizedBox(height: 10) : const Spacer(),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${m['n']}: отложено '),
              TextSpan(
                text: '${(WidgetViewData._d(m['done']) / math.max(1, WidgetViewData._d(m['plan'])) * 100).round()}%',
                style: TextStyle(color: _text, fontWeight: FontWeight.w700),
              ),
            ]),
            style: TextStyle(color: _dim, fontSize: 10.5),
          ),
          _bar(WidgetViewData._d(m['done']) / math.max(1, WidgetViewData._d(m['plan']))),
        ],
      ],
    );
  }

  Widget _row(String a, String b, {Color? color, String? sub}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(b, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? _text)),
            ]),
            if (sub != null) Text(sub, maxLines: 1, style: TextStyle(color: _dim, fontSize: 10)),
          ],
        ),
      );

  Widget _list(WidgetViewData d, WidgetSlot slot, int rows) {
    if (slot == WidgetSlot.payouts) {
      final items = d.divs.take(math.max(1, rows - 1)).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label('Выплаты по бумагам'),
          if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('пока не объявлены', style: TextStyle(color: _dim))),
          for (final i in items)
            _row('${i['n']}', d.hidden ? '•••' : _money(WidgetViewData._d(i['rub'])), sub: '${i['k']} ${_date(i['d'] as int)}'),
        ],
      );
    }
    final items = d.leaders.take(rows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label('Сегодня в портфеле'),
        if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('нет цен с биржи', style: TextStyle(color: _dim))),
        for (final i in items) _row(i.$1, '${i.$2 >= 0 ? '▲' : '▼'} ${_pct(i.$2)}', color: i.$2 >= 0 ? _up : _down),
      ],
    );
  }

  Widget _chart(WidgetViewData d, {double? height}) {
    final painter = CustomPaint(painter: _ChartPainter(d.chart, _accent), size: Size.infinite);
    final body = d.chart.length < 2
        ? Center(child: Text('График появится после загрузки цен', textAlign: TextAlign.center, style: TextStyle(color: _dim)))
        : painter;
    return height == null ? body : SizedBox(height: height, width: double.infinity, child: body);
  }

  /// Часть, которая растягивается на свободное место (или фиксированной
  /// высоты, если карточка по содержимому).
  Widget _grow(Widget child, {double fixed = 56}) =>
      cfg.fit ? SizedBox(height: fixed, width: double.infinity, child: child) : Expanded(child: child);

  Widget _slot(WidgetViewData d, WidgetSlot slot, {required int rows, bool divider = true}) {
    switch (slot) {
      case WidgetSlot.chart:
        return _grow(Padding(padding: const EdgeInsets.only(top: 8), child: _chart(d)));
      case WidgetSlot.chartBudget:
        return _grow(Column(children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: _chart(d))),
          const SizedBox(height: 6),
          _budgetLine(d),
        ]), fixed: 84);
      case WidgetSlot.budget:
        return Column(mainAxisSize: MainAxisSize.min, children: [if (divider) _divider(), _budget(d)]);
      case WidgetSlot.payouts:
      case WidgetSlot.leaders:
        return Column(mainAxisSize: MainAxisSize.min, children: [if (divider) _divider(), _list(d, slot, rows)]);
      case WidgetSlot.none:
        return const SizedBox.shrink();
    }
  }

  /// Ближайшая выплата одной строкой — для 3×2.
  Widget _budgetLine(WidgetViewData d) {
    final (current, next, _) = _pays(d);
    Map<String, dynamic>? p;
    if (current != null && WidgetViewData._d(current['plan']) > 0.5 && WidgetViewData._d(current['left']) > 0.5) {
      p = current;
    } else {
      p = next;
    }
    if (p == null) return const SizedBox.shrink();
    final plan = WidgetViewData._d(p['plan']);
    final left = WidgetViewData._d(p['left']);
    final done = plan <= 0 ? 0.0 : ((plan - left) / plan).clamp(0.0, 1.0);
    return Column(children: [
      Row(children: [
        Expanded(child: _payTitle(p)),
        Text(d.hidden ? 'отложено ' : 'осталось ', style: TextStyle(color: _dim, fontSize: 10.5)),
        Text(d.hidden ? '${(done * 100).round()}%' : _money(left), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
      _bar(done),
    ]);
  }

  Widget _content(WidgetViewData d) {
    switch (size) {
      case WidgetSize.s21:
        if (cfg.budgetOnly) return Align(alignment: Alignment.centerLeft, child: _budget(d, fs: 15));
        return Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: cfg.fit ? MainAxisSize.min : MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.start, children: [_header(d, fs: 17)]);
      case WidgetSize.s31:
      case WidgetSize.s41: {
        final right = cfg.slot == WidgetSlot.none
            ? null
            : cfg.slot == WidgetSlot.chart
                ? _chart(d, height: 56)
                : cfg.slot == WidgetSlot.budget
                    ? _budget(d, fs: 14)
                    : _list(d, cfg.slot, 2);
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: _header(d, fs: 18)),
            if (right != null) ...[_divider(vertical: true), Expanded(child: right)],
          ]),
        );
      }
      case WidgetSize.s22:
      case WidgetSize.s32:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: cfg.fit ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _header(d, fs: size == WidgetSize.s22 ? 21 : 22, todayWord: size == WidgetSize.s32),
            if (!cfg.fit && (cfg.slot == WidgetSlot.budget || cfg.slot == WidgetSlot.payouts || cfg.slot == WidgetSlot.leaders))
              const Spacer(),
            _slot(d, cfg.slot, rows: 3),
          ],
        );
      case WidgetSize.s42: {
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: cfg.fit ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _header(d, fs: 20),
            if (cfg.chart) _grow(Padding(padding: const EdgeInsets.only(top: 8), child: _chart(d)), fixed: 60),
          ],
        );
        final Widget? right = switch (cfg.slot) {
          WidgetSlot.budget => _budgetColumn(d),
          WidgetSlot.payouts || WidgetSlot.leaders => _list(d, cfg.slot, 3),
          _ => null,
        };
        final row = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 58, child: left),
          if (right != null) ...[_divider(vertical: true), Expanded(flex: 42, child: right)],
        ]);
        return cfg.fit ? IntrinsicHeight(child: row) : row;
      }
    }
  }
}

class _DashedCell extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCell oldDelegate) => false;
}

class _ChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _ChartPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo < 1e-6 ? 1.0 : hi - lo;
    const top = 3.0;
    final bottom = size.height - 1.5;
    Offset at(int i) => Offset(
          1.5 + (size.width - 3) * i / (values.length - 1),
          hi - lo < 1e-6 ? (top + bottom) / 2 : bottom - (bottom - top) * (values[i] - lo) / span,
        );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i < values.length; i++) {
      final a = at(i - 1), b = at(i);
      final cx = (a.dx + b.dx) / 2;
      line.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.22), color.withOpacity(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.values != values || old.color != color;
}
