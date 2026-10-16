import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/goal_service.dart';
import '../services/passive_goal_service.dart';
import '../services/payout_calendar_service.dart';
import 'goal_widgets.dart';
import 'payout_picker_sheet.dart';

const _green = AppColors.positive;

/// Тонкая строка «+ Цель …» под карточкой цели — чтобы поставить вторую цель
/// другого вида.
class GoalAddLine extends StatelessWidget {
  final GoalKind kind;

  const GoalAddLine({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => showGoalEditSheet(context, kind: kind),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 16, color: context.dim),
            const SizedBox(width: 4),
            Text(
              kind == GoalKind.passive ? 'Цель по пассивному доходу' : 'Цель накопить сумму',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
            ),
          ],
        ),
      ),
    );
  }
}

String _passiveTitle(PassivePlan p) {
  final target = '${Fmt.money(p.goal.monthly)}/мес';
  return p.goal.name.trim().isEmpty ? 'Пассивный доход · $target' : '${p.goal.name.trim()} · $target';
}

String _passiveSubtitle(PassivePlan p) {
  if (p.reached) return 'цель достигнута · ≈${Fmt.money(p.current)}/мес';
  final now = 'сейчас ≈${Fmt.money(p.current)}';
  final d = p.reachDate;
  if (d != null && p.saving > 0) return '$now · успеете ${goalDeadlineText(d)}';
  final need = p.shortfall;
  return need == null ? now : '$now · ещё ≈${goalShortRub(need)} вложений';
}

/// Карточка цели «пассивный доход» на главной. Сворачивается так же, как
/// карточка цели «накопить сумму».
class PassiveGoalCard extends StatelessWidget {
  final PassivePlan plan;
  final bool collapsed;
  final VoidCallback onToggle;

  const PassiveGoalCard({super.key, required this.plan, required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final title = _passiveTitle(p);
    final subtitle = _passiveSubtitle(p);
    final percent = '${(p.progress * 100).floor()}%';

    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: _green.withOpacity(0.15), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.savings_outlined, size: 18, color: _green),
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
                HiddenAmount.forText(
                  subtitle,
                  fontSize: 11.5,
                  child: AdaptiveSingleLineText(
                    collapsed ? subtitle : (p.goal.mode == PassiveMode.average ? 'в среднем за год' : 'каждый месяц'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.dim),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(percent, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _green)),
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
        border: Border.all(color: collapsed ? context.hairline : _green.withOpacity(0.35), width: 1.1),
        gradient: collapsed
            ? LinearGradient(
                colors: [_green.withOpacity(0.16), _green.withOpacity(0.16), base, base],
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
                    onTap: () => showPassiveGoalDetailsSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _expanded(context, p),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context, PassivePlan p) {
    final now = '≈${Fmt.money(p.current)}';
    final need = p.shortfall;
    final d = p.reachDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: p.progress,
            minHeight: 9,
            backgroundColor: context.hairline,
            valueColor: const AlwaysStoppedAnimation(_green),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            HiddenAmount.forText(
              now,
              fontSize: 12.5,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: now, style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' /мес сейчас', style: TextStyle(color: context.dim)),
              ]), style: const TextStyle(fontSize: 12.5)),
            ),
            const Spacer(),
            Text(
              p.goal.mode == PassiveMode.average ? 'в среднем за год' : 'в самый слабый месяц',
              style: TextStyle(fontSize: 11.5, color: context.dim),
            ),
          ],
        ),
        if (!p.reached) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: _green.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HiddenAmount.forText(
                  need == null ? '' : goalShortRub(need),
                  fontSize: 13.5,
                  child: Text(
                    need == null
                        ? 'Пока нет выплат — расчёт появится с ними'
                        : 'Не хватает ≈${goalShortRub(need)} вложений',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _green),
                  ),
                ),
                if (need != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    p.saving > 0
                        ? d == null
                            ? 'Откладываете ${Fmt.money(p.saving)}/мес — дольше 50 лет'
                            : 'Откладываете ${Fmt.money(p.saving)}/мес — успеете ${goalDeadlineText(d)}'
                        : 'Сколько откладываете, можно указать в цели',
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: context.dim),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Подробности цели «пассивный доход»: выплаты по месяцам на год вперёд
/// (столбики нажимаются), сколько нужно вложить и когда дойдёте.
Future<void> showPassiveGoalDetailsSheet(BuildContext context) {
  if (GoalService.passive == null) return Future.value();
  int? selected;
  return showAppSheet(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: GoalService.version,
      builder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final goal = GoalService.passive;
          if (goal == null) return const SizedBox.shrink();
          final p = PassiveGoalService.plan(goal);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: goal.name.trim().isEmpty ? 'Пассивный доход' : goal.name.trim(),
                    subtitle: '${Fmt.money(goal.monthly)}/мес · '
                        '${goal.mode == PassiveMode.average ? 'в среднем за год' : 'каждый месяц'}',
                    trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ),
                  const SizedBox(height: 12),
                  if (p.months.isNotEmpty)
                    Text(
                      'Выплаты ${monthNamesNom[p.months.first.month.month - 1]} ${p.months.first.month.year} — '
                      '${monthNamesNom[p.months.last.month.month - 1]} ${p.months.last.month.year}',
                      style: TextStyle(fontSize: 12, color: ctx.dim),
                    ),
                  const SizedBox(height: 8),
                  _PassiveBars(
                    plan: p,
                    selected: selected,
                    onSelect: (i) => setSheet(() => selected = (selected == i ? null : i)),
                  ),
                  const SizedBox(height: 4),
                  _monthLabels(ctx, p),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _legend(ctx, _green, 'купоны и объявленные дивиденды'),
                      _legend(ctx, _green, 'дивиденды по прошлому году', hatched: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selected != null && selected! < p.months.length)
                    ..._monthDetails(context, ctx, p, p.months[selected!])
                  else
                    ..._summary(ctx, p),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            showGoalEditSheet(context, kind: GoalKind.passive);
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
                            if (ctx.mounted) Navigator.pop(ctx);
                            await GoalService.savePassive(null);
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
          );
        },
      ),
    ),
  );
}

