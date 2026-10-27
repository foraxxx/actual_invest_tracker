import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/budget_service.dart';
import 'home_screen.dart';

// Названия месяцев во всех нужных падежах: «ноябрь», «15 ноября»,
// «в ноябре», «на ноябрь».
const _monthsNom = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

const _monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const _monthsPrep = [
  'январе', 'феврале', 'марте', 'апреле', 'мае', 'июне',
  'июле', 'августе', 'сентябре', 'октябре', 'ноябре', 'декабре',
];

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
String _monthTitle(int y, int m) => '${_cap(_monthsNom[m - 1])} $y';

/// Суммы прячутся вместе со всем приложением («Скрывать суммы»).
bool get _hidden => false;
String _num(double v) => _hidden ? '•••' : Fmt.group(v);
String _rub(double v) => _hidden ? '••• ₽' : Fmt.money(v);

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

String _days(int n) => '$n ${Fmt.plural(n, 'день', 'дня', 'дней')}';

/// Значки для категорий.
const _emojis = [
  '📈', '🏠', '🚗', '🏖', '💻', '🛋', '🏋', '👕', '💊', '🎁', '📺', '🌐',
  '✈', '🎓', '🐾', '👶', '🍽', '🛒', '📱', '🎮', '💍', '🧰', '🚲', '⛽',
  '🏦', '💰', '🎉', '📚', '🧴', '🪴',
];

String _sourceLabel(BudgetSource s, BudgetConfig config) => switch (s) {
      BudgetSource.auto => 'Авто',
      BudgetSource.half => 'Пополам',
      BudgetSource.salary => config.names[0],
      BudgetSource.advance => config.names[1],
    };

String _sourceHint(BudgetSource s, BudgetConfig config) => switch (s) {
      BudgetSource.auto => 'Приложение само выберет выплату, с которой отложить: ту, где после остальных сумм '
          'остаётся больше денег. Разделит сумму, только если целиком она не помещается.',
      BudgetSource.half => 'Поровну с обеих выплат.',
      BudgetSource.salary => 'Вся сумма — с выплаты «${config.names[0]}».',
      BudgetSource.advance => 'Вся сумма — с выплаты «${config.names[1]}».',
    };

