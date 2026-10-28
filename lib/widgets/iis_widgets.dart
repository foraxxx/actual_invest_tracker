import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/iis_service.dart';
import '../services/tax_service.dart';
import 'tax_widgets.dart';
import '../services/portfolio_service.dart';
import '../services/storage_service.dart';
import '../models/deposit.dart';
import 'package:uuid/uuid.dart';
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
    final pending = IisService.pendingYears(settings);
    final pendingText = _pendingText(pending);

    final title = collapsed
        ? (done
            ? (withDeduction ? 'ИИС · максимальный вычет за $year' : 'ИИС · лимит взносов $year достигнут')
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
                  child: AdaptiveSingleLineText(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 1),
                // Если за прошлый год вычет не отмечен — напоминание вместо
                // обычной строки.
                AdaptiveSingleLineText(
                  collapsed && pendingText != null
                      ? '$pendingText · $days ${Fmt.plural(days, 'день', 'дня', 'дней')} до конца года'
                      : subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: collapsed && pendingText != null ? AppColors.warning : context.dim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!done) Text(percent, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
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
                      child: _expanded(context, y, color, pending),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context, IisYear y, Color color, List<IisYear> pending) {
    final received = IisService.totalReceived(settings);
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
              child: Text(contributed, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.positive),
                    ),
                  ]),
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  y.limitReached
                      ? 'Внесено достаточно для максимального вычета ${Fmt.money(y.maxDeduction)} — подайте декларацию в ${y.year + 1}'
                      : 'Внесите ещё ${Fmt.money(y.leftToLimit)} до 31 декабря — будет ${Fmt.money(y.maxDeduction)}',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: context.dim),
                ),
              ],
            ),
          ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PendingPlaque(pending: pending),
        ],
        if (received > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('Получено вычетов', style: TextStyle(fontSize: 12, color: context.dim))),
              HiddenAmount.forText(
                Fmt.money(received),
                fontSize: 13,
                child: Text(
                  Fmt.money(received),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.positive),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _IisTaxBlock(settings: settings, termEnd: termEnd, now: now),
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

/// «вычет за 2027 ждёт декларации» / «вычеты за 2 года ждут декларации».
String? _pendingText(List<IisYear> pending) {
  if (pending.isEmpty) return null;
  if (pending.length == 1) return 'вычет за ${pending.first.year} ждёт декларации';
  final n = pending.length;
  return 'вычеты за $n ${Fmt.plural(n, 'год', 'года', 'лет')} ждут декларации';
}

/// Жёлтая плашка-напоминание в развёрнутой карточке: один год — сразу
/// кнопка «Получен», несколько — одна общая строка и переход в подробности.
class _PendingPlaque extends StatelessWidget {
  final List<IisYear> pending;

  const _PendingPlaque({required this.pending});

  @override
  Widget build(BuildContext context) {
    final single = pending.length == 1;
    final sum = pending.fold(0.0, (a, y) => a + y.deduction);
    final title = single
        ? 'Вычет за ${pending.first.year} ждёт декларации'
        : 'Вычеты за ${pending.length} ${Fmt.plural(pending.length, 'год', 'года', 'лет')} ждут декларации';
    final sub = single ? '${Fmt.money(sum)} · пришёл? отметьте' : '${Fmt.money(sum)} · отметьте в подробностях';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning)),
                const SizedBox(height: 2),
                HiddenAmount.forText(
                  sub,
                  fontSize: 11.5,
                  child: Text(sub, style: TextStyle(fontSize: 11.5, color: context.dim)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: BorderSide(color: _blue.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 34),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => single
                ? showIisReceivedSheet(context, pending.first)
                : showIisDetailsSheet(context),
            child: Text(single ? 'Получен' : 'Отметить', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Отметка «вычет за год получен»: сколько пришло, когда и — для новой
/// отметки — внести ли эти деньги обратно в портфель пополнением.
Future<void> showIisReceivedSheet(BuildContext context, IisYear year) {
  final s = IisService.current;
  if (s == null) return Future.value();
  final existing = s.received[year.year];
  final amountCtrl = TextEditingController(
    text: (existing?.amount ?? year.deduction).toStringAsFixed(0),
  );
  DateTime? date = existing?.date ?? DateTime.now();
  var addDeposit = false;
  String? error;

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Вычет за ${year.year}',
              subtitle: 'По расчёту — ${Fmt.money(year.deduction)}',
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: amountCtrl,
              label: 'Сколько пришло, ₽',
              number: true,
              onChanged: (_) {
                if (error != null) setSheet(() => error = null);
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Меньше расчёта — если НДФЛ за год уплачено меньше',
              style: TextStyle(fontSize: 11.5, color: ctx.dim),
            ),
            const SizedBox(height: 12),
            AppDateField(
              value: date,
              label: 'Когда пришёл (необязательно)',
              firstDate: DateTime(year.year),
              lastDate: DateTime.now(),
              onPicked: (d) => setSheet(() => date = d),
            ),
            // Пополнение добавляется только при новой отметке — иначе при
            // правке появлялись бы повторные пополнения.
            if (existing == null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: addDeposit,
                onChanged: (v) => setSheet(() => addDeposit = v),
                title: const Text('Внести обратно в портфель', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Добавит пополнение на эту сумму с этой датой. Оно засчитается во взносы '
                  '${(date ?? DateTime.now()).year} года',
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: 'Сохранить',
              icon: Icons.check_rounded,
              onPressed: () async {
                final amount = double.tryParse(
                  amountCtrl.text.replaceAll(' ', '').replaceAll('\u00a0', '').replaceAll(',', '.'),
                );
                if (amount == null || amount <= 0) {
                  setSheet(() => error = 'Укажите сумму');
                  return;
                }
                await IisService.setReceived(year.year, IisReceived(amount: amount, date: date));
                if (addDeposit) {
                  await StorageService.addDeposit(Deposit(
                    id: const Uuid().v4(),
                    date: date ?? DateTime.now(),
                    amount: amount,
                    note: 'Вычет ИИС за ${year.year}',
                  ));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            if (existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.negative),
                onPressed: () async {
                  await IisService.setReceived(year.year, null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Снять отметку'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Черновик настроек ИИС в форме, пока их не сохранили.
class _IisDraft {
  bool isIis;
  IisType type;
  DateTime opened;
  int rate;

  /// Отметки о полученных вычетах — форма их не показывает, но и не теряет.
  final Map<int, IisReceived> received;

  _IisDraft(IisSettings? s)
      : isIis = s != null,
        type = s?.type ?? IisType.newType,
        opened = s?.openedAt ?? DateTime.now(),
        rate = s?.ratePct ?? 13,
        received = s?.received ?? const {};

  IisSettings? get settings =>
      isIis ? IisSettings(type: type, openedAt: opened, ratePct: rate, received: received) : null;
}

/// Переключатель «Это ИИС» и, если включён, тип, дата открытия и ставка.
/// Общие для формы нового портфеля и настроек ИИС существующего.
List<Widget> _iisFields(BuildContext ctx, StateSetter setSheet, _IisDraft d) => [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: d.isIis,
        onChanged: (v) => setSheet(() => d.isIis = v),
        title: const Text('Это ИИС', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('На главной появится карточка: взносы за год, вычет и срок счёта'),
      ),
      if (d.isIis) ...[
        const SizedBox(height: 8),
        Text('Тип счёта', style: TextStyle(fontSize: 12, color: ctx.dim)),
        const SizedBox(height: 6),
        SegmentedToggle<IisType>(
          values: IisType.values,
          selected: d.type,
          labelOf: (t) => t.title,
          onChanged: (t) => setSheet(() => d.type = t),
        ),
        const SizedBox(height: 12),
        AppDateField(
          value: d.opened,
          label: 'Дата открытия',
          firstDate: DateTime(2015),
          lastDate: DateTime.now(),
          onPicked: (v) => setSheet(() => d.opened = v),
        ),
        if (d.type.hasContributionDeduction) ...[
          const SizedBox(height: 8),
          Text(
            'Вычет считается по ставке НДФЛ из настроек налога (13% или 15%).',
            style: TextStyle(fontSize: 11.5, height: 1.35, color: ctx.dim),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Правила ИИС — по данным на 2026 год: вычет со взносов до 400 000 ₽ в год; '
          'у нового ИИС минимальный срок 5 лет для открытых в 2024–2026 годах и на год больше '
          'за каждый следующий год, у старого — 3 года. Точные условия уточняйте у брокера.',
          style: TextStyle(fontSize: 11, height: 1.35, color: ctx.dim),
        ),
      ],
    ];

/// Отметка «Это ИИС» для портфеля: тип, дата открытия, ставка вычета.
Future<void> showIisSettingsSheet(BuildContext context, PortfolioMeta portfolio) {
  final draft = _IisDraft(IisService.settingsFor(portfolio.id));

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
            ..._iisFields(ctx, setSheet, draft),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Сохранить',
              icon: Icons.check_rounded,
              onPressed: () async {
                await IisService.save(portfolio.id, draft.settings);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Новый портфель: название и сразу — ИИС ли это. Всё сохраняется одной
/// кнопкой. Возвращает созданный портфель или null, если форму закрыли.
Future<PortfolioMeta?> showNewPortfolioSheet(BuildContext context) {
  final nameCtrl = TextEditingController();
  final draft = _IisDraft(null);
  String? error;

  return showAppSheet<PortfolioMeta>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Новый портфель',
              subtitle: 'Своя история сделок, выплат и планов',
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: nameCtrl,
              label: 'Название',
              hint: 'Например, «Брокерский» или «ИИС»',
              autofocus: true,
              onChanged: (_) {
                if (error != null) setSheet(() => error = null);
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
            ],
            const SizedBox(height: 6),
            ..._iisFields(ctx, setSheet, draft),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Создать',
              icon: Icons.add_rounded,
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setSheet(() => error = 'Введите название');
                  return;
                }
                final meta = await PortfolioService.create(name);
                final iis = draft.settings;
                if (iis != null) await IisService.save(meta.id, iis);
                if (ctx.mounted) Navigator.pop(ctx, meta);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Подробности ИИС: взносы по месяцам текущего года, вычеты по годам, срок.
Future<void> showIisDetailsSheet(BuildContext context) {
  if (IisService.current == null) return Future.value();
  var showAll = false;

  return showAppSheet(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      // Отметка «вычет получен» меняет список сразу, не закрывая окно.
      valueListenable: IisService.version,
      builder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final s = IisService.current;
          if (s == null) return const SizedBox.shrink();
          return _IisDetails(
            settings: s,
            showAll: showAll,
            onShowAll: () => setSheet(() => showAll = true),
            outerContext: context,
          );
        },
      ),
    ),
  );
}

const _monthNames = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

class _IisDetails extends StatelessWidget {
  final IisSettings settings;
  final bool showAll;
  final VoidCallback onShowAll;
  final BuildContext outerContext;

  const _IisDetails({
    required this.settings,
    required this.showAll,
    required this.onShowAll,
    required this.outerContext,
  });

  Widget _box(BuildContext ctx, Widget child, {Color? border, Color? fill}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: fill ?? (ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh),
          borderRadius: BorderRadius.circular(12),
          border: border == null ? null : Border.all(color: border),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext ctx) {
    final s = settings;
    final byMonth = IisService.contributionsByMonth();
    final year = DateTime.now().year;
    final months = byMonth.entries.where((e) => e.key.year == year).toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxMonth = months.fold(0.0, (m, e) => math.max(m, e.value));
    final termEnd = IisService.minTermEnd(s);
    final withDeduction = s.type.hasContributionDeduction;
    final totalReceived = IisService.totalReceived(s);

    // Годы: текущий, все с неотмеченным вычетом и два последних полученных.
    // Остальные — под «Показать все годы», чтобы через 10 лет не было ленты.
    final allYears = IisService.years(s).reversed.toList();
    final summaries = {for (final y in allYears) y: IisService.yearSummary(s, y, byMonth: byMonth)};
    bool isPending(int y) => withDeduction && y < year && !s.received.containsKey(y) && summaries[y]!.deduction > 0.5;
    final shownReceived = allYears.where((y) => s.received.containsKey(y)).take(2).toSet();
    final visible = showAll
        ? allYears
        : allYears.where((y) => y == year || isPending(y) || shownReceived.contains(y)).toList();
    final hiddenCount = allYears.length - visible.length;

    Widget yearRow(int y) {
      final sum = summaries[y]!;
      final received = s.received[y];
      final String status;
      final Color? statusColor;
      final String line;
      Widget? trailing;
      Color? border;
      if (!withDeduction) {
        status = y == year ? ' · идёт год' : '';
        statusColor = null;
        line = sum.contributed > 0 ? 'внесено ${Fmt.money(sum.contributed)}' : 'взносов не было';
      } else if (y == year) {
        status = ' · идёт год';
        statusColor = null;
        line = 'внесено ${Fmt.money(sum.contributed)} из ${Fmt.money(sum.limit)}';
        trailing = Text(
          '≈${Fmt.money(sum.deduction)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _blue),
        );
      } else if (received != null) {
        status = ' · ✓ получен';
        statusColor = AppColors.positive;
        line = 'пришло ${Fmt.money(received.amount)}${received.date == null ? '' : ' · ${Fmt.date(received.date!)}'}';
        trailing = const Icon(Icons.check_rounded, color: AppColors.positive, size: 20);
      } else if (sum.deduction > 0.5) {
        status = ' · подайте декларацию';
        statusColor = AppColors.warning;
        line = 'внесено ${Fmt.money(sum.contributed)} · вычет ${Fmt.money(sum.deduction)}';
        border = AppColors.warning.withOpacity(0.35);
        trailing = OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _blue,
            side: BorderSide(color: _blue.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 34),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => showIisReceivedSheet(ctx, sum),
          child: const Text('Получен', style: TextStyle(fontWeight: FontWeight.w700)),
        );
      } else {
        status = '';
        statusColor = null;
        line = 'взносов не было';
        trailing = Text('—', style: TextStyle(fontSize: 13, color: ctx.dim));
      }
      final row = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$y', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (status.isNotEmpty)
                      TextSpan(
                        text: status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: statusColor == null ? FontWeight.w500 : FontWeight.w700,
                          color: statusColor ?? ctx.dim,
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 3),
                HiddenAmount.forText(
                  line,
                  fontSize: 12,
                  child: Text(line, style: TextStyle(fontSize: 12, color: ctx.dim)),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      );
      // Полученный год можно открыть и поправить или снять отметку.
      return received != null && withDeduction
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showIisReceivedSheet(ctx, sum),
              child: _box(ctx, row),
            )
          : _box(ctx, row, border: border);
    }

    return SafeArea(
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
                      width: 74,
                      child: Text(_monthNames[e.key.month - 1], style: TextStyle(fontSize: 12, color: ctx.dim)),
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
            Text(withDeduction ? 'Вычеты по годам' : 'По годам', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
            const SizedBox(height: 8),
            for (final y in visible) yearRow(y),
            if (hiddenCount > 0)
              TextButton(
                onPressed: onShowAll,
                child: Text('Показать все годы ($hiddenCount)'),
              ),
            if (withDeduction && totalReceived > 0)
              _box(
                ctx,
                Row(
                  children: [
                    Expanded(child: Text('Всего получено', style: TextStyle(fontSize: 13, color: ctx.dim))),
                    HiddenAmount.forText(
                      Fmt.money(totalReceived),
                      fontSize: 14,
                      child: Text(
                        Fmt.money(totalReceived),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.positive),
                      ),
                    ),
                  ],
                ),
                fill: AppColors.positive.withOpacity(0.08),
              ),
            const SizedBox(height: 8),
            _box(
              ctx,
              Row(
                children: [
                  Expanded(child: Text('Закрыть без потери льгот', style: TextStyle(fontSize: 12.5, color: ctx.dim))),
                  Text('после ${Fmt.date(termEnd)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (s.type != IisType.oldA)
              _box(
                ctx,
                Row(
                  children: [
                    Expanded(
                      child: Text('Купоны и продажи', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
                    ),
                    const Text(
                      'без налога после срока',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.positive),
                    ),
                  ],
                ),
              ),
            Builder(builder: (_) {
              final tax = TaxService.taxIfClosedNow();
              if (tax <= 0.5) return const SizedBox.shrink();
              final early = s.type != IisType.oldA;
              return _box(
                ctx,
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(early ? 'Налог при досрочном закрытии' : 'Налог при закрытии счёта',
                              style: TextStyle(fontSize: 12.5, color: ctx.dim)),
                          Text('${(TaxService.rate * 100).round()}% с купонов и прибыли от продаж',
                              style: TextStyle(fontSize: 10.5, color: ctx.dim)),
                        ],
                      ),
                    ),
                    Text('≈ ${Fmt.money(tax)}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.negative)),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            Text(
              '${withDeduction ? 'Нажмите на полученный год, чтобы изменить или снять отметку. ' : ''}'
              'Взносы — ваши пополнения портфеля, как в «Вложено». Вычет — ориентир: не больше НДФЛ, '
              'уплаченного вами за год. Правила ИИС — по данным на 2026 год, уточняйте у брокера.',
              style: TextStyle(fontSize: 11, height: 1.4, color: ctx.dim),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                showIisSettingsSheet(outerContext, PortfolioService.active);
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Настройки ИИС'),
            ),
          ],
        ),
      ),
    );
  }
}


/// Срок счёта и налоги в развёрнутой карточке ИИС: сколько налога не
/// платится и сколько будет, если закрыть счёт раньше срока.
class _IisTaxBlock extends StatelessWidget {
  final IisSettings settings;
  final DateTime termEnd;
  final DateTime now;

  const _IisTaxBlock({required this.settings, required this.termEnd, required this.now});

  @override
  Widget build(BuildContext context) {
    final opened = settings.openedAt;
    final total = termEnd.difference(opened).inDays;
    final passed = now.difference(opened).inDays;
    final share = total <= 0 ? 1.0 : (passed / total).clamp(0.0, 1.0).toDouble();
    final termPassed = !termEnd.isAfter(now);
    final regime = TaxService.regime;
    final exempt = TaxService.exemptAtTermFor(regime);
    final tax = TaxService.taxIfClosedNow();
    final returnDeductions = settings.type.hasContributionDeduction ? IisService.totalReceived(settings) : 0.0;

    Widget line(String title, String value, {String? sub, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13)),
                    if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: context.dim)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('До минимального срока', style: TextStyle(fontSize: 12, color: context.dim))),
            Text(
              termPassed ? 'пройден' : '${monthsText(_monthsBetween(now, termEnd))} · ${Fmt.date(termEnd)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 6,
            backgroundColor: context.hairline,
            valueColor: const AlwaysStoppedAnimation(AppColors.positive),
          ),
        ),
        if (exempt && tax > 0.5) ...[
          line('Налог не платится', '≈ ${Fmt.money(tax)}',
              sub: 'с купонов и продаж на сегодня', color: AppColors.positive),
          if (!termPassed)
            line('Если закрыть раньше', '≈ ${Fmt.money(tax + returnDeductions)}',
                sub: returnDeductions > 0 ? 'налог и возврат полученных вычетов' : 'налог с купонов и продаж',
                color: AppColors.negative),
        ] else if (!exempt && tax > 0.5)
          line('Налог при закрытии счёта', '≈ ${Fmt.money(tax)}',
              sub: 'с купонов и продаж — удержат при закрытии', color: AppColors.negative),
        if (settings.type == IisType.newType) ...[
          const SizedBox(height: 10),
          const TaxNote(text: 'Дивиденды можно выводить на карту. Купоны — только с закрытием счёта.'),
        ],
      ],
    );
  }
}
