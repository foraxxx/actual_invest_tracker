import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'settings_screen.dart' show importBackupFlow;
import 'broker_import_screen.dart';
import '../design/charts.dart';
import '../services/appearance_service.dart';
import '../design/page_tour.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import 'dart:async';

import '../services/analytics_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_price_service.dart';
import '../services/portfolio_service.dart';
import '../services/iis_service.dart';
import '../widgets/iis_widgets.dart';
import '../services/storage_service.dart';
import 'budget_screen.dart';
import 'home_screen.dart';
import 'root_screen.dart';

/// Стартовый экран приложения: все портфели со сводкой сверху. Тап по
/// портфелю делает его активным и открывает — дальше весь интерфейс
/// работает уже с ним.
class PortfoliosScreen extends StatefulWidget {
  const PortfoliosScreen({super.key});

  @override
  State<PortfoliosScreen> createState() => _PortfoliosScreenState();
}

class _PortfolioStat {
  final double valueRub;
  final double profitRub;
  const _PortfolioStat({required this.valueRub, required this.profitRub});
}

class _PortfoliosScreenState extends State<PortfoliosScreen> {
  Map<String, _PortfolioStat> _stats = {};
  bool _loading = true;
  bool _reloading = false;
  bool _reloadPending = false;

  /// Закрытые портфели свёрнуты, чтобы длинный список не прятал бюджет.
  bool _closedOpen = false;

  @override
  void initState() {
    super.initState();
    PortfolioService.version.addListener(_onPortfoliosChanged);
    // Стоимость портфеля считается по кэшу котировок. Пока цены грузятся,
    // экран должен пересчитаться сам — иначе суммы останутся вчерашними до
    // тех пор, пока пользователь не зайдёт в портфель и не выйдет обратно.
    OnlinePriceService.version.addListener(_onPricesChanged);
    _load();
    // Обновление всех портфелей сразу при входе: цены неактивных портфелей
    // обычный цикл не запрашивает.
    unawaited(MoexSyncService.instance.refreshAllPortfolios());
  }

  @override
  void dispose() {
    PortfolioService.version.removeListener(_onPortfoliosChanged);
    OnlinePriceService.version.removeListener(_onPricesChanged);
    super.dispose();
  }

  void _onPortfoliosChanged() => _load();

  void _onPricesChanged() => _load();

