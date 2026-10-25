import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/plan.dart';
import '../models/purchase.dart';
import '../services/appearance_service.dart';
import '../services/storage_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_price_service.dart';
import '../services/plan_filter_service.dart';
import '../widgets/security_picker_field.dart';
import '../widgets/ticker_avatar.dart';
import 'home_screen.dart';

/// Период, за который показываются планы. Отсчитывается от сегодняшнего дня
/// вперёд: планы — это будущие покупки, поэтому «месяц» здесь означает
/// «ближайший месяц», а не «прошедший».
/// [calendarYear] — календарный год из [_PlansScreenState._year]; в отличие
/// от [year], это «весь 2027», а не «ближайшие 12 месяцев».
enum _DatePreset { month, threeMonths, year, all, custom, calendarYear }

/// Отбор по состоянию плана.
///
/// «Просрочено» — не поле модели, а вычисление: срок прошёл, а план всё ещё
/// активен. Поэтому фильтр отдельный от [PlanStatus], а не его продолжение.
enum _StatusFilter { all, overdue, pending, done }

/// Сумма планов по одному тикеру за выбранный период — для сводной карточки
/// сверху экрана: объединяет планы с разными датами, если они об одной бумаге.
class _TickerPlanSummary {
  final String ticker;
  final String name;
  final AssetType type;
  final double totalQty;
  final double totalEstimated;
  final int planCount;
  final bool allHavePrice;

  /// Сколько бумаг уже куплено в счёт этих планов и на какую сумму.
  final double purchasedQty;
  final double purchasedMoney;

  _TickerPlanSummary({
    required this.ticker,
    required this.name,
    required this.type,
    required this.totalQty,
    required this.totalEstimated,
    required this.planCount,
    required this.allHavePrice,
    this.purchasedQty = 0,
    this.purchasedMoney = 0,
  });

  double get progress => totalQty <= 0 ? 0 : (purchasedQty / totalQty).clamp(0.0, 1.0);
}

/// Планы, объединённые по общему сроку. Планы без срока попадают в отдельную
/// псевдо-группу с ключом [_PlanGroup.noDateKey].
class _PlanGroup {
  static const noDateKey = '_none';

  final String key;
  final DateTime? date;
  final List<Plan> plans;

  _PlanGroup(this.key, this.date, this.plans);

  double get totalEstimated => plans.fold(0.0, (s, p) => s + (p.estimatedTotal ?? 0));
  bool get allHavePrice => plans.every((p) => p.targetPrice != null);
  int get doneCount => plans.where((p) => p.status == PlanStatus.done).length;


  PlanStatus get status {
    if (plans.every((p) => p.status == PlanStatus.done)) return PlanStatus.done;
    if (plans.every((p) => p.status == PlanStatus.cancelled)) return PlanStatus.cancelled;
    return PlanStatus.active;
  }
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _summaryExpanded = false;
  _DatePreset _preset = _DatePreset.all;
  _StatusFilter _status = _StatusFilter.all;
  DateTimeRange? _customRange;

  /// Выбранный календарный год, если [_preset] — [_DatePreset.calendarYear].
  int? _year;


  /// Сколько условий отличается от «показывать всё» — для счётчика на кнопке.
  int get _activeFilterCount =>
      (_preset == _DatePreset.all ? 0 : 1) + (_status == _StatusFilter.all ? 0 : 1);

  @override
  void initState() {
    super.initState();
    StorageService.dataVersion.addListener(_onDataChanged);
    _restoreFilters();
  }

  void _restoreFilters() {
    final saved = PlanFilterService.saved;
    if (saved == null) return;
    _preset = _DatePreset.values.firstWhere(
      (p) => p.name == saved['preset'],
      orElse: () => _DatePreset.all,
    );
    _status = _StatusFilter.values.firstWhere(
      (st) => st.name == saved['status'],
      orElse: () => _StatusFilter.all,
    );
    _year = (saved['year'] as num?)?.toInt();
    final from = DateTime.tryParse('${saved['from'] ?? ''}');
    final to = DateTime.tryParse('${saved['to'] ?? ''}');
    _customRange = from != null && to != null ? DateTimeRange(start: from, end: to) : null;
    // Запись могла оказаться неполной — тогда не оставляем фильтр, который
    // нечем применить.
    if (_preset == _DatePreset.calendarYear && _year == null) _preset = _DatePreset.all;
    if (_preset == _DatePreset.custom && _customRange == null) _preset = _DatePreset.all;
  }

  /// Фильтры сохраняются всегда — при следующем открытии они те же.
  ///
  /// «Месяц» и «3 месяца» хранятся как пресет, а не как даты: при следующем
  /// открытии они снова отсчитываются от сегодняшнего дня.
  void _persistFilters() {
    PlanFilterService.save({
      'preset': _preset.name,
      'status': _status.name,
      if (_year != null) 'year': _year,
      if (_customRange != null) 'from': _customRange!.start.toIso8601String(),
      if (_customRange != null) 'to': _customRange!.end.toIso8601String(),
    });
  }

  /// Годы, на которые есть планы, по возрастанию.
  ///
  /// Сохранённый год остаётся в списке, даже если его планы уже удалены:
  /// иначе фильтр висел бы невидимым и снять его было бы нечем.
  List<int> get _planYears {
    final years = <int>{
      for (final p in StorageService.plans)
        if (p.targetDate != null) p.targetDate!.year,
    };
    if (_year != null) years.add(_year!);
    return years.toList()..sort();
  }

  @override
  void dispose() {
    StorageService.dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }



  /// Активный план, срок которого прошёл.
  bool _planOverdue(Plan p) {
    final d = p.targetDate;
    if (d == null || p.status != PlanStatus.active) return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Группы по сроку: планы «к дате» — по дате, «на месяц» — по месяцу.
  /// Просроченные — отдельной группой в конце,
  /// планы без срока — последними.
  List<_PlanGroup> _groupByMonth(List<Plan> plans) {
    final map = <String, List<Plan>>{};
    for (final p in plans) {
      final d = p.targetDate;
      // Планы «к дате» — по своей дате, планы «на месяц» — по месяцу.
      final key = d == null
              ? _PlanGroup.noDateKey
              : p.isMonthPlan
                  ? '${d.year}-${d.month.toString().padLeft(2, '0')}-m'
                  : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(p);
    }
    int order(String k) => k == _doneKey ? 4 : k == _overdueKey ? 3 : (k == _PlanGroup.noDateKey ? 2 : 1);
    final groups = [
      for (final e in map.entries)
        _PlanGroup(
          e.key,
          e.value.map((p) => p.targetDate).whereType<DateTime>().fold<DateTime?>(
              null, (a, b) => a == null || b.isAfter(a) ? b : a),
          e.value..sort((a, b) => (a.targetDate ?? DateTime(9999)).compareTo(b.targetDate ?? DateTime(9999))),
        ),
    ]..sort((a, b) {
        final o = order(a.key).compareTo(order(b.key));
        if (o != 0) return o;
        // По сроку: группа «на месяц» — после всех дат этого месяца.
        return (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999));
      });
    return groups;
  }

  bool _matchesFilter(_PlanGroup g) => _matchesDate(g) && _matchesStatus(g);

  bool _matchesDate(_PlanGroup g) {
    // «Без срока» фильтром по дате не скрываем: такой план не привязан ни к
    // какому периоду, и спрятать его значило бы потерять из виду насовсем.
    if (g.date == null) return true;
    final now = DateTime.now();
    switch (_preset) {
      case _DatePreset.all:
        return true;
      case _DatePreset.month:
        return !g.date!.isAfter(DateTime(now.year, now.month + 1, now.day));
      case _DatePreset.threeMonths:
        return !g.date!.isAfter(DateTime(now.year, now.month + 3, now.day));
      case _DatePreset.year:
        return !g.date!.isAfter(DateTime(now.year + 1, now.month, now.day));
      case _DatePreset.custom:
        if (_customRange == null) return true;
        return !g.date!.isBefore(_customRange!.start) && !g.date!.isAfter(_customRange!.end);
      case _DatePreset.calendarYear:
        return _year == null || g.date!.year == _year;
    }
  }

