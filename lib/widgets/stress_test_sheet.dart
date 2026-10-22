import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/beta_service.dart';
import '../services/stress_test_service.dart';

String _signed(double v, String unit) {
  final s = v == v.roundToDouble() ? v.abs().toStringAsFixed(0) : v.abs().toStringAsFixed(1);
  return '${v > 0 ? '+' : v < 0 ? '−' : ''}$s$unit';
}

/// Окно «Стресс-тест»: ползунки рынка, ставки и рубля прямо на первом
/// экране, готовые сценарии кнопками над ними, итог и разбор по всем бумагам.
/// [onOpenTicker] открывает карточку бумаги по нажатию в разборе.
Future<void> showStressTestSheet(BuildContext context, {ValueChanged<String>? onOpenTicker}) {
  return showAppSheet(
    context: context,
    builder: (_) => _StressSheet(onOpenTicker: onOpenTicker),
  );
}

class _StressSheet extends StatefulWidget {
  final ValueChanged<String>? onOpenTicker;

  const _StressSheet({this.onOpenTicker});

  @override
  State<_StressSheet> createState() => _StressSheetState();
}

class _StressSheetState extends State<_StressSheet> {
  /// Текущее положение ползунков.
  StressScenario _s = StressTestService.scenarios.first;

  /// false — первый экран, true — разбор по всем бумагам.
  bool _details = false;

  /// В разборе: группами по типам или одним списком по потерям.
  bool _byLoss = false;

  @override
  void initState() {
    super.initState();
    BetaService.version.addListener(_refresh);
    BetaService.refreshInBackground(StressTestService.betaTickers());
  }

