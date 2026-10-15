import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/goal_service.dart';

const _gold = AppColors.gold;

/// «к декабрю 2028» — месяц полностью, в нужном падеже.
String goalDeadlineText(DateTime d) {
  const months = [
    'январю', 'февралю', 'марту', 'апрелю', 'маю', 'июню',
    'июлю', 'августу', 'сентябрю', 'октябрю', 'ноябрю', 'декабрю',
  ];
  return 'к ${months[d.month - 1]} ${d.year}';
}

/// «2 г 2 мес», «5 мес».
String monthsText(int months) {
  if (months <= 0) return 'срок наступил';
  final y = months ~/ 12;
  final m = months % 12;
  if (y == 0) return '$m мес';
  if (m == 0) return '$y ${Fmt.plural(y, 'год', 'года', 'лет')}';
  return '$y г $m мес';
}

/// Главная мысль цели одной строкой.
String goalAdvice(GoalPlan p) {
  if (p.reached) return 'цель достигнута';
  if (p.overdue) return 'срок прошёл · осталось ${Fmt.money(p.remaining)}';
  if (p.monthly <= 0.5) return 'успеваете и без новых взносов';
  return 'вносите ≈${Fmt.money(_round100(p.monthly))}/мес';
}

double _round100(double v) => (v / 100).ceil() * 100.0;

/// Карточка цели на главной. Пока цели нет — тонкая строка «Поставить цель».
///
/// Свёрнутая карточка — одна строка, а сама она залита золотым на долю
/// пройденного пути. Развёрнутая — полоса прогресса, суммы и сколько
/// вносить. Нажатие на заголовок сворачивает, на остальное — открывает
/// подробности.
class GoalCard extends StatelessWidget {
  final GoalPlan? plan;
  final bool collapsed;
  final VoidCallback onToggle;

  const GoalCard({super.key, required this.plan, required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final p = plan;
    if (p == null) {
      return Pressable(
        onTap: () => showGoalEditSheet(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.hairline, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: context.dim),
              const SizedBox(width: 6),
              Text(
                'Поставить финансовую цель',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.dim),
              ),
            ],
          ),
        ),
      );
    }

    final color = p.reached ? AppColors.positive : _gold;
    final title = p.goal.name.trim().isEmpty
        ? 'Цель · ${Fmt.money(p.goal.amount)}'
        : '${p.goal.name.trim()} · ${Fmt.money(p.goal.amount)}';
    final percent = '${(p.progress * 100).floor()}%';
    final subtitle = p.reached
        ? 'цель достигнута'
        : '${goalDeadlineText(p.goal.deadline)} · ${goalAdvice(p)}';

    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(11)),
            child: Icon(p.reached ? Icons.flag_rounded : Icons.track_changes_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HiddenAmount.forText(
                  title,
                  fontSize: 15,
                  child: AdaptiveSingleLineText(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 1),
                // Названия месяцев не обрезаются: если строка длинная, текст
                // немного уменьшается.
                AdaptiveSingleLineText(
                  collapsed || p.reached ? subtitle : '${goalDeadlineText(p.goal.deadline)} · осталось ${monthsText(p.monthsLeft)}',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(percent, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: collapsed ? 0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more_rounded, size: 22, color: context.dim),
          ),
        ],
      ),
    );

    final base = context.isDark ? AppColors.darkSurface : Colors.white;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: collapsed ? context.hairline : color.withOpacity(0.35), width: 1.1),
        // Свёрнутая — залита цветом на долю пройденного пути.
        gradient: collapsed
            ? LinearGradient(
                colors: [color.withOpacity(0.16), color.withOpacity(0.16), base, base],
                stops: [0, p.progress, p.progress, 1],
              )
            : null,
        color: collapsed ? null : base,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showGoalDetailsSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _expanded(context, p, color),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context, GoalPlan p, Color color) {
    final now = Fmt.money(p.current);
    final left = Fmt.money(p.remaining);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: p.progress,
            minHeight: 9,
            backgroundColor: context.hairline,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: HiddenAmount.forText(
                now,
                fontSize: 11.5,
                child: AdaptiveSingleLineText('$now сейчас', style: TextStyle(fontSize: 11.5, color: context.dim)),
              ),
            ),
            const SizedBox(width: 8),
            if (!p.reached)
              HiddenAmount.forText(
                left,
                fontSize: 11.5,
                child: Text('осталось $left', style: TextStyle(fontSize: 11.5, color: context.dim)),
              ),
          ],
        ),
        if (!p.reached) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.overdue
                      ? 'Срок прошёл — цель можно продлить'
                      : p.monthly <= 0.5
                          ? 'Успеваете и без новых взносов'
                          : 'Вносите ≈${Fmt.money(_round100(p.monthly))} в месяц',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  'с ростом по прогнозу ≈${p.annualGrowthPct.toStringAsFixed(0)}% годовых',
                  style: TextStyle(fontSize: 11.5, color: context.dim),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Постановка или правка цели.