Widget _legend(BuildContext ctx, Color color, String text, {bool hatched = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CustomPaint(painter: _SwatchPainter(color, hatched)),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 11, color: ctx.dim)),
      ],
    );

class _SwatchPainter extends CustomPainter {
  final Color color;
  final bool hatched;

  _SwatchPainter(this.color, this.hatched);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    if (!hatched) {
      canvas.drawRRect(r, Paint()..color = color);
      return;
    }
    canvas.drawRRect(r, Paint()..color = color.withOpacity(0.25));
    canvas.save();
    canvas.clipRRect(r);
    _hatch(canvas, Offset.zero & size, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.hatched != hatched;
}

void _hatch(Canvas canvas, Rect rect, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.6;
  for (double x = rect.left - rect.height; x < rect.right; x += 5) {
    canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), paint);
  }
}

Widget _monthLabels(BuildContext ctx, PassivePlan p) {
  // Полные названия — каждый третий месяц, чтобы помещались.
  return LayoutBuilder(
    builder: (c, box) {
      final n = p.months.length;
      if (n == 0) return const SizedBox.shrink();
      final w = box.maxWidth / n;
      return SizedBox(
        height: 14,
        child: Stack(
          children: [
            for (int i = 0; i < n; i += 3)
              Positioned(
                left: i * w,
                child: Text(
                  monthNamesNom[p.months[i].month.month - 1],
                  style: TextStyle(fontSize: 10.5, color: ctx.dim),
                ),
              ),
          ],
        ),
      );
    },
  );
}

Widget _row(BuildContext ctx, String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: ctx.dim))),
          HiddenAmount.forText(
            value,
            fontSize: 13.5,
            child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      ),
    );

BoxDecoration _boxDeco(BuildContext ctx, {Color? fill}) => BoxDecoration(
      color: fill ?? (ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh),
      borderRadius: BorderRadius.circular(12),
    );

