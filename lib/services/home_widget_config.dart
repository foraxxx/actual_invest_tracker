import 'dart:convert';

/// Размеры виджета, для которых настраивается своё содержимое. Ширина в
/// клетках рабочего стола: 2 — узкий, 3 — средний, 4 — широкий.
enum WidgetSize {
  s21('2×1', 2, 1),
  s31('3×1', 3, 1),
  s41('4×1', 4, 1),
  s22('2×2', 2, 2),
  s32('3×2', 3, 2),
  s42('4×2', 4, 2);

  final String label;
  final int cols;
  final int rows;
  const WidgetSize(this.label, this.cols, this.rows);

  /// Типичный размер на телефоне, точки — для превью.
  double get previewWidth => switch (cols) { 2 => 160.0, 3 => 244.0, _ => 340.0 };
  double get previewHeight => rows == 1 ? 82.0 : 190.0;
}

/// Что можно поставить в свободную часть виджета.
enum WidgetSlot {
  chart('График за месяц'),
  budget('Бюджет'),
  chartBudget('График и выплата'),
  payouts('Выплаты по бумагам'),
  leaders('Лидеры дня'),
  none('Ничего');

  final String label;
  const WidgetSlot(this.label);

  static WidgetSlot from(Object? v, WidgetSlot fallback) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return fallback;
  }
}

/// Варианты свободной части для каждого размера.
List<WidgetSlot> slotsFor(WidgetSize size) => switch (size) {
      WidgetSize.s21 => const [],
      WidgetSize.s31 || WidgetSize.s41 => const [
          WidgetSlot.budget,
          WidgetSlot.chart,
          WidgetSlot.payouts,
          WidgetSlot.leaders,
          WidgetSlot.none,
        ],
      WidgetSize.s22 => const [
          WidgetSlot.chart,
          WidgetSlot.budget,
          WidgetSlot.payouts,
          WidgetSlot.leaders,
          WidgetSlot.none,
        ],
      WidgetSize.s32 => const [
          WidgetSlot.chartBudget,
          WidgetSlot.chart,
          WidgetSlot.budget,
          WidgetSlot.payouts,
          WidgetSlot.leaders,
          WidgetSlot.none,
        ],
      // У 4×2 это правая колонка; график слева включается отдельно.
      WidgetSize.s42 => const [
          WidgetSlot.budget,
          WidgetSlot.payouts,
          WidgetSlot.leaders,
          WidgetSlot.none,
        ],
    };

/// Содержимое и размер карточки для одного размера виджета.
class WidgetSizeConfig {
  /// Только для 2×1: показывать портфель или бюджет.
  final bool budgetOnly;
  final bool today;
  final bool total;
  final bool time;
  final WidgetSlot slot;

  /// Только для 4×2: график в левой колонке.
  final bool chart;

  /// true — карточка по содержимому, false — на всю клетку.
  final bool fit;

  /// Ширина и высота карточки в процентах от места под виджет.
  final int width;
  final int height;

  /// Где стоит карточка, если она меньше места: top, center, bottom.
  final String align;

  const WidgetSizeConfig({
    this.budgetOnly = false,
    this.today = true,
    this.total = true,
    this.time = false,
    this.slot = WidgetSlot.none,
    this.chart = true,
    this.fit = false,
    this.width = 100,
    this.height = 100,
    this.align = 'center',
  });

  WidgetSizeConfig copyWith({
    bool? budgetOnly,
    bool? today,
    bool? total,
    bool? time,
    WidgetSlot? slot,
    bool? chart,
    bool? fit,
    int? width,
    int? height,
    String? align,
  }) =>
      WidgetSizeConfig(
        budgetOnly: budgetOnly ?? this.budgetOnly,
        today: today ?? this.today,
        total: total ?? this.total,
        time: time ?? this.time,
        slot: slot ?? this.slot,
        chart: chart ?? this.chart,
        fit: fit ?? this.fit,
        width: width ?? this.width,
        height: height ?? this.height,
        align: align ?? this.align,
      );