/// Вкладка «Бюджет»: сколько отложить с зарплаты и аванса.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  late int _y;
  late int _m;
  bool _ready = false;

  /// Траты, убранные свайпом: пока сохранение не закончилось, строку уже не
  /// показываем.
  final Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _y = now.year;
    _m = now.month;
    BudgetService.version.addListener(_onChange);
    AppearanceService.version.addListener(_onChange);
    AppearanceService.revealed.addListener(_onChange);
    BudgetService.checkMonthChange().then((_) => BudgetService.ensureStarted()).then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    BudgetService.version.removeListener(_onChange);
    AppearanceService.version.removeListener(_onChange);
    AppearanceService.revealed.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(_dismissed.clear);
  }

  void _go(int y, int m) => setState(() {
        _y = y;
        _m = m;
      });

  String get _monthIn => _monthsPrep[_m - 1];

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
      children.addAll(v.filled ? _monthBody(v) : _emptyMonth(v));
    }
    children.add(const SizedBox(height: kListBottomPadding));

    return PageTour(
      pageId: 'budget',
      steps: const [
        PageTourStep(
          anchor: 'budget_month',
          title: 'Месяц',
          text: 'Нажмите на название, чтобы перейти к любому месяцу. Стрелки справа — соседние месяцы, '
              'кнопка «⋮» — доходы месяца, копирование и сброс.',
        ),
        PageTourStep(
          anchor: 'budget_pay',
          title: 'Зарплата и аванс',
          text: 'Сколько приходит и когда. Кнопка «Отложить всё» отмечает разом всё, что откладывается с этой выплаты.',
        ),
        PageTourStep(
          anchor: 'budget_row',
          title: 'Отложить',
          text: 'Что отложить в этом месяце и с какой выплаты. Нажмите на сумму — она отмечена как отложенная, '
              'ещё раз — отметка снимется. Нажмите на название, чтобы изменить сумму или перенести её на '
              'следующий месяц. Смахните строку влево, чтобы убрать категорию из месяца.',
        ),
        PageTourStep(
          anchor: 'budget_foot',
          title: 'Итоги по выплатам',
          text: 'Сколько отложить с каждой выплаты, сколько остаётся на жизнь и сколько денег ещё не '
              'распределено. Красная сумма — запланировано больше, чем приходит.',
        ),
      ],
      child: Scaffold(
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
      ),
    );
  }

  // --- Шапка ---

  Widget _iconButton(IconData icon, VoidCallback onTap) {
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
    // Верхняя строка — месяц и кнопки, всегда одной высоты: стрелки не
    // прыгают при переходе на пустой месяц. Подпись — отдельной строкой ниже.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TourSpot(
                  id: 'budget_month',
                  child: Pressable(
                    onTap: _pickMonth,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: _cap(_monthsNom[_m - 1])),
                        TextSpan(
                          text: ' $_y',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: context.dim),
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.expand_more_rounded, color: context.dim),
                        ),
                      ]),
                      // Месяц и год не обрезаются: в крайнем случае год
                      // переносится на вторую строку.
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_hidden) ...[
                _iconButton(
                  AppearanceService.revealed.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  AppearanceService.toggleReveal,
                ),
                const SizedBox(width: 6),
              ],
              // Место под «⋮» держится и у пустого месяца — стрелки не сдвигаются.
              if (v != null && v.filled)
                _iconButton(Icons.more_vert_rounded, () => _monthMenu(v))
              else
                const SizedBox(width: 34),
              const SizedBox(width: 6),
              _iconButton(Icons.chevron_left_rounded, () {
                final p = _shift(_y, _m, -1);
                _go(p.$1, p.$2);
              }),
              const SizedBox(width: 6),
              _iconButton(Icons.chevron_right_rounded, () {
                final p = _shift(_y, _m, 1);
                _go(p.$1, p.$2);
              }),
            ],
          ),
          if (v != null && v.filled) ...[
            const SizedBox(height: 4),
            Pressable(
              onTap: () => _incomeSheet(v),
              child: Text(
                v.data.living > 0
                    ? 'На жизнь остаётся ${_rub(v.data.living)} с каждой выплаты'
                    : 'Укажите, сколько оставлять на жизнь',
                style: TextStyle(fontSize: 12.5, color: context.dim),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Пустой месяц ---

  List<Widget> _emptyMonth(BudgetMonthView v) {
    final prev = BudgetService.previousFilled(_y, _m);
    final carry = v.lines.where((l) => l.carryTotal > 0.5).toList();
    return [
      const SizedBox(height: 24),
      EmptyState(
        icon: Icons.event_note_outlined,
        title: '${_cap(_monthsNom[_m - 1])} ещё не заполнен',
        subtitle: prev == null
            ? 'Укажите зарплату, аванс и что нужно отложить в этом месяце.'
            : 'Скопируйте ${_monthsNom[prev.$2 - 1]}: зарплату, аванс, сумму на жизнь и что откладывать. '
                'Потом поправьте то, что изменилось. Или заполните месяц с нуля.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prev != null)
              GradientButton(
                label: 'Скопировать ${_monthsNom[prev.$2 - 1]}${prev.$1 == _y ? '' : ' ${prev.$1}'}',
                icon: Icons.copy_rounded,
                expand: false,
                onPressed: () => BudgetService.copyMonth(prev, (_y, _m)),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await BudgetService.startEmpty(_y, _m);
                if (!mounted) return;
                _incomeSheet(BudgetService.view(_y, _m));
              },
              child: const Text('Заполнить с нуля'),
            ),
          ],
        ),
      ),
      if (carry.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Уже перенесено из прошлого месяца: '
            '${carry.map((l) => '${l.category.name} ${_num(l.carryTotal)}').join(', ')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.dim),
          ),
        ),
    ];
  }

  // --- Заполненный месяц ---

  List<Widget> _monthBody(BudgetMonthView v) {
    final names = v.config.names;
    final result = <Widget>[
      TourSpot(
        id: 'budget_pay',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _payTile(v, 0)),
            const SizedBox(width: 8),
            Expanded(child: _payTile(v, 1)),
          ],
        ),
      ),
    ];

    if (v.data.income[0] <= 0 && v.data.income[1] <= 0) {
      result.add(const SizedBox(height: 10));
      result.add(InfoBanner(
        text: 'Укажите, сколько приходит в ${names[0].toLowerCase()} и ${names[1].toLowerCase()} и сколько '
            'оставлять на жизнь — тогда приложение разложит суммы по выплатам.',
        icon: Icons.edit_note_rounded,
        color: AppColors.info,
        onTap: () => _incomeSheet(v),
      ));
    }

    result.add(const SizedBox(height: 10));
    result.add(_progressCard(v));

    result.add(const SizedBox(height: 18));
    result.add(_sectionTitle('Отложить', '+ Добавить', () => _itemSheet(v)));
    result.add(_table(v));

    result.add(const SizedBox(height: 22));
    result.add(_sectionTitle('Категории', '+ Категория', () => _editCategory(null)));
    result.add(_categoriesList());
    return result;
  }

  Widget _sectionTitle(String title, String action, VoidCallback onAction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          TextButton(
            onPressed: onAction,
            child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _payTile(BudgetMonthView v, int i) {
    final date = v.payDate(i);
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final came = !date.isAfter(day0);
    final daysLeft = date.difference(day0).inDays;
    final extras = v.data.extras.where((e) => e.payout == i).toList();
    final left = v.leftFor(i);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: AppRadius.sm,
      onTap: () => _incomeSheet(v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v.config.names[i],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: context.dim, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          AdaptiveSingleLineText(
            _num(v.data.income[i]),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            '${date.day} ${_monthsGen[date.month - 1]} · '
            '${came ? 'пришла' : daysLeft <= 31 ? 'через ${_days(daysLeft)}' : 'ожидается'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: v.dayMoved(i) ? AppColors.gold : context.dim),
          ),
          for (final e in extras.take(2))
            Text(
              '+ ${e.name.isEmpty ? 'поступление' : e.name.toLowerCase()} ${_num(e.amount)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w600),
            ),
          if (left > 0.5) ...[
            const SizedBox(height: 8),
            Pressable(
              onTap: () => _markAll(v, i),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.positive.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Отложить всё · ${_num(left)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.positive),
                  ),
                ),
              ),
            ),
          ] else if (v.planned(i) > 0.5) ...[
            const SizedBox(height: 8),
            const Text('Всё отложено ✓',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.positive)),
          ],
        ],
      ),
    );
  }

  Future<void> _markAll(BudgetMonthView v, int i) async {
    final left = v.leftFor(i);
    final count = v.lines.where((l) => l.left(i) > 0.5).length;
    final ok = await _confirm(
      title: 'Отложить всё с выплаты «${v.config.names[i]}»?',
      text: '${_rub(left)} — ${count == 1 ? 'одна категория' : '$count ${Fmt.plural(count, 'категория', 'категории', 'категорий')}'}. '
          'Каждую отметку потом можно снять отдельно.',
      action: 'Отложить ${_num(left)}',
      positive: true,
    );
    if (!ok) return;
    final ids = await BudgetService.markAllPayout(_y, _m, i);
    if (!mounted || ids.isEmpty) return;
    _snack('Отмечено: ${_rub(left)} с выплаты «${v.config.names[i]}»', undo: () => BudgetService.deleteEntries(ids));
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
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Отложено за месяц', style: TextStyle(fontSize: 12.5, color: context.dim))),
              Text.rich(TextSpan(children: [
                TextSpan(text: _num(v.doneTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' из ${_rub(v.plannedTotal)}', style: TextStyle(color: context.dim)),
              ]), style: const TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          _bar(v.progress, AppColors.positive, height: 9),
          const SizedBox(height: 6),
          Text(
            v.complete ? 'Всё отложено ✓' : '$pct%',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: v.complete ? AppColors.positive : context.dim,
            ),
          ),
        ],
      ),
    );
  }

  // --- Таблица трат ---

  static const double _colWidth = 72;

  Widget _divider() => Container(height: 1, color: context.hairline);

  Widget _numCell(String text, {Color? color, FontWeight weight = FontWeight.w600}) {
    return SizedBox(
      width: _colWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: TextStyle(fontSize: 12, color: color ?? context.dim, fontWeight: weight)),
      ),
    );
  }

  Widget _payHead(BudgetMonthView v, int i) {
    return SizedBox(
      width: _colWidth,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v.config.names[i], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          Text('${v.payDay(i)} ${_monthsGen[_m - 1]}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: context.dim)),
        ],
      ),
    );
  }

  Widget _table(BudgetMonthView v) {
    final lines = v.lines.where((l) => !_dismissed.contains(l.category.id)).toList();
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Row(
          children: [
            Expanded(child: Text('Категория', style: TextStyle(fontSize: 11.5, color: context.dim))),
            _payHead(v, 0),
            const SizedBox(width: 6),
            _payHead(v, 1),
          ],
        ),
      ),
    ];
    if (lines.isEmpty) {
      rows.add(_divider());
      rows.add(Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Пока ничего не запланировано. Нажмите «+ Добавить», выберите категорию и сумму, которую нужно отложить '
          'в $_monthIn.',
          style: TextStyle(fontSize: 12.5, color: context.dim, height: 1.4),
        ),
      ));
    }
    for (int i = 0; i < lines.length; i++) {
      rows.add(_divider());
      final row = _dismissibleRow(v, lines[i]);
      rows.add(i == 0 ? TourSpot(id: 'budget_row', child: row) : row);
    }

    Widget footRow(String label, double a, double b, {bool bold = false, bool rest = false}) {
      Color? colorOf(double x) {
        if (!rest) return bold ? Theme.of(context).colorScheme.onSurface : context.dim;
        return x < -0.5 ? AppColors.negative : AppColors.gold;
      }

      String fmt(double x) => rest && x < -0.5 ? '−${_num(-x)}' : _num(x);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: bold ? null : context.dim,
                  )),
            ),
            _numCell(fmt(a), color: colorOf(a), weight: bold || rest ? FontWeight.w700 : FontWeight.w600),
            const SizedBox(width: 6),
            _numCell(fmt(b), color: colorOf(b), weight: bold || rest ? FontWeight.w700 : FontWeight.w600),
          ],
        ),
      );
    }

    rows.add(Container(height: 1.5, color: context.dim.withOpacity(0.35)));
    rows.add(TourSpot(id: 'budget_foot', child: footRow('Итого отложить', v.planned(0), v.planned(1), bold: true)));
    rows.add(_divider());
    rows.add(GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _incomeSheet(v),
      child: footRow('На жизнь', v.data.living, v.data.living),
    ));
    rows.add(_divider());
    rows.add(footRow('Не распределено', v.rest(0), v.rest(1), rest: true));
    if (v.rest(0) < -0.5 || v.rest(1) < -0.5) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Text(
          'Запланировано больше, чем приходит. Уменьшите суммы или сумму на жизнь, '
          'либо перенесите часть на следующий месяц.',
          style: TextStyle(fontSize: 11.5, color: AppColors.negative.withOpacity(0.9), height: 1.35),
        ),
      ));
    } else if (v.freeTotal >= 1) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.gold, visualDensity: VisualDensity.compact),
            onPressed: () => _distributeSheet(v),
            icon: const Icon(Icons.call_split_rounded, size: 16),
            label: Text('Добавить ${_num(v.freeTotal)} к категории', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ));
    }

    return AppCard(
      padding: EdgeInsets.zero,
      radius: AppRadius.sm,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
    );
  }

  Widget _dismissibleRow(BudgetMonthView v, BudgetLine l) {
    final id = l.category.id;
    return Dismissible(
      key: ValueKey('budget-$_y-$_m-$id'),
      direction: l.item == null ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        color: AppColors.negative.withOpacity(0.18),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.negative, size: 20),
            SizedBox(width: 6),
            Text('Убрать', style: TextStyle(color: AppColors.negative, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      onDismissed: (_) async {
        setState(() => _dismissed.add(id));
        final before = BudgetService.monthData(_y, _m);
        await BudgetService.removeItem(_y, _m, id);
        if (!mounted) return;
        _snack('«${l.category.name}» убрана из ${_monthsGen[_m - 1]}',
            undo: before == null ? null : () => BudgetService.restoreMonth(before));
      },
      child: _row(v, l),
    );
  }

  String _subtitle(BudgetLine l) {
    final prev = _shift(_y, _m, -1);
    final next = _shift(_y, _m, 1);
    final parts = <String>['отложено ${_num(l.doneTotal)} из ${_num(l.planTotal)}'];
    if (l.carryTotal > 0.5) parts.add('+${_num(l.carryTotal)} из ${_monthsGen[prev.$2 - 1]}');
    if (l.movedTotal > 0.5) parts.add('${_num(l.movedTotal)} на ${_monthsNom[next.$2 - 1]}');
    return parts.join(' · ');
  }

  Widget _row(BudgetMonthView v, BudgetLine l) {
    final c = l.category;
    return Container(
      color: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _itemMenu(c.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(c.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          c.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _subtitle(l),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: l.complete ? AppColors.positive : context.dim),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _cell(l, 0),
          const SizedBox(width: 6),
          _cell(l, 1),
        ],
      ),
    );
  }

  Widget _cell(BudgetLine l, int i) {
    final plan = l.plan[i];
    final done = l.done[i];
    final isDone = l.cellDone(i);
    final empty = plan <= 0.5 && done <= 0.5;
    final started = done > 0.5 && !isDone;
    String text;
    Color? color;
    if (empty) {
      text = '—';
      color = context.dim;
    } else if (isDone) {
      text = '✓ ${_num(done)}';
      color = AppColors.positive;
    } else if (started) {
      text = '${_num(done)}/${_num(plan)}';
      color = AppColors.gold;
    } else {
      text = _num(plan);
    }
    return Pressable(
      onTap: empty ? null : () => _onCell(l, i),
      child: Container(
        width: _colWidth,
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: empty
              ? Colors.transparent
              : isDone
                  ? AppColors.positive.withOpacity(0.13)
                  : (context.isDark ? Colors.white.withOpacity(0.06) : AppColors.lightSurfaceHigh),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ),
      ),
    );
  }

  Future<void> _onCell(BudgetLine l, int i) async {
    final name = l.category.name;
    final names = BudgetService.config.names;
    if (l.cellDone(i)) {
      final ok = await _confirm(
        title: 'Снять отметку?',
        text: '«$name», ${names[i].toLowerCase()}: отмечено ${_rub(l.done[i])}. Отметка будет удалена.',
        action: 'Снять отметку',
      );
      if (ok) await BudgetService.clearCell(_y, _m, l.category.id, i);
      return;
    }
    await _partSheet(l, i);
  }

  /// Лист ячейки: отложить остаток целиком или свою сумму. Ниже — уже
  /// внесённые части, каждую можно удалить.
  Future<void> _partSheet(BudgetLine l, int i) async {
    final name = l.category.name;
    final payoutName = BudgetService.config.names[i].toLowerCase();
    final ctrl = TextEditingController();
    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final line = BudgetService.view(_y, _m).lines.firstWhere(
              (x) => x.category.id == l.category.id,
              orElse: () => l,
            );
        final plan = line.plan[i];
        final done = line.done[i];
        final left = line.left(i);
        final entries = (BudgetService.monthData(_y, _m)?.entries ?? const <BudgetEntry>[])
            .where((e) => e.category == l.category.id && e.payout == i)
            .toList();
        final custom = double.tryParse(ctrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
        Future<void> add(double amount) async {
          if (amount <= 0) return;
          await BudgetService.addEntry(_y, _m, l.category.id, i, amount);
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted) _snack('Отложено ${_rub(amount)} · $name');
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: '${l.category.emoji} $name · $payoutName',
                subtitle: 'По плану ${_rub(plan)} · отложено ${_rub(done)}',
              ),
              const SizedBox(height: 12),
              MiniProgressBar(value: plan <= 0 ? 0 : (done / plan).clamp(0.0, 1.0), color: AppColors.gold),
              const SizedBox(height: 14),
              if (left > 0.5)
                GradientButton(label: 'Отложить остаток · ${_rub(left)}', onPressed: () => add(left)),
              const SizedBox(height: 10),
              AppTextField(
                controller: ctrl,
                label: 'Или другая сумма',
                number: true,
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 8),
              GradientButton(
                label: custom > 0 ? 'Отложить ${_rub(custom)}' : 'Отложить',
                secondary: true,
                onPressed: custom > 0 ? () => add(custom) : null,
              ),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Уже отложено', style: TextStyle(fontSize: 12, color: context.dim)),
                for (final e in entries)
                  Row(
                    children: [
                      Expanded(
                        child: Text('${_rub(e.amount)} · ${Fmt.dayShort(e.date)}',
                            style: const TextStyle(fontSize: 14)),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        icon: Icon(Icons.close_rounded, size: 18, color: context.dim),
                        onPressed: () async {
                          await BudgetService.deleteEntries([e.id]);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
              ],
            ],
          ),
        );
      }),
    );
    ctrl.dispose();
  }

  // --- Категории ---

  Widget _categoriesList() {
    final cats = BudgetService.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in cats)
              Pressable(
                onTap: () => _editCategory(c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.hairline),
                  ),
                  child: Text('${c.emoji} ${c.name}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          cats.isEmpty
              ? 'Категорий нет. Нажмите «+ Категория», чтобы создать первую.'
              : 'Нажмите на категорию, чтобы переименовать её, сменить значок или удалить.',
          style: TextStyle(fontSize: 11, color: context.dim),
        ),
      ],
    );
  }

  // --- Окна ---

  Future<bool> _confirm({
    required String title,
    required String text,
    required String action,
    bool positive = false,
  }) async {
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
              colors: positive ? null : const [AppColors.negative, Color(0xFFFF7A59)],
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

  Widget _menuAction(
    BuildContext ctx, {
    required IconData icon,
    required String title,
    String? subtitle,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        radius: AppRadius.sm,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 19, color: color ?? ctx.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                  if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Меню месяца «⋮»: доходы, копирование трат, сброс.
  Future<void> _monthMenu(BudgetMonthView v) async {
    final prev = BudgetService.previousFilled(_y, _m);
    await showAppSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: _monthTitle(_y, _m),
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ),
            const SizedBox(height: 14),
            _menuAction(
              ctx,
              icon: Icons.payments_outlined,
              title: 'Доходы месяца',
              subtitle: 'Зарплата, аванс, премии и сколько оставлять на жизнь',
              onTap: () {
                Navigator.pop(ctx);
                _incomeSheet(v);
              },
            ),
            if (prev != null)
              _menuAction(
                ctx,
                icon: Icons.copy_rounded,
                title: 'Скопировать суммы из ${_monthsGen[prev.$2 - 1]}',
                subtitle: 'Что откладывать в этом месяце — возьмётся из ${_monthsGen[prev.$2 - 1]}',
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirm(
                    title: 'Скопировать суммы из ${_monthsGen[prev.$2 - 1]}?',
                    text: 'Категории и суммы в $_monthIn заменятся теми, что были в ${_monthsGen[prev.$2 - 1]}. Отметки останутся.',
                    action: 'Скопировать',
                    positive: true,
                  );
                  if (ok) await BudgetService.copyItems(prev, (_y, _m));
                },
              ),
            _menuAction(
              ctx,
              icon: Icons.restart_alt_rounded,
              title: 'Сбросить ${_monthsNom[_m - 1]}',
              subtitle: 'Месяц станет пустым: удалятся доходы, суммы и все отметки',
              color: AppColors.negative,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm(
                  title: 'Сбросить ${_monthsNom[_m - 1]} $_y?',
                  text: 'Удалятся зарплата, аванс, сумма на жизнь, премии, все суммы и отметки этого месяца. '
                      'Категории и другие месяцы не изменятся.',
                  action: 'Сбросить месяц',
                );
                if (ok) await BudgetService.resetMonth(_y, _m);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Меню траты: отметки, перенос, сумма и способ деления, убрать из месяца.
  Future<void> _itemMenu(String id) async {
    final y = _y;
    final m = _m;
    final next = _shift(y, m, 1);
    final nextName = _monthsNom[next.$2 - 1];
    final initial = BudgetService.view(y, m).lineFor(id);
    final initialAmount = initial?.item?.amount ?? 0;
    final amountCtrl = TextEditingController(text: initialAmount > 0 ? _plain(initialAmount) : '');
    var source = initial?.source ?? BudgetSource.auto;

    await showAppSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: BudgetService.version,
        builder: (ctx, _, __) => StatefulBuilder(
          builder: (ctx, setSheet) {
            final v = BudgetService.view(y, m);
            final l = v.lineFor(id);
            if (l == null) return const SizedBox(height: 120);
            final c = l.category;
            final left = l.leftTotal;

            ButtonStyle outlined(Color color) => OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withOpacity(0.5)),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                );

            final children = <Widget>[
              SheetHeader(
                title: '${c.emoji} ${c.name}',
                subtitle: '${_cap(_monthsNom[m - 1])}: отложено ${_num(l.doneTotal)} из ${_rub(l.planTotal)}',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 12),
            ];

            if (l.planTotal > 0.5) {
              children.add(Row(
                children: [
                  if (left > 0.5) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: outlined(AppColors.positive),
                        onPressed: () async {
                          final ids = await BudgetService.markLeft(y, m, id);
                          if (!mounted) return;
                          if (ids.isNotEmpty) {
                            _snack('Отложено ${_rub(left)} · ${c.name}', undo: () => BudgetService.deleteEntries(ids));
                          }
                        },
                        child: FittedBox(
                          child: Text('✓ Отложил ${_num(left)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      style: outlined(ctx.isDark ? Colors.white : Colors.black87),
                      onPressed: () => _otherAmount(v, l),
                      child: const FittedBox(
                        child: Text('Другая сумма', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ));
              if (left > 0.5) {
                children.add(const SizedBox(height: 6));
                children.add(OutlinedButton(
                  style: outlined(ctx.dim),
                  onPressed: () => BudgetService.moveToNext(y, m, id),
                  child: Text('Перенести ${_num(left)} на $nextName',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ));
              }
            }
            if (l.movedTotal > 0.5) {
              children.add(_menuNote(
                '${_num(l.movedTotal)} перенесено на $nextName',
                'Вернуть',
                () => BudgetService.undoMove(y, m, id),
              ));
            }
            if (l.carryTotal > 0.5) {
              final prev = _shift(y, m, -1);
              children.add(_menuNote('В том числе ${_num(l.carryTotal)} перенесено из ${_monthsGen[prev.$2 - 1]}', null, null));
            }

            children.addAll([
              const SizedBox(height: 16),
              AppTextField(controller: amountCtrl, label: 'Сумма в ${_monthsPrep[m - 1]}, ₽', number: true),
              const SizedBox(height: 12),
              Text('С какой выплаты откладывать', style: TextStyle(fontSize: 12, color: ctx.dim)),
              const SizedBox(height: 6),
              SegmentedToggle<BudgetSource>(
                values: BudgetSource.values,
                selected: source,
                height: 42,
                labelOf: (s) => _sourceLabel(s, v.config),
                onChanged: (s) => setSheet(() => source = s),
              ),
              const SizedBox(height: 4),
              Text(_sourceHint(source, v.config), style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.35)),
              const SizedBox(height: 14),
              GradientButton(
                label: 'Сохранить',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final a = math.max(0.0, _parse(amountCtrl.text) ?? 0);
                  await BudgetService.setItem(y, m, id, BudgetItem(amount: a, source: source));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 6),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.negative),
                onPressed: () async {
                  final before = BudgetService.monthData(y, m);
                  await BudgetService.removeItem(y, m, id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  _snack('«${c.name}» убрана из ${_monthsGen[m - 1]}',
                      undo: before == null ? null : () => BudgetService.restoreMonth(before));
                },
                child: Text('Убрать из ${_monthsGen[m - 1]}'),
              ),
            ]);

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            );
          },
        ),
      ),
    );
  }

  Widget _menuNote(String text, String? action, VoidCallback? onAction) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.gold))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(action,
                    style: TextStyle(fontSize: 12, color: context.accent, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  /// «+ Трата»: категория, сумма, с какой выплаты. Одна трата на категорию в
  /// месяце, поэтому в списке только категории, которых в месяце ещё нет.
  Future<void> _itemSheet(BudgetMonthView v) async {
    String? selected;
    final ctrl = TextEditingController();
    var source = BudgetSource.auto;
    String? error;
    await showAppSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: BudgetService.version,
        builder: (ctx, _, __) => StatefulBuilder(
          builder: (ctx, setSheet) {
            final used = BudgetService.view(_y, _m).data.items.keys.toSet();
            final cats = BudgetService.categories.where((c) => !used.contains(c.id)).toList();
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: 'Что отложить в $_monthIn',
                    subtitle: 'Выберите категорию, сумму и с какой выплаты откладывать',
                    trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ),
                  const SizedBox(height: 14),
                  Text('Категория', style: TextStyle(fontSize: 12, color: ctx.dim)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in cats)
                        ChoiceChip(
                          label: Text('${c.emoji} ${c.name}'),
                          selected: selected == c.id,
                          onSelected: (_) => setSheet(() {
                            selected = c.id;
                            error = null;
                          }),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Новая категория'),
                        onPressed: () async {
                          final created = await _editCategory(null);
                          if (created != null) setSheet(() => selected = created);
                        },
                      ),
                    ],
                  ),
                  if (cats.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Все категории уже есть в $_monthIn. Чтобы изменить сумму, нажмите на нужную строку в таблице, '
                      'или создайте новую категорию.',
                      style: TextStyle(fontSize: 11.5, color: ctx.dim, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: ctrl,
                    label: 'Сумма в $_monthIn, ₽',
                    number: true,
                    onChanged: (_) {
                      if (error != null) setSheet(() => error = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('С какой выплаты откладывать', style: TextStyle(fontSize: 12, color: ctx.dim)),
                  const SizedBox(height: 6),
                  SegmentedToggle<BudgetSource>(
                    values: BudgetSource.values,
                    selected: source,
                    height: 42,
                    labelOf: (s) => _sourceLabel(s, v.config),
                    onChanged: (s) => setSheet(() => source = s),
                  ),
                  const SizedBox(height: 4),
                  Text(_sourceHint(source, v.config), style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.35)),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
                  ],
                  const SizedBox(height: 16),
                  GradientButton(
                    label: 'Добавить',
                    icon: Icons.check_rounded,
                    onPressed: () async {
                      final id = selected;
                      if (id == null) {
                        setSheet(() => error = 'Выберите категорию');
                        return;
                      }
                      final a = _parse(ctrl.text);
                      if (a == null || a <= 0) {
                        setSheet(() => error = 'Укажите сумму');
                        return;
                      }
                      await BudgetService.setItem(_y, _m, id, BudgetItem(amount: a, source: source));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
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
                subtitle: 'Сколько отложено — можно меньше или больше запланированного',
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
                label: 'Отметить',
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

  /// Добавить нераспределённые деньги к трате.
  Future<void> _distributeSheet(BudgetMonthView v) async {
    final cats = BudgetService.categories;
    if (cats.isEmpty) return;
    var selected = cats.first.id;
    for (final l in v.lines) {
      if (cats.any((c) => c.id == l.category.id)) {
        selected = l.category.id;
        break;
      }
    }
    final free = v.freeTotal;
    final ctrl = TextEditingController(text: _plain(free >= 100 ? (free / 100).floor() * 100.0 : free.floorToDouble()));
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
                title: 'Не распределено ${_rub(free)}',
                subtitle: 'Сумма прибавится к выбранной категории в $_monthIn',
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
              Text('К какой категории', style: TextStyle(fontSize: 12, color: ctx.dim)),
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
                label: 'Добавить',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final a = _parse(ctrl.text);
                  if (a == null || a <= 0) {
                    setSheet(() => error = 'Укажите сумму');
                    return;
                  }
                  await BudgetService.addToItem(_y, _m, selected, a);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Доходы месяца: зарплата, аванс, их дни, на жизнь, премии.
  Future<void> _incomeSheet(BudgetMonthView v) async {
    final config = v.config;
    final incomeCtrl = [
      for (int i = 0; i < 2; i++) TextEditingController(text: v.data.income[i] > 0 ? _plain(v.data.income[i]) : ''),
    ];
    final livingCtrl = TextEditingController(text: v.data.living > 0 ? _plain(v.data.living) : '');
    final days = [v.payDay(0), v.payDay(1)];
    final extras = [...v.data.extras];
    final dim = daysInMonth(_y, _m);
    int defaultDay(int i) => config.days[i].scheduled(_y, _m);

    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Доходы · ${_monthsNom[_m - 1]}',
                subtitle: 'Суммы, которые приходят на руки',
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
                        label: days[i] == defaultDay(i) ? 'Когда приходит' : 'Только в этом месяце',
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
                'Если выплата пришла в другой день, например раньше из-за выходных, поменяйте дату — '
                'это касается только этого месяца. Обычные дни выплат задаются в Настройках, раздел «Бюджет».',
                style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.35),
              ),
              const SizedBox(height: 12),
              AppTextField(controller: livingCtrl, label: 'Оставлять на жизнь с каждой выплаты, ₽', number: true),
              const SizedBox(height: 4),
              Text(
                'Эти деньги не распределяются по категориям — они остаются на текущие расходы.',
                style: TextStyle(fontSize: 11, color: ctx.dim, height: 1.35),
              ),
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
                              Text('распределяется вместе с выплатой «${config.names[extras[k].payout]}»',
                                  style: TextStyle(fontSize: 11, color: ctx.dim)),
                            ],
                          ),
                        ),
                        Text(_num(extras[k].amount), style: const TextStyle(fontWeight: FontWeight.w700)),
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
                  label: const Text('Добавить поступление: премию, возврат и т. п.'),
                ),
              ),
              const SizedBox(height: 12),
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
    var payout = existing?.payout ?? (day < config.days[1].scheduled(_y, _m) ? 0 : 1);
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
                subtitle: 'Премия, возврат, подарок — деньги, которые пришли только в этом месяце',
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
              Text('Распределять вместе с выплатой', style: TextStyle(fontSize: 12, color: ctx.dim)),
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

  /// Создать или изменить категорию. Возвращает id созданной категории.
  Future<String?> _editCategory(BudgetCategory? existing) async {
    var emoji = existing?.emoji ?? _emojis.first;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String? error;
    String? createdId;
    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: existing == null ? 'Новая категория' : existing.name,
                subtitle: 'Название и значок. Сколько откладывать, задаётся в каждом месяце',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: nameCtrl,
                label: 'Название',
                autofocus: existing == null,
                onChanged: (_) {
                  if (error != null) setSheet(() => error = null);
                },
              ),
              const SizedBox(height: 12),
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
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: existing == null ? 'Создать' : 'Сохранить',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    setSheet(() => error = 'Введите название');
                    return;
                  }
                  final duplicate = BudgetService.categories
                      .any((c) => c.id != existing?.id && c.name.toLowerCase() == name.toLowerCase());
                  if (duplicate) {
                    setSheet(() => error = 'Категория с таким названием уже есть');
                    return;
                  }
                  final id = existing?.id ?? BudgetService.newId();
                  await BudgetService.saveCategory(
                    existing?.copyWith(name: name, emoji: emoji) ?? BudgetCategory(id: id, name: name, emoji: emoji),
                  );
                  if (existing == null) createdId = id;
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
                      title: 'Удалить категорию «${existing.name}»?',
                      text: 'Её больше нельзя будет добавить в новые месяцы. В месяцах, где она уже есть, '
                          'она останется.',
                      action: 'Удалить',
                    );
                    if (ok) await BudgetService.deleteCategory(existing.id);
                  },
                  child: const Text('Удалить категорию'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return createdId;
  }

  // --- Выбор месяца ---

  Future<void> _pickMonth() async {
    final r = await showMonthPicker(context, _y, _m);
    if (r == null || !mounted) return;
    _go(r.$1, r.$2);
  }
}