Future<void> showGoalEditSheet(BuildContext context) {
  final existing = GoalService.current;
  final amountCtrl = TextEditingController(
    text: existing == null ? '' : existing.amount.toStringAsFixed(0),
  );
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final now = DateTime.now();
  var month = existing?.deadline.month ?? 12;
  var year = existing?.deadline.year ?? now.year + 2;
  String? error;

  const monthNames = [
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];

  double? parse() => double.tryParse(amountCtrl.text.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.'));

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        final amount = parse();
        final preview = amount != null && amount > 0
            ? GoalService.plan(FinancialGoal(amount: amount, deadline: DateTime(year, month)))
            : null;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Финансовая цель',
                subtitle: 'Сколько и к какому сроку хотите накопить в этом портфеле',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: amountCtrl,
                label: 'Сумма цели, ₽',
                number: true,
                onChanged: (_) => setSheet(() => error = null),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in const [1, 2, 3, 5, 10])
                    ChoiceChip(
                      label: Text('$m млн'),
                      selected: amount == m * 1000000,
                      onSelected: (_) => setSheet(() => amountCtrl.text = '${m * 1000000}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppDropdown<int>(
                      value: month,
                      label: 'Месяц',
                      items: [
                        for (int i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(monthNames[i - 1])),
                      ],
                      onChanged: (v) => setSheet(() => month = v ?? month),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AppDropdown<int>(
                      value: year,
                      label: 'Год',
                      items: [
                        for (int y = now.year; y <= now.year + 40; y++) DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setSheet(() => year = v ?? year),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(controller: nameCtrl, label: 'Название (необязательно)', hint: 'Например, «Квартира»'),
              if (preview != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _gold.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    preview.reached
                        ? 'В портфеле уже ${Fmt.money(preview.current)} — цель достигнута.'
                        : 'Сейчас в портфеле ${Fmt.money(preview.current)} — это ${(preview.progress * 100).floor()}%.\n'
                            '${preview.monthsLeft <= 0 ? 'Срок уже наступил.' : preview.monthly <= 0.5 ? 'Успеваете и без новых взносов.' : 'Чтобы успеть, нужно вносить ≈${Fmt.money(_round100(preview.monthly))} в месяц.'}',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 18),
              GradientButton(
                label: 'Сохранить цель',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final a = parse();
                  if (a == null || a <= 0) {
                    setSheet(() => error = 'Укажите сумму цели');
                    return;
                  }
                  if (DateTime(year, month).isBefore(DateTime(now.year, now.month))) {
                    setSheet(() => error = 'Срок уже прошёл — выберите месяц позже');
                    return;
                  }
                  await GoalService.save(FinancialGoal(amount: a, deadline: DateTime(year, month), name: nameCtrl.text.trim()));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Подробности цели: график пути к цели, расчёт и правка.
Future<void> showGoalDetailsSheet(BuildContext context) {
  final goal = GoalService.current;
  if (goal == null) return Future.value();
  final p = GoalService.plan(goal);
  final monthly = _round100(p.monthly);

  Widget row(BuildContext ctx, String label, String value, {Color? color}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: ctx.dim))),
            HiddenAmount.forText(
              value,
              fontSize: 14,
              child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      );

  return showAppSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: goal.name.trim().isEmpty ? 'Цель · ${Fmt.money(goal.amount)}' : goal.name.trim(),
              subtitle: '${Fmt.money(goal.amount)} ${goalDeadlineText(goal.deadline)}',
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 14),
            if (p.monthsLeft > 0) ...[
              SizedBox(
                height: 170,
                child: CustomPaint(
                  painter: _GoalChartPainter(
                    withContrib: p.pathWith,
                    without: p.pathWithout,
                    target: goal.amount,
                    grid: ctx.hairline,
                  ),
                  size: Size.infinite,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                children: [
                  _legend(ctx, _gold, monthly > 0 ? 'с взносами ${Fmt.money(monthly)}/мес' : 'путь к цели', dashed: false),
                  _legend(ctx, AppColors.violet, 'без новых взносов', dashed: true),
                ],
              ),
              const SizedBox(height: 14),
            ],
            row(ctx, 'Сейчас', '${Fmt.money(p.current)} · ${(p.progress * 100).floor()}%'),
            if (!p.reached && p.monthsLeft > 0) ...[
              row(ctx, 'Без новых взносов к сроку', '≈${Fmt.money(p.withoutContributions)}'),
              row(ctx, 'Нужно вносить', monthly > 0 ? '≈${Fmt.money(monthly)}/мес' : 'не нужно', color: _gold),
            ],
            if (p.averageMonthly > 0) row(ctx, 'Вы вносили в среднем', '≈${Fmt.money(_round100(p.averageMonthly))}/мес'),
            const SizedBox(height: 4),
            Text(
              'Рост — по реалистичному сценарию прогноза стоимости (≈${p.annualGrowthPct.toStringAsFixed(1)}% годовых): '
              'купоны, погашения, дивиденды, рост акций. До налогов. Не гарантия.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showGoalEditSheet(context);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Изменить'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.negative),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: const Text('Удалить цель?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await GoalService.delete();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Удалить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _legend(BuildContext context, Color color, String text, {required bool dashed}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 3,
        decoration: BoxDecoration(
          color: dashed ? null : color,
          border: dashed ? Border(top: BorderSide(color: color, width: 2)) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 11.5, color: context.dim)),
    ],
  );
}

class _GoalChartPainter extends CustomPainter {
  final List<double> withContrib;
  final List<double> without;
  final double target;
  final Color grid;

  _GoalChartPainter({required this.withContrib, required this.without, required this.target, required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    if (withContrib.length < 2) return;
    final all = [...withContrib, ...without, target];
    final lo = all.reduce(math.min) * 0.95;
    final hi = all.reduce(math.max) * 1.05;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => i / (withContrib.length - 1) * size.width;

    void dashedH(double yy, Color c) {
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.4;
      for (double xx = 0; xx < size.width; xx += 10) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 6, size.width), yy), p);
      }
    }

    dashedH(y(target), _gold.withOpacity(0.9));

    Path pathOf(List<double> v) {
      final path = Path()..moveTo(x(0), y(v[0]));
      for (int i = 1; i < v.length; i++) {
        path.lineTo(x(i), y(v[i]));
      }
      return path;
    }

    // Без взносов — пунктиром.
    final dashPaint = Paint()
      ..color = AppColors.violet.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in pathOf(without).computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), dashPaint);
      }
    }
    canvas.drawPath(
      pathOf(withContrib),
      Paint()
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(x(0), y(withContrib.first)), 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GoalChartPainter old) =>
      old.target != target || old.withContrib.length != withContrib.length;
}