  static WidgetSizeConfig defaults(WidgetSize s) => switch (s) {
        WidgetSize.s21 => const WidgetSizeConfig(),
        WidgetSize.s31 => const WidgetSizeConfig(total: false, slot: WidgetSlot.budget),
        WidgetSize.s41 => const WidgetSizeConfig(slot: WidgetSlot.budget),
        WidgetSize.s22 => const WidgetSizeConfig(slot: WidgetSlot.chart, time: true),
        WidgetSize.s32 => const WidgetSizeConfig(slot: WidgetSlot.chartBudget, time: true),
        WidgetSize.s42 => const WidgetSizeConfig(slot: WidgetSlot.budget, time: true),
      };

  Map<String, dynamic> toJson() => {
        'bo': budgetOnly,
        'td': today,
        'tt': total,
        'tm': time,
        'sl': slot.name,
        'ch': chart,
        'fit': fit,
        'w': width,
        'h': height,
        'al': align,
      };

  static WidgetSizeConfig fromJson(Object? raw, WidgetSize s) {
    final d = defaults(s);
    if (raw is! Map) return d;
    final allowed = slotsFor(s);
    var slot = WidgetSlot.from(raw['sl'], d.slot);
    if (allowed.isNotEmpty && !allowed.contains(slot)) slot = d.slot;
    int pct(Object? v, int min, int fallback) => ((v as num?)?.round() ?? fallback).clamp(min, 100).toInt();
    final align = raw['al'];
    return WidgetSizeConfig(
      budgetOnly: raw['bo'] == true,
      today: raw['td'] is bool ? raw['td'] as bool : d.today,
      total: raw['tt'] is bool ? raw['tt'] as bool : d.total,
      time: raw['tm'] is bool ? raw['tm'] as bool : d.time,
      slot: slot,
      chart: raw['ch'] is bool ? raw['ch'] as bool : d.chart,
      fit: raw['fit'] == true,
      width: pct(raw['w'], 60, 100),
      height: pct(raw['h'], 50, 100),
      align: align == 'top' || align == 'bottom' ? align as String : 'center',
    );
  }
}

/// Оформление виджета — общее для всех размеров. Цвета — 0xRRGGBB.
class WidgetStyle {
  final String preset;
  final int bg;
  final int bgAlpha;

  /// none, thin, edge.
  final String border;
  final int borderColor;
  final int borderAlpha;

  /// none, soft, strong.
  final String shadow;
  final int text;
  final int up;
  final int down;

  /// Цвет графика и полосок бюджета.
  final int accent;

  /// system, small, large.
  final String radius;

  const WidgetStyle({
    this.preset = 'graphite',
    this.bg = 0x111214,
    this.bgAlpha = 100,
    this.border = 'thin',
    this.borderColor = 0xFFFFFF,
    this.borderAlpha = 13,
    this.shadow = 'none',
    this.text = 0xF2F2F4,
    this.up = 0x3EE6A8,
    this.down = 0xFF6B7A,
    this.accent = 0xF2F2F4,
    this.radius = 'system',
  });

  static const presets = <String, (String, WidgetStyle)>{
    'graphite': ('Графит', WidgetStyle()),
    'glass': (
      'Стекло',
      WidgetStyle(
        preset: 'glass',
        bg: 0x14161C,
        bgAlpha: 55,
        borderAlpha: 19,
        text: 0xFFFFFF,
        up: 0x5FF0B8,
        down: 0xFF8A96,
        accent: 0xFFFFFF,
      ),
    ),
    'app': (
      'Как приложение',
      WidgetStyle(
        preset: 'app',
        bg: 0x111A2B,
        borderColor: 0x3DA9FC,
        borderAlpha: 27,
        text: 0xFFFFFF,
        up: 0x16D796,
        down: 0xFF4D6D,
        accent: 0x3DA9FC,
      ),
    ),
    'light': (
      'Светлый',
      WidgetStyle(
        preset: 'light',
        bg: 0xF4F5F7,
        borderColor: 0x000000,
        borderAlpha: 8,
        text: 0x14161A,
        up: 0x0F9F6E,
        down: 0xD93A4F,
        accent: 0x14161A,
      ),
    ),
  };