class _ExtraResult {
  final BudgetExtra? extra;
  final bool deleted;
  const _ExtraResult({this.extra, this.deleted = false});
}

(String, Color) _statusLabel(BuildContext context, BudgetMonthStatus s) {
  final pct = (s.progress * 100).round();
  return switch (s.state) {
    BudgetMonthState.complete => ('всё отложено', AppColors.positive),
    BudgetMonthState.partial => ('отложено $pct%', AppColors.gold),
    BudgetMonthState.current => ('сейчас · $pct%', context.accent),
    BudgetMonthState.future => ('заполнен', context.dim),
    BudgetMonthState.empty => ('—', context.dim),
  };
}

/// Быстрый выбор месяца: год стрелками, месяц — одним нажатием.
Future<(int, int)?> showMonthPicker(BuildContext context, int year, int month) {
  var y = year;
  final now = DateTime.now();
  return showAppSheet<(int, int)>(
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
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: const Text('Текущий месяц'),
                  onPressed: () => Navigator.pop(ctx, (now.year, now.month)),
                ),
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
    onTap: () => Navigator.pop(ctx, (y, m)),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    ),
  );
}

/// Дни и названия выплат для всех месяцев. Открывается из Настроек.
Future<void> showPayDaysSheet(BuildContext context) async {
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
              title: 'Дни зарплаты и аванса',
              subtitle: 'Когда обычно приходит каждая выплата и как она называется. Действует для всех '
                  'месяцев, кроме прошедших и тех, где дату меняли вручную',
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
                AppTextField(controller: dayCtrl[i], label: 'Число месяца', number: true, integerOnly: true)
              else
                Text(
                  'Например, в ноябре — 30-го, в декабре — 31-го, в феврале — 28-го или 29-го.',
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
                      setSheet(() => error = 'Число месяца — от 1 до 31');
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

/// Плашка бюджета на стартовом экране: сколько отложено за месяц и когда
/// следующая выплата. Нажатие открывает бюджет.
class BudgetSummaryCard extends StatelessWidget {
  final VoidCallback onTap;
  const BudgetSummaryCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppearanceService.revealed,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: BudgetService.version,
        builder: (context, _, __) {
          if (!BudgetService.started) return const SizedBox.shrink();
          final now = DateTime.now();
          final v = BudgetService.view(now.year, now.month);
          if (!v.filled || v.plannedTotal <= 0.5) return const SizedBox.shrink();
          final today = DateTime(now.year, now.month, now.day);
          String inDays(String name, int days) => days == 0 ? '$name сегодня' : '$name через ${_days(days)}';
          String? next;
          int? best;
          for (int i = 0; i < 2; i++) {
            final d = v.payDate(i);
            if (d.isBefore(today)) continue;
            final days = d.difference(today).inDays;
            if (best == null || days < best) {
              best = days;
              next = inDays(v.config.names[i].toLowerCase(), days);
            }
          }
          final pct = (v.progress * 100).round();
          final status = v.complete ? 'Всё отложено ✓' : 'Отложено $pct%';
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 17, color: context.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Бюджет · ${_monthsNom[now.month - 1]}',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: _num(v.doneTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' из ${_rub(v.plannedTotal)}', style: TextStyle(color: context.dim)),
                        ]),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: v.progress,
                      minHeight: 5,
                      color: AppColors.positive,
                      backgroundColor:
                          context.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    next == null ? status : '$status · $next',
                    style: TextStyle(fontSize: 11.5, color: context.dim),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
