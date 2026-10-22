import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/home_widget_config.dart';
import '../services/home_widget_service.dart';
import '../services/portfolio_service.dart';
import '../widgets/home_widget_preview.dart';

/// Конструктор виджета на экране телефона: для каждого размера — своё
/// содержимое и размер карточки, оформление общее для всех размеров.
class WidgetConstructorScreen extends StatefulWidget {
  const WidgetConstructorScreen({super.key});

  @override
  State<WidgetConstructorScreen> createState() => _WidgetConstructorScreenState();
}

class _WidgetConstructorScreenState extends State<WidgetConstructorScreen> {
  late WidgetConfig _cfg = HomeWidgetService.config;
  WidgetSize _size = WidgetSize.s22;
  bool _styleTab = false;

  @override
  void initState() {
    super.initState();
    if (HomeWidgetService.lastSnapshot.value == null) HomeWidgetService.schedule(quick: true);
  }

  WidgetSizeConfig get _sc => _cfg.of(_size);

  /// Меняет настройки на экране; [save] — сразу записать и отправить
  /// виджету. Ползунки сохраняют только когда палец отпущен.
  void _update(WidgetConfig c, {bool save = true}) {
    setState(() => _cfg = c);
    if (save) HomeWidgetService.setConfig(c);
  }

  void _setSize(WidgetSizeConfig c, {bool save = true}) => _update(_cfg.withSize(_size, c), save: save);
  void _setStyle(WidgetStyle s, {bool save = true}) => _update(_cfg.withStyle(s), save: save);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Виджет на экране')),
      body: Column(
        children: [
          _preview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              children: [
                _segmented<WidgetSize>(
                  values: WidgetSize.values,
                  selected: _size,
                  label: (s) => s.label,
                  onTap: (s) => setState(() => _size = s),
                ),
                const SizedBox(height: 8),
                _segmented<bool>(
                  values: const [false, true],
                  selected: _styleTab,
                  label: (v) => v ? 'Оформление' : 'Содержимое',
                  onTap: (v) => setState(() => _styleTab = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: _styleTab ? _styleControls() : _contentControls(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    return Container(
      width: double.infinity,
      height: 230,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B4A5A), Color(0xFF6A5A46), Color(0xFF1D2630)],
        ),
      ),
      child: ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: HomeWidgetService.lastSnapshot,
        builder: (context, snap, _) => FittedBox(
          fit: BoxFit.contain,
          child: HomeWidgetPreview(size: _size, cfg: _sc, style: _cfg.style, data: WidgetViewData.from(snap)),
        ),
      ),
    );
  }

  // --- Содержимое ---

  List<Widget> _contentControls() {
    final sc = _sc;
    final slots = slotsFor(_size);
    final slotTitle = switch (_size) {
      WidgetSize.s31 || WidgetSize.s41 => 'СПРАВА',
      WidgetSize.s42 => 'ПРАВАЯ КОЛОНКА',
      _ => 'НИЖНЯЯ ЧАСТЬ',
    };
    return [
      _caption('ПОРТФЕЛЬ — ДЛЯ ВСЕХ РАЗМЕРОВ'),
      _wrap([
        _chip('Все вместе', _cfg.source == HomeWidgetService.allId,
            () => _update(_cfg.withSource(HomeWidgetService.allId))),
        for (final p in PortfolioService.list) _chip(p.name, _cfg.source == p.id, () => _update(_cfg.withSource(p.id))),
      ]),
      if (_size == WidgetSize.s21) ...[
        _caption('ЧТО ПОКАЗЫВАТЬ'),
        _wrap([
          _chip('Портфель', !sc.budgetOnly, () => _setSize(sc.copyWith(budgetOnly: false))),
          _chip('Только бюджет', sc.budgetOnly, () => _setSize(sc.copyWith(budgetOnly: true))),
        ]),
      ],
      if (!(_size == WidgetSize.s21 && sc.budgetOnly)) ...[
        _caption('ПОД СТОИМОСТЬЮ'),
        _wrap([
          _chip('Сегодня', sc.today, () => _setSize(sc.copyWith(today: !sc.today)), check: true),
          _chip('За всё время', sc.total, () => _setSize(sc.copyWith(total: !sc.total)), check: true),
          _chip('Время обновления', sc.time, () => _setSize(sc.copyWith(time: !sc.time)), check: true),
        ]),
      ],
      if (_size == WidgetSize.s42) ...[
        _caption('ЛЕВАЯ КОЛОНКА'),
        _wrap([_chip('График за месяц', sc.chart, () => _setSize(sc.copyWith(chart: !sc.chart)), check: true)]),
      ],
      if (slots.isNotEmpty) ...[
        _caption(slotTitle),
        _wrap([for (final s in slots) _chip(s.label, sc.slot == s, () => _setSize(sc.copyWith(slot: s)))]),
      ],
      _caption('РАЗМЕР КАРТОЧКИ'),
      _wrap([
        _chip('На всю клетку', !sc.fit, () => _setSize(sc.copyWith(fit: false))),
        _chip('По содержимому', sc.fit, () => _setSize(sc.copyWith(fit: true))),
      ]),
      _slider('Ширина', sc.width, 60, 100, (v) => _setSize(sc.copyWith(width: v), save: false),
          (v) => _setSize(sc.copyWith(width: v))),
      if (!sc.fit)
        _slider('Высота', sc.height, 50, 100, (v) => _setSize(sc.copyWith(height: v), save: false),
            (v) => _setSize(sc.copyWith(height: v))),
      _caption('ПОЛОЖЕНИЕ'),
      _wrap([
        _chip('Сверху', sc.align == 'top', () => _setSize(sc.copyWith(align: 'top'))),
        _chip('По центру', sc.align == 'center', () => _setSize(sc.copyWith(align: 'center'))),
        _chip('Снизу', sc.align == 'bottom', () => _setSize(sc.copyWith(align: 'bottom'))),
      ]),
      const SizedBox(height: 14),
      Text(
        'Место под виджет задаёт телефон — клетками рабочего стола. Карточка внутри может быть меньше; '
        'пустая часть прозрачная, нажатие по ней тоже открывает приложение. '
        'Ширина, высота и «по содержимому» работают на Android 12 и новее.\n\n'
        'Как добавить виджет: долгое нажатие на пустом месте рабочего стола → «Виджеты» → Invest Tracker.',
        style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
      ),
    ];
  }

