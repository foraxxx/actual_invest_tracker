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

/// Что раскрыто на экране цели: открыто всегда что-то одно.
enum _Open { none, have, buy, pace, month }

/// Подробности цели «пассивный доход».
///
/// Сверху — доход сейчас из цели, полоса «есть + докупить», строка «Успеете».
/// Ниже — месяцы: в режиме «в среднем» полоска квадратиков со строкой
/// выбранного месяца, в режиме «каждый месяц» — сетка с долей от цели.
/// Полоса, строка и месяцы нажимаются и раскрывают подробности на месте.
Future<void> showPassiveGoalDetailsSheet(BuildContext context) {
  if (GoalService.passive == null) return Future.value();
  PassiveGoalService.refreshInBackground();
  var open = _Open.none;
  int? month;
  return showAppSheet(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: GoalService.version,
      builder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final goal = GoalService.passive;
          if (goal == null) return const SizedBox.shrink();
          final p = PassiveGoalService.plan(goal);
          final average = goal.mode == PassiveMode.average;
          // По умолчанию выбран ближайший месяц с выплатой.
          month ??= _firstPaying(p);
          void toggle(_Open o) => setSheet(() => open = open == o ? _Open.none : o);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: goal.name.trim().isEmpty ? 'Пассивный доход' : goal.name.trim(),
                    subtitle: '${Fmt.money(goal.monthly)}/мес · '
                        '${average ? 'в среднем за год' : 'каждый месяц'}'
                        '${goal.deadline == null ? '' : ' · ${goalDeadlineText(goal.deadline!)}'}',
                    trailing: IconButton(
                      icon: const Icon(Icons.info_outline_rounded),
                      tooltip: 'Как считается',
                      onPressed: () => _showHowSheet(ctx, p),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _headline(ctx, p),
                  const SizedBox(height: 10),
                  if (!p.reached) ...[
                    _capitalBar(ctx, p, open, toggle),
                    if (open == _Open.have) _havePanel(ctx, p),
                    if (open == _Open.buy) _buyPanel(context, ctx, p),
                    const SizedBox(height: 8),
                    _paceRow(ctx, p, open == _Open.pace, () => toggle(_Open.pace)),
                    if (open == _Open.pace) _milestonesPanel(ctx, p),
                  ],
                  const SizedBox(height: 14),
                  if (average) ...[
                    _monthReadout(ctx, p, month, open == _Open.month, () => toggle(_Open.month)),
                    const SizedBox(height: 8),
                    _MonthStrip(
                      plan: p,
                      selected: month,
                      onSelect: (i) => setSheet(() => month = i),
                    ),
                  ] else ...[
                    _MonthGrid(
                      plan: p,
                      selected: open == _Open.month ? month : null,
                      onSelect: (i) => setSheet(() {
                        if (open == _Open.month && month == i) {
                          open = _Open.none;
                        } else {
                          month = i;
                          open = _Open.month;
                        }
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(_gridSummary(p), style: TextStyle(fontSize: 11.5, color: ctx.dim)),
                  ],
                  if (open == _Open.month && month != null && month! < p.months.length) ...[
                    const SizedBox(height: 10),
                    ..._monthPayouts(context, ctx, p, p.months[month!], withTitle: !average),
                  ],
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

int? _firstPaying(PassivePlan p) {
  for (int i = 0; i < p.months.length; i++) {
    if (p.months[i].total > 0.5) return i;
  }
  return p.months.isEmpty ? null : 0;
}

Widget _headline(BuildContext ctx, PassivePlan p) {
  final now = '≈${Fmt.money(p.current)}';
  return Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      HiddenAmount.forText(
        now,
        fontSize: 24,
        child: Text(now, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      ),
      const Spacer(),
      Text(
        p.reached
            ? 'цель достигнута'
            : 'из ${Fmt.money(p.goal.monthly)}/мес · ${(p.progress * 100).floor()}%',
        style: TextStyle(fontSize: 12.5, color: p.reached ? _green : ctx.dim),
      ),
    ],
  );
}

/// Полоса «Нужно в портфеле»: зелёное — что есть, штриховка — докупить.
/// Обе части нажимаются.
Widget _capitalBar(BuildContext ctx, PassivePlan p, _Open open, void Function(_Open) toggle) {
  final need = p.neededCapital;
  final haveShare = need <= 0 ? 1.0 : (p.value / need).clamp(0.02, 0.98).toDouble();
  final dimHave = open == _Open.buy;
  final dimBuy = open == _Open.have;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: _boxDeco(ctx),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Нужно в портфеле', style: TextStyle(fontSize: 12, color: ctx.dim))),
            HiddenAmount.forText(
              goalShortRub(need),
              fontSize: 13.5,
              child: Text('≈${goalShortRub(need)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 18,
          child: Row(
            children: [
              Expanded(
                flex: (haveShare * 1000).round(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => toggle(_Open.have),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: dimHave ? 0.35 : 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _green,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                        border: open == _Open.have ? Border.all(color: Colors.white, width: 2) : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: ((1 - haveShare) * 1000).round(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => toggle(_Open.buy),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: dimBuy ? 0.35 : 1,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                      child: CustomPaint(
                        painter: _StripesPainter(AppColors.info, outlined: open == _Open.buy),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            HiddenAmount.forText(
              goalShortRub(p.value),
              fontSize: 11.5,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: goalShortRub(p.value).replaceAll(' ₽', ''), style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' есть', style: TextStyle(color: ctx.dim)),
              ]), style: const TextStyle(fontSize: 11.5)),
            ),
            const Spacer(),
            HiddenAmount.forText(
              goalShortRub(p.toBuy),
              fontSize: 11.5,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: '+${goalShortRub(p.toBuy).replaceAll(' ₽', '')}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.info),
                ),
                TextSpan(text: ' докупить', style: TextStyle(color: ctx.dim)),
              ]), style: const TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StripesPainter extends CustomPainter {
  final Color color;
  final bool outlined;

  _StripesPainter(this.color, {this.outlined = false});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color.withOpacity(0.22));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    if (outlined) {
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => old.color != color || old.outlined != outlined;
}

Widget _panel(BuildContext ctx, Color border, List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

/// Что из того, что есть, уже платит выплаты.
Widget _havePanel(BuildContext ctx, PassivePlan p) {
  final paying = p.payingValue;
  final idle = math.max(0.0, p.value - paying);
  return _panel(ctx, _green, [
    Text('Из ${goalShortRub(p.value)} в портфеле', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    _row(ctx, 'Платят выплаты', '${goalShortRub(paying)} · ${_pctText(p.payingYieldPct)}'),
    Text('облигации и акции с дивидендами', style: TextStyle(fontSize: 11, color: ctx.dim)),
    const SizedBox(height: 8),
    _row(ctx, 'Не платят', goalShortRub(idle)),
    Text('фонды и акции без дивидендов — растут в цене, а не выплатами',
        style: TextStyle(fontSize: 11, color: ctx.dim)),
  ]);
}

/// Что даст докупка — и сразу к подбору облигаций с ежемесячным купоном.
Widget _buyPanel(BuildContext outer, BuildContext ctx, PassivePlan p) {
  final now = DateTime.now();
  return _panel(ctx, AppColors.info, [
    HiddenAmount.forText(
      goalShortRub(p.toBuy),
      fontSize: 13,
      child: Text(
        'Докупить ≈${goalShortRub(p.toBuy)} под ${_pctText(p.newYieldPct)}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    ),
    const SizedBox(height: 4),
    HiddenAmount.forText(
      Fmt.money(p.monthlyGap),
      fontSize: 11.5,
      child: Text(
        'Облигации на эту сумму добавят ≈${Fmt.money(p.monthlyGap)} в месяц. '
        '${_pctText(p.newYieldPct)} — купон к цене облигаций на бирже сейчас',
        style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
      ),
    ),
    const SizedBox(height: 10),
    GradientButton(
      label: 'Подобрать облигации с ежемесячным купоном',
      maxLines: 2,
      onPressed: () => showPayoutPickerSheet(
        outer,
        month: DateTime(now.year, now.month + 1),
        deficit: p.monthlyGap,
        monthlyOnly: true,
      ),
    ),
  ]);
}

Widget _paceRow(BuildContext ctx, PassivePlan p, bool selected, VoidCallback onTap) {
  final ok = p.savingEnough && p.reachDate != null;
  final color = ok ? _green : AppColors.warning;
  final d = p.reachDate;
  final deadline = p.goal.deadline;
  final req = p.requiredMonthly;
  final String title;
  if (deadline != null && req != null && !p.savingEnough) {
    title = 'Нужно ≈${Fmt.money(_round100(req))}/мес';
  } else if (d == null) {
    title = p.saving > 0 ? 'Дольше 50 лет' : 'Укажите, сколько откладываете';
  } else {
    title = 'Успеете ${goalDeadlineText(d)}';
  }
  final right = deadline != null && req != null && !p.savingEnough
      ? goalDeadlineText(deadline)
      : p.saving > 0
          ? '${Fmt.money(p.saving)}/мес'
          : '';
  return Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? (ctx.isDark ? Colors.white : Colors.black87) : Colors.transparent, width: 1.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: HiddenAmount.forText(
              title,
              fontSize: 13.5,
              child: AdaptiveSingleLineText(
                title,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          HiddenAmount.forText(
            right,
            fontSize: 12,
            child: Text(right, style: TextStyle(fontSize: 12, color: ctx.dim)),
          ),
          Icon(selected ? Icons.expand_less_rounded : Icons.chevron_right_rounded, size: 18, color: ctx.dim),
        ],
      ),
    ),
  );
}

/// Вехи: когда будет четверть, половина, три четверти и вся цель.
Widget _milestonesPanel(BuildContext ctx, PassivePlan p) {
  final now = DateTime.now();
  final items = <(String, String, String, bool)>[
    ('Сейчас', '≈${Fmt.money(p.current)}/мес', '${(p.progress * 100).floor()}%', true),
    for (final (share, months) in p.milestones())
      (
        share >= 1 ? 'Цель' : '${(share * 100).round()}%',
        '${Fmt.money(p.goal.monthly * share)}/мес',
        months == null
            ? 'дольше 50 лет'
            : months == 0
                ? 'уже'
                : '${monthNamesNom[DateTime(now.year, now.month + months).month - 1]} '
                    '${DateTime(now.year, now.month + months).year}',
        months == 0,
      ),
  ];
  return _panel(ctx, _green, [
    for (int i = 0; i < items.length; i++)
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 14,
              child: Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: items[i].$4 ? _green : Colors.transparent,
                      border: Border.all(color: _green, width: 2),
                    ),
                  ),
                  if (i < items.length - 1)
                    Expanded(child: Container(width: 2, color: _green.withOpacity(0.35))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: i < items.length - 1 ? 10 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(items[i].$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                        Text(items[i].$3, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    HiddenAmount.forText(
                      items[i].$2,
                      fontSize: 11,
                      child: Text(items[i].$2, style: TextStyle(fontSize: 11, color: ctx.dim)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
  ]);
}

/// Строка выбранного месяца над квадратиками: месяц, сумма, «выплаты ›».
Widget _monthReadout(BuildContext ctx, PassivePlan p, int? index, bool open, VoidCallback onTap) {
  if (index == null || index >= p.months.length) return const SizedBox.shrink();
  final m = p.months[index];
  final label = '${monthNamesNom[m.month.month - 1]} ${m.month.year}';
  final amount = m.total <= 0.5 ? 'выплат нет' : '${m.estimatedTotal > 0 ? '≈' : ''}${Fmt.money(m.total)}';
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      children: [
        Expanded(
          child: HiddenAmount.forText(
            amount,
            fontSize: 13.5,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$label · '),
              TextSpan(text: amount, style: TextStyle(color: m.total <= 0.5 ? ctx.dim : _green)),
            ]), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          ),
        ),
        Text('выплаты', style: TextStyle(fontSize: 12, color: ctx.dim)),
        Icon(open ? Icons.expand_less_rounded : Icons.chevron_right_rounded, size: 18, color: ctx.dim),
      ],
    ),
  );
}

/// 12 квадратиков месяцев без подписей: чем ярче — тем больше выплат.
/// Между декабрём и январём — разделитель, под ним годы.
class _MonthStrip extends StatelessWidget {
  final PassivePlan plan;
  final int? selected;
  final ValueChanged<int> onSelect;

  const _MonthStrip({required this.plan, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final months = plan.months;
    final maxTotal = months.fold(0.0, (m, x) => math.max(m, x.total));
    final empty = context.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh;
    final cells = <Widget>[];
    final yearLabels = <Widget>[];
    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      if (i > 0 && m.month.month == 1) {
        cells.add(Container(width: 1, height: 38, margin: const EdgeInsets.symmetric(horizontal: 2), color: context.dim));
      } else if (i > 0) {
        cells.add(const SizedBox(width: 3));
      }
      final isSel = selected == i;
      cells.add(Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 30,
            decoration: BoxDecoration(
              color: m.total <= 0.5
                  ? empty
                  : _green.withOpacity(0.2 + 0.7 * (maxTotal <= 0 ? 0 : m.total / maxTotal)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSel ? (context.isDark ? Colors.white : Colors.black87) : Colors.transparent,
                width: 1.6,
              ),
            ),
          ),
        ),
      ));
    }
    // Подписи годов: первый — под началом, следующий — под январём.
    final janIndex = months.indexWhere((m) => m.month.month == 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: cells),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (c, box) {
            final w = box.maxWidth / (months.isEmpty ? 1 : months.length);
            yearLabels
              ..clear()
              ..add(Positioned(
                left: 0,
                child: Text('${months.isEmpty ? '' : months.first.month.year}',
                    style: TextStyle(fontSize: 10, color: context.dim)),
              ));
            if (janIndex > 0) {
              yearLabels.add(Positioned(
                left: janIndex * w + 2,
                child: Text('${months[janIndex].month.year}', style: TextStyle(fontSize: 10, color: context.dim)),
              ));
            }
            return SizedBox(height: 13, child: Stack(children: yearLabels));
          },
        ),
      ],
    );
  }
}

/// Окно «Как считается» — все пояснения в одном месте.
Future<void> _showHowSheet(BuildContext context, PassivePlan p) {
  Widget part(BuildContext ctx, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$title — ', style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: text),
          ]),
          style: const TextStyle(fontSize: 13, height: 1.45),
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
              title: 'Как считается',
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 12),
            part(
              ctx,
              'Сейчас',
              p.goal.mode == PassiveMode.average
                  ? 'выплаты на 12 месяцев вперёд ÷ 12.'
                  : 'выплаты самого слабого месяца из следующих 12.',
            ),
            part(ctx, 'Выплаты',
                'купоны — полной суммой, как приходят на счёт; дивиденды — после налога. «≈» — дивиденды, '
                'которые компания ещё не объявила: по прошлому году.'),
            part(
              ctx,
              'Нужно в портфеле',
              'то, что есть, плюс докупка: недостающие ${Fmt.money(p.monthlyGap * 12)} в год ÷ '
                  '${_pctText(p.newYieldPct)}. ${_pctText(p.newYieldPct)} — купон к цене облигаций на бирже, '
                  'обновляется сам раз в сутки.',
            ),
            part(
              ctx,
              'Успеете',
              p.goal.deadline == null
                  ? 'когда портфель дорастёт до нужного с вашими взносами${p.saving > 0 ? ' ${Fmt.money(p.saving)}/мес' : ''}.'
                  : 'сколько откладывать в месяц, чтобы успеть к сроку, и хватает ли ваших взносов.',
            ),
            if (p.couponTaxYear > 0.5)
              Text(
                'Налог с купонов в конце года ≈${Fmt.money(p.couponTaxYear)} — брокер удержит его со счёта.',
                style: TextStyle(fontSize: 12, height: 1.4, color: ctx.dim),
              )
            else if (p.iis)
              Text('На ИИС налог с купонов не удерживается.', style: TextStyle(fontSize: 12, color: ctx.dim)),
          ],
        ),
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

/// Выплаты месяца по бумагам и подбор бумаг на этот месяц. В режиме
/// «каждый месяц» сверху ещё итог месяца против цели.
List<Widget> _monthPayouts(BuildContext outer, BuildContext ctx, PassivePlan p, PassiveMonth m, {required bool withTitle}) {
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
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 4),
      decoration: _boxDeco(ctx),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (withTitle) ...[
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
                HiddenAmount.forText(
                  Fmt.money(m.total),
                  fontSize: 13.5,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: Fmt.group(m.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' из ${Fmt.money(target)}', style: TextStyle(color: ctx.dim)),
                  ]), style: const TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 9),
          ],
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text('Выплат в этом месяце не ожидается', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
            ),
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
