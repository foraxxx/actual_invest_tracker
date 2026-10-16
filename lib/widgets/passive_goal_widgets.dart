import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/goal_service.dart';
import '../services/passive_goal_service.dart';
import '../services/payout_calendar_service.dart';
import 'goal_widgets.dart';
import 'payout_picker_sheet.dart';

const _green = AppColors.positive;

String _passiveTitle(PassivePlan p) {
  final target = '${Fmt.money(p.goal.monthly)}/мес';
  return p.goal.name.trim().isEmpty ? 'Пассивный доход · $target' : '${p.goal.name.trim()} · $target';
}

String _passiveSubtitle(PassivePlan p) {
  if (p.reached) return 'цель достигнута · ≈${Fmt.money(p.current)}/мес';
  final now = 'сейчас ≈${Fmt.money(p.current)}';
  final deadline = p.goal.deadline;
  if (deadline != null) {
    return p.savingEnough
        ? '${goalDeadlineText(deadline)} · успеваете'
        : '${goalDeadlineText(deadline)} · нужно ≈${Fmt.money(_round100(p.requiredMonthly ?? 0))}/мес';
  }
  final d = p.reachDate;
  if (d != null && p.saving > 0) return '$now · успеете ${goalDeadlineText(d)}';
  return '$now · докупить ≈${goalShortRub(p.toBuy)}';
}

double _round100(double v) => (v / 100).ceil() * 100.0;