  bool _matchesStatus(_PlanGroup g) {
    switch (_status) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.overdue:
        return _isOverdue(g);
      case _StatusFilter.pending:
        // Ожидающие — активные, но ещё не просроченные: иначе просроченный
        // план попадал бы сразу в два фильтра и «ожидающие» переставали
        // отвечать на вопрос «что впереди».
        return g.status == PlanStatus.active && !_isOverdue(g);
      case _StatusFilter.done:
        return g.status == PlanStatus.done;
    }
  }

  bool _isOverdue(_PlanGroup g) {
    if (g.date == null) return false;
    final now = DateTime.now();
    return g.date!.isBefore(DateTime(now.year, now.month, now.day)) &&
        g.status == PlanStatus.active;
  }

  String _presetLabel(_DatePreset p) {
    switch (p) {
      case _DatePreset.all:
        return 'Всё время';
      case _DatePreset.month:
        return 'Месяц';
      case _DatePreset.threeMonths:
        return '3 месяца';
      case _DatePreset.year:
        return 'Год';
      case _DatePreset.custom:
        return _customRange == null
            ? 'Свой период'
            : '${Fmt.date(_customRange!.start)} – ${Fmt.date(_customRange!.end)}';
      case _DatePreset.calendarYear:
        return _year == null ? 'Год' : '$_year год';
    }
  }

  String _statusLabel(_StatusFilter s) {
    switch (s) {
      case _StatusFilter.all:
        return 'Все';
      case _StatusFilter.overdue:
        return 'Просроченные';
      case _StatusFilter.pending:
        return 'Ожидающие';
      case _StatusFilter.done:
        return 'Завершённые';
    }
  }

  String _periodPhrase() {
    switch (_preset) {
      case _DatePreset.all:
        return 'за всё время';
      case _DatePreset.month:
        return 'на ближайший месяц';
      case _DatePreset.threeMonths:
        return 'на 3 месяца';
      case _DatePreset.year:
        return 'на год';
      case _DatePreset.custom:
        return _customRange != null
            ? 'за ${Fmt.date(_customRange!.start)} – ${Fmt.date(_customRange!.end)}'
            : 'за выбранный период';
      case _DatePreset.calendarYear:
        return _year == null ? 'за всё время' : 'на $_year год';
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = StorageService.plans;
    // Отбор — по каждому плану, а уже потом группировка по месяцам: в одном
    // месяце бывают планы с разными сроками и состояниями.
    final visible = all.where((p) => _matchesFilter(_PlanGroup('', p.targetDate, [p]))).toList();
    final groups = _groupByMonth(visible.where((p) => p.status == PlanStatus.active && !_planOverdue(p)).toList());
    final overdueGroups = _groupByMonth(visible.where(_planOverdue).toList()).reversed.toList();
    final doneGroups = _groupByMonth(visible.where((p) => p.status != PlanStatus.active).toList()).reversed.toList();
    final nothing = groups.isEmpty && overdueGroups.isEmpty && doneGroups.isEmpty;

    // Итог по периоду: все видимые планы, кроме отменённых — они больше не
    // считаются планом.
    final periodPlans = visible.where((p) => p.status != PlanStatus.cancelled).toList();
    final periodTotal = periodPlans.fold(0.0, (s, p) => s + (p.estimatedTotal ?? 0));
    final allHavePrice = periodPlans.isNotEmpty && periodPlans.every((p) => p.targetPrice != null);
    final byTicker = _summarizeByTicker(periodPlans);
    // Прогресс считается по деньгам, а не по числу завершённых планов: план
    // на 100 акций, из которых куплено 99, при подсчёте «по планам» давал
    // ровно 0%. Сумма берётся по средней цене засчитанных сделок — это факт.
    final purchasedMoney =
        periodPlans.fold(0.0, (s, p) => s + p.purchasedQuantity * p.purchasedAvgPrice);
    final overdueCount = periodPlans.where(_planOverdue).length;

    return PageTour(
      pageId: 'plans',
      steps: const [
        PageTourStep(
          anchor: 'fab',
          title: 'Новый план',
          text: 'Что и когда Вы собираетесь купить. Приложение рассчитает необходимую сумму.',
        ),
        PageTourStep(
          anchor: 'list',
          title: 'Прогресс по планам',
          text: 'Купленное засчитывается автоматически, если при записи сделки отметить «учитывать в плане».',
        ),
      ],
      child: Scaffold(
      body: TourSpot(
        id: 'list',
        child: SafeArea(
        bottom: false,
        child: all.isEmpty
            ? const EmptyState(
                icon: Icons.flag_rounded,
                title: 'Планов пока нет',
                subtitle: 'Запланируйте будущие покупки — приложение соберёт их по срокам '
                    'и посчитает, сколько денег на это понадобится.',
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Планы', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                        const SizedBox(height: 10),
                        _filterBar(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: nothing
                        ? Center(
                            child: Text(
                              'Нет планов за выбранный период',
                              style: TextStyle(color: context.dim, fontSize: 13),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            children: [
                              if (periodPlans.isNotEmpty)
                                FadeSlideIn(
                                  child: _summaryCard(
                                    total: periodTotal,
                                    allHavePrice: allHavePrice,
                                    byTicker: byTicker,
                                    purchasedMoney: purchasedMoney,
                                    count: periodPlans.length,
                                    overdue: overdueCount,
                                  ),
                                ),
                              for (final g in groups) _monthGroup(g),
                              if (overdueGroups.isNotEmpty) _foldSection(_overdueKey, overdueGroups),
                              if (doneGroups.isNotEmpty) _foldSection(_doneKey, doneGroups),
                              const SizedBox(height: kListBottomPadding),
                            ],
                          ),
                  ),
                ],
              ),
      ),
      ),
      floatingActionButton: TourSpot(
        id: 'fab',
        child: FloatingActionButton.extended(
        // Без heroTag Flutter считает все кнопки действия одной и той же и
        // при переходе между экранами перетекает одну в другую: на списке
        // портфелей «+ Портфель» на глазах превращался в «+ План».
        heroTag: null,
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('План', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      ),
      ),
    );
  }

  /// Кнопка фильтров плюс ряд снятых одним касанием условий.
  ///
  /// Раньше здесь была горизонтальная лента пилюль. Она занимала строку под
  /// заголовком на каждом экране и вмещала только отбор по дате — добавить
  /// второе измерение (статус) было некуда. Один вход в лист, как на бирже,
  /// освобождает место и снимает это ограничение.
  Widget _filterBar() {
    final active = _activeFilterCount;
    return Row(
      children: [
        Expanded(
          child: Text(
            active == 0
                ? 'Показаны все планы'
                : [
                    if (_preset != _DatePreset.all) _presetLabel(_preset),
                    if (_status != _StatusFilter.all) _statusLabel(_status),
                  ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: context.dim, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: _openFilterSheet,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: AppRadius.all(AppRadius.sm),
              color: active > 0
                  ? context.accent.withOpacity(0.16)
                  : (context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh),
              border: Border.all(
                color: active > 0 ? context.accent.withOpacity(0.5) : context.hairline,
                width: active > 0 ? 1.4 : 1.2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.tune_rounded, size: 20, color: active > 0 ? context.accent : context.dim),
                if (active > 0)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.accent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '$active',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openFilterSheet() async {
    final years = _planYears;
    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Фильтры',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  if (_activeFilterCount > 0)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _preset = _DatePreset.all;
                          _status = _StatusFilter.all;
                          _customRange = null;
                          _year = null;
                        });
                        setSheetState(() {});
                      },
                      child: const Text('Сбросить'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Срок', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in [
                    _DatePreset.month,
                    _DatePreset.threeMonths,
                    _DatePreset.year,
                    _DatePreset.all,
                  ])
                    _filterPill(
                      label: _presetLabel(preset),
                      selected: _preset == preset,
                      onTap: () {
                        setState(() {
                          _preset = preset;
                          _year = null;
                        });
                        setSheetState(() {});
                      },
                    ),
                  _filterPill(
                    label: _presetLabel(_DatePreset.custom),
                    icon: Icons.date_range_rounded,
                    selected: _preset == _DatePreset.custom,
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 5),
                        initialDateRange: _customRange,
                      );
                      if (picked == null) return;
                      setState(() {
                        _customRange = picked;
                        _preset = _DatePreset.custom;
                        _year = null;
                      });
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
              // Годы — одной прокручиваемой строкой: сколько бы их ни было,
              // они занимают одну высоту и не раздувают лист. Год и пресеты
              // выше исключают друг друга: оба фильтруют по дате, и вместе
              // («Месяц» плюс «2028») давали бы заведомо пустой список.
              if (years.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Или выберите год', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.dim)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: years.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final y = years[i];
                      final isOn = _preset == _DatePreset.calendarYear && _year == y;
                      return Center(
                        child: _filterPill(
                          label: '$y',
                          selected: isOn,
                          onTap: () {
                            // Повторное касание снимает год.
                            setState(() {
                              _preset = isOn ? _DatePreset.all : _DatePreset.calendarYear;
                              _year = isOn ? null : y;
                            });
                            setSheetState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text('Статус', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in _StatusFilter.values)
                    _filterPill(
                      label: _statusLabel(status),
                      selected: _status == status,
                      onTap: () {
                        setState(() => _status = status);
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 18),
              GradientButton(
                label: 'Показать',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
    // Фильтры меняются только внутри листа, поэтому сохраняем один раз —
    // когда он закрылся, а не на каждое нажатие.
    _persistFilters();
  }

  Widget _filterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final accent = context.accent;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: selected ? AppGradient.accent(accent) : null,
          color: selected ? null : (context.isDark ? Colors.white.withOpacity(0.05) : Colors.white),
          border: Border.all(color: selected ? Colors.transparent : context.hairline),
          boxShadow: selected
              ? [BoxShadow(color: accent.withOpacity(0.32), blurRadius: 14, offset: const Offset(0, 5))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : context.dim),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : context.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_TickerPlanSummary> _summarizeByTicker(List<Plan> plans) {
    final map = <String, _TickerPlanSummary>{};
    for (final p in plans) {
      final estimated = p.estimatedTotal ?? 0;
      final existing = map[p.ticker];
      if (existing == null) {
        map[p.ticker] = _TickerPlanSummary(
          ticker: p.ticker,
          name: p.name,
          type: p.type,
          totalQty: p.targetQuantity,
          totalEstimated: estimated,
          planCount: 1,
          allHavePrice: p.targetPrice != null,
          purchasedQty: p.purchasedQuantity,
          purchasedMoney: p.purchasedQuantity * p.purchasedAvgPrice,
        );
      } else {
        map[p.ticker] = _TickerPlanSummary(
          ticker: existing.ticker,
          name: existing.name,
          type: existing.type,
          totalQty: existing.totalQty + p.targetQuantity,
          totalEstimated: existing.totalEstimated + estimated,
          planCount: existing.planCount + 1,
          allHavePrice: existing.allHavePrice && p.targetPrice != null,
          purchasedQty: existing.purchasedQty + p.purchasedQuantity,
          purchasedMoney: existing.purchasedMoney + p.purchasedQuantity * p.purchasedAvgPrice,
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.totalEstimated.compareTo(a.totalEstimated));
    return list;
  }

  /// Сводка по всем планам выбранного периода: сколько нужно денег, общий
  /// прогресс, сколько куплено, сколько планов и сколько просрочено. По
  /// нажатию раскрывается разбивка по бумагам.
  Widget _summaryCard({
    required double total,
    required bool allHavePrice,
    required List<_TickerPlanSummary> byTicker,
    required double purchasedMoney,
    required int count,
    required int overdue,
  }) {
    final accent = context.accent;
    final hidden = AppearanceService.amountsHidden;
    final progress = total <= 0 ? 0.0 : (purchasedMoney / total).clamp(0.0, 1.0);
    Widget stat(String label, String value, Color? color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.dim)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Pressable(
            onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Нужно ${_periodPhrase()}', style: TextStyle(fontSize: 13, color: context.dim)),
                      ),
                      Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 13, color: context.dim)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    total <= 0 ? '—' : (hidden ? '••• ₽' : '≈ ${Fmt.money(total)}'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6),
                  ),
                  if (total > 0 && !allHavePrice)
                    Text('цена указана не у всех', style: TextStyle(fontSize: 11.5, color: context.dim)),
                  const SizedBox(height: 10),
                  MiniProgressBar(value: progress, color: AppColors.positive),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      stat('Куплено', hidden ? '••• ₽' : Fmt.money(purchasedMoney), AppColors.positive),
                      stat('Покупок', '$count', null),
                      stat('Просрочено', '$overdue', overdue > 0 ? AppColors.negative : null),
                      AnimatedRotation(
                        turns: _summaryExpanded ? 0.5 : 0,
                        duration: AppDuration.fast,
                        child: Icon(Icons.expand_more_rounded, color: context.dim),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  Divider(color: context.hairline, height: 1),
                  const SizedBox(height: 6),
                  ...byTicker.map((t) => _summaryRow(t, accent)),
                ],
              ),
            ),
            crossFadeState: _summaryExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AppDuration.normal,
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(_TickerPlanSummary t, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          TickerAvatar(ticker: t.ticker, size: 30, glow: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                Text(
                  // Без упоминания числа планов: сколько раз бумага
                  // встречается в планах, при взгляде на прогресс не помогает.
                  t.purchasedQty > 0
                      ? '${Fmt.assetType(t.type)} · куплено ${Fmt.qty(t.purchasedQty)} из ${Fmt.qty(t.totalQty)} шт'
                      : '${Fmt.assetType(t.type)} · ${Fmt.qty(t.totalQty)} шт',
                  style: TextStyle(fontSize: 11, color: context.dim),
                ),
                if (t.purchasedQty > 0) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: t.progress,
                      minHeight: 4,
                      backgroundColor: accent.withOpacity(0.15),
                      valueColor: const AlwaysStoppedAnimation(AppColors.positive),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t.totalEstimated > 0 ? '≈${Fmt.money(t.totalEstimated)}' : '—',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: accent),
              ),
              if (t.purchasedQty > 0)
                Text(
                  '${(t.progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.positive,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Ключ, под которым запоминается, свёрнута ли группа.
  String _foldKey(String section, _PlanGroup g) => 'plansG:$section:${g.key}';
  bool _isOpen(String key, {bool byDefault = true}) {
    final v = AppearanceService.ui(key);
    return v == null ? byDefault : v == 'open';
  }

  Future<void> _toggle(String key, bool open) async {
    await AppearanceService.setUi(key, open ? 'closed' : 'open');
    if (mounted) setState(() {});
  }

  String _titleOf(_PlanGroup g) => g.key == _PlanGroup.noDateKey ? 'Без срока' : _groupTitle(g);

  /// Кнопка «⋯» группы. Меню появляется прямо под кнопкой, а если снизу
  /// не хватает места — над ней.
  Widget _groupMenuButton(_PlanGroup g, {required String foldKey, required bool open, required String section}) {
    return Builder(
      builder: (btnCtx) => SizedBox(
        width: 34,
        height: 30,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_horiz_rounded, size: 18, color: context.dim),
          onPressed: () => _openGroupMenu(btnCtx, g, foldKey: foldKey, open: open, section: section),
        ),
      ),
    );
  }

  Future<void> _openGroupMenu(BuildContext btnCtx, _PlanGroup g,
      {required String foldKey, required bool open, required String section}) async {
    final hasActive = g.plans.any((p) => p.status == PlanStatus.active);
    final items = <(String, String, bool)>[
      ('fold', open ? 'Свернуть группу' : 'Развернуть группу', false),
      if (section != _doneKey) ('move', 'Перенести на месяц…', false),
      if (hasActive) ('done', 'Отметить выполненными', false),
      ('delete', 'Удалить группу', true),
    ];
    final box = btnCtx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
    final menuHeight = items.length * 48.0 + 16;
    final screenBottom = overlay.size.height - MediaQuery.of(context).padding.bottom - 90;
    final below = pos.dy + box.size.height + menuHeight <= screenBottom;
    final top = below ? pos.dy + box.size.height : pos.dy - menuHeight;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        top,
        overlay.size.width - pos.dx - box.size.width,
        overlay.size.height - top,
      ),
      color: context.isDark ? AppColors.darkSurfaceTop : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        for (final (v, label, danger) in items)
          PopupMenuItem(
            value: v,
            child: Text(label, style: TextStyle(color: danger ? AppColors.negative : null, fontSize: 15)),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'fold':
        await _toggle(foldKey, open);
      case 'move':
        final picked = await showDialog<DateTime>(
          context: context,
          builder: (_) => _MonthPickerDialog(initial: g.date ?? DateTime.now()),
        );
        if (picked == null) return;
        for (final p in g.plans) {
          p.targetDate = _monthEnd(picked);
          p.wholeMonth = true;
          await StorageService.updatePlan(p);
        }
        if (mounted) setState(() {});
      case 'done':
        for (final p in g.plans.where((p) => p.status == PlanStatus.active)) {
          p.status = PlanStatus.done;
          await StorageService.updatePlan(p);
        }
        if (mounted) setState(() {});
      case 'delete':
        await _confirmDeleteGroup(g);
    }
  }

  Widget _rowsBlock(List<Plan> plans) => Column(
        children: [
          for (int i = 0; i < plans.length; i++) ...[
            // Полоса фона между планами — каждый план читается отдельно.
            if (i > 0) Container(height: 6, color: context.isDark ? AppColors.darkBg : AppColors.lightBg),
            _planRow(plans[i]),
          ],
        ],
      );

  /// Группа по сроку. Открытая — заголовок и карточка с покупками;
  /// свёрнутая — одна карточка со сводкой.
  Widget _monthGroup(_PlanGroup g) {
    final hidden = AppearanceService.amountsHidden;
    final foldKey = _foldKey('a', g);
    final open = _isOpen(foldKey);
    final title = _titleOf(g);
    final sum = g.totalEstimated;
    final surface = context.isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final menu = _groupMenuButton(g, foldKey: foldKey, open: open, section: 'a');

    if (!open) {
      final bought = g.plans.fold(0.0, (s, p) => s + p.purchasedQuantity * p.purchasedAvgPrice);
      final progress = sum <= 0 ? 0.0 : (bought / sum).clamp(0.0, 1.0);
      final tickers = <String>[];
      for (final p in g.plans) {
        if (!tickers.contains(p.ticker)) tickers.add(p.ticker);
      }
      final shown = tickers.take(3).toList();
      final n = g.plans.length;
      final caption = '$n ${Fmt.purchases(n)} · '
          '${bought <= 0 ? 'ничего не куплено' : hidden ? 'куплено •••' : 'куплено на ${Fmt.money(bought)}'}';
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Material(
          color: surface,
          borderRadius: AppRadius.all(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _toggle(foldKey, open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: context.dim),
                      menu,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26.0 + (shown.length - 1) * 16,
                          height: 26,
                          child: Stack(
                            children: [
                              for (int i = 0; i < shown.length; i++)
                                Positioned(
                                  left: i * 16.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: surface, width: 2),
                                    ),
                                    child: TickerAvatar(ticker: shown[i], size: 22, glow: false),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(caption, style: TextStyle(fontSize: 12.5, color: context.dim)),
                        ),
                        const SizedBox(width: 8),
                        if (sum > 0)
                          Text(
                            hidden ? '•••' : '≈ ${Fmt.money(sum)}',
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Expanded(child: MiniProgressBar(value: progress, color: context.accent)),
                        const SizedBox(width: 10),
                        Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 12, color: context.dim)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggle(foldKey, open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    '${g.plans.length}${sum > 0 ? ' · ${hidden ? '•••' : '≈ ${Fmt.money(sum)}'}' : ''}',
                    style: TextStyle(fontSize: 12.5, color: context.dim),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: context.dim),
                  menu,
                ],
              ),
            ),
          ),
          ClipRRect(
            borderRadius: AppRadius.all(AppRadius.md),
            child: Container(color: surface, child: _rowsBlock(g.plans)),
          ),
        ],
      ),
    );
  }

  /// «Просрочено» и «Выполнено» (с отменёнными) — внизу, свёрнутым блоком.
  /// Внутри — те же группы по срокам, каждая сворачивается.
  Widget _foldSection(String section, List<_PlanGroup> groups) {
    final hidden = AppearanceService.amountsHidden;
    final overdue = section == _overdueKey;
    final uiKey = 'plansFold$section';
    final open = _isOpen(uiKey, byDefault: false);
    final count = groups.fold(0, (s, g) => s + g.plans.length);
    final sum = groups.fold(0.0, (s, g) => s + g.totalEstimated);
    final dot = overdue ? AppColors.negative : AppColors.positive;
    final bg = context.isDark ? AppColors.darkBg : AppColors.lightBg;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: AppRadius.all(AppRadius.md),
        child: Container(
          color: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => _toggle(uiKey, open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${overdue ? 'Просрочено' : 'Выполнено'} · $count',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (sum > 0)
                        Text(hidden ? '•••' : '≈ ${Fmt.money(sum)}', style: TextStyle(fontSize: 13, color: context.dim)),
                      const SizedBox(width: 6),
                      Icon(
                        open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: context.dim,
                      ),
                    ],
                  ),
                ),
              ),
              if (open)
                for (final g in groups) ...[
                  Container(height: 6, color: bg),
                  _subGroup(section, g),
                ],
            ],
          ),
        ),
      ),
    );
  }

  /// Группа по сроку внутри «Просрочено» или «Выполнено».
  Widget _subGroup(String section, _PlanGroup g) {
    final hidden = AppearanceService.amountsHidden;
    final foldKey = _foldKey(section, g);
    final open = _isOpen(foldKey);
    final sum = g.totalEstimated;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _toggle(foldKey, open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _titleOf(g),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.dim),
                  ),
                ),
                Text(
                  '${g.plans.length}${sum > 0 ? ' · ${hidden ? '•••' : '≈ ${Fmt.money(sum)}'}' : ''}',
                  style: TextStyle(fontSize: 12, color: context.dim),
                ),
                const SizedBox(width: 4),
                Icon(
                  open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: context.dim,
                ),
                _groupMenuButton(g, foldKey: foldKey, open: open, section: section),
              ],
            ),
          ),
        ),
        if (open) _rowsBlock(g.plans),
      ],
    );
  }

  /// «До 15 декабря» или «На декабрь 2026». Год пишется, если он не текущий.
  String _groupTitle(_PlanGroup g) {
    final d = g.date!;
    final month = Fmt.monthTitle('${d.year}-${d.month}');
    if (g.key.endsWith('-m')) {
      final m = month.split(' ').first.toLowerCase();
      return d.year == DateTime.now().year ? 'На $m' : 'На $m ${d.year}';
    }
    final long = Fmt.dateLong(d);
    return 'До ${d.year == DateTime.now().year ? long.substring(0, long.lastIndexOf(' ')) : long}';
  }

  Widget _planRow(Plan p) {
    final isDone = p.status == PlanStatus.done;
    final isCancelled = p.status == PlanStatus.cancelled;
    final overdue = _planOverdue(p);
    final progress = p.targetQuantity <= 0 ? 0.0 : (p.purchasedQuantity / p.targetQuantity).clamp(0.0, 1.0);
    final barColor = overdue
        ? AppColors.negative
        : isDone
            ? AppColors.positive
            : context.accent;

    // На оставшиеся по плану деньги лот уже не купить — подсказываем, что
    // план можно закрыть вручную.
    final spent = p.purchasedQuantity * p.purchasedAvgPrice;
    final budget = p.estimatedTotal;
    final remainingBudget = budget != null ? (budget - spent) : null;
    final quote = MoexSyncService.marketSnapshot.value[p.ticker.toUpperCase()];
    final cached = OnlinePriceService.get(p.ticker);
    final currentPrice = quote?.price ?? cached?.price;
    final lotSize = quote?.lotSize ?? cached?.lotSize ?? 1;
    final cantAffordMore = p.status == PlanStatus.active &&
        p.purchasedQuantity > 0 &&
        p.purchasedQuantity < p.targetQuantity &&
        remainingBudget != null &&
        currentPrice != null &&
        currentPrice > 0 &&
        remainingBudget < currentPrice * lotSize;

    return Dismissible(
      key: Key(p.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      background: Container(
        color: AppColors.negative,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        StorageService.deletePlan(p.id);
        setState(() {});
      },
      child: InkWell(
        onTap: () => _showAddSheet(context, existing: p),
        onLongPress: () => _showStatusMenu(p),
        child: Opacity(
          opacity: isCancelled ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TickerAvatar(ticker: p.ticker, size: 36, glow: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              decoration: isDone || isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${Fmt.qty(p.purchasedQuantity)} из ${Fmt.qty(p.targetQuantity)} шт'
                            '${p.targetPrice != null ? ' · до ${Fmt.price(p.targetPrice!, type: p.type)}' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: context.dim),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (budget != null && budget > 0)
                          HiddenAmount.forText(
                            '≈ ${Fmt.money(budget)}',
                            fontSize: 15,
                            child: Text(
                              '≈ ${Fmt.money(budget)}',
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        Text(
                          isDone ? 'готово' : isCancelled ? 'отменён' : '${(progress * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isDone ? FontWeight.w700 : null,
                            color: isDone ? AppColors.positive : overdue ? AppColors.negative : context.dim,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if ((p.note ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, top: 8),
                    child: Text(
                      '«${p.note!.trim()}»',
                      style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: context.dim),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 48, top: 9),
                  child: MiniProgressBar(value: isDone ? 1 : progress, color: barColor),
                ),
                if (cantAffordMore) ...[
                  const SizedBox(height: 6),
                  Text(
                    'На остаток плана лот по ${Fmt.price(currentPrice!, type: p.type)} уже не купить — '
                    'можно отметить выполненным',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.warning),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Долгое нажатие на план: сменить состояние или удалить.
  Future<void> _showStatusMenu(Plan p) async {
    final choice = await showAppSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(title: p.name),
              for (final (value, label) in const [
                ('active', 'Активный'),
                ('done', 'Выполнен'),
                ('cancelled', 'Отменён'),
              ])
                ListTile(
                  title: Text(label),
                  trailing: p.status.name == value ? Icon(Icons.check_rounded, color: ctx.accent) : null,
                  onTap: () => Navigator.pop(ctx, value),
                ),
              ListTile(
                title: const Text('Удалить план', style: TextStyle(color: AppColors.negative)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'delete') {
      if (await _confirmDelete(context)) {
        await StorageService.deletePlan(p.id);
      }
    } else {
      p.status = PlanStatus.values.byName(choice);
      await StorageService.updatePlan(p);
    }
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить план?'),
            content: const Text('Запланированная покупка будет удалена без возможности восстановления.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _confirmDeleteGroup(_PlanGroup g) async {
    final label = g.key == _PlanGroup.noDateKey
            ? 'без срока'
            : '«${_groupTitle(g)}»';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: Text(
          'Будет удалено ${g.plans.length} ${Fmt.purchases(g.plans.length)} $label — без возможности восстановления.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final p in g.plans) {
        await StorageService.deletePlan(p.id);
      }
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Форма создания и редактирования плана
  // ---------------------------------------------------------------------------

  void _showAddSheet(BuildContext context, {Plan? existing}) {
    final editing = existing != null;
    final initialQuote = existing == null
        ? null
        : MoexSyncService.marketSnapshot.value[existing.ticker.toUpperCase()];
    final initialCached = existing == null
        ? null
        : OnlinePriceService.get(existing.ticker);
    int lotSize = initialQuote?.lotSize ?? initialCached?.lotSize ?? 1;
    if (existing != null && existing.targetQuantity % lotSize != 0) lotSize = 1;

    final tickerCtrl = TextEditingController(text: existing?.ticker ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final qtyCtrl = TextEditingController(
      text: existing == null ? '' : Fmt.qty(existing.targetQuantity / lotSize),
    );
    final priceCtrl = TextEditingController(
      text: existing?.targetPrice == null
          ? ''
          : Fmt.priceInput(existing!.targetPrice!, type: existing.type),
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    AssetType type = existing?.type ?? AssetType.stock;
    String selectedTicker = existing?.ticker.toUpperCase() ?? '';
    bool priceEdited = existing != null;
    DateTime? targetDate = existing?.targetDate;
    // Тип плана: «к дате» или «на месяц». У нового плана — тот, что выбирали
    // в прошлый раз.
    bool monthPlan = existing != null
        ? existing.isMonthPlan
        : AppearanceService.ui(_planTypeKey) == 'month';

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
          final lots = int.tryParse(qtyCtrl.text) ?? 0;
          final qty = lots * lotSize.toDouble();
          final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
          final estimated = qty * price;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: editing ? 'Редактировать план' : 'Новый план',
                  subtitle: editing ? 'Измените параметры запланированной покупки' : 'Что и когда Вы хотите купить',
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(height: 18),
                SecurityPickerField(
                  onSelected: (s) async {
                    final key = s.ticker.toUpperCase();
                    selectedTicker = key;
                    priceEdited = false;
                    tickerCtrl.text = key;
                    nameCtrl.text = s.name;
                    final quote =
                        MoexSyncService.marketSnapshot.value[key];
                    final cached = OnlinePriceService.get(key);
                    final currentPrice = quote?.price ?? cached?.price;
                    if (currentPrice != null && currentPrice > 0) {
                      priceCtrl.text = Fmt.priceInput(currentPrice, type: s.type);
                    }
                    setSheetState(() {
                      type = s.type;
                      lotSize = quote?.lotSize ?? cached?.lotSize ?? 1;
                      if (qtyCtrl.text.isEmpty) qtyCtrl.text = '1';
                    });

                    // Даже при закрытой бирже уточняем последнюю доступную
                    // цену и лот выбранной бумаги. Весь рынок не загружается.
                    final fresh = await MoexSyncService.instance.fetchQuote(key);
                    if (!ctx.mounted || fresh == null || selectedTicker != key) return;
                    setSheetState(() {
                      lotSize = fresh.lotSize;
                      if (!priceEdited && fresh.price > 0) {
                        priceCtrl.text = Fmt.priceInput(fresh.price, type: s.type);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: tickerCtrl,
                        label: 'Тикер',
                        upperCase: true,
                        onChanged: (value) => setSheetState(() {
                          lotSize = MoexSyncService
                                  .marketSnapshot.value[value.trim().toUpperCase()]?.lotSize ??
                              1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: AppTextField(controller: nameCtrl, label: 'Название')),
                  ],
                ),
                const SizedBox(height: 12),
                AppDropdown<AssetType>(
                  value: type,
                  label: 'Тип актива',
                  icon: Icons.category_outlined,
                  items: AssetType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(Fmt.assetType(t))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => type = v ?? AssetType.stock),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Уменьшить на один лот',
                      icon: const Icon(Icons.remove_rounded),
                      onPressed: () => setSheetState(() {
                        qtyCtrl.text = '${((int.tryParse(qtyCtrl.text) ?? 0) - 1).clamp(1, 1000000)}';
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppTextField(
                        controller: qtyCtrl,
                        label: 'Количество лотов',
                        number: true,
                        integerOnly: true,
                        suffixText: '× $lotSize шт.',
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Добавить один лот',
                      icon: const Icon(Icons.add_rounded),
                      onPressed: () => setSheetState(() {
                        qtyCtrl.text = '${((int.tryParse(qtyCtrl.text) ?? 0) + 1).clamp(1, 1000000)}';
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InfoBanner(
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.info,
                  text: '$lots лот. × $lotSize шт. = ${Fmt.qty(qty)} шт.',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: priceCtrl,
                  label: 'Желаемая цена за одну бумагу',
                  number: true,
                  onChanged: (_) {
                    priceEdited = true;
                    setSheetState(() {});
                  },
                ),
                if (estimated > 0) ...[
                  const SizedBox(height: 12),
                  InfoBanner(
                    icon: Icons.calculate_outlined,
                    color: context.accent,
                    text: 'Понадобится примерно ${Fmt.money(estimated)}',
                  ),
                ],
                const SizedBox(height: 12),
                SegmentedToggle<bool>(
                  values: const [false, true],
                  selected: monthPlan,
                  labelOf: (m) => m ? 'На месяц' : 'К дате',
                  onChanged: (m) => setSheetState(() {
                    monthPlan = m;
                    // Дата превращается в конец своего месяца и обратно —
                    // выбранный срок не теряется при переключении.
                    if (m && targetDate != null) targetDate = _monthEnd(targetDate!);
                  }),
                ),
                const SizedBox(height: 10),
                if (monthPlan)
                  _MonthField(
                    value: targetDate,
                    onPicked: (d) => setSheetState(() => targetDate = d == null ? null : _monthEnd(d)),
                  )
                else
                  AppDateField(
                    value: targetDate,
                    label: 'Срок (необязательно)',
                    emptyLabel: 'Без срока',
                    firstDate: existing?.targetDate != null && existing!.targetDate!.isBefore(DateTime.now())
                        ? existing.targetDate
                        : DateTime.now(),
                    lastDate: DateTime(2100),
                    onPicked: (d) => setSheetState(() => targetDate = d),
                  ),
                const SizedBox(height: 12),
                AppTextField(controller: noteCtrl, label: 'Заметка (необязательно)'),
                const SizedBox(height: 22),
                GradientButton(
                  label: editing ? 'Сохранить изменения' : 'Добавить план',
                  icon: editing ? Icons.save_outlined : Icons.flag_rounded,
                  onPressed: () async {
                    final enteredLots = int.tryParse(qtyCtrl.text);
                    // Запоминаем тип — в следующий раз подставится он же.
                    AppearanceService.setUi(_planTypeKey, monthPlan ? 'month' : 'date');
                    final p = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
                    if (tickerCtrl.text.isEmpty || enteredLots == null || enteredLots <= 0) return;
                    if (existing == null) {
                      await StorageService.addPlan(Plan(
                        id: const Uuid().v4(),
                        ticker: tickerCtrl.text.toUpperCase(),
                        name: nameCtrl.text.isEmpty ? tickerCtrl.text : nameCtrl.text,
                        type: type,
                        targetQuantity: enteredLots * lotSize.toDouble(),
                        targetPrice: p,
                        targetDate: targetDate,
                        note: noteCtrl.text.isEmpty ? null : noteCtrl.text,
                        createdAt: DateTime.now(),
                        wholeMonth: monthPlan && targetDate != null ? true : null,
                      ));
                    } else {
                      existing
                        ..ticker = tickerCtrl.text.toUpperCase()
                        ..name = nameCtrl.text.isEmpty ? tickerCtrl.text : nameCtrl.text
                        ..type = type
                        ..targetQuantity = enteredLots * lotSize.toDouble()
                        ..targetPrice = p
                        ..targetDate = targetDate
                        ..wholeMonth = monthPlan && targetDate != null ? true : null
                        ..note = noteCtrl.text.isEmpty ? null : noteCtrl.text;
                      await StorageService.updatePlan(existing);
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Ключ группы просроченных планов.
const _overdueKey = '_overdue';
const _doneKey = '_done';

/// Ключ, под которым запоминается последний выбранный тип плана.
const _planTypeKey = 'planType';

/// Последний день месяца даты [d].
DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Срок плана «на месяц»: месяц и год. Нажатие открывает сетку месяцев.
class _MonthField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onPicked;

  const _MonthField({required this.value, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Pressable(
      onTap: () async {
        final picked = await showDialog<DateTime>(
          context: context,
          builder: (_) => _MonthPickerDialog(initial: v ?? DateTime.now()),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
          borderRadius: AppRadius.all(AppRadius.sm),
          border: Border.all(color: context.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 19, color: context.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                v == null ? 'Месяц (необязательно)' : Fmt.monthTitle('${v.year}-${v.month}'),
                style: TextStyle(fontSize: 15, color: v == null ? context.dim : null),
              ),
            ),
            if (v != null)
              GestureDetector(
                onTap: () => onPicked(null),
                child: Icon(Icons.close_rounded, size: 18, color: context.dim),
              ),
          ],
        ),
      ),
    );
  }
}

/// Год стрелками, месяц — одним нажатием. Прошедшие месяцы бледнее.
class _MonthPickerDialog extends StatefulWidget {
  final DateTime initial;
  const _MonthPickerDialog({required this.initial});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initial.year;
  static const _names = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final selected = widget.initial;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _year > now.year ? () => setState(() => _year--) : null,
                ),
                Text('$_year', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => setState(() => _year++),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (int m = 1; m <= 12; m++)
                  Builder(builder: (context) {
                    final past = _year < now.year || (_year == now.year && m < now.month);
                    final on = selected.year == _year && selected.month == m;
                    return Pressable(
                      onTap: past ? null : () => Navigator.pop(context, DateTime(_year, m, 1)),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on
                              ? context.accent
                              : (context.isDark ? Colors.white.withOpacity(0.05) : AppColors.lightSurfaceHigh),
                          borderRadius: AppRadius.all(AppRadius.sm),
                        ),
                        child: Text(
                          _names[m - 1],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                            color: on ? Colors.white : (past ? context.dim.withOpacity(0.5) : null),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
