import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/goal_service.dart';
import '../services/passive_goal_service.dart';

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

/// Короткая сумма для тесных мест: «5,43 млн», «540 тыс», «900 ₽».
String goalShort(double v, {bool unit = true}) {
  final abs = v.abs();
  if (abs >= 1000000) {
    var t = (v / 1000000).toStringAsFixed(abs >= 100000000 ? 0 : 2);
    if (t.contains('.')) t = t.replaceFirst(RegExp(r'\.?0+$'), '');
    return unit ? '${t.replaceAll('.', ',')} млн' : t.replaceAll('.', ',');
  }
  if (abs >= 1000) return unit ? '${(v / 1000).round()} тыс' : '${(v / 1000).round()}';
  return Fmt.money(v);
}

/// То же с рублём: «2,54 млн ₽», «540 тыс ₽», «900 ₽».
String goalShortRub(double v) => v.abs() >= 1000 ? '${goalShort(v)} ₽' : Fmt.money(v);

/// «≈5,43 млн из 7» — сколько будет к сроку из суммы цели.
String goalWillHave(GoalPlan p) {
  final will = p.atDeadlineWithSaving;
  final sameMln = will.abs() >= 1000000 && p.goal.amount.abs() >= 1000000;
  return '≈${goalShort(will)} из ${goalShort(p.goal.amount, unit: !sameMln)}';
}

/// Главная мысль цели одной строкой — для свёрнутой карточки.
String goalAdvice(GoalPlan p) {
  if (p.reached) return 'цель достигнута';
  if (p.overdue) return 'срок прошёл · осталось ${Fmt.money(p.remaining)}';
  final deadline = goalDeadlineText(p.goal.deadline);
  if (p.monthly <= 0.5) {
    final d = p.reachWithoutDate;
    return d == null ? '$deadline · успеваете и без взносов' : '$deadline · без взносов — ${goalDeadlineText(d)}';
  }
  if (p.savingEnough) {
    final d = p.reachDate;
    return d == null ? '$deadline · успеваете' : '$deadline · успеете ${goalDeadlineText(d)}';
  }
  return '$deadline · будет ${goalWillHave(p)}';
}

double _round100(double v) => (v / 100).ceil() * 100.0;

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
    final subtitle = goalAdvice(p);

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
                if (collapsed && !p.reached)
                  HiddenAmount.forText(
                    subtitle,
                    fontSize: 11.5,
                    child: AdaptiveSingleLineText(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.dim),
                    ),
                  )
                else
                  AdaptiveSingleLineText(
                    p.reached ? subtitle : '${goalDeadlineText(p.goal.deadline)} · осталось ${monthsText(p.monthsLeft)}',
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
            child: _advice(context, p, color),
          ),
        ],
      ],
    );
  }
}

/// Совет в развёрнутой карточке: хватает ли того, что человек откладывает.
Widget _advice(BuildContext context, GoalPlan p, Color color) {
  final title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color);
  final dim = TextStyle(fontSize: 11.5, height: 1.35, color: context.dim);
  final growth = 'с ростом по прогнозу ≈${p.annualGrowthPct.toStringAsFixed(0)}% годовых';

  Widget line(String text, TextStyle style) => HiddenAmount.forText(
        text,
        fontSize: style.fontSize,
        child: Text(text, style: style),
      );

  final lines = <Widget>[];
  if (p.overdue) {
    lines.add(Text('Срок прошёл — цель можно продлить', style: title));
  } else if (p.monthly <= 0.5) {
    lines
      ..add(Text(
        p.reachWithoutDate == null
            ? 'Успеваете и без новых взносов'
            : 'Без новых взносов — примерно ${goalDeadlineText(p.reachWithoutDate!)}',
        style: title,
      ))
      ..add(const SizedBox(height: 3))
      ..add(Text(growth, style: dim));
  } else if (p.savingEnough) {
    final d = p.reachDate;
    lines
      ..add(line(
        'Откладываете ${Fmt.money(p.saving)}/мес — успеете${d == null ? '' : ' ${goalDeadlineText(d)}'}',
        title,
      ))
      ..add(const SizedBox(height: 3))
      ..add(Text(growth, style: dim));
  } else {
    final need = _round100(p.monthly);
    final pct = p.goal.amount <= 0 ? 0 : (p.atDeadlineWithSaving / p.goal.amount * 100).floor();
    final d = p.reachDate;
    lines
      ..add(line('Нужно ≈${Fmt.money(need)}/мес', title))
      ..add(const SizedBox(height: 3))
      ..add(line(
        p.saving > 0
            ? 'откладываете ${Fmt.money(p.saving)} — не хватает ${Fmt.money(_round100(p.savingShortfall))}'
            : 'сколько откладываете, можно указать в цели',
        dim,
      ))
      ..add(line(
        '${_capital(goalDeadlineText(p.goal.deadline))} накопите ≈${Fmt.money((p.atDeadlineWithSaving / 1000).round() * 1000.0)} — $pct% цели',
        dim,
      ));
    if (d != null && p.saving > 0) lines.add(line('С вашими взносами цель — ${goalDeadlineText(d)}', dim));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
}