  @override
  void dispose() {
    BetaService.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Какой готовый сценарий совпадает с ползунками; иначе — «Свой».
  StressScenario? get _preset {
    for (final p in StressTestService.scenarios) {
      if (p.sameAs(_s)) return p;
    }
    return null;
  }

  void _setSliders(StressScenario s) {
    setState(() => _s = s);
  }

  void _saveCustom() {
    if (_preset == null) StressTestService.saveCustom(_s);
  }

  @override
  Widget build(BuildContext context) {
    final r = StressTestService.run(_s);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
          child: _details
              ? KeyedSubtree(key: const ValueKey('details'), child: _detailsPage(context, r))
              : KeyedSubtree(key: const ValueKey('main'), child: _mainPage(context, r)),
        ),
      ),
    );
  }

  // --- Первый экран ---

  Widget _mainPage(BuildContext context, StressResult r) {
    final preset = _preset;
    final custom = StressTestService.custom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Стресс-тест',
          subtitle: 'Как изменится портфель при резких событиях на рынке',
        ),
        const SizedBox(height: 12),
        // Готовые сценарии: нажатие ставит ползунки на место. Лента
        // прокручивается вбок.
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in StressTestService.scenarios)
                _chip(context, p.title, preset?.id == p.id, () => _setSliders(p)),
              _chip(context, 'Свой', preset == null, () => _setSliders(custom)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
          radius: AppRadius.sm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _slider(context, 'Рынок акций', _s.market, -50, 30, 5, '%',
                  (v) => _setSliders(_s.copyWith(market: v))),
              _slider(context, 'Ставка', _s.rate, -5, 5, 0.5, ' п.п.', (v) => _setSliders(_s.copyWith(rate: v))),
              _slider(context, 'Рубль', _s.ruble, -30, 20, 5, '%', (v) => _setSliders(_s.copyWith(ruble: v))),
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: Text(
                  'Индекс МосБиржи ≈ ${_signed(StressTestService.indexChange(_s).roundToDouble(), '%')}'
                  '${_s.ruble < 0 ? ' · доллар ${_signed((_s.fx * 100).roundToDouble(), '%')}' : ''}',
                  style: TextStyle(fontSize: 11, color: context.dim),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (r.before <= 0)
          Text('В портфеле пока нет бумаг.', style: TextStyle(fontSize: 13.5, color: context.dim))
        else ...[
          _result(context, r),
          const SizedBox(height: 6),
          _sources(context, r),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _details = true),
              child: const Text('Разбор по всем бумагам ›'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Это оценка чувствительности, а не прогноз. Акции двигаются вместе с рынком по своей бете — '
          'она считается по истории цен за два года, а пока истории нет, берётся средняя для отрасли. '
          'Рост ставки удешевляет облигации (тем сильнее, чем дальше погашение) и большинство акций, '
          'но компании с большими деньгами на счетах — Сургутнефтегаз, Мосбиржа, НМТП — больше зарабатывают на процентах. '
          'Слабый рубль поднимает валюту, золото и экспортёров.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Pressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? context.accent.withOpacity(0.18) : Colors.transparent,
              border: Border.all(color: on ? context.accent : context.hairline),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? context.accent : null),
            ),
          ),
        ),
      );

  Widget _slider(BuildContext context, String label, double value, double min, double max, double step,
      String unit, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: ((max - min) / step).round(),
                onChanged: (v) => onChanged((v / step).round() * step),
                onChangeEnd: (_) => _saveCustom(),
              ),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              _signed(value, unit),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, StressResult r) {
    final afterText = Fmt.money(r.after);
    final deltaText = Fmt.signedMoney(r.delta);
    final color = r.delta.abs() < 0.5 ? context.dim : AppColors.pnl(r.delta);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Портфель станет', style: TextStyle(fontSize: 12, color: context.dim)),
              HiddenAmount.forText(
                afterText,
                fontSize: 24,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(afterText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            HiddenAmount.forText(
              deltaText,
              fontSize: 15,
              child: Text(deltaText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
            ),
            Text(Fmt.pct(r.pct), style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ],
    );
  }

  /// «Откуда изменение»: вклад рынка, ставки и курса — полосы от центра.
  Widget _sources(BuildContext context, StressResult r) {
    final rows = <(String, String, double)>[
      (_s.market <= 0 ? 'Падение рынка' : 'Рост рынка', 'акции и фонды', r.fromMarket),
      (_s.rate >= 0 ? 'Рост ставки' : 'Снижение ставки', 'облигации и акции', r.fromRate),
      (_s.ruble <= 0 ? 'Слабый рубль' : 'Крепкий рубль', 'валюта, золото, экспортёры', r.fromFx),
    ];
    final maxAbs = rows.fold(0.0, (m, e) => math.max(m, e.$3.abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cap(context, 'ОТКУДА ИЗМЕНЕНИЕ'),
        for (final e in rows) _divergingRow(context, e.$1, e.$2, e.$3, maxAbs),
      ],
    );
  }

  Widget _divergingRow(BuildContext context, String label, String hint, double value, double maxAbs) {
    final zero = value.abs() < 0.5;
    final color = zero ? context.dim : AppColors.pnl(value);
    final text = zero ? '0 ₽' : Fmt.signedMoney(value);
    final share = maxAbs <= 0 ? 0.0 : value.abs() / maxAbs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.dim)),
              ),
              HiddenAmount.forText(
                text,
                fontSize: 13,
                child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 8,
            child: LayoutBuilder(
              builder: (context, c) {
                final half = c.maxWidth / 2;
                final w = half * share;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.hairline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (!zero)
                      Positioned(
                        left: value < 0 ? half - w : half,
                        width: w,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    Positioned(
                      left: half - 0.5,
                      width: 1,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(color: context.dim.withOpacity(0.6)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cap(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.dim),
        ),
      );

  // --- Разбор по всем бумагам ---

  Widget _detailsPage(BuildContext context, StressResult r) {
    final preset = _preset;
    final title = preset == null ? 'Свой сценарий' : preset.title;
    final totalText = '${Fmt.signedMoney(r.delta)} · ${Fmt.pct(r.pct)}';
    final groups = r.byGroup.entries.toList()..sort((a, b) => a.key.index.compareTo(b.key.index));
    final sorted = [...r.impacts]..sort((a, b) => a.delta.compareTo(b.delta));

    Widget assumption(String text, Color color) => Container(
          margin: const EdgeInsets.only(right: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(7)),
          child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _details = false),
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            label: const Text('Стресс-тест'),
          ),
        ),
        Text('$title · все бумаги', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          children: [
            if (_s.market != 0)
              assumption('рынок ${_signed(_s.market, '%')}', _s.market < 0 ? AppColors.negative : AppColors.positive),
            if (_s.rate != 0)
              assumption('ставка ${_signed(_s.rate, ' п.п.')}', _s.rate > 0 ? AppColors.negative : AppColors.positive),
            if (_s.ruble != 0) assumption('рубль ${_signed(_s.ruble, '%')}', AppColors.warning),
          ],
        ),
        Text(
          'Индекс МосБиржи в этом сценарии ≈ ${_signed(StressTestService.indexChange(_s).roundToDouble(), '%')}',
          style: TextStyle(fontSize: 12, color: context.dim),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Text('Итого', style: TextStyle(fontSize: 13, color: context.dim))),
            HiddenAmount.forText(
              totalText,
              fontSize: 15,
              child: Text(
                totalText,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.pnl(r.delta)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(height: 30, child: _chip(context, 'По типам', !_byLoss, () => setState(() => _byLoss = false))),
            SizedBox(height: 30, child: _chip(context, 'По потерям', _byLoss, () => setState(() => _byLoss = true))),
          ],
        ),
        const SizedBox(height: 6),
        if (_byLoss)
          for (final i in sorted) _paperRow(context, i)
        else
          for (final g in groups) ...[
            _groupHeader(context, g.key, g.value.$1, g.value.$2, r.before),
            for (final i in sorted.where((i) => i.group == g.key))
              if (g.key != StressGroup.cash) _paperRow(context, i),
          ],
        const SizedBox(height: 12),
        Text(
          'Метки — из чего складывается изменение каждой бумаги. '
          'Нажатие на бумагу открывает её карточку.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
        ),
      ],
    );
  }

  Widget _groupHeader(BuildContext context, StressGroup g, double value, double delta, double total) {
    final share = total <= 0 ? 0 : (value / total * 100).round();
    final zero = delta.abs() < 0.5;
    final color = zero ? context.dim : AppColors.pnl(delta);
    final deltaText = zero ? '0 ₽' : Fmt.signedMoney(delta);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.hairline))),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${g.title.toUpperCase()} · $share%',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.dim),
            ),
          ),
          HiddenAmount.forText(
            deltaText,
            fontSize: 12.5,
            child: Text(deltaText, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
          ),
          SizedBox(
            width: 56,
            child: Text(
              zero || value <= 0 ? '0%' : Fmt.pct(delta / value * 100),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperRow(BuildContext context, StressImpact i) {
    final zero = i.delta.abs() < 0.5;
    final color = zero ? context.dim : AppColors.pnl(i.delta);
    final deltaText = zero ? '0 ₽' : Fmt.signedMoney(i.delta);
    final open = widget.onOpenTicker;
    return InkWell(
      onTap: i.ticker.isEmpty || open == null ? null : () => open(i.ticker),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.hairline.withOpacity(0.6)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    children: [for (final t in i.tags) _tagChip(context, t)],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HiddenAmount.forText(
                  deltaText,
                  fontSize: 13,
                  child: Text(deltaText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                ),
                Text(zero ? '0%' : Fmt.pct(i.pct), style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(BuildContext context, StressTag t) {
    final color = t.sign < 0
        ? AppColors.negative
        : t.sign > 0
            ? AppColors.positive
            : context.dim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(5)),
      child: Text(t.text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
