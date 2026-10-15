import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/iis_service.dart';
import '../services/portfolio_service.dart';
import 'goal_widgets.dart' show monthsText;

const _blue = AppColors.info;

/// Дней до 31 декабря включительно.
int _daysLeftInYear([DateTime? now]) {
  final today = now ?? DateTime.now();
  final d = DateTime(today.year, today.month, today.day);
  return DateTime(today.year, 12, 31).difference(d).inDays + 1;
}

int _monthsBetween(DateTime from, DateTime to) =>
    math.max(0, (to.year - from.year) * 12 + to.month - from.month - (to.day < from.day ? 1 : 0));

/// Карточка ИИС на главной — только у портфеля, отмеченного как ИИС.
///
/// Свёрнутая — одна строка, залитая синим на долю внесённого за год (как
/// цель — золотым). Развёрнутая — взносы, вычет и срок счёта.
class IisCard extends StatelessWidget {
  final IisSettings settings;
  final bool collapsed;
  final VoidCallback onToggle;

  const IisCard({super.key, required this.settings, required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final y = IisService.yearSummary(settings, year);
    final done = y.limitReached;
    final color = done ? AppColors.positive : _blue;
    final days = _daysLeftInYear();
    final percent = '${(y.progress * 100).floor()}%';
    final withDeduction = settings.type.hasContributionDeduction;

    final title = collapsed
        ? (done
            ? 'ИИС · лимит $year выбран'
            : 'ИИС · ${Fmt.money(y.contributed)} из ${Fmt.money(y.limit)}')
        : 'ИИС · взносы $year';
    final subtitle = collapsed
        ? (withDeduction
            ? (done
                ? 'вычет ≈${Fmt.money(y.deduction)} — подайте декларацию в ${year + 1}'
                : 'вычет ≈${Fmt.money(y.deduction)} · $days ${Fmt.plural(days, 'день', 'дня', 'дней')} до конца года')
            : 'лимит взносов · $days ${Fmt.plural(days, 'день', 'дня', 'дней')} до конца года')
        : '$days ${Fmt.plural(days, 'день', 'дня', 'дней')} до конца года';

    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(11)),
            child: Icon(done ? Icons.verified_rounded : Icons.account_balance_rounded, size: 18, color: color),
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
                AdaptiveSingleLineText(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!done) Text(percent, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
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
        gradient: collapsed
            ? LinearGradient(
                colors: [color.withOpacity(0.18), color.withOpacity(0.18), base, base],
                stops: [0, y.progress, y.progress, 1],
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
                    onTap: () => showIisDetailsSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _expanded(context, y, color),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context, IisYear y, Color color) {
    final withDeduction = settings.type.hasContributionDeduction;
    final contributed = Fmt.money(y.contributed);
    final termEnd = IisService.minTermEnd(settings);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: y.progress,
            minHeight: 9,
            backgroundColor: context.hairline,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            HiddenAmount.forText(
              contributed,
              fontSize: 16,
              child: Text(contributed, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            Text(
              withDeduction ? 'из ${Fmt.money(y.limit)} для вычета' : 'из ${Fmt.money(y.limit)} лимита',
              style: TextStyle(fontSize: 11.5, color: context.dim),
            ),
          ],
        ),
        if (withDeduction) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Вычет за ${y.year}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                      text: '≈${Fmt.money(y.deduction)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.positive),
                    ),
                  ]),
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  y.limitReached
                      ? 'Лимит выбран — подайте декларацию в ${y.year + 1}'
                      : 'Внесите ещё ${Fmt.money(y.leftToLimit)} до 31 декабря — будет ${Fmt.money(y.maxDeduction)}',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: context.dim),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Text('До минимального срока', style: TextStyle(fontSize: 12, color: context.dim))),
            Text(
              termEnd.isAfter(now) ? '${monthsText(_monthsBetween(now, termEnd))} · ${Fmt.date(termEnd)}' : 'пройден',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (withDeduction) ...[
          const SizedBox(height: 6),
          Text(
            'Вычет — не больше НДФЛ, уплаченного вами за год',
            style: TextStyle(fontSize: 10.5, color: context.dim),
          ),
        ],
      ],
    );
  }
}