  Future<void> _load() async {
    // Пересчёт запускается и по приходу цен, и по изменению списка портфелей —
    // два одновременных прохода по боксам друг другу мешают.
    if (_reloading) {
      _reloadPending = true;
      return;
    }
    _reloading = true;
    try {
      final stats = <String, _PortfolioStat>{};
      for (final p in PortfolioService.list) {
        final data = await StorageService.readDataFor(p.id);
        final summary = AnalyticsService.summaryFor(purchases: data.purchases, incomes: data.incomes);
        stats[p.id] = _PortfolioStat(valueRub: summary.valueRub, profitRub: summary.profitRub);
      }
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } finally {
      _reloading = false;
      if (_reloadPending) {
        _reloadPending = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _pullToRefresh() async {
    await MoexSyncService.instance.refreshAllPortfolios();
    await _load();
  }

  Future<void> _openPortfolio(PortfolioMeta p) async {
    if (p.id != PortfolioService.activeId) {
      await PortfolioService.switchTo(p.id);
    }
    if (!mounted) return;
    await Navigator.push(context, AppPageRoute(builder: (_) => const HomeScreen()));
    // Пока пользователь был внутри портфеля, он мог что-то купить или продать —
    // по возвращении пересчитываем стоимость и прибыль заново.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = PortfolioService.list;
    final active = list.where((p) => p.status == PortfolioStatus.active).toList();
    final closed = list.where((p) => p.status == PortfolioStatus.closed).toList();

    final totalValue = active.fold(0.0, (s, p) => s + (_stats[p.id]?.valueRub ?? 0));
    final totalProfit = active.fold(0.0, (s, p) => s + (_stats[p.id]?.profitRub ?? 0));

    final distribution = <String, double>{};
    for (final p in active) {
      final v = _stats[p.id]?.valueRub ?? 0;
      if (v > 0) distribution[p.name] = v;
    }

    return PageTour(
      // Пока портфелей нет, показываем только кнопку создания; полный тур —
      // когда появится первый портфель.
      key: ValueKey(list.isEmpty),
      pageId: list.isEmpty ? 'portfolios_empty' : 'portfolios',
      steps: list.isEmpty
          ? const [
              PageTourStep(
                anchor: 'start',
                title: 'Начните с портфеля',
                text: 'Портфель — это отдельный счёт: брокерский или ИИС. Создайте новый, '
                    'загрузите отчёт брокера или восстановите данные из бэкапа.',
              ),
            ]
          : const [
        PageTourStep(
          anchor: 'summary',
          title: 'Сводка по всем портфелям',
          text: 'Общая стоимость активных портфелей и суммарная прибыль. Закрытые портфели '
              'сюда не входят — они остаются в истории.',
        ),
        PageTourStep(
          anchor: 'card',
          title: 'Портфель',
          text: 'Нажмите, чтобы открыть: внутри своя история сделок, выплат и планов. '
              'Долгий список кнопок справа — переименовать, закрыть или удалить.',
        ),
        PageTourStep(
          anchor: 'fab',
          title: 'Новый портфель',
          text: 'Брокерский счёт и ИИС удобно вести раздельно: у каждого портфеля своя '
              'статистика и свои налоги.',
        ),
      ],
      child: Scaffold(
      body: AuroraBackground(
        profit: totalProfit,
        child: SafeArea(
          bottom: false,
          child: list.isEmpty
              ? _firstRun()
              : RefreshIndicator(
                  onRefresh: _pullToRefresh,
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'INVEST TRACKER',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w700,
                                  color: context.dim,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text('Портфели', style: Theme.of(context).textTheme.headlineMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    FadeSlideIn(
                      child: TourSpot(
                        id: 'summary',
                        child: _summaryCard(totalValue, totalProfit, active.length, distribution, active),
                      ),
                    ),

                    if (active.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _sectionHeader('Активные', active.length),
                      for (int i = 0; i < active.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FadeSlideIn.staggered(
                            index: i,
                            child: i == 0
                                ? TourSpot(
                                    id: 'card',
                                    child: _portfolioCard(active[i], list.length, active.length, totalValue),
                                  )
                                : _portfolioCard(active[i], list.length, active.length, totalValue),
                          ),
                        ),
                    ],

                    if (closed.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _closedOpen = !_closedOpen),
                        child: Row(
                          children: [
                            Expanded(child: _sectionHeader('Закрытые', closed.length)),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Text(_closedOpen ? 'Свернуть' : 'Показать',
                                      style: TextStyle(fontSize: 12, color: context.accent, fontWeight: FontWeight.w700)),
                                  Icon(_closedOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                      size: 18, color: context.accent),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_closedOpen)
                        for (final p in closed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _portfolioCard(p, list.length, active.length, totalValue),
                          ),
                    ],

                    // Бюджет — общий для всех портфелей: короткая сводка месяца
                    // под списком портфелей.
                    BudgetSummaryCard(onTap: RootScreen.goToBudget),

                    const SizedBox(height: kListBottomPadding),
                  ],
                ),
                ),
        ),
      ),
      // Пока портфелей нет, создание — в карточках на экране.
      floatingActionButton: list.isEmpty ? null : TourSpot(
        id: 'fab',
        child: FloatingActionButton.extended(
        // Без heroTag Flutter считает все кнопки действия одной и той же и
        // при переходе между экранами перетекает одну в другую: на списке
        // портфелей «+ Портфель» на глазах превращался в «+ План».
        heroTag: null,
        onPressed: _createDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Портфель', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      ),
    );
  }

  /// Первый запуск: портфелей нет — три понятных способа начать.
  Widget _firstRun() {
    Widget choice(IconData icon, String title, String text, Color color, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: context.isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(13)),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(text, style: TextStyle(fontSize: 12.5, height: 1.3, color: context.dim)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.dim),
                  ],
                ),
              ),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        Text('INVEST TRACKER',
            style: TextStyle(fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w700, color: context.dim)),
        const SizedBox(height: 3),
        Text('Портфели', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 18),
        Text('С чего начнём?', style: TextStyle(fontSize: 14, color: context.dim)),
        const SizedBox(height: 10),
        TourSpot(
          id: 'start',
          child: choice(Icons.add_rounded, 'Новый портфель', 'Внести сделки вручную или загрузить отчёт потом',
              AppColors.positive, _createDialog),
        ),
        choice(Icons.upload_file_rounded, 'Из отчёта брокера', 'Сделки и выплаты сразу — выберите своего брокера',
            AppColors.info, () async {
          await Navigator.push(context, AppPageRoute(builder: (_) => const BrokerImportScreen()));
          if (mounted) _load();
        }),
        choice(Icons.restore_rounded, 'Из бэкапа', 'Если переустановили приложение или сменили телефон',
            AppColors.violet, () => importBackupFlow(context, onDone: () {
                  if (mounted) _load();
                })),
      ],
    );
  }