/// Строка «как успеваете»: со сроком — сколько откладывать и хватает ли,
/// без срока — когда цель будет достигнута.
String _pace(PassivePlan p) {
  final d = p.reachDate;
  final deadline = p.goal.deadline;
  final req = p.requiredMonthly;
  if (deadline != null && req != null) {
    if (p.savingEnough) {
      return 'Откладываете ${Fmt.money(p.saving)}/мес — успеете${d == null ? '' : ' ${goalDeadlineText(d)}'}';
    }
    final gap = _round100(req - p.saving);
    return 'Чтобы успеть ${goalDeadlineText(deadline)}, нужно ≈${Fmt.money(_round100(req))}/мес — '
        '${p.saving > 0 ? 'не хватает ${Fmt.money(gap)}/мес' : 'укажите в цели, сколько откладываете'}'
        '${d != null && p.saving > 0 ? '. С вашими взносами — ${goalDeadlineText(d)}' : ''}';
  }
  if (p.saving <= 0) return 'Сколько откладываете, можно указать в цели';
  return d == null
      ? 'Откладываете ${Fmt.money(p.saving)}/мес — дольше 50 лет'
      : 'Откладываете ${Fmt.money(p.saving)}/мес — успеете ${goalDeadlineText(d)}';
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
                  goalShortRub(p.toBuy),
                  fontSize: 13.5,
                  child: Text(
                    'Докупить ≈${goalShortRub(p.toBuy)} под ${_pctText(p.newYieldPct)}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _green),
                  ),
                ),
                const SizedBox(height: 3),
                HiddenAmount.forText(
                  _pace(p),
                  fontSize: 11.5,
                  child: Text(_pace(p), style: TextStyle(fontSize: 11.5, height: 1.35, color: context.dim)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

String _pctText(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

/// Подробности цели «пассивный доход»: выплаты по месяцам на год вперёд
/// (клетки нажимаются), сколько докупить и когда успеете.
Future<void> showPassiveGoalDetailsSheet(BuildContext context) {
  if (GoalService.passive == null) return Future.value();
  PassiveGoalService.refreshInBackground();
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
          final first = p.months.isEmpty ? null : p.months.first.month;
          final last = p.months.isEmpty ? null : p.months.last.month;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: goal.name.trim().isEmpty ? 'Пассивный доход' : goal.name.trim(),
                    subtitle: '${Fmt.money(goal.monthly)}/мес · '
                        '${goal.mode == PassiveMode.average ? 'в среднем за год' : 'каждый месяц'}'
                        '${goal.deadline == null ? '' : ' · ${goalDeadlineText(goal.deadline!)}'}',
                    trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ),
                  const SizedBox(height: 12),
                  if (first != null && last != null)
                    Text(
                      'Выплаты ${monthNamesNom[first.month - 1]} ${first.year} — '
                      '${monthNamesNom[last.month - 1]} ${last.year} · доля от цели месяца',
                      style: TextStyle(fontSize: 12, color: ctx.dim),
                    ),
                  const SizedBox(height: 8),
                  _MonthGrid(
                    plan: p,
                    selected: selected,
                    onSelect: (i) => setSheet(() => selected = (selected == i ? null : i)),
                  ),
                  const SizedBox(height: 8),
                  Text(_gridSummary(p), style: TextStyle(fontSize: 11.5, color: ctx.dim)),
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

String _gridSummary(PassivePlan p) {
  final n = p.monthsReached;
  final w = p.weakest;
  final reached = n == 0
      ? 'Все месяцы ниже цели'
      : n == p.months.length
          ? 'Все месяцы выполняют цель'
          : 'Цель выполняют $n ${Fmt.plural(n, 'месяц', 'месяца', 'месяцев')} из ${p.months.length}';
  if (w == null || n == p.months.length) return reached;
  final pct = p.goal.monthly <= 0 ? 0 : (w.total / p.goal.monthly * 100).floor();
  return '$reached. Самый слабый — ${monthNamesNom[w.month.month - 1]}, $pct%';
}

/// Сетка 3×4: месяц, сумма, доля от цели месяца полоской и процентом. Ниже
/// цели — красным, выполнил — зелёным. Дивиденды по прошлому году
/// помечены «≈».
class _MonthGrid extends StatelessWidget {
  final PassivePlan plan;
  final int? selected;
  final ValueChanged<int> onSelect;

  const _MonthGrid({required this.plan, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final target = plan.goal.monthly;
    final rows = <Widget>[];
    for (int r = 0; r * 3 < plan.months.length; r++) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            for (int c = 0; c < 3; c++) ...[
              if (c > 0) const SizedBox(width: 6),
              Expanded(
                child: r * 3 + c < plan.months.length
                    ? _cell(context, r * 3 + c, plan.months[r * 3 + c], target)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _cell(BuildContext context, int index, PassiveMonth m, double target) {
    final share = target <= 0 ? 0.0 : m.total / target;
    final ok = share >= 1 - 1e-9;
    final color = ok ? _green : AppColors.negative;
    final isSelected = selected == index;
    final amount = '${m.estimatedTotal > 0 ? '≈' : ''}${Fmt.group(m.total)}';
    return Pressable(
      onTap: () => onSelect(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? (context.isDark ? Colors.white : Colors.black87) : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AdaptiveSingleLineText(
                    monthNamesNom[m.month.month - 1],
                    style: TextStyle(fontSize: 11, color: context.dim),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${(share * 100).floor()}%',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
            const SizedBox(height: 2),
            HiddenAmount.forText(
              amount,
              fontSize: 13,
              child: AdaptiveSingleLineText(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0).toDouble(),
                minHeight: 4,
                backgroundColor: context.hairline,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _row(BuildContext ctx, String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: ctx.dim))),
          const SizedBox(width: 8),
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
  final weakest = p.weakest;
  return [
    Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 4),
      decoration: _boxDeco(ctx),
      child: Column(
        children: [
          _row(ctx, 'Сейчас в среднем', '≈${Fmt.money(p.average)}/мес'),
          if (weakest != null)
            _row(ctx, 'Самый слабый месяц', '${monthNamesNom[weakest.month.month - 1]} · ${Fmt.money(weakest.total)}'),
          _row(ctx, 'Цель', '${Fmt.money(p.goal.monthly)}/мес'),
          if (p.couponTaxYear > 0.5)
            _row(ctx, 'Налог с купонов в конце года', '≈${Fmt.money(p.couponTaxYear)}'),
        ],
      ),
    ),
    const SizedBox(height: 8),
    if (!p.reached)
      Container(
        padding: const EdgeInsets.all(12),
        decoration: _boxDeco(ctx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Чтобы добрать ${Fmt.money(p.monthlyGap)}/мес', style: TextStyle(fontSize: 12, color: ctx.dim)),
            const SizedBox(height: 6),
            _row(ctx, 'Докупить под ${_pctText(p.newYieldPct)}', '≈${goalShortRub(p.toBuy)}'),
            Text(
              'Это ${Fmt.money(p.monthlyGap * 12)} в год ÷ ${_pctText(p.newYieldPct)}. '
              '${p.newYieldAuto ? 'Доходность — купон к цене по рынку облигаций, автоматически.' : 'Доходность — ваша, из цели.'} '
              'Нынешние выплаты остаются и учтены.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
            ),
          ],
        ),
      ),
    if (!p.reached) ...[
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: _boxDeco(ctx, fill: (p.savingEnough ? _green : AppColors.warning).withOpacity(0.08)),
        child: HiddenAmount.forText(
          _pace(p),
          fontSize: 12.5,
          child: Text(_pace(p), style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600)),
        ),
      ),
    ],
    const SizedBox(height: 8),
    Text(
      'Купоны — полной суммой, как приходят на счёт${p.iis ? ' (на ИИС налог с них не удерживается)' : '; налог с них брокер удержит в конце года'}. '
      'Дивиденды — после налога. Ещё не объявленные дивиденды — по прошлому году, со знаком «≈». '
      'Нажмите на месяц, чтобы увидеть его выплаты.',
      style: TextStyle(fontSize: 11, height: 1.4, color: ctx.dim),
    ),
  ];
}

List<Widget> _monthDetails(BuildContext outer, BuildContext ctx, PassivePlan p, PassiveMonth m) {
  final target = p.goal.monthly;
  final deficit = math.max(0.0, target - m.total);
  final name = monthNamesNom[m.month.month - 1];
  final title = '${name[0].toUpperCase()}${name.substring(1)} ${m.month.year}';
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
    // Надпись длинная — переносится на вторую строку, а не обрезается.
    GradientButton(
      label: 'Подобрать бумаги с выплатами в $monthIn',
      maxLines: 2,
      onPressed: () => showPayoutPickerSheet(outer, month: m.month, deficit: deficit),
    ),
  ];
}