/// Отметка «Это ИИС» для портфеля: тип, дата открытия, ставка вычета.
Future<void> showIisSettingsSheet(BuildContext context, PortfolioMeta portfolio) {
  final existing = IisService.settingsFor(portfolio.id);
  var isIis = existing != null;
  var type = existing?.type ?? IisType.newType;
  var opened = existing?.openedAt ?? DateTime.now();
  var rate = existing?.ratePct ?? 13;

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'ИИС',
              subtitle: portfolio.name,
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isIis,
              onChanged: (v) => setSheet(() => isIis = v),
              title: const Text('Это ИИС', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('На главной появится карточка: взносы за год, вычет и срок счёта'),
            ),
            if (isIis) ...[
              const SizedBox(height: 8),
              Text('Тип счёта', style: TextStyle(fontSize: 12, color: ctx.dim)),
              const SizedBox(height: 6),
              SegmentedToggle<IisType>(
                values: IisType.values,
                selected: type,
                labelOf: (t) => t.title,
                onChanged: (t) => setSheet(() => type = t),
              ),
              const SizedBox(height: 12),
              AppDateField(
                value: opened,
                label: 'Дата открытия',
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
                onPicked: (d) => setSheet(() => opened = d),
              ),
              if (type.hasContributionDeduction) ...[
                const SizedBox(height: 12),
                Text('Ставка вычета', style: TextStyle(fontSize: 12, color: ctx.dim)),
                const SizedBox(height: 6),
                SegmentedToggle<int>(
                  values: const [13, 15],
                  selected: rate,
                  labelOf: (r) => '$r%',
                  onChanged: (r) => setSheet(() => rate = r),
                ),
                const SizedBox(height: 6),
                Text(
                  '15% — если ваш доход за год больше 2,4 млн ₽. Вычет возвращается по той ставке, '
                  'по которой вы платили налог.',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: ctx.dim),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Правила ИИС — по данным на 2026 год: вычет со взносов до 400 000 ₽ в год; '
                'у нового ИИС минимальный срок 5 лет для открытых в 2024–2026 годах, у старого — 3 года. '
                'Точные условия уточняйте у брокера.',
                style: TextStyle(fontSize: 11, height: 1.35, color: ctx.dim),
              ),
            ],
            const SizedBox(height: 18),
            GradientButton(
              label: 'Сохранить',
              icon: Icons.check_rounded,
              onPressed: () async {
                await IisService.save(
                  portfolio.id,
                  isIis ? IisSettings(type: type, openedAt: opened, ratePct: rate) : null,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Подробности ИИС: взносы по месяцам текущего года, итоги по годам, срок.
Future<void> showIisDetailsSheet(BuildContext context) {
  final s = IisService.current;
  if (s == null) return Future.value();
  final byMonth = IisService.contributionsByMonth();
  final year = DateTime.now().year;
  final months = byMonth.entries.where((e) => e.key.year == year).toList()..sort((a, b) => a.key.compareTo(b.key));
  final maxMonth = months.fold(0.0, (m, e) => math.max(m, e.value));
  final termEnd = IisService.minTermEnd(s);
  final withDeduction = s.type.hasContributionDeduction;

  Widget box(BuildContext ctx, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
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
              title: PortfolioService.active.name,
              subtitle: 'ИИС · ${s.type.short} · открыт ${Fmt.date(s.openedAt)}',
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 14),
            Text('Взносы $year по месяцам', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
            const SizedBox(height: 8),
            if (months.isEmpty)
              Text('В этом году взносов пока не было', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
            for (final e in months)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(Fmt.monthShort(e.key.month), style: TextStyle(fontSize: 12, color: ctx.dim)),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (c, box) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: maxMonth <= 0 ? 0 : box.maxWidth * e.value / maxMonth,
                            height: 8,
                            decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    HiddenAmount.forText(
                      Fmt.money(e.value),
                      fontSize: 12,
                      child: Text(Fmt.money(e.value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text('По годам', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
            const SizedBox(height: 8),
            for (final y in IisService.years(s).reversed)
              () {
                final sum = IisService.yearSummary(s, y, byMonth: byMonth);
                final text = withDeduction
                    ? '${Fmt.money(sum.contributed)} · вычет ${y == year ? '≈' : ''}${Fmt.money(sum.deduction)}'
                    : Fmt.money(sum.contributed);
                return box(
                  ctx,
                  Row(
                    children: [
                      Text('$y', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      HiddenAmount.forText(
                        text,
                        fontSize: 13,
                        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                );
              }(),
            const SizedBox(height: 8),
            box(
              ctx,
              Row(
                children: [
                  Expanded(child: Text('Закрыть без потери льгот', style: TextStyle(fontSize: 12.5, color: ctx.dim))),
                  Text('после ${Fmt.date(termEnd)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (s.type != IisType.oldA)
              box(
                ctx,
                Row(
                  children: [
                    Expanded(child: Text('Доход по счёту', style: TextStyle(fontSize: 12.5, color: ctx.dim))),
                    const Text(
                      'без налога',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.positive),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Взносы — ваши пополнения портфеля, как в «Вложено». Вычет — ориентир: не больше НДФЛ, '
              'уплаченного вами за год. Правила ИИС — по данным на 2026 год, уточняйте у брокера.',
              style: TextStyle(fontSize: 11, height: 1.4, color: ctx.dim),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                showIisSettingsSheet(context, PortfolioService.active);
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Настройки ИИС'),
            ),
          ],
        ),
      ),
    ),
  );
}