  // --- Оформление ---

  static const _bgColors = [0x111214, 0x1B1D22, 0x111A2B, 0x1A1430, 0x0F1F1A, 0x2A1A14, 0xF4F5F7, 0xFFFFFF];
  static const _lineColors = [0xFFFFFF, 0x000000, 0x3DA9FC, 0x3EE6A8, 0x8B7CFF, 0xFFC53D];
  static const _textColors = [0xF2F2F4, 0xFFFFFF, 0xE8E2D4, 0xCFD6E4, 0x14161A];
  static const _pairs = [(0x3EE6A8, 0xFF6B7A), (0x16D796, 0xFF4D6D), (0x7EE081, 0xFF9A62), (0xF2F2F4, 0x8B8F98), (0x0F9F6E, 0xD93A4F)];
  static const _accents = [0xF2F2F4, 0x3EE6A8, 0x3DA9FC, 0x8B7CFF, 0xFFC53D, 0x14161A];

  List<Widget> _styleControls() {
    final st = _cfg.style;
    return [
      _caption('ГОТОВЫЙ СТИЛЬ — ДЛЯ ВСЕХ РАЗМЕРОВ'),
      _wrap([
        for (final e in WidgetStyle.presets.entries)
          _chip(e.value.$1, st.preset == e.key, () => _setStyle(e.value.$2.copyWith(preset: e.key))),
        if (st.preset == 'custom') _chip('Свой', true, () {}),
      ]),
      _caption('ФОН'),
      _swatches(_bgColors, st.bg, (c) => _setStyle(st.copyWith(bg: c))),
      _slider('Непрозрачность', st.bgAlpha, 20, 100, (v) => _setStyle(st.copyWith(bgAlpha: v), save: false),
          (v) => _setStyle(st.copyWith(bgAlpha: v))),
      _caption('РАМКА'),
      _wrap([
        _chip('Нет', st.border == 'none', () => _setStyle(st.copyWith(border: 'none'))),
        _chip('Тонкая', st.border == 'thin', () => _setStyle(st.copyWith(border: 'thin'))),
        _chip('Светлый край', st.border == 'edge', () => _setStyle(st.copyWith(border: 'edge'))),
      ]),
      if (st.border != 'none') ...[
        _swatches(_lineColors, st.borderColor, (c) => _setStyle(st.copyWith(borderColor: c))),
        _slider('Яркость', st.borderAlpha, 4, 60, (v) => _setStyle(st.copyWith(borderAlpha: v), save: false),
            (v) => _setStyle(st.copyWith(borderAlpha: v))),
      ],
      _caption('ТЕНЬ'),
      _wrap([
        _chip('Нет', st.shadow == 'none', () => _setStyle(st.copyWith(shadow: 'none'))),
        _chip('Мягкая', st.shadow == 'soft', () => _setStyle(st.copyWith(shadow: 'soft'))),
        _chip('Заметная', st.shadow == 'strong', () => _setStyle(st.copyWith(shadow: 'strong'))),
      ]),
      _caption('ТЕКСТ'),
      _swatches(_textColors, st.text, (c) => _setStyle(st.copyWith(text: c))),
      _caption('РОСТ И ПАДЕНИЕ'),
      Wrap(
        children: [
          for (final p in _pairs)
            _swatch(
              selected: st.up == p.$1 && st.down == p.$2,
              onTap: () => _setStyle(st.copyWith(up: p.$1, down: p.$2)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  stops: const [0.5, 0.5],
                  colors: [Color(0xFF000000 | p.$1), Color(0xFF000000 | p.$2)],
                ),
              ),
            ),
        ],
      ),
      _caption('ГРАФИК И ПОЛОСКИ'),
      _swatches(_accents, st.accent, (c) => _setStyle(st.copyWith(accent: c))),
      _caption('СКРУГЛЕНИЕ'),
      _wrap([
        _chip('Как у системы', st.radius == 'system', () => _setStyle(st.copyWith(radius: 'system'))),
        _chip('Меньше', st.radius == 'small', () => _setStyle(st.copyWith(radius: 'small'))),
        _chip('Больше', st.radius == 'large', () => _setStyle(st.copyWith(radius: 'large'))),
      ]),
      const SizedBox(height: 14),
      Text(
        'Android не умеет размывать обои под виджетом, поэтому полупрозрачный фон — без размытия. '
        'Тень у виджетов тоже ненастоящая: это мягкое затемнение по краю.',
        style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
      ),
    ];
  }

  // --- Элементы ---

  Widget _caption(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 0, 8),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.dim)),
      );

  Widget _wrap(List<Widget> children) => Wrap(spacing: 6, runSpacing: 6, children: children);

  Widget _chip(String label, bool on, VoidCallback onTap, {bool check = false}) {
    final accent = context.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: on ? accent.withOpacity(0.16) : Colors.transparent,
          border: Border.all(color: on ? accent : context.dim.withOpacity(0.35)),
        ),
        child: Text(
          check && on ? '✓ $label' : label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? accent : null),
        ),
      ),
    );
  }

  Widget _segmented<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onTap,
  }) {
    final accent = context.accent;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected ? accent.withOpacity(0.22) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    label(v),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: v == selected ? null : context.dim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider(String label, int value, int min, int max, ValueChanged<int> onChanged, ValueChanged<int> onEnd) {
    return Row(
      children: [
        SizedBox(width: 112, child: Text(label, style: TextStyle(fontSize: 12.5, color: context.dim))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            onChanged: (v) => onChanged(v.round()),
            onChangeEnd: (v) => onEnd(v.round()),
          ),
        ),
        SizedBox(width: 40, child: Text('$value%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
      ],
    );
  }

  Widget _swatches(List<int> colors, int selected, ValueChanged<int> onPick) {
    final inList = colors.contains(selected);
    return Wrap(
      children: [
        for (final c in colors)
          _swatch(
            selected: c == selected,
            onTap: () => onPick(c),
            decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFF000000 | c)),
          ),
        _swatch(
          selected: !inList,
          onTap: () async {
            final c = await _pickColor(selected);
            if (c != null) onPick(c);
          },
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: inList ? null : Color(0xFF000000 | selected),
            gradient: inList
                ? const SweepGradient(colors: [
                    Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                  ])
                : null,
          ),
        ),
      ],
    );
  }

  Widget _swatch({required bool selected, required VoidCallback onTap, required BoxDecoration decoration}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(right: 10, bottom: 8),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? context.accent : context.dim.withOpacity(0.3), width: selected ? 2 : 1),
        ),
        child: Container(decoration: decoration),
      ),
    );
  }

  /// Свой цвет: тон, насыщенность и яркость.
  Future<int?> _pickColor(int initial) {
    var hsv = HSVColor.fromColor(Color(0xFF000000 | initial));
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget row(String label, double value, double max, ValueChanged<double> onChanged) => Row(
                children: [
                  SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 12.5))),
                  Expanded(child: Slider(value: value, max: max, onChanged: (v) => set(() => onChanged(v)))),
                ],
              );
          return AlertDialog(
            title: const Text('Свой цвет'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(color: hsv.toColor(), borderRadius: BorderRadius.circular(12)),
                ),
                const SizedBox(height: 10),
                row('Оттенок', hsv.hue, 360, (v) => hsv = hsv.withHue(v)),
                row('Насыщенность', hsv.saturation, 1, (v) => hsv = hsv.withSaturation(v)),
                row('Яркость', hsv.value, 1, (v) => hsv = hsv.withValue(v)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, hsv.toColor().value & 0xFFFFFF),
                child: const Text('Готово'),
              ),
            ],
          );
        },
      ),
    );
  }
}