  WidgetStyle copyWith({
    String? preset,
    int? bg,
    int? bgAlpha,
    String? border,
    int? borderColor,
    int? borderAlpha,
    String? shadow,
    int? text,
    int? up,
    int? down,
    int? accent,
    String? radius,
  }) =>
      WidgetStyle(
        // Любая ручная правка превращает готовый стиль в свой.
        preset: preset ?? 'custom',
        bg: bg ?? this.bg,
        bgAlpha: bgAlpha ?? this.bgAlpha,
        border: border ?? this.border,
        borderColor: borderColor ?? this.borderColor,
        borderAlpha: borderAlpha ?? this.borderAlpha,
        shadow: shadow ?? this.shadow,
        text: text ?? this.text,
        up: up ?? this.up,
        down: down ?? this.down,
        accent: accent ?? this.accent,
        radius: radius ?? this.radius,
      );

  Map<String, dynamic> toJson() => {
        'p': preset,
        'bg': bg,
        'ba': bgAlpha,
        'b': border,
        'bc': borderColor,
        'bra': borderAlpha,
        'sh': shadow,
        'tx': text,
        'up': up,
        'dn': down,
        'ac': accent,
        'r': radius,
      };

  static WidgetStyle fromJson(Object? raw) {
    const d = WidgetStyle();
    if (raw is! Map) return d;
    int color(Object? v, int fallback) => ((v as num?)?.toInt() ?? fallback) & 0xFFFFFF;
    int pct(Object? v, int fallback) => ((v as num?)?.round() ?? fallback).clamp(0, 100).toInt();
    String pick(Object? v, List<String> allowed, String fallback) =>
        allowed.contains(v) ? v as String : fallback;
    return WidgetStyle(
      preset: raw['p'] is String ? raw['p'] as String : d.preset,
      bg: color(raw['bg'], d.bg),
      bgAlpha: pct(raw['ba'], d.bgAlpha),
      border: pick(raw['b'], const ['none', 'thin', 'edge'], d.border),
      borderColor: color(raw['bc'], d.borderColor),
      borderAlpha: pct(raw['bra'], d.borderAlpha),
      shadow: pick(raw['sh'], const ['none', 'soft', 'strong'], d.shadow),
      text: color(raw['tx'], d.text),
      up: color(raw['up'], d.up),
      down: color(raw['dn'], d.down),
      accent: color(raw['ac'], d.accent),
      radius: pick(raw['r'], const ['system', 'small', 'large'], d.radius),
    );
  }
}

/// Всё, что настраивается в конструкторе виджета.
class WidgetConfig {
  final String source;
  final WidgetStyle style;
  final Map<WidgetSize, WidgetSizeConfig> sizes;

  const WidgetConfig({required this.source, required this.style, required this.sizes});

  static WidgetConfig defaults(String source) => WidgetConfig(
        source: source,
        style: const WidgetStyle(),
        sizes: {for (final s in WidgetSize.values) s: WidgetSizeConfig.defaults(s)},
      );

  WidgetSizeConfig of(WidgetSize s) => sizes[s] ?? WidgetSizeConfig.defaults(s);

  WidgetConfig withSize(WidgetSize s, WidgetSizeConfig c) =>
      WidgetConfig(source: source, style: style, sizes: {...sizes, s: c});

  WidgetConfig withStyle(WidgetStyle st) => WidgetConfig(source: source, style: st, sizes: sizes);

  WidgetConfig withSource(String id) => WidgetConfig(source: id, style: style, sizes: sizes);

  Map<String, dynamic> toJson() => {
        'src': source,
        'st': style.toJson(),
        'sz': {for (final e in sizes.entries) e.key.name: e.value.toJson()},
      };

  String encode() => jsonEncode(toJson());

  static WidgetConfig decode(String? raw, String fallbackSource) {
    if (raw == null) return defaults(fallbackSource);
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return defaults(fallbackSource);
      final sz = m['sz'];
      return WidgetConfig(
        source: m['src'] is String ? m['src'] as String : fallbackSource,
        style: WidgetStyle.fromJson(m['st']),
        sizes: {
          for (final s in WidgetSize.values) s: WidgetSizeConfig.fromJson(sz is Map ? sz[s.name] : null, s),
        },
      );
    } catch (_) {
      return defaults(fallbackSource);
    }
  }
}