  /// График в сводке: скрыт, пока не нажали стрелку справа от суммы.
  bool _chartOpen = AppearanceService.ui('portfoliosChart') == 'open';
  int _chartTab = 0;

  void _toggleChart() {
    setState(() => _chartOpen = !_chartOpen);
    AppearanceService.setUi('portfoliosChart', _chartOpen ? 'open' : 'closed');
  }

  Widget _chartButton() => Material(
        color: context.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggleChart,
          child: SizedBox(
            width: 36,
            height: 36,
            child: AnimatedRotation(
              turns: _chartOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more_rounded, size: 22, color: context.dim),
            ),
          ),
        ),
      );

  /// Распределение между портфелями или их доходность.
  Widget _summaryChart(Map<String, double> distribution, List<PortfolioMeta> active) {
    final colors = [AppColors.info, AppColors.violet, AppColors.positive, AppColors.gold, AppColors.cyan, AppColors.negative];
    final rows = [
      for (final p in active)
        if ((_stats[p.id]?.valueRub ?? 0) > 0) p,
    ];
    double pctOf(PortfolioMeta p) {
      final st = _stats[p.id]!;
      final cost = st.valueRub - st.profitRub;
      return cost <= 0 ? 0 : st.profitRub / cost * 100;
    }

    final maxPct = rows.fold(0.0, (m, p) => math.max(m, pctOf(p).abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        SegmentedToggle<int>(
          values: const [0, 1],
          selected: _chartTab,
          labelOf: (i) => i == 0 ? 'Распределение' : 'Доходность',
          onChanged: (i) => setState(() => _chartTab = i),
          height: 38,
        ),
        const SizedBox(height: 12),
        if (_chartTab == 0)
          DonutChart(data: distribution, valueFormatter: (v) => Fmt.money(v), centerLabel: 'Всего', size: 170)
        else
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i].name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  ),
                  Text(
                    Fmt.pct(pctOf(rows[i])),
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.pnl(pctOf(rows[i]))),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: maxPct <= 0 ? 0 : (pctOf(rows[i]).abs() / maxPct).clamp(0.0, 1.0).toDouble(),
                minHeight: 9,
                backgroundColor: context.hairline,
                valueColor: AlwaysStoppedAnimation(
                    pctOf(rows[i]) >= 0 ? colors[i % colors.length] : AppColors.negative),
              ),
            ),
          ],
        if (_chartTab == 1) ...[
          const SizedBox(height: 8),
          Text('Прибыль за всё время к вложенному в бумаги.',
              style: TextStyle(fontSize: 11, color: context.dim)),
        ],
      ],
    );
  }

  Widget _summaryCard(double value, double profit, int count, Map<String, double> distribution,
      List<PortfolioMeta> active) {
    final accent = context.accent;
    return GlassCard(
      glow: accent,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Активные портфели · $count',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Shimmer(width: 200, height: 38, radius: 10),
            )
          else
            Row(
              children: [
                Flexible(
                  child: HiddenAmount.forText(active: true, toggles: true,
                    Fmt.money(value),
                    fontSize: 34,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: RollingNumber(
                        value: value,
                        formatter: (v) => Fmt.money(v),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1.4),
                      ),
                    ),
                  ),
                ),
                if (distribution.length > 1) ...[
                  const SizedBox(width: 8),
                  _chartButton(),
                ],
              ],
            ),
          const SizedBox(height: 10),
          if (_loading)
            const Shimmer(width: 140, height: 16, radius: 8)
          else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.pnl(profit).withOpacity(0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    profit >= 0 ? Icons.arrow_outward_rounded : Icons.south_east_rounded,
                    size: 14,
                    color: AppColors.pnl(profit),
                  ),
                ),
                const SizedBox(width: 8),
                HiddenAmount.forText(
                  active: true,
                  Fmt.signedMoney(profit),
                  fontSize: 15,
                  child: Text(
                    Fmt.signedMoney(profit),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pnl(profit),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('суммарной прибыли', style: TextStyle(fontSize: 11.5, color: context.dim)),
              ],
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _chartOpen && distribution.length > 1
                ? _summaryChart(distribution, active)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
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

  Widget _portfolioCard(PortfolioMeta p, int totalCount, int activeCount, double totalValue) {
    final isActive = p.id == PortfolioService.activeId;
    final isClosed = p.status == PortfolioStatus.closed;
    final stat = _stats[p.id];
    final accent = context.accent;
    final share = (totalValue <= 0 || stat == null) ? 0.0 : stat.valueRub / totalValue;
    final isIis = IisService.settingsFor(p.id) != null;
    // «Текущий» нужен, только когда есть из чего выбирать.
    final showCurrent = isActive && totalCount > 1;
    final hasTags = showCurrent || isIis || isClosed;

    return AppCard(
      onTap: () => _openPortfolio(p),
      padding: const EdgeInsets.all(14),
      glow: isActive ? accent : null,
      border: isActive ? Border.all(color: accent.withOpacity(0.45), width: 1.2) : null,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isActive ? accent : accent.withOpacity(0.14),
                ),
                child: Icon(
                  isClosed ? Icons.lock_outline_rounded : Icons.account_balance_wallet_outlined,
                  size: 21,
                  color: isActive ? Colors.white : accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    // Метки — одной строкой; «активен» не пишем, это и так
                    // видно по разделу.
                    if (hasTags) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (showCurrent) TagChip(text: 'текущий', color: accent, fontSize: 9.5),
                          if (showCurrent && (isIis || isClosed)) const SizedBox(width: 6),
                          if (isIis) const TagChip(text: 'ИИС', color: AppColors.info, fontSize: 9.5),
                          if (isIis && isClosed) const SizedBox(width: 6),
                          if (isClosed) const TagChip(text: 'закрыт', color: AppColors.neutral, fontSize: 9.5),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_loading)
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Shimmer(width: 78, height: 15, radius: 6),
                    SizedBox(height: 6),
                    Shimmer(width: 54, height: 12, radius: 6),
                  ],
                )
              else if (stat != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    HiddenAmount.forText(active: true, 
                      Fmt.money(stat.valueRub),
                      fontSize: 14.5,
                      child: Text(
                        Fmt.money(stat.valueRub),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                    ),
                    const SizedBox(height: 3),
                    TagChip(
                      text: Fmt.signedMoney(stat.profitRub),
                      color: AppColors.pnl(stat.profitRub),
                      fontSize: 10,
                    ),
                  ],
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 19, color: context.dim),
                onSelected: (v) {
                  if (v == 'rename') _renameDialog(p);
                  if (v == 'iis') showIisSettingsSheet(context, p).then((_) => _load());
                  if (v == 'close') PortfolioService.setStatus(p.id, PortfolioStatus.closed);
                  if (v == 'reopen') PortfolioService.setStatus(p.id, PortfolioStatus.active);
                  if (v == 'delete') _confirmDelete(p, totalCount);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                  PopupMenuItem(
                    value: 'iis',
                    child: Text(isIis ? 'Настройки ИИС' : 'Отметить как ИИС'),
                  ),
                  if (isClosed)
                    const PopupMenuItem(value: 'reopen', child: Text('Открыть заново'))
                  else
                    const PopupMenuItem(value: 'close', child: Text('Закрыть портфель')),
                  if (totalCount > 1)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить', style: TextStyle(color: AppColors.negative)),
                    ),
                ],
              ),
            ],
          ),
          // Доля имеет смысл, только когда активных портфелей несколько.
          if (!_loading && !isClosed && activeCount > 1 && share > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: MiniProgressBar(value: share, color: accent)),
                const SizedBox(width: 8),
                Text(
                  '${(share * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.dim),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createDialog() async {
    await showNewPortfolioSheet(context);
    if (mounted) _load();
  }

  Future<void> _renameDialog(PortfolioMeta p) async {
    final ctrl = TextEditingController(text: p.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать портфель'),
        content: AppTextField(controller: ctrl, label: 'Название', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await PortfolioService.rename(p.id, ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(PortfolioMeta p, int totalCount) async {
    if (totalCount <= 1) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить портфель?'),
        content: Text(
          'Все сделки, выплаты, планы и секторы портфеля «${p.name}» будут удалены '
          'без возможности восстановления.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PortfolioService.delete(p.id);
    }
  }
}