/// Вид финансовой цели.
enum GoalKind { sum, passive }

/// Постановка или правка цели. [kind] — какой вид открыть; без него, если
/// целей ещё нет, сверху есть выбор «Накопить сумму / Пассивный доход».
Future<void> showGoalEditSheet(BuildContext context, {GoalKind? kind}) {
  final existing = GoalService.current;
  final existingPassive = GoalService.passive;
  // Цель у портфеля одна: либо накопить сумму, либо пассивный доход. Вид
  // можно сменить прямо в форме — прежняя цель при сохранении заменится.
  const allowSwitch = true;
  var goalKind = kind ?? (existing == null && existingPassive != null ? GoalKind.passive : GoalKind.sum);
  final incomeCtrl = TextEditingController(
    text: existingPassive == null ? '' : existingPassive.monthly.toStringAsFixed(0),
  );
  final passiveNameCtrl = TextEditingController(text: existingPassive?.name ?? '');
  var passiveMode = existingPassive?.mode ?? PassiveMode.average;
  DateTime? passiveDeadline = existingPassive?.deadline;
  PassiveGoalService.refreshInBackground();
  final amountCtrl = TextEditingController(
    text: existing == null ? '' : existing.amount.toStringAsFixed(0),
  );
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final suggested = GoalService.suggestedMonthlySaving();
  final initialSaving = (goalKind == GoalKind.passive ? existingPassive?.monthlySaving : existing?.monthlySaving) ??
      suggested;
  final savingCtrl = TextEditingController(text: initialSaving > 0 ? initialSaving.toStringAsFixed(0) : '');
  final now = DateTime.now();
  var month = existing?.deadline.month ?? 12;
  var year = existing?.deadline.year ?? now.year + 2;
  String? error;

  const monthNames = [
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];

  double? parseText(String t) => double.tryParse(t.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.'));
  double? parse() => parseText(amountCtrl.text);
  double? parseSaving() {
    final v = parseText(savingCtrl.text);
    return v == null || v < 0 ? null : v;
  }

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        if (goalKind == GoalKind.passive) {
          return _passiveForm(
            ctx,
            keyboard: keyboard,
            allowSwitch: allowSwitch,
            onSwitch: (k) => setSheet(() => goalKind = k),
            incomeCtrl: incomeCtrl,
            savingCtrl: savingCtrl,
            nameCtrl: passiveNameCtrl,
            suggested: suggested,
            mode: passiveMode,
            onMode: (m) => setSheet(() => passiveMode = m),
            deadline: passiveDeadline,
            onDeadline: (d) => setSheet(() => passiveDeadline = d),
            onChanged: () => setSheet(() => error = null),
            error: error,
            parseText: parseText,
            onError: (e) => setSheet(() => error = e),
          );
        }
        final amount = parse();
        final preview = amount != null && amount > 0
            ? GoalService.plan(FinancialGoal(
                amount: amount,
                deadline: DateTime(year, month),
                monthlySaving: parseSaving() ?? 0,
              ))
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
              if (allowSwitch) ...[
                const SizedBox(height: 12),
                _kindToggle(GoalKind.sum, (k) => setSheet(() => goalKind = k)),
              ],
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
              AppTextField(
                controller: savingCtrl,
                label: 'Откладываю в месяц, ₽',
                number: true,
                onChanged: (_) => setSheet(() {}),
              ),
              if (suggested > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'По вашим пополнениям за полгода — обычно ≈${Fmt.money(suggested)} в месяц',
                  style: TextStyle(fontSize: 11.5, color: ctx.dim),
                ),
              ],
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
                            '${preview.monthsLeft <= 0 ? 'Срок уже наступил.' : preview.monthly <= 0.5 ? 'Успеваете и без новых взносов${preview.reachWithoutDate == null ? '' : ' — примерно ${goalDeadlineText(preview.reachWithoutDate!)}'}.' : 'Чтобы успеть, нужно вносить ≈${Fmt.money(_round100(preview.monthly))} в месяц.'}'
                            '${preview.monthsLeft > 0 && preview.monthly > 0.5 ? (preview.savingEnough ? '\nС вашими взносами успеете${preview.reachDate == null ? '' : ' ${goalDeadlineText(preview.reachDate!)}'}.' : '\nС вашими взносами к сроку будет ${goalWillHave(preview)}.') : ''}',
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
                  await GoalService.save(FinancialGoal(
                    amount: a,
                    deadline: DateTime(year, month),
                    name: nameCtrl.text.trim(),
                    monthlySaving: parseSaving() ?? 0,
                  ));
                  // Цель одна — прежняя цель по доходу заменяется.
                  await GoalService.savePassive(null);
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

const _monthNom = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

Widget _kindToggle(GoalKind selected, ValueChanged<GoalKind> onChanged) => SegmentedToggle<GoalKind>(
      values: GoalKind.values,
      selected: selected,
      labelOf: (k) => k == GoalKind.sum ? 'Накопить сумму' : 'Пассивный доход',
      onChanged: onChanged,
    );

/// Форма цели «пассивный доход».
Widget _passiveForm(
  BuildContext ctx, {
  required double keyboard,
  required bool allowSwitch,
  required ValueChanged<GoalKind> onSwitch,
  required TextEditingController incomeCtrl,
  required TextEditingController savingCtrl,
  required TextEditingController nameCtrl,
  required double suggested,
  required PassiveMode mode,
  required ValueChanged<PassiveMode> onMode,
  required DateTime? deadline,
  required ValueChanged<DateTime?> onDeadline,
  required VoidCallback onChanged,
  required String? error,
  required double? Function(String) parseText,
  required ValueChanged<String> onError,
}) {
  final income = parseText(incomeCtrl.text);
  final saving = parseText(savingCtrl.text);
  final preview = income != null && income > 0
      ? PassiveGoalService.plan(PassiveGoal(
          monthly: income,
          mode: mode,
          monthlySaving: saving == null || saving < 0 ? 0 : saving,
          deadline: deadline,
        ))
      : null;
  final now = DateTime.now();
  String previewText(PassivePlan p) {
    final cur = '≈${Fmt.money(p.current)}/мес';
    if (p.reached) return 'Сейчас $cur — цель уже достигнута.';
    final d = p.reachDate;
    final req = p.requiredMonthly;
    return 'Сейчас $cur — это ${(p.progress * 100).floor()}%. '
        'Докупить ≈${goalShortRub(p.toBuy)}.'
        '${req != null && p.goal.deadline != null ? '\nЧтобы успеть ${goalDeadlineText(p.goal.deadline!)}, откладывать ≈${Fmt.money(_round100(req))}/мес.' : ''}'
        '${d != null && p.saving > 0 ? '\nОткладывая ${Fmt.money(p.saving)}/мес, дойдёте ${goalDeadlineText(d)}.' : ''}';
  }

  return SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Финансовая цель',
          subtitle: 'Какой доход в месяц хотите получать выплатами',
          trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
        ),
        if (allowSwitch) ...[
          const SizedBox(height: 12),
          _kindToggle(GoalKind.passive, onSwitch),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: incomeCtrl,
          label: 'Доход в месяц, ₽',
          number: true,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        Text('Как считать', style: TextStyle(fontSize: 12, color: ctx.dim)),
        const SizedBox(height: 6),
        SegmentedToggle<PassiveMode>(
          values: PassiveMode.values,
          selected: mode,
          labelOf: (m) => m == PassiveMode.average ? 'В среднем за год' : 'Каждый месяц',
          onChanged: onMode,
        ),
        const SizedBox(height: 6),
        Text(
          mode == PassiveMode.average
              ? 'Выплаты за год ÷ 12. Купоны и дивиденды приходят неравномерно — так обычно и считают пассивный доход.'
              : 'Даже в самый слабый месяц — не меньше цели. Нужно намного больше вложений.',
          style: TextStyle(fontSize: 11.5, height: 1.35, color: ctx.dim),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppDropdown<int>(
                value: deadline?.month ?? 0,
                label: 'Срок: месяц',
                items: [
                  const DropdownMenuItem(value: 0, child: Text('без срока')),
                  for (int i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(_monthNom[i - 1])),
                ],
                onChanged: (v) => onDeadline(
                  v == null || v == 0 ? null : DateTime(deadline?.year ?? now.year + 5, v),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: AppDropdown<int>(
                value: deadline?.year ?? 0,
                label: 'год',
                items: [
                  const DropdownMenuItem(value: 0, child: Text('—')),
                  for (int y = now.year; y <= now.year + 40; y++) DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => onDeadline(v == null || v == 0 ? null : DateTime(v, deadline?.month ?? 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          deadline == null ? 'Без срока — покажу, когда цель будет достигнута' : 'Посчитаю, сколько откладывать, чтобы успеть',
          style: TextStyle(fontSize: 11.5, color: ctx.dim),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: savingCtrl,
          label: 'Откладываю в месяц, ₽',
          number: true,
          onChanged: (_) => onChanged(),
        ),
        if (suggested > 0) ...[
          const SizedBox(height: 4),
          Text(
            'По вашим пополнениям за полгода — обычно ≈${Fmt.money(suggested)} в месяц',
            style: TextStyle(fontSize: 11.5, color: ctx.dim),
          ),
        ],
        const SizedBox(height: 12),
        AppTextField(controller: nameCtrl, label: 'Название (необязательно)', hint: 'Например, «Вторая зарплата»'),
        if (preview != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.positive.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(previewText(preview), style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
        ],
        const SizedBox(height: 18),
        GradientButton(
          label: 'Сохранить цель',
          icon: Icons.check_rounded,
          onPressed: () async {
            final i = parseText(incomeCtrl.text);
            if (i == null || i <= 0) {
              onError('Укажите доход в месяц');
              return;
            }
            final sv = parseText(savingCtrl.text);
            if (deadline != null && deadline.isBefore(DateTime(now.year, now.month))) {
              onError('Срок уже прошёл — выберите месяц позже');
              return;
            }
            await GoalService.savePassive(PassiveGoal(
              monthly: i,
              mode: mode,
              monthlySaving: sv == null || sv < 0 ? 0 : sv,
              name: nameCtrl.text.trim(),
              deadline: deadline,
            ));
            // Цель одна — прежняя цель накопить сумму заменяется.
            await GoalService.delete();
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ],
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
                    needed: p.monthly > 0.5 ? p.pathWith : const [],
                    saving: p.saving > 0 ? p.pathSaving : const [],
                    without: p.pathWithout,
                    target: goal.amount,
                    grid: ctx.hairline,
                    hidden: AppearanceService.amountsHidden,
                  ),
                  size: Size.infinite,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                children: [
                  if (monthly > 0) _legend(ctx, _gold, 'нужно ${Fmt.money(monthly)}/мес', dashed: false),
                  if (p.saving > 0) _legend(ctx, _savingColor, 'ваши ${Fmt.money(p.saving)}/мес', dashed: false),
                  _legend(ctx, AppColors.violet, 'без взносов', dashed: true),
                ],
              ),
              const SizedBox(height: 14),
            ],
            row(ctx, 'Сейчас', '${Fmt.money(p.current)} · ${(p.progress * 100).floor()}%'),
            if (!p.reached && p.monthsLeft > 0) ...[
              if (monthly > 0) _savingScale(ctx, p, monthly) else row(ctx, 'Нужно вносить', 'не нужно', color: _gold),
              // Успевает и без взносов — показываем, когда примерно.
              if (monthly <= 0 && p.reachWithoutDate != null)
                row(ctx, 'Без взносов цель', 'примерно ${goalDeadlineText(p.reachWithoutDate!)}'),
              if (monthly > 0 && p.reachDate != null && p.saving > 0)
                row(ctx, 'С вашими взносами цель', goalDeadlineText(p.reachDate!)),
            ],
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

/// Шкала взноса: сколько из нужного в месяц человек уже откладывает.
Widget _savingScale(BuildContext context, GoalPlan p, double needed) {
  final enough = p.savingEnough;
  final share = needed <= 0 ? 1.0 : (p.saving / needed).clamp(0.0, 1.0).toDouble();
  final color = enough ? AppColors.positive : _savingColor;
  final top = '${Fmt.group(p.saving)} из ${Fmt.money(needed)}';
  final bottom = enough
      ? 'хватает, чтобы успеть'
      : p.saving > 0
          ? 'не хватает ${Fmt.money(_round100(p.savingShortfall))}/мес'
          : 'укажите в цели, сколько откладываете';
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
    decoration: BoxDecoration(
      color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Взнос в месяц', style: TextStyle(fontSize: 12.5, color: context.dim))),
            HiddenAmount.forText(
              top,
              fontSize: 14,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: Fmt.group(p.saving)),
                  TextSpan(
                    text: ' из ${Fmt.money(needed)}',
                    style: TextStyle(color: context.dim, fontWeight: FontWeight.w600),
                  ),
                ]),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 9,
            backgroundColor: context.hairline,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              '${(share * 100).floor()}% нужного',
              style: TextStyle(fontSize: 11.5, color: context.dim),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: HiddenAmount.forText(
                  bottom,
                  fontSize: 11.5,
                  child: AdaptiveSingleLineText(
                    bottom,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: enough
                          ? AppColors.positive
                          : p.saving > 0
                              ? AppColors.negative
                              : context.dim,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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

const _savingColor = AppColors.info;

class _GoalChartPainter extends CustomPainter {
  /// Нужный путь к цели (с нужными взносами). Пусто — успеваете и так.
  final List<double> needed;

  /// Путь с тем, что человек откладывает. Пусто — взносы не указаны.
  final List<double> saving;
  final List<double> without;
  final double target;
  final Color grid;
  final bool hidden;

  _GoalChartPainter({
    required this.needed,
    required this.saving,
    required this.without,
    required this.target,
    required this.grid,
    required this.hidden,
  });

  static const _labelSpace = 66.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (without.length < 2) return;
    // Справа оставляем место под подписи сумм у концов линий.
    final w = size.width - _labelSpace;
    final all = [...needed, ...saving, ...without, target];
    final lo = all.reduce(math.min) * 0.95;
    final hi = all.reduce(math.max) * 1.05;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => i / (without.length - 1) * w;

    final dashH = Paint()
      ..color = _gold.withOpacity(0.9)
      ..strokeWidth = 1.4;
    for (double xx = 0; xx < w; xx += 10) {
      canvas.drawLine(Offset(xx, y(target)), Offset(math.min(xx + 6, w), y(target)), dashH);
    }

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
    Paint solid(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    if (needed.length > 1) canvas.drawPath(pathOf(needed), solid(_gold, 2.6));
    if (saving.length > 1) canvas.drawPath(pathOf(saving), solid(_savingColor, 2.4));
    canvas.drawCircle(Offset(x(0), y(without.first)), 4.5, Paint()..color = Colors.white);

    // Подписи у концов линий: цель, с вашими взносами, без взносов. Если
    // концы рядом, подписи раздвигаются, чтобы не налезать друг на друга.
    final labels = <({double value, String text, Color color})>[
      (value: target, text: goalShort(target), color: _gold),
      if (saving.length > 1 && (saving.last - target).abs() > (hi - lo) * 0.02)
        (value: saving.last, text: '≈${goalShort(saving.last)}', color: _savingColor),
      (value: without.last, text: '≈${goalShort(without.last)}', color: AppColors.violet),
    ];
    final painters = [
      for (final l in labels)
        TextPainter(
          text: TextSpan(
            text: hidden ? '•••' : l.text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: l.color),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: _labelSpace - 6),
    ];
    final order = List.generate(labels.length, (i) => i)..sort((a, b) => y(labels[a].value).compareTo(y(labels[b].value)));
    final tops = List<double>.filled(labels.length, 0);
    const gap = 2.0;
    double prevBottom = -double.infinity;
    for (final i in order) {
      final h = painters[i].height;
      var top = (y(labels[i].value) - h / 2).clamp(0.0, size.height - h).toDouble();
      if (top < prevBottom + gap) top = prevBottom + gap;
      tops[i] = top;
      prevBottom = top + h;
    }
    // Если вылезли за низ — сдвигаем всю стопку вверх.
    final overflow = prevBottom - size.height;
    if (overflow > 0) {
      for (int i = 0; i < tops.length; i++) {
        tops[i] = math.max(0, tops[i] - overflow);
      }
    }
    for (int i = 0; i < labels.length; i++) {
      painters[i].paint(canvas, Offset(w + 6, tops[i]));
    }
  }

  @override
  bool shouldRepaint(_GoalChartPainter old) =>
      old.target != target ||
      old.hidden != hidden ||
      old.needed.length != needed.length ||
      old.saving.length != saving.length ||
      old.without.length != without.length;
}