List<Widget> _summary(BuildContext ctx, PassivePlan p) {
  final need = p.neededCapital;
  final short = p.shortfall;
  final d = p.reachDate;
  final weakest = p.weakest;
  final sumGoal = GoalService.current;
  return [
    Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 4),
      decoration: _boxDeco(ctx),
      child: Column(
        children: [
          _row(ctx, 'Сейчас в среднем', '≈${Fmt.money(p.average)}/мес'),
          if (weakest != null)
            _row(
              ctx,
              'Самый слабый месяц',
              '${monthNamesNom[weakest.month.month - 1]} · ${Fmt.money(weakest.total)}',
            ),
          _row(ctx, 'Доходность выплат', '${p.yieldPct.toStringAsFixed(1).replaceAll('.', ',')}% в год'),
        ],
      ),
    ),
    const SizedBox(height: 8),
    if (need != null)
      Container(
        padding: const EdgeInsets.all(12),
        decoration: _boxDeco(ctx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Сколько нужно вложить', style: TextStyle(fontSize: 12, color: ctx.dim)),
            const SizedBox(height: 6),
            _row(ctx, 'Для ${Fmt.money(p.goal.monthly)}/мес', '≈${goalShortRub(need)}'),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (p.value / need).clamp(0.0, 1.0).toDouble(),
                minHeight: 9,
                backgroundColor: ctx.hairline,
                valueColor: const AlwaysStoppedAnimation(_green),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: HiddenAmount.forText(
                    goalShortRub(p.value),
                    fontSize: 11.5,
                    child: Text('в портфеле ${goalShortRub(p.value)}', style: TextStyle(fontSize: 11.5, color: ctx.dim)),
                  ),
                ),
                if (short != null && short > 0.5)
                  HiddenAmount.forText(
                    goalShortRub(short),
                    fontSize: 11.5,
                    child: Text(
                      'не хватает ≈${goalShortRub(short)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.negative),
                    ),
                  )
                else
                  const Text('хватает',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _green)),
              ],
            ),
          ],
        ),
      )
    else
      Text('Пока выплат в прогнозе нет — посчитать, сколько вложить, нельзя.',
          style: TextStyle(fontSize: 12.5, color: ctx.dim)),
    if (need != null && !p.reached) ...[
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 4),
        decoration: _boxDeco(ctx),
        child: _row(
          ctx,
          p.saving > 0 ? 'Откладываете ${Fmt.money(p.saving)}/мес' : 'Без новых взносов',
          d == null ? 'дольше 50 лет' : goalDeadlineText(d),
        ),
      ),
    ],
    if (sumGoal != null && p.current > 0) ...[
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: _boxDeco(ctx, fill: AppColors.gold.withOpacity(0.08)),
        child: HiddenAmount.forText(
          goalShortRub(sumGoal.amount),
          fontSize: 12.5,
          child: Text(
            'Когда накопите ${goalShortRub(sumGoal.amount)} (цель ${goalDeadlineText(sumGoal.deadline)}), '
            'пассивный доход будет ≈${Fmt.money(p.incomeAt(sumGoal.amount))}/мес',
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ),
    ],
    const SizedBox(height: 8),
    Text(
      'Расчёт — по нынешнему составу портфеля: купоны и дивиденды по прогнозу, после налога 13%. '
      'Дивиденды, которые компании ещё не объявили, — по прошлому году (штриховка). '
      'Если реинвестировать выплаты, дойдёте раньше. Нажмите на месяц, чтобы увидеть его выплаты.',
      style: TextStyle(fontSize: 11, height: 1.4, color: ctx.dim),
    ),
  ];
}

List<Widget> _monthDetails(BuildContext outer, BuildContext ctx, PassivePlan p, PassiveMonth m) {
  final target = p.goal.monthly;
  final deficit = math.max(0.0, target - m.total);
  final title = '${monthNamesNom[m.month.month - 1][0].toUpperCase()}${monthNamesNom[m.month.month - 1].substring(1)} '
      '${m.month.year}';
  final items = <(String, double, bool)>[
    for (final e in m.sure.entries) (e.key, e.value, false),
    for (final e in m.estimated.entries) (e.key, e.value, true),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  final monthIn = monthNamesIn[m.month.month - 1];
  return [
    Container(
      padding: const EdgeInsets.all(12),
      decoration: _boxDeco(ctx),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              HiddenAmount.forText(
                Fmt.money(m.total),
                fontSize: 14,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: Fmt.group(m.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: ' из ${Fmt.money(target)}', style: TextStyle(color: ctx.dim)),
                ]), style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: target <= 0 ? 0 : (m.total / target).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: ctx.hairline,
              valueColor: AlwaysStoppedAnimation(deficit > 0.5 ? AppColors.negative : _green),
            ),
          ),
          const SizedBox(height: 7),
          HiddenAmount.forText(
            Fmt.money(deficit),
            fontSize: 12,
            child: Text(
              deficit > 0.5 ? 'не хватает ${Fmt.money(deficit)} в этом месяце' : 'в этом месяце цель выполнена',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: deficit > 0.5 ? AppColors.negative : _green,
              ),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 4),
      decoration: _boxDeco(ctx),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text('Выплат в этом месяце не ожидается', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
            )
          : Column(
              children: [
                for (final it in items)
                  _row(
                    ctx,
                    '${PayoutCalendarService.nameOf(it.$1)}${it.$3 ? ' · по прошлому году' : ''}',
                    '${it.$3 ? '≈' : ''}${Fmt.money(it.$2)}',
                  ),
              ],
            ),
    ),
    const SizedBox(height: 10),
    GradientButton(
      label: 'Подобрать бумаги с выплатами в $monthIn',
      icon: Icons.search_rounded,
      onPressed: () => showPayoutPickerSheet(outer, month: m.month, deficit: deficit),
    ),
  ];
}

