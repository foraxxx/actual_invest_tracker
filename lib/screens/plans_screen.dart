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
import '../services/storage_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_price_service.dart';
import '../widgets/security_picker_field.dart';
import '../widgets/ticker_avatar.dart';
import 'home_screen.dart';

enum _DatePreset { all, thisMonth, next3Months, overdue, custom }

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

  _TickerPlanSummary({
    required this.ticker,
    required this.name,
    required this.type,
    required this.totalQty,
    required this.totalEstimated,
    required this.planCount,
    required this.allHavePrice,
  });
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
  final Set<String> _expanded = {};
  bool _summaryExpanded = false;
  _DatePreset _preset = _DatePreset.all;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    StorageService.dataVersion.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    StorageService.dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  Color _statusColor(PlanStatus s) {
    switch (s) {
      case PlanStatus.active:
        return context.accent;
      case PlanStatus.done:
        return AppColors.positive;
      case PlanStatus.cancelled:
        return AppColors.neutral;
    }
  }

  List<_PlanGroup> _groupPlans(List<Plan> plans) {
    final map = <String, List<Plan>>{};
    final dateOf = <String, DateTime?>{};
    for (final p in plans) {
      final d = p.targetDate;
      final key = d == null
          ? _PlanGroup.noDateKey
          : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(p);
      dateOf[key] = d == null ? null : DateTime(d.year, d.month, d.day);
    }
    final groups = map.entries.map((e) => _PlanGroup(e.key, dateOf[e.key], e.value)).toList();
    groups.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return a.date!.compareTo(b.date!);
    });
    return groups;
  }

  bool _matchesFilter(_PlanGroup g) {
    if (g.date == null) return true; // «без срока» фильтром по дате не скрываем
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _DatePreset.all:
        return true;
      case _DatePreset.thisMonth:
        return g.date!.year == now.year && g.date!.month == now.month;
      case _DatePreset.next3Months:
        final end = DateTime(now.year, now.month + 3, now.day);
        return !g.date!.isBefore(today) && !g.date!.isAfter(end);
      case _DatePreset.overdue:
        return g.date!.isBefore(today) && g.status != PlanStatus.done;
      case _DatePreset.custom:
        if (_customRange == null) return true;
        return !g.date!.isBefore(_customRange!.start) && !g.date!.isAfter(_customRange!.end);
    }
  }

  String _presetLabel(_DatePreset p) {
    switch (p) {
      case _DatePreset.all:
        return 'Все';
      case _DatePreset.thisMonth:
        return 'Этот месяц';
      case _DatePreset.next3Months:
        return 'Ближайшие 3 мес';
      case _DatePreset.overdue:
        return 'Просрочено';
      case _DatePreset.custom:
        return _customRange == null
            ? 'Диапазон'
            : '${Fmt.date(_customRange!.start)} – ${Fmt.date(_customRange!.end)}';
    }
  }

  String _periodPhrase() {
    switch (_preset) {
      case _DatePreset.all:
        return 'за всё время';
      case _DatePreset.thisMonth:
        return 'в этом месяце';
      case _DatePreset.next3Months:
        return 'в ближайшие 3 месяца';
      case _DatePreset.overdue:
        return 'по просроченным';
      case _DatePreset.custom:
        return _customRange != null
            ? 'за ${Fmt.date(_customRange!.start)} – ${Fmt.date(_customRange!.end)}'
            : 'за выбранный период';
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = StorageService.plans;
    final groups = _groupPlans(all).where(_matchesFilter).toList();

    final active = groups.where((g) => g.status == PlanStatus.active).toList();
    final done = groups.where((g) => g.status == PlanStatus.done).toList();
    final cancelled = groups.where((g) => g.status == PlanStatus.cancelled).toList();

    // Итог по периоду: все планы из видимых групп, кроме отменённых — они
    // больше не считаются планом.
    final periodPlans =
        groups.expand((g) => g.plans).where((p) => p.status != PlanStatus.cancelled).toList();
    final periodTotal = periodPlans.fold(0.0, (s, p) => s + (p.estimatedTotal ?? 0));
    final allHavePrice = periodPlans.isNotEmpty && periodPlans.every((p) => p.targetPrice != null);
    final byTicker = _summarizeByTicker(periodPlans);
    final doneCount = periodPlans.where((p) => p.status == PlanStatus.done).length;

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
                        Text('Планы покупок', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${all.length} ${Fmt.plural(all.length, "план", "плана", "планов")} · '
                          '${groups.length} ${Fmt.plural(groups.length, "срок", "срока", "сроков")}',
                          style: TextStyle(fontSize: 12, color: context.dim),
                        ),
                        const SizedBox(height: 14),
                        _filterBar(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: groups.isEmpty
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
                                      periodPlans.length, doneCount, periodTotal, allHavePrice, byTicker),
                                ),
                              if (active.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                _sectionHeader('Ожидают', active.length),
                                ...active.map((g) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _groupCard(g),
                                    )),
                              ],
                              if (done.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _sectionHeader('Выполнено', done.length),
                                ...done.map((g) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _groupCard(g),
                                    )),
                              ],
                              if (cancelled.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _sectionHeader('Отменено', cancelled.length),
                                ...cancelled.map((g) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _groupCard(g),
                                    )),
                              ],
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

  Widget _filterBar() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          for (final p in [
            _DatePreset.all,
            _DatePreset.thisMonth,
            _DatePreset.next3Months,
            _DatePreset.overdue,
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _filterPill(
                label: _presetLabel(p),
                selected: _preset == p,
                onTap: () => setState(() => _preset = p),
              ),
            ),
          _filterPill(
            label: _presetLabel(_DatePreset.custom),
            icon: Icons.date_range_rounded,
            selected: _preset == _DatePreset.custom,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 5),
                initialDateRange: _customRange,
              );
              if (picked != null) {
                setState(() {
                  _customRange = picked;
                  _preset = _DatePreset.custom;
                });
              }
            },
          ),
        ],
      ),
    );
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
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.totalEstimated.compareTo(a.totalEstimated));
    return list;
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.dim)),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    int planCount,
    int doneCount,
    double total,
    bool allHavePrice,
    List<_TickerPlanSummary> byTicker,
  ) {
    final accent = context.accent;
    final progress = planCount == 0 ? 0.0 : doneCount / planCount;

    return AppCard(
      padding: EdgeInsets.zero,
      glow: accent,
      color: accent.withOpacity(context.isDark ? 0.10 : 0.07),
      border: Border.all(color: accent.withOpacity(0.32), width: 1.3),
      child: Column(
        children: [
          Pressable(
            onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ProgressRing(
                    progress: progress,
                    color: accent,
                    size: 52,
                    child: Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Итого по плану ${_periodPhrase()}',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: accent),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$planCount ${Fmt.purchases(planCount)} · '
                          '${byTicker.length} ${Fmt.papers(byTicker.length)} · выполнено $doneCount',
                          style: TextStyle(fontSize: 11.5, color: context.dim),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        total > 0 ? '≈${Fmt.money(total)}' : '—',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: accent),
                      ),
                      if (total > 0 && !allHavePrice)
                        Text('цена не у всех', style: TextStyle(fontSize: 10, color: context.dim)),
                    ],
                  ),
                  AnimatedRotation(
                    turns: _summaryExpanded ? 0.5 : 0,
                    duration: AppDuration.fast,
                    child: Icon(Icons.expand_more_rounded, color: accent),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  Divider(color: accent.withOpacity(0.2), height: 1),
                  const SizedBox(height: 8),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                Text(
                  '${Fmt.assetType(t.type)} · ${Fmt.qty(t.totalQty)} шт'
                  '${t.planCount > 1 ? ' · ${t.planCount} план.' : ''}',
                  style: TextStyle(fontSize: 11, color: context.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t.totalEstimated > 0 ? '≈${Fmt.money(t.totalEstimated)}' : '—',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(_PlanGroup g) {
    final expanded = _expanded.contains(g.key);
    final color = _statusColor(g.status);
    final now = DateTime.now();
    final isOverdue = g.date != null &&
        g.date!.isBefore(DateTime(now.year, now.month, now.day)) &&
        g.status == PlanStatus.active;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Pressable(
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(g.key);
              } else {
                _expanded.add(g.key);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.28), color.withOpacity(0.08)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      g.date == null ? Icons.all_inbox_rounded : Icons.event_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.date == null ? 'Без срока' : 'к ${Fmt.dateLong(g.date!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                              ),
                            ),
                            if (isOverdue) ...[
                              const SizedBox(width: 6),
                              const TagChip(text: 'просрочен', color: AppColors.warning, fontSize: 9.5),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${g.plans.length} ${Fmt.papers(g.plans.length)}'
                          '${g.totalEstimated > 0 ? ' · ≈${Fmt.money(g.totalEstimated)}' : ''}'
                          '${g.totalEstimated > 0 && !g.allHavePrice ? ' (цена не у всех)' : ''}',
                          style: TextStyle(fontSize: 11.5, color: context.dim),
                        ),
                      ],
                    ),
                  ),
                  TagChip(
                    text: g.status == PlanStatus.done
                        ? 'Выполнено'
                        : g.status == PlanStatus.cancelled
                            ? 'Отменено'
                            : '${g.doneCount}/${g.plans.length}',
                    color: color,
                    fontSize: 10,
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, size: 19, color: context.dim),
                    onSelected: (v) {
                      if (v == 'delete_group') _confirmDeleteGroup(g);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete_group', child: Text('Удалить группу')),
                    ],
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppDuration.fast,
                    child: Icon(Icons.expand_more_rounded, color: context.dim),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(children: g.plans.map(_planRow).toList()),
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AppDuration.normal,
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _planRow(Plan p) {
    final isDone = p.status == PlanStatus.done;
    final isCancelled = p.status == PlanStatus.cancelled;
    final progress = p.targetQuantity <= 0 ? 0.0 : (p.purchasedQuantity / p.targetQuantity).clamp(0.0, 1.0);
    final color = _statusColor(p.status);

    // Прогресс по деньгам может обогнать прогресс по штукам, если цена
    // выросла с момента постановки плана — тогда на тот же бюджет купится
    // меньше бумаг, чем задумывалось. Оба числа показываем рядом, а решение
    // "хватит ли этого" оставляем пользователю — авто-порог тут был бы
    // произвольным.
    final spent = p.purchasedQuantity * p.purchasedAvgPrice;
    final budget = p.estimatedTotal;
    final moneyProgress = (budget != null && budget > 0) ? (spent / budget).clamp(0.0, 1.0) : null;
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
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.sm),
          gradient: LinearGradient(colors: [AppColors.negative.withOpacity(0.15), AppColors.negative]),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        StorageService.deletePlan(p.id);
        setState(() {});
      },
      child: Pressable(
        onTap: () => _showAddSheet(context, existing: p),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
            borderRadius: AppRadius.all(AppRadius.sm),
          ),
          child: Opacity(
            opacity: isCancelled ? 0.5 : 1,
            child: Column(
            children: [
              Row(
                children: [
                  TickerAvatar(ticker: p.ticker, size: 34, glow: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            decoration: isDone || isCancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MarqueeText(
                          'Цель: ${Fmt.qty(p.targetQuantity)} шт. × '
                          '${p.targetPrice != null ? Fmt.price(p.targetPrice!, type: p.type) : 'цена не указана'}',
                          alwaysScroll: true,
                          style: TextStyle(fontSize: 11.2, color: context.dim),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: isDone,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) {
                      p.status = v == true ? PlanStatus.done : PlanStatus.active;
                      StorageService.updatePlan(p);
                      setState(() {});
                    },
                  ),
                  PopupMenuButton<PlanStatus>(
                    icon: Icon(Icons.flag_rounded, size: 17, color: color),
                    onSelected: (s) {
                      p.status = s;
                      StorageService.updatePlan(p);
                      setState(() {});
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: PlanStatus.active, child: Text('Активный')),
                      PopupMenuItem(value: PlanStatus.done, child: Text('Выполнен')),
                      PopupMenuItem(value: PlanStatus.cancelled, child: Text('Отменён')),
                    ],
                  ),
                ],
              ),
              if (p.purchasedQuantity > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: MiniProgressBar(value: progress, color: AppColors.positive)),
                    const SizedBox(width: 8),
                    Text(
                      'куплено ${Fmt.qty(p.purchasedQuantity)} по ${Fmt.price(p.purchasedAvgPrice, type: p.type)}',
                      style: TextStyle(fontSize: 10.3, fontWeight: FontWeight.w700, color: context.dim),
                    ),
                  ],
                ),
                if (moneyProgress != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'по деньгам: ${Fmt.money(spent)} из ~${Fmt.money(budget!)} (${(moneyProgress * 100).round()}%)',
                    style: TextStyle(fontSize: 10.3, color: context.dim),
                  ),
                ],
                if (cantAffordMore) ...[
                  const SizedBox(height: 6),
                  InfoBanner(
                    icon: Icons.info_outline_rounded,
                    color: AppColors.warning,
                    text: 'По текущей цене (${Fmt.price(currentPrice!, type: p.type)}) на оставшийся '
                        'бюджет плана лот уже не купить — если это устраивает, отметьте план '
                        'выполненным вручную',
                  ),
                ],
              ],
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.note?.isNotEmpty == true ? p.note! : 'Без комментария',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.2, fontStyle: FontStyle.italic, color: context.dim),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.estimatedTotal != null ? Fmt.money(p.estimatedTotal!) : '—',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
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
    final label = g.date == null ? 'без срока' : 'на ${Fmt.date(g.date!)}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: Text(
          'Будет удалено ${g.plans.length} ${Fmt.papers(g.plans.length)} $label — без возможности восстановления.',
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
      _expanded.remove(g.key);
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
                      ));
                    } else {
                      existing
                        ..ticker = tickerCtrl.text.toUpperCase()
                        ..name = nameCtrl.text.isEmpty ? tickerCtrl.text : nameCtrl.text
                        ..type = type
                        ..targetQuantity = enteredLots * lotSize.toDouble()
                        ..targetPrice = p
                        ..targetDate = targetDate
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
