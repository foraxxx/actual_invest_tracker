import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/stress_test_service.dart';

String _signed(double v, String unit) {
  final s = v == v.roundToDouble() ? v.abs().toStringAsFixed(0) : v.abs().toStringAsFixed(1);
  return '${v > 0 ? '+' : v < 0 ? '−' : ''}$s$unit';
}

/// Окно «Стресс-тест»: что будет с портфелем при падении рынка, росте ставки
/// или скачке курса.
Future<void> showStressTestSheet(BuildContext context) {
  var scenario = StressTestService.scenarios.first;
  var custom = StressTestService.custom.copyWith(stocks: -20, rate: 2, fx: 10);
  var isCustom = false;
  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final current = isCustom ? custom : scenario;
        final r = StressTestService.run(current);
        final groups = r.byGroup.entries.toList()..sort((a, b) => a.key.index.compareTo(b.key.index));
        final worst = r.worst.take(5).toList();

        Widget chip(String label, bool selected, VoidCallback onTap) => Pressable(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? ctx.accent.withOpacity(0.18) : Colors.transparent,
                  border: Border.all(color: selected ? ctx.accent : ctx.hairline),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? ctx.accent : null,
                  ),
                ),
              ),
            );

        Widget slider(String label, double value, double min, double max, double step, String unit,
            ValueChanged<double> onChanged) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                  Text(_signed(value, unit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: ((max - min) / step).round(),
                onChanged: (v) => onChanged((v / step).round() * step),
              ),
            ],
          );
        }

        final afterText = Fmt.money(r.after);
        final deltaText = Fmt.signedMoney(r.delta);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHeader(
                  title: 'Стресс-тест',
                  subtitle: 'Что будет с портфелем, если рынок резко изменится',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in StressTestService.scenarios)
                      chip(s.title, !isCustom && scenario.id == s.id, () => setSheet(() {
                            scenario = s;
                            isCustom = false;
                          })),
                    chip(StressTestService.custom.title, isCustom, () => setSheet(() => isCustom = true)),
                  ],
                ),
                const SizedBox(height: 8),
                if (isCustom) ...[
                  slider('Акции', custom.stocks, -50, 50, 5, '%',
                      (v) => setSheet(() => custom = custom.copyWith(stocks: v))),
                  slider('Ключевая ставка', custom.rate, -5, 5, 0.5, ' п.п.',
                      (v) => setSheet(() => custom = custom.copyWith(rate: v))),
                  slider('Курс валют', custom.fx, -30, 30, 5, '%',
                      (v) => setSheet(() => custom = custom.copyWith(fx: v))),
                ] else
                  Text(
                    _describe(current),
                    style: TextStyle(fontSize: 12.5, color: ctx.dim),
                  ),
                const SizedBox(height: 16),
                if (r.before <= 0)
                  Text('В портфеле пока нет бумаг.', style: TextStyle(fontSize: 13.5, color: ctx.dim))
                else ...[
                  Text('Портфель станет', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
                  const SizedBox(height: 2),
                  HiddenAmount.forText(
                    afterText,
                    fontSize: 26,
                    child: Text(afterText, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      HiddenAmount.forText(
                        deltaText,
                        fontSize: 14,
                        child: Text(
                          deltaText,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pnl(r.delta)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(Fmt.pct(r.pct), style: TextStyle(fontSize: 14, color: AppColors.pnl(r.delta))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('ПО ТИПАМ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ctx.dim)),
                  const SizedBox(height: 6),
                  for (final g in groups) _groupRow(ctx, g.key, g.value.$1, g.value.$2, r.before),
                  if (worst.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('СИЛЬНЕЕ ВСЕГО ПОСТРАДАЮТ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ctx.dim)),
                    const SizedBox(height: 6),
                    for (final i in worst) _impactRow(ctx, i),
                  ],
                ],
                const SizedBox(height: 14),
                Text(
                  'Это грубая оценка, а не прогноз. Акции и фонды акций меняются вместе с рынком, '
                  'облигации — по дюрации: чем дальше погашение, тем сильнее цена реагирует на ставку. '
                  'Флоатеры и фонды денежного рынка от ставки почти не зависят, валюта и золото меняются вместе с курсом.',
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

String _describe(StressScenario s) {
  final parts = <String>[
    if (s.stocks != 0) 'акции ${_signed(s.stocks, '%')}',
    if (s.rate != 0) 'ключевая ставка ${_signed(s.rate, ' п.п.')}',
    if (s.fx != 0) 'курс валют ${_signed(s.fx, '%')}',
  ];
  if (parts.isEmpty) return 'Без изменений';
  final text = parts.join(', ');
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

Widget _groupRow(BuildContext ctx, StressGroup g, double value, double delta, double total) {
  final share = total <= 0 ? 0.0 : value / total;
  final deltaText = Fmt.signedMoney(delta);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${g.title} · ${(share * 100).round()}%', style: const TextStyle(fontSize: 13)),
            ),
            HiddenAmount.forText(
              deltaText,
              fontSize: 13,
              child: Text(
                delta.abs() < 0.5 ? '0 ₽' : deltaText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: delta.abs() < 0.5 ? ctx.dim : AppColors.pnl(delta),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: math.min(1.0, share),
            minHeight: 5,
            backgroundColor: ctx.hairline,
            color: delta < -0.5
                ? AppColors.negative
                : delta > 0.5
                    ? AppColors.positive
                    : AppColors.neutral,
          ),
        ),
      ],
    ),
  );
}

Widget _impactRow(BuildContext ctx, StressImpact i) {
  final deltaText = Fmt.signedMoney(i.delta);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              Text(i.reason, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: ctx.dim)),
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
              child: Text(deltaText,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.pnl(i.delta))),
            ),
            Text(Fmt.pct(i.pct), style: TextStyle(fontSize: 11, color: ctx.dim)),
          ],
        ),
      ],
    ),
  );
}
