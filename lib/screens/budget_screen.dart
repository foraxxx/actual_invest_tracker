import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/budget_service.dart';
import 'home_screen.dart';

const _monthsNom = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

const _monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
String _monthTitle(int y, int m) => '${_cap(_monthsNom[m - 1])} $y';
String _num(double v) => Fmt.group(v);
String _rub(double v) => Fmt.money(v);

double? _parse(String raw) {
  final t = raw.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.').trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

(int, int) _shift(int y, int m, int delta) {
  final o = y * 12 + (m - 1) + delta;
  return (o ~/ 12, o % 12 + 1);
}

/// Значки для категорий.
const _emojis = [
  '📈', '🏠', '🚗', '🏖', '💻', '🛋', '🏋', '👕', '💊', '🎁', '📺', '🌐',
  '✈', '🎓', '🐾', '👶', '🍽', '🛒', '📱', '🎮', '💍', '🧰', '🚲', '⛽',
  '🏦', '💰', '🎉', '📚', '🧴', '🪴',
];

/// Вкладка «Бюджет»: как распределить зарплату и аванс по категориям и что
/// уже отложено.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  late int _y;
  late int _m;
  final Set<String> _expanded = {};
  final Set<String> _allHistory = {};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _y = now.year;
    _m = now.month;
    BudgetService.version.addListener(_onChange);
    BudgetService.ensureStarted().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    BudgetService.version.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _go(int y, int m) => setState(() {
        _y = y;
        _m = m;
        _expanded.clear();
      });

  bool get _isPast {
    final now = DateTime.now();
    return _y * 12 + _m < now.year * 12 + now.month;
  }

  void _snack(String text, {VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      action: undo == null ? null : SnackBarAction(label: 'Отменить', onPressed: undo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (!_ready) {
      children.add(_header(null));
    } else {
      final v = BudgetService.view(_y, _m);
      children.add(_header(v));
      if (!v.stored && _isPast) {
        children.addAll(_emptyPast());
      } else {
        children.addAll(_monthBody(v));
      }
    }
    children.add(const SizedBox(height: kListBottomPadding));

    return Scaffold(
      body: AuroraBackground(
        profit: 0,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: children,
          ),
        ),
      ),
    );
  }

  // --- Шапка ---

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.06) : AppColors.lightSurfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: context.dim),
      ),
    );
  }

  Widget _header(BudgetMonthView? v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'БЮДЖЕТ',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w700, color: context.dim),
                ),
                const SizedBox(height: 3),
                Pressable(
                  onTap: _pickMonth,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _monthTitle(_y, _m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, color: context.accent),
                    ],
                  ),
                ),
                if (v != null && (v.stored || !_isPast)) ...[
                  const SizedBox(height: 2),
                  Pressable(
                    onTap: () => _monthSettings(v),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'на жизнь по ${_rub(v.data.living)} · '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.settings_outlined, size: 13, color: context.dim),
                        ),
                        const TextSpan(text: ' месяц'),
                      ]),
                      style: TextStyle(fontSize: 12, color: context.dim),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _arrow(Icons.chevron_left_rounded, () {
            final p = _shift(_y, _m, -1);
            _go(p.$1, p.$2);
          }),
          const SizedBox(width: 6),
          _arrow(Icons.chevron_right_rounded, () {
            final p = _shift(_y, _m, 1);
            _go(p.$1, p.$2);
          }),
        ],
      ),
    );
  }

  List<Widget> _emptyPast() {
    return [
      const SizedBox(height: 30),
      EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'В ${_monthsNom[_m - 1]} $_y бюджет не вели',
        subtitle: 'Можно заполнить месяц задним числом: суммы возьмутся из ближайшего месяца, '
            'категории — нынешние.',
        action: GradientButton(
          label: 'Заполнить месяц',
          icon: Icons.edit_calendar_outlined,
          expand: false,
          onPressed: () => BudgetService.startMonth(_y, _m),
        ),
      ),
    ];
  }

  List<Widget> _monthBody(BudgetMonthView v) {
    final names = v.config.names;
    final result = <Widget>[];

    result.add(Row(
      children: [
        Expanded(child: _payTile(v, 0)),
        const SizedBox(width: 8),
        Expanded(child: _payTile(v, 1)),
      ],
    ));

    if (v.data.income[0] <= 0 && v.data.income[1] <= 0) {
      result.add(const SizedBox(height: 10));
      result.add(InfoBanner(
        text: 'Укажите, сколько приходит с ${names[0].toLowerCase()} и ${names[1].toLowerCase()} '
            'и сколько оставлять на жизнь — тогда станет видно, хватает ли на всё.',
        icon: Icons.edit_note_rounded,
        color: AppColors.info,
        onTap: () => _monthSettings(v),
      ));
    } else {
      for (int i = 0; i < 2; i++) {
        final rest = v.rest(i);
        if (rest < -0.5) {
          result.add(const SizedBox(height: 10));
          result.add(InfoBanner(
            text: '${names[i]}: не хватает ${_rub(-rest)}. Запланировано ${_num(v.planned(i))} '
                '+ на жизнь ${_num(v.data.living)} из ${_num(v.income(i))}.',
            icon: Icons.warning_amber_rounded,
            color: AppColors.negative,
            onTap: () => _monthSettings(v),
          ));
        }
      }
    }

    result.add(const SizedBox(height: 10));
    result.add(_progressCard(v));

    if (v.freeTotal >= 1) {
      result.add(const SizedBox(height: 10));
      result.add(_freeCard(v));
    }

    final active = <BudgetLine>[];
    final idle = <BudgetLine>[];
    for (final l in v.lines) {
      final has = l.planTotal > 0.5 || l.doneTotal > 0.5 || l.movedTotal > 0.5;
      (has ? active : idle).add(l);
    }

    result.add(const SizedBox(height: 22));
    result.add(Row(
      children: [
        const Expanded(child: Text('Категории', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        TextButton.icon(
          onPressed: () => _editCategory(null),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Категория', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ));
    result.add(const SizedBox(height: 4));
    for (int i = 0; i < active.length; i++) {
      result.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FadeSlideIn.staggered(index: i, child: _categoryCard(v, active[i])),
      ));
    }
    if (active.isEmpty) {
      result.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Пока ни в одной категории нет суммы. Нажмите на категорию ниже и задайте, сколько откладывать.',
          style: TextStyle(fontSize: 12.5, color: context.dim, height: 1.4),
        ),
      ));
    }
    if (idle.isNotEmpty) {
      result.add(const SizedBox(height: 8));
      result.add(Text('Без суммы в этом месяце', style: TextStyle(fontSize: 12, color: context.dim)));
      result.add(const SizedBox(height: 8));
      result.add(Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in idle)
            Pressable(
              onTap: () => _editCategory(l.category),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: context.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.hairline),
                ),
                child: Text('${l.category.emoji} ${l.category.name}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ));
    }
    return result;
  }

  // --- Выплаты ---

  Widget _payTile(BudgetMonthView v, int i) {
    final date = v.payDate(i);
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final came = !date.isAfter(day0);
    final daysLeft = date.difference(day0).inDays;
    final extras = v.data.extras.where((e) => e.payout == i).toList();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: AppRadius.sm,
      onTap: () => _monthSettings(v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${date.day} ${_monthsGen[date.month - 1]} · ${v.config.names[i].toLowerCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: v.dayMoved(i) ? AppColors.gold : context.dim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (came) const Icon(Icons.check_rounded, size: 14, color: AppColors.positive),
            ],
          ),
          const SizedBox(height: 3),
          AdaptiveSingleLineText(
            _num(v.data.income[i]),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          if (extras.isNotEmpty)
            ...[
              for (final e in extras.take(2))
                Text(
                  '+ ${e.name.isEmpty ? 'поступление' : e.name.toLowerCase()} ${_num(e.amount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w600),
                ),
            ]
          else
            Text(
              came
                  ? 'пришла'
                  : daysLeft <= 31
                      ? 'через $daysLeft ${Fmt.plural(daysLeft, 'день', 'дня', 'дней')}'
                      : 'ожидается',
              style: TextStyle(fontSize: 11, color: context.dim),
            ),
        ],
      ),
    );
  }

  Widget _bar(double value, Color color, {double height = 5}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: context.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0).toDouble(),
          child: Container(color: color),
        ),
      ),
    );
  }

  Widget _progressCard(BudgetMonthView v) {
    final pct = (v.progress * 100).round();
    final names = v.config.names;
    final parts = <String>[
      for (int i = 0; i < 2; i++)
        if (v.planned(i) - v.doneFor(i) > 0.5) '${names[i].toLowerCase()}: ещё ${_num(v.planned(i) - v.doneFor(i))}',
    ];
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Отложено за месяц', style: TextStyle(fontSize: 12.5, color: context.dim))),
              Text.rich(TextSpan(children: [
                TextSpan(text: _num(v.doneTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' из ${_rub(v.plannedTotal)}', style: TextStyle(color: context.dim)),
              ]), style: const TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          _bar(v.progress, AppColors.positive, height: 9),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(v.complete ? 'Всё отложено ✓' : '$pct%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: v.complete ? AppColors.positive : context.dim,
                  )),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  parts.join(' · '),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.dim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _freeCard(BudgetMonthView v) {
    final names = v.config.names;
    final parts = <String>[
      for (int i = 0; i < 2; i++)
        if (v.rest(i) >= 1) 'с ${names[i].toLowerCase()} ${_num(v.rest(i))}',
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      color: AppColors.gold.withOpacity(context.isDark ? 0.08 : 0.07),
      border: Border.all(color: AppColors.gold.withOpacity(0.35)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Остаток ${_rub(v.freeTotal)}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  'не распределено · ${parts.join(' · ')}',
                  style: TextStyle(fontSize: 11.5, color: context.dim),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: BorderSide(color: AppColors.gold.withOpacity(0.6)),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _directSheet(v),
            child: const Text('Направить', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // --- Категория ---

  Widget _categoryCard(BudgetMonthView v, BudgetLine l) {
    final c = l.category;
    final expanded = _expanded.contains(c.id);
    final ratio = l.planTotal <= 0 ? (l.doneTotal > 0 ? 1.0 : 0.0) : l.doneTotal / l.planTotal;
    final prev = _shift(_y, _m, -1);
    final next = _shift(_y, _m, 1);
    final directedTotal = l.directed[0] + l.directed[1];
    final notes = <Widget>[
      if (l.carryTotal > 0.5)
        _note('+${_num(l.carryTotal)} перенесено из ${_monthsGen[prev.$2 - 1]}', AppColors.gold),
      if (directedTotal > 0.5)
        _note('+${_num(directedTotal)} из остатка', AppColors.gold,
            action: 'убрать', onAction: () => BudgetService.undoDirect(_y, _m, c.id)),
      if (l.movedTotal > 0.5)
        _note('${_num(l.movedTotal)} перенесено на ${_monthsNom[next.$2 - 1]}', context.dim,
            action: 'вернуть', onAction: () => BudgetService.undoMove(_y, _m, c.id)),
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: AppRadius.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => expanded ? _expanded.remove(c.id) : _expanded.add(c.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(c.emoji, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (c.toDate) ...[
                      const SizedBox(width: 6),
                      const TagChip(text: 'копить', color: AppColors.gold, fontSize: 9.5),
                    ],
                    if (c.source == BudgetSource.balance) ...[
                      const SizedBox(width: 6),
                      const TagChip(text: 'выровнять', color: AppColors.positive, fontSize: 9.5),
                    ],
                    const Spacer(),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: _num(l.doneTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: ' из ${_num(l.planTotal)}', style: TextStyle(color: context.dim)),
                      ]),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: context.dim),
                  ],
                ),
                const SizedBox(height: 7),
                _bar(ratio, AppColors.positive),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _cell(v, l, 0)),
              const SizedBox(width: 6),
              Expanded(child: _cell(v, l, 1)),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...notes,
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded ? _expandedPart(v, l) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _note(String text, Color color, {String? action, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(action,
                    style: TextStyle(fontSize: 11, color: context.accent, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(BudgetMonthView v, BudgetLine l, int i) {
    final plan = l.plan[i];
    final done = l.done[i];
    final isDone = l.cellDone(i);
    final empty = plan <= 0.5 && done <= 0.5;
    final started = done > 0.5 && !isDone;
    final dark = context.isDark;
    final Color bg = isDone
        ? AppColors.positive.withOpacity(0.12)
        : (dark ? Colors.white.withOpacity(empty ? 0.025 : 0.05) : AppColors.lightSurfaceHigh);
    final Color border = isDone
        ? AppColors.positive.withOpacity(0.4)
        : started
            ? AppColors.gold.withOpacity(0.45)
            : Colors.transparent;
    Widget value;
    if (empty) {
      value = Text('—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.dim));
    } else if (isDone) {
      value = Text('✓ ${_num(done)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.positive));
    } else if (started) {
      value = Text.rich(TextSpan(children: [
        TextSpan(text: _num(done), style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: ' из ${_num(plan)}', style: TextStyle(color: context.dim, fontWeight: FontWeight.w500)),
      ]), style: const TextStyle(fontSize: 13));
    } else {
      value = Text(_num(plan), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800));
    }
    return Pressable(
      onTap: empty ? null : () => _onCell(v, l, i),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${v.payDay(i)} · ${v.config.names[i].toLowerCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: context.dim),
            ),
            const SizedBox(height: 1),
            value,
          ],
        ),
      ),
    );
  }

  Future<void> _onCell(BudgetMonthView v, BudgetLine l, int i) async {
    final name = l.category.name;
    if (l.cellDone(i)) {
      final ok = await _confirm(
        title: 'Снять отметку?',
        text: '${l.category.emoji} $name · ${v.config.names[i].toLowerCase()}: отложено ${_rub(l.done[i])}. '
            'Отметки этой выплаты в ${_monthsNom[_m - 1]} будут удалены.',
        action: 'Снять отметку',
      );
      if (ok) await BudgetService.clearCell(_y, _m, l.category.id, i);
      return;
    }
    final left = l.left(i);
    final ids = await BudgetService.markLeft(_y, _m, l.category.id, payout: i);
    if (!mounted) return;
    if (ids.isNotEmpty) {
      _snack('Отложено ${_rub(left)} · $name', undo: () => BudgetService.deleteEntries(ids));
    }
  }

  Widget _expandedPart(BudgetMonthView v, BudgetLine l) {
    final c = l.category;
    final next = _shift(_y, _m, 1);
    final history = BudgetService.history(c.id);
    final showAll = _allHistory.contains(c.id);
    final shown = showAll ? history : history.take(5).toList();
    final saved = BudgetService.savedTotal(c.id);
    final children = <Widget>[];

    if (c.target != null && c.target! > 0) {
      final pct = (saved / c.target! * 100).clamp(0, 999).round();
      final when = c.toDate ? ' к ${_toMonth(c.targetMonth!)} ${c.targetYear}' : '';
      children.addAll([
        Row(
          children: [
            Expanded(
              child: Text('Цель: ${_num(c.target!)}$when', style: TextStyle(fontSize: 11.5, color: context.dim)),
            ),
            Text('${_num(saved)} · $pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 5),
        _bar(saved / c.target!, AppColors.gold, height: 4),
        const SizedBox(height: 10),
      ]);
    } else if (saved > 0.5) {
      children.addAll([
        Text('Всего отложено: ${_rub(saved)}', style: TextStyle(fontSize: 11.5, color: context.dim)),
        const SizedBox(height: 10),
      ]);
    }

    ButtonStyle outlined(Color color) => OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        );

    final left = l.leftTotal;
    children.add(Row(
      children: [
        if (left > 0.5) ...[
          Expanded(
            child: OutlinedButton(
              style: outlined(AppColors.positive),
              onPressed: () async {
                final ids = await BudgetService.markLeft(_y, _m, c.id);
                if (!mounted) return;
                if (ids.isNotEmpty) {
                  _snack('Отложено ${_rub(left)} · ${c.name}', undo: () => BudgetService.deleteEntries(ids));
                }
              },
              child: FittedBox(child: Text('✓ Отложил ${_num(left)}', style: const TextStyle(fontWeight: FontWeight.w700))),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: OutlinedButton(
            style: outlined(context.isDark ? Colors.white : Colors.black87),
            onPressed: () => _otherAmount(v, l),
            child: const FittedBox(child: Text('Другая сумма', style: TextStyle(fontWeight: FontWeight.w700))),
          ),
        ),
      ],
    ));
    if (left > 0.5) {
      children.add(const SizedBox(height: 6));
      children.add(OutlinedButton(
        style: outlined(context.dim),
        onPressed: () async {
          await BudgetService.moveToNext(_y, _m, c.id);
          if (!mounted) return;
          _snack('${_rub(left)} перенесено на ${_monthsNom[next.$2 - 1]}',
              undo: () => BudgetService.undoMove(_y, _m, c.id));
        },
        child: Text('Перенести ${_num(left)} на ${_monthsNom[next.$2 - 1]}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ));
    }

    children.add(const SizedBox(height: 10));
    children.add(Row(
      children: [
        Expanded(child: Text('Когда сколько отложено', style: TextStyle(fontSize: 11, color: context.dim))),
        GestureDetector(
          onTap: () => _editCategory(c),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 13, color: context.accent),
              const SizedBox(width: 3),
              Text('Настроить',
                  style: TextStyle(fontSize: 11.5, color: context.accent, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    ));
    children.add(const SizedBox(height: 4));
    if (history.isEmpty) {
      children.add(Text('Пока ничего', style: TextStyle(fontSize: 12, color: context.dim)));
    }
    final nowYear = DateTime.now().year;
    for (final e in shown) {
      final date = '${e.date.day} ${_monthsGen[e.date.month - 1]}${e.date.year == nowYear ? '' : ' ${e.date.year}'}';
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: date),
                  TextSpan(
                    text: ' · ${v.config.names[e.payout].toLowerCase()}',
                    style: TextStyle(color: context.dim, fontSize: 11),
                  ),
                ]),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            Text('+${_num(e.amount)}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.positive)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await BudgetService.deleteEntry(e.id);
                if (!mounted) return;
                _snack('Отметка удалена', undo: () => BudgetService.restoreEntry(e));
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                child: Icon(Icons.close_rounded, size: 15, color: context.dim),
              ),
            ),
          ],
        ),
      ));
    }
    if (history.length > shown.length || showAll && history.length > 5) {
      children.add(GestureDetector(
        onTap: () => setState(() => showAll ? _allHistory.remove(c.id) : _allHistory.add(c.id)),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            showAll ? 'Свернуть' : 'Показать все (${history.length})',
            style: TextStyle(fontSize: 11.5, color: context.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.hairline))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  // --- Окна ---

  Future<bool> _confirm({required String title, required String text, required String action}) async {
    final ok = await showAppSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: title, subtitle: text),
            const SizedBox(height: 18),
            GradientButton(
              label: action,
              colors: const [AppColors.negative, Color(0xFFFF7A59)],
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _otherAmount(BudgetMonthView v, BudgetLine l) async {
    var payout = l.left(0) > 0.5 || l.left(1) <= 0.5 ? 0 : 1;
    final ctrl = TextEditingController(text: l.left(payout) > 0.5 ? _plain(l.left(payout)) : '');
    final now = DateTime.now();
    final inMonth = now.year == _y && now.month == _m;
    DateTime date = inMonth ? DateTime(now.year, now.month, now.day) : v.payDate(payout);
    String? error;
    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: '${l.category.emoji} ${l.category.name}',
                subtitle: 'Сколько отложено — можно меньше или больше плана',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 14),
              Text('С какой выплаты', style: TextStyle(fontSize: 12, color: ctx.dim)),
              const SizedBox(height: 6),
              SegmentedToggle<int>(
                values: const [0, 1],
                selected: payout,
                labelOf: (i) => v.config.names[i],
                onChanged: (i) => setSheet(() {
                  payout = i;
                  if (l.left(i) > 0.5) ctrl.text = _plain(l.left(i));
                  if (!inMonth) date = v.payDate(i);
                }),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: ctrl,
                label: 'Сумма, ₽',
                number: true,
                autofocus: true,
                onChanged: (_) {
                  if (error != null) setSheet(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              AppDateField(
                value: date,
                label: 'Когда',
                firstDate: DateTime(_y, _m, 1),
                lastDate: DateTime(_y, _m, daysInMonth(_y, _m)),
                onPicked: (d) => setSheet(() => date = d),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: 'Отложил',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final a = _parse(ctrl.text);
                  if (a == null || a <= 0) {
                    setSheet(() => error = 'Укажите сумму');
                    return;
                  }
                  await BudgetService.addEntry(_y, _m, l.category.id, payout, a, date: date);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _directSheet(BudgetMonthView v) async {
    final cats = BudgetService.categories;
    if (cats.isEmpty) return;
    String selected = cats.first.id;
    final ctrl = TextEditingController(text: _plain(v.freeTotal.floorToDouble()));
    String? error;
    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Направить остаток',
                subtitle: 'Свободно ${_rub(v.freeTotal)}. Сумма добавится к плану категории в этом месяце.',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: ctrl,
                label: 'Сколько, ₽',
                number: true,
                onChanged: (_) {
                  if (error != null) setSheet(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              Text('В какую категорию', style: TextStyle(fontSize: 12, color: ctx.dim)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in cats)
                    ChoiceChip(
                      label: Text('${c.emoji} ${c.name}'),
                      selected: selected == c.id,
                      onSelected: (_) => setSheet(() => selected = c.id),
                    ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: 'Направить',
                icon: Icons.call_split_rounded,
                onPressed: () async {
                  final a = _parse(ctrl.text);
                  if (a == null || a <= 0) {
                    setSheet(() => error = 'Укажите сумму');
                    return;
                  }
                  await BudgetService.direct(_y, _m, selected, a);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _monthSettings(BudgetMonthView v) async {
    final config = v.config;
    final incomeCtrl = [
      for (int i = 0; i < 2; i++) TextEditingController(text: v.data.income[i] > 0 ? _plain(v.data.income[i]) : ''),
    ];
    final livingCtrl = TextEditingController(text: v.data.living > 0 ? _plain(v.data.living) : '');
    final days = [v.payDay(0), v.payDay(1)];
    final extras = [...v.data.extras];
    final dim = daysInMonth(_y, _m);
    int defaultDay(int i) => config.days[i].inMonth(_y, _m);

    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: _monthTitle(_y, _m),
                subtitle: 'Суммы на руки. Новый месяц берёт их из прошлого',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 14),
              for (int i = 0; i < 2; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(controller: incomeCtrl[i], label: '${config.names[i]}, ₽', number: true),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: AppDropdown<int>(
                        value: days[i],
                        label: days[i] == defaultDay(i) ? 'Дата' : 'Дата · этот месяц',
                        items: [
                          for (int d = 1; d <= dim; d++)
                            DropdownMenuItem(value: d, child: Text('$d ${_monthsGen[_m - 1]}')),
                        ],
                        onChanged: (d) {
                          if (d != null) setSheet(() => days[i] = d);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Text(
                'Дату можно сдвинуть только для этого месяца — например, если выплата пришла раньше из-за выходных.',
                style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.35),
              ),
              const SizedBox(height: 12),
              AppTextField(controller: livingCtrl, label: 'На жизнь с каждой выплаты, ₽', number: true),
              const SizedBox(height: 16),
              Text('Разовые поступления', style: TextStyle(fontSize: 12.5, color: ctx.dim)),
              const SizedBox(height: 6),
              for (int k = 0; k < extras.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    radius: AppRadius.sm,
                    onTap: () async {
                      final r = await _extraSheet(extras[k], config);
                      if (r == null) return;
                      setSheet(() {
                        if (r.deleted) {
                          extras.removeAt(k);
                        } else {
                          extras[k] = r.extra!;
                        }
                      });
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${extras[k].name.isEmpty ? 'Поступление' : extras[k].name} · '
                                '${math.min(extras[k].day, dim)} ${_monthsGen[_m - 1]}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              Text('вместе с ${config.names[extras[k].payout].toLowerCase()}',
                                  style: TextStyle(fontSize: 11, color: ctx.dim)),
                            ],
                          ),
                        ),
                        Text(_num(extras[k].amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final r = await _extraSheet(null, config);
                    if (r?.extra != null) setSheet(() => extras.add(r!.extra!));
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Добавить поступление'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Категории переходят на новый месяц сами.',
                style: TextStyle(fontSize: 11, color: ctx.dim),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _configSheet(),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Даты и названия выплат по умолчанию'),
                ),
              ),
              const SizedBox(height: 8),
              GradientButton(
                label: 'Сохранить',
                icon: Icons.check_rounded,
                onPressed: () async {
                  await BudgetService.saveMonth(
                    year: _y,
                    month: _m,
                    income: [for (int i = 0; i < 2; i++) math.max(0.0, _parse(incomeCtrl[i].text) ?? 0)],
                    dayOverride: [for (int i = 0; i < 2; i++) days[i] == defaultDay(i) ? null : days[i]],
                    living: math.max(0.0, _parse(livingCtrl.text) ?? 0),
                    extras: extras,
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

  Future<_ExtraResult?> _extraSheet(BudgetExtra? existing, BudgetConfig config) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final amountCtrl = TextEditingController(text: existing == null ? '' : _plain(existing.amount));
    final dim = daysInMonth(_y, _m);
    var day = math.min(existing?.day ?? DateTime.now().day, dim);
    var payout = existing?.payout ?? (day < config.days[1].inMonth(_y, _m) ? 0 : 1);
    String? error;
    return showAppSheet<_ExtraResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: existing == null ? 'Разовое поступление' : 'Поступление',
                subtitle: 'Премия, возврат, подарок — только в этом месяце',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 14),
              AppTextField(controller: nameCtrl, label: 'Название', hint: 'Премия'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: amountCtrl,
                      label: 'Сумма, ₽',
                      number: true,
                      onChanged: (_) {
                        if (error != null) setSheet(() => error = null);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: AppDropdown<int>(
                      value: day,
                      label: 'Дата',
                      items: [
                        for (int d = 1; d <= dim; d++)
                          DropdownMenuItem(value: d, child: Text('$d ${_monthsGen[_m - 1]}')),
                      ],
                      onChanged: (d) {
                        if (d != null) setSheet(() => day = d);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Распределять вместе с', style: TextStyle(fontSize: 12, color: ctx.dim)),
              const SizedBox(height: 6),
              SegmentedToggle<int>(
                values: const [0, 1],
                selected: payout,
                labelOf: (i) => config.names[i],
                onChanged: (i) => setSheet(() => payout = i),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: existing == null ? 'Добавить' : 'Готово',
                icon: Icons.check_rounded,
                onPressed: () {
                  final a = _parse(amountCtrl.text);
                  if (a == null || a <= 0) {
                    setSheet(() => error = 'Укажите сумму');
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    _ExtraResult(
                      extra: BudgetExtra(
                        id: existing?.id ?? BudgetService.newId(),
                        name: nameCtrl.text.trim(),
                        day: day,
                        amount: a,
                        payout: payout,
                      ),
                    ),
                  );
                },
              ),
              if (existing != null) ...[
                const SizedBox(height: 6),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.negative),
                  onPressed: () => Navigator.pop(ctx, const _ExtraResult(deleted: true)),
                  child: const Text('Удалить поступление'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _configSheet() async {
    final c = BudgetService.config;
    final nameCtrl = [for (int i = 0; i < 2; i++) TextEditingController(text: c.names[i])];
    final last = [c.days[0].last, c.days[1].last];
    final dayCtrl = [for (int i = 0; i < 2; i++) TextEditingController(text: c.days[i].last ? '' : '${c.days[i].day}')];
    String? error;
    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Даты выплат',
                subtitle: 'Для всех месяцев. Прошедшие и вручную сдвинутые даты не меняются',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              for (int i = 0; i < 2; i++) ...[
                const SizedBox(height: 16),
                AppTextField(controller: nameCtrl[i], label: i == 0 ? 'Первая выплата' : 'Вторая выплата'),
                const SizedBox(height: 8),
                SegmentedToggle<bool>(
                  values: const [false, true],
                  selected: last[i],
                  labelOf: (b) => b ? 'Последний день' : 'Число месяца',
                  onChanged: (b) => setSheet(() => last[i] = b),
                ),
                const SizedBox(height: 8),
                if (!last[i])
                  AppTextField(controller: dayCtrl[i], label: 'Число', number: true, integerOnly: true)
                else
                  Text(
                    'ноябрь — 30-е · декабрь — 31-е · февраль — 28-е или 29-е',
                    style: TextStyle(fontSize: 11.5, color: ctx.dim),
                  ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 18),
              GradientButton(
                label: 'Сохранить',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final days = <PayDay>[];
                  for (int i = 0; i < 2; i++) {
                    if (last[i]) {
                      days.add(const PayDay.lastDay());
                    } else {
                      final d = int.tryParse(dayCtrl[i].text.trim());
                      if (d == null || d < 1 || d > 31) {
                        setSheet(() => error = 'Число — от 1 до 31');
                        return;
                      }
                      days.add(PayDay.day(d));
                    }
                  }
                  await BudgetService.saveConfig(BudgetConfig(
                    names: [
                      for (int i = 0; i < 2; i++)
                        nameCtrl[i].text.trim().isEmpty ? BudgetConfig.initial.names[i] : nameCtrl[i].text.trim(),
                    ],
                    days: days,
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editCategory(BudgetCategory? existing) async {
    final config = BudgetService.config;
    var emoji = existing?.emoji ?? _emojis.first;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var mode = existing?.mode ?? BudgetMode.monthly;
    final amountCtrl = TextEditingController(
      text: existing != null && existing.amount > 0 ? _plain(existing.amount) : '',
    );
    final targetCtrl = TextEditingController(
      text: existing?.target != null && existing!.target! > 0 ? _plain(existing.target!) : '',
    );
    final now = DateTime.now();
    var ty = existing?.targetYear ?? now.year + 1;
    var tm = existing?.targetMonth ?? now.month;
    var source = existing?.source ?? BudgetSource.half;
    String? error;

    String sourceHint(BudgetSource s) => switch (s) {
          BudgetSource.salary => 'Вся сумма — с ${config.names[0].toLowerCase()}.',
          BudgetSource.advance => 'Вся сумма — с ${config.names[1].toLowerCase()}.',
          BudgetSource.half => 'Поровну с обеих выплат.',
          BudgetSource.balance =>
            'Программа сама делит сумму так, чтобы после всех категорий с обеих выплат оставалось одинаково.',
        };

    String? toDateHint() {
      final t = _parse(targetCtrl.text);
      if (t == null || t <= 0) return null;
      final saved = existing == null ? 0.0 : BudgetService.savedBefore(existing.id, now.year, now.month);
      final months = (ty * 12 + tm) - (now.year * 12 + now.month) + 1;
      if (months < 1) return 'Месяц цели уже прошёл';
      final left = t - saved;
      if (left <= 0.5) return 'Уже накоплено ${_num(saved)} — цель достигнута';
      final raw = left / months;
      final per = raw >= 100 ? (raw / 100).ceil() * 100.0 : raw.ceilToDouble();
      final have = saved > 0.5 ? 'Уже есть ${_num(saved)} — осталось ${_num(left)}' : 'Нужно ${_num(left)}';
      return '$have за $months ${Fmt.plural(months, 'месяц', 'месяца', 'месяцев')}: ≈${_num(per)} в месяц';
    }

    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final hint = mode == BudgetMode.toDate ? toDateHint() : null;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: existing == null ? 'Новая категория' : existing.name,
                  subtitle: 'Изменения действуют с текущего месяца, прошлые не меняются',
                  trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: nameCtrl,
                  label: 'Название',
                  onChanged: (_) {
                    if (error != null) setSheet(() => error = null);
                  },
                ),
                const SizedBox(height: 10),
                Text('Значок', style: TextStyle(fontSize: 12, color: ctx.dim)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final e in _emojis)
                      GestureDetector(
                        onTap: () => setSheet(() => emoji = e),
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: e == emoji ? ctx.accent.withOpacity(0.18) : Colors.transparent,
                            border: Border.all(color: e == emoji ? ctx.accent : Colors.transparent),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 19)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Как откладывать', style: TextStyle(fontSize: 12, color: ctx.dim)),
                const SizedBox(height: 6),
                SegmentedToggle<BudgetMode>(
                  values: BudgetMode.values,
                  selected: mode,
                  labelOf: (m) => m == BudgetMode.monthly ? 'Каждый месяц' : 'Копить к дате',
                  onChanged: (m) => setSheet(() => mode = m),
                ),
                const SizedBox(height: 10),
                if (mode == BudgetMode.monthly) ...[
                  AppTextField(controller: amountCtrl, label: 'Сколько в месяц, ₽', number: true),
                  const SizedBox(height: 10),
                  AppTextField(
                    controller: targetCtrl,
                    label: 'Цель, ₽ — необязательно',
                    number: true,
                  ),
                  const SizedBox(height: 4),
                  Text('С целью в карточке будет видно, сколько накоплено за всё время.',
                      style: TextStyle(fontSize: 11, color: ctx.dim)),
                ] else ...[
                  AppTextField(
                    controller: targetCtrl,
                    label: 'Накопить, ₽',
                    number: true,
                    onChanged: (_) => setSheet(() => error = null),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppDropdown<int>(
                          value: tm,
                          label: 'К месяцу',
                          items: [
                            for (int m = 1; m <= 12; m++)
                              DropdownMenuItem(value: m, child: Text(_cap(_monthsNom[m - 1]))),
                          ],
                          onChanged: (m) {
                            if (m != null) setSheet(() => tm = m);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: AppDropdown<int>(
                          value: ty,
                          label: 'Год',
                          items: [
                            for (int y = math.min(ty, now.year); y <= math.max(ty, now.year + 15); y++)
                              DropdownMenuItem(value: y, child: Text('$y')),
                          ],
                          onChanged: (y) {
                            if (y != null) setSheet(() => ty = y);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(hint, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                Text('Откуда брать', style: TextStyle(fontSize: 12, color: ctx.dim)),
                const SizedBox(height: 6),
                SegmentedToggle<BudgetSource>(
                  values: const [BudgetSource.salary, BudgetSource.half, BudgetSource.advance, BudgetSource.balance],
                  selected: source,
                  labelOf: (s) => switch (s) {
                    BudgetSource.salary => config.names[0],
                    BudgetSource.advance => config.names[1],
                    BudgetSource.half => 'Пополам',
                    BudgetSource.balance => 'Выровнять',
                  },
                  onChanged: (s) => setSheet(() => source = s),
                ),
                const SizedBox(height: 6),
                Text(sourceHint(source), style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.35)),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
                ],
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Сохранить',
                  icon: Icons.check_rounded,
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setSheet(() => error = 'Введите название');
                      return;
                    }
                    final target = _parse(targetCtrl.text);
                    if (mode == BudgetMode.toDate && (target == null || target <= 0)) {
                      setSheet(() => error = 'Укажите, сколько накопить');
                      return;
                    }
                    await BudgetService.saveCategory(BudgetCategory(
                      id: existing?.id ?? BudgetService.newId(),
                      name: name,
                      emoji: emoji,
                      mode: mode,
                      amount: mode == BudgetMode.monthly ? math.max(0.0, _parse(amountCtrl.text) ?? 0) : 0,
                      target: target != null && target > 0 ? target : null,
                      targetYear: mode == BudgetMode.toDate ? ty : null,
                      targetMonth: mode == BudgetMode.toDate ? tm : null,
                      source: source,
                    ));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                if (existing != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.negative),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final ok = await _confirm(
                        title: 'Удалить «${existing.name}»?',
                        text: 'В новых месяцах категории не будет. Прошлые месяцы и отметки останутся.',
                        action: 'Удалить',
                      );
                      if (ok) await BudgetService.deleteCategory(existing.id);
                    },
                    child: const Text('Удалить категорию'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Выбор месяца и итоги ---

  Future<void> _pickMonth() async {
    final r = await showMonthPicker(context, _y, _m);
    if (r == null || !mounted) return;
    if (r.yearSummary) {
      final picked = await Navigator.push<(int, int)>(
        context,
        AppPageRoute(builder: (_) => BudgetYearScreen(year: r.year)),
      );
      if (picked != null && mounted) _go(picked.$1, picked.$2);
    } else {
      _go(r.year, r.month);
    }
  }
}

String _toMonth(int m) => _monthsDat[m - 1];

/// «к июлю»
const _monthsDat = [
  'январю', 'февралю', 'марту', 'апрелю', 'маю', 'июню',
  'июлю', 'августу', 'сентябрю', 'октябрю', 'ноябрю', 'декабрю',
];

class _ExtraResult {
  final BudgetExtra? extra;
  final bool deleted;
  const _ExtraResult({this.extra, this.deleted = false});
}

class MonthPick {
  final int year;
  final int month;
  final bool yearSummary;
  const MonthPick(this.year, this.month, {this.yearSummary = false});
}

(String, Color) _statusLabel(BuildContext context, BudgetMonthStatus s) {
  final pct = (s.progress * 100).round();
  return switch (s.state) {
    BudgetMonthState.complete => ('план ✓', AppColors.positive),
    BudgetMonthState.partial => ('$pct%', AppColors.gold),
    BudgetMonthState.current => ('идёт · $pct%', context.dim),
    BudgetMonthState.future => ('—', context.dim),
    BudgetMonthState.none => ('—', context.dim),
  };
}

/// Быстрый выбор месяца: год стрелками, месяц — одним нажатием.
Future<MonthPick?> showMonthPicker(BuildContext context, int year, int month) {
  var y = year;
  final now = DateTime.now();
  return showAppSheet<MonthPick>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Widget arrow(IconData icon, int delta) => IconButton(
              onPressed: () => setSheet(() => y += delta),
              icon: Icon(icon),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'Выбор месяца'),
              const SizedBox(height: 8),
              Row(
                children: [
                  arrow(Icons.chevron_left_rounded, -1),
                  Expanded(
                    child: Text('$y',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  arrow(Icons.chevron_right_rounded, 1),
                ],
              ),
              const SizedBox(height: 8),
              for (int r = 0; r < 4; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (int c = 0; c < 3; c++) ...[
                        if (c > 0) const SizedBox(width: 6),
                        Expanded(child: _monthTile(ctx, y, r * 3 + c + 1, y == year && r * 3 + c + 1 == month)),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Текущий месяц'),
                    onPressed: () => Navigator.pop(ctx, MonthPick(now.year, now.month)),
                  ),
                  ActionChip(
                    label: Text('Итоги $y года'),
                    onPressed: () => Navigator.pop(ctx, MonthPick(y, 1, yearSummary: true)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

Widget _monthTile(BuildContext ctx, int y, int m, bool selected) {
  final s = BudgetService.status(y, m);
  final (label, color) = _statusLabel(ctx, s);
  final done = s.state == BudgetMonthState.complete;
  return Pressable(
    onTap: () => Navigator.pop(ctx, MonthPick(y, m)),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: done
            ? AppColors.positive.withOpacity(0.12)
            : (ctx.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? ctx.accent : Colors.transparent, width: 1.5),
      ),
      child: Column(
        children: [
          Text(_monthsNom[m - 1], style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    ),
  );
}

/// Итоги года: сколько отложено по категориям и как выполнялся план.
class BudgetYearScreen extends StatefulWidget {
  final int year;
  const BudgetYearScreen({super.key, required this.year});

  @override
  State<BudgetYearScreen> createState() => _BudgetYearScreenState();
}

class _BudgetYearScreenState extends State<BudgetYearScreen> {
  late int _year = widget.year;

  @override
  Widget build(BuildContext context) {
    final totals = BudgetService.yearTotals(_year);
    final saved = totals.fold(0.0, (a, t) => a + t.$2);
    return Scaffold(
      appBar: AppBar(
        title: Text('Бюджет · $_year'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _year--),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            onPressed: () => setState(() => _year++),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: Text('Отложено за год', style: TextStyle(fontSize: 13, color: context.dim))),
                Text(_rub(saved), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (totals.isEmpty)
            Text('В $_year году отметок нет.', style: TextStyle(fontSize: 13, color: context.dim)),
          for (final t in totals)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${t.$1.emoji} ${t.$1.name}', style: const TextStyle(fontSize: 13.5)),
                      ),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: _num(t.$2), style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (t.$3 > 0.5) TextSpan(text: ' / ${_num(t.$3)}', style: TextStyle(color: context.dim)),
                      ]), style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: t.$3 <= 0.5 ? 1 : (t.$2 / t.$3).clamp(0.0, 1.0).toDouble(),
                      minHeight: 5,
                      color: AppColors.positive,
                      backgroundColor: context.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text('План по месяцам', style: TextStyle(fontSize: 12.5, color: context.dim)),
          const SizedBox(height: 8),
          for (int r = 0; r < 3; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (int c = 0; c < 4; c++) ...[
                    if (c > 0) const SizedBox(width: 6),
                    Expanded(child: _yearCell(r * 4 + c + 1)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text('Нажмите на месяц, чтобы открыть его.', style: TextStyle(fontSize: 11, color: context.dim)),
        ],
      ),
    );
  }

  Widget _yearCell(int m) {
    final s = BudgetService.status(_year, m);
    final (label, color) = _statusLabel(context, s);
    final done = s.state == BudgetMonthState.complete;
    return Pressable(
      onTap: () => Navigator.pop(context, (_year, m)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
        decoration: BoxDecoration(
          color: done
              ? AppColors.positive.withOpacity(0.12)
              : (context.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_monthsNom[m - 1],
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: context.dim)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}