/// Столбики выплат по месяцам. Нажатие или ведение пальцем выбирает месяц.
class _PassiveBars extends StatelessWidget {
  final PassivePlan plan;
  final int? selected;
  final ValueChanged<int> onSelect;

  const _PassiveBars({required this.plan, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (c, box) {
        final n = plan.months.length;
        int indexAt(double dx) => n == 0 ? 0 : (dx / box.maxWidth * n).floor().clamp(0, n - 1);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onSelect(indexAt(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) {
            final i = indexAt(d.localPosition.dx);
            if (i != selected) onSelect(i);
          },
          child: SizedBox(
            height: 130,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarsPainter(
                months: plan.months,
                target: plan.goal.monthly,
                average: plan.average,
                selected: selected,
                everyMonth: plan.goal.mode == PassiveMode.everyMonth,
                hidden: AppearanceService.amountsHidden,
                textColor: context.isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<PassiveMonth> months;
  final double target;
  final double average;
  final int? selected;
  final bool everyMonth;
  final bool hidden;
  final Color textColor;

  _BarsPainter({
    required this.months,
    required this.target,
    required this.average,
    required this.selected,
    required this.everyMonth,
    required this.hidden,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    final maxValue = [target, average, ...months.map((m) => m.total)].reduce(math.max) * 1.12;
    if (maxValue <= 0) return;
    double y(double v) => size.height - v / maxValue * size.height;
    final slot = size.width / months.length;
    const gap = 4.0;

    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final dim = selected != null && selected != i;
      final below = everyMonth && m.total < target - 0.5;
      final base = below ? AppColors.negative : _green;
      final color = dim ? base.withOpacity(0.35) : base;
      final left = i * slot + gap / 2;
      final right = (i + 1) * slot - gap / 2;
      // Известная часть — снизу сплошная, оценка — сверху штриховкой.
      final sureTop = y(m.sureTotal);
      final allTop = y(m.total);
      if (m.sureTotal > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, sureTop, right, size.height),
            topLeft: Radius.circular(m.estimatedTotal > 0 ? 0 : 3),
            topRight: Radius.circular(m.estimatedTotal > 0 ? 0 : 3),
          ),
          Paint()..color = color,
        );
      }
      if (m.estimatedTotal > 0) {
        final rect = Rect.fromLTRB(left, allTop, right, sureTop);
        final rr = RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
        canvas.drawRRect(rr, Paint()..color = color.withOpacity(dim ? 0.1 : 0.25));
        canvas.save();
        canvas.clipRRect(rr);
        _hatch(canvas, rect, color);
        canvas.restore();
      }
      if (selected == i) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(left - 1.5, allTop - 1.5, right + 1.5, size.height), const Radius.circular(4)),
          Paint()
            ..color = textColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    void dashed(double value, Color c, String label) {
      final yy = y(value);
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.4;
      for (double x = 0; x < size.width; x += 9) {
        canvas.drawLine(Offset(x, yy), Offset(math.min(x + 5, size.width), yy), p);
      }
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width, math.max(0, yy - tp.height - 1)));
    }

    dashed(target, _green, 'цель ${hidden ? '•••' : Fmt.group(target)}');
    // Линия среднего — если она не сливается с линией цели.
    if ((average - target).abs() / maxValue > 0.08) {
      dashed(average, textColor.withOpacity(0.7), '≈${hidden ? '•••' : Fmt.group(average)}');
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.selected != selected ||
      old.target != target ||
      old.average != average ||
      old.months.length != months.length ||
      old.hidden != hidden ||
      old.everyMonth != everyMonth;
}
