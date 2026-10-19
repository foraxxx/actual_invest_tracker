import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tilt_shine_card.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
import '../models/deposit.dart';
import '../models/purchase.dart';
import '../services/cash_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/storage_service.dart';
import '../services/manual_price_service.dart';
import '../services/online_price_service.dart';
import '../services/portfolio_service.dart';
import '../services/tax_service.dart';
import '../services/benchmark_service.dart';
import '../services/beta_service.dart';
import '../services/cbr_service.dart';
import '../services/real_return_service.dart';
import '../services/stress_test_service.dart';
import '../services/portfolio_history_service.dart';
import '../services/value_forecast_service.dart';
import '../services/mini_history_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_settings_service.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/choice_cards.dart';
import '../widgets/forecast_sheet.dart';
import '../widgets/value_forecast_sheet.dart';
import '../widgets/updated_ago.dart';
import '../widgets/goal_widgets.dart';
import '../widgets/profit_sheet.dart';
import '../widgets/passive_goal_widgets.dart';
import '../services/passive_goal_service.dart';
import '../widgets/iis_widgets.dart';
import '../services/goal_service.dart';
import '../services/iis_service.dart';
import '../widgets/payout_calendar.dart';
import '../widgets/payout_years_chart.dart';
import '../widgets/real_return_sheet.dart';
import '../widgets/stress_test_sheet.dart';
import '../services/payout_calendar_service.dart';
import 'home_screen.dart';
import 'ticker_detail_screen.dart';
import 'wrapped_screen.dart';

/// По какому признаку строится кольцевая диаграмма распределения.
enum _AllocationMode { sectors, tickers }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  PeriodFilter _period = PeriodFilter.all;
  /// Год в календаре «Выплаты».
  int _incomeYear = DateTime.now().year;
  // Вкладка «Распределения» запоминается между запусками.
  _AllocationMode _alloc = _AllocationMode.values.firstWhere(
    (m) => m.name == AppearanceService.allocationTab,
    orElse: () => _AllocationMode.sectors,
  );

  /// Какой метод расчёта доходности показан: 0 — XIRR, 1 — TWR.
  ///
  /// Живёт только в состоянии экрана: выбор метода — это взгляд на одни и те
  /// же деньги под другим углом, а не настройка, которую стоит помнить между
  /// запусками.
  int _returnSegment = 0;

  /// Что показывает карточка прогноза: 0 — выплаты, 1 — стоимость портфеля.
  int _forecastSegment = 0;

  void _onForecastSegment(int i) {
    setState(() => _forecastSegment = i);
    // История индекса нужна только прогнозу стоимости — грузим её, когда
    // человек впервые на него переключился, а не при каждом входе на главную.
    if (i == 1) ValueForecastService.loadMarketHistory();
  }

  @override
  void initState() {
    super.initState();
    // Графики купонов и дивидендов могли ещё не загрузиться к моменту, когда
    // появились бумаги, — просим догрузить при входе на вкладку.
    PayoutForecastService.refresh();
    BenchmarkService.refresh();
    CbrService.refreshInBackground();
    PortfolioHistoryService.refresh();
    CbrService.version.addListener(_onDataChanged);
    BetaService.version.addListener(_onDataChanged);
    BetaService.refreshInBackground(StressTestService.betaTickers());
    StorageService.dataVersion.addListener(_onDataChanged);
    ManualPriceService.version.addListener(_onDataChanged);
    OnlinePriceService.version.addListener(_onPriceChanged);
    BenchmarkService.returnPercent.addListener(_onDataChanged);
    BenchmarkService.error.addListener(_onDataChanged);
    PortfolioHistoryService.timeline.addListener(_onDataChanged);
    PortfolioHistoryService.error.addListener(_onDataChanged);
    // Уточнённые по истории индекса допущения меняют итог в карточке прогноза.
    ValueForecastService.version.addListener(_onDataChanged);
    MiniHistoryService.version.addListener(_onDataChanged);
    GoalService.version.addListener(_onDataChanged);
    IisService.version.addListener(_onDataChanged);
    // Мини-графики в составе: история за 30 дней, не чаще раза в день.
    MiniHistoryService.refresh(AnalyticsService.currentHoldings().keys);
  }

  Future<void> _pullToRefresh() async {
    PortfolioHistoryService.refresh();
    PayoutForecastService.refresh(force: true);
    BenchmarkService.refresh();
    CbrService.refreshInBackground();
    MiniHistoryService.refresh(AnalyticsService.currentHoldings().keys, force: true);
    if (OnlineSettingsService.enabled) {
      await MoexSyncService.instance.refreshNow(force: true);
    }
  }

  /// Что сейчас разглядывают на графике стоимости — для показа над графиком.
  final ValueNotifier<ChartInspection?> _chartInspect = ValueNotifier(null);

  @override
  void dispose() {
    _chartInspect.dispose();
    CbrService.version.removeListener(_onDataChanged);
    BetaService.version.removeListener(_onDataChanged);
    StorageService.dataVersion.removeListener(_onDataChanged);
    ManualPriceService.version.removeListener(_onDataChanged);
    OnlinePriceService.version.removeListener(_onPriceChanged);
    BenchmarkService.returnPercent.removeListener(_onDataChanged);
    BenchmarkService.error.removeListener(_onDataChanged);
    PortfolioHistoryService.timeline.removeListener(_onDataChanged);
    PortfolioHistoryService.error.removeListener(_onDataChanged);
    ValueForecastService.version.removeListener(_onDataChanged);
    MiniHistoryService.version.removeListener(_onDataChanged);
    GoalService.version.removeListener(_onDataChanged);
    IisService.version.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    // Новая сделка могла добавить облигацию. Сразу загружаем её будущий
    // купонный календарь, не дожидаясь следующего фонового обновления MOEX.
    PayoutForecastService.refresh();
    if (mounted) setState(() {});
  }

  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  String _periodLabel(PeriodFilter f) {
    switch (f) {
      case PeriodFilter.month1:
        return '1 мес';
      case PeriodFilter.month3:
        return '3 мес';
      case PeriodFilter.month6:
        return '6 мес';
      case PeriodFilter.year1:
        return '1 год';
      case PeriodFilter.all:
        return 'Всё время';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageTour(
      pageId: 'dashboard',
      steps: const [
        PageTourStep(
          anchor: 'hero',
          title: 'Стоимость портфеля',
          text: 'Сколько сейчас стоят бумаги и сколько Вы на них заработали. График показывает, '
              'как менялась стоимость. Проведите по нему пальцем — он покажет дату и сумму.',
        ),
        // Один шаг на обе величины: они теперь в одной карточке. Шаг с
        // якорем 'cash' указывал на плитку, которой в разметке не было, —
        // экскурсия на нём спотыкалась.
        PageTourStep(
          anchor: 'invested',
          title: 'Вложено и свободно',
          text: 'Сверху — только Ваши деньги, поступившие извне: продажа и новая покупка вложенную '
              'сумму не увеличивают. Снизу — то, что лежит на счёте и ещё не вложено в бумаги. Если Вы '
              'сняли деньги у брокера, запишите вывод, иначе следующая покупка спишется с них и '
              'вложения окажутся занижены. Нажмите, чтобы открыть счёт.',
        ),
        PageTourStep(
          anchor: 'holdings',
          title: 'Состав портфеля',
          text: 'Позиции с долями и результатом по каждой. Ниже — распределение по секторам '
              'и бумагам. Тап по позиции открывает карточку бумаги.',
        ),
      ],
      child: ValueListenableBuilder<int>(
      valueListenable: StorageService.dataVersion,
      // Прогноз выплат приезжает асинхронно — без подписки плитка так и
      // осталась бы со старым числом до перезахода на вкладку.
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: PayoutForecastService.version,
        builder: (context, forecastVersion, ___) => _buildContent(context),
      ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final currentValue = AnalyticsService.currentPortfolioValueRub();
    final onlineTimeline = PortfolioHistoryService.timeline.value;
    final timeline = PortfolioHistoryService.withCurrentPoint(
      onlineTimeline.length > 1
          ? onlineTimeline
          : AnalyticsService.portfolioValueTimeline(),
      currentValue,
    );
    final chartError = PortfolioHistoryService.error.value;
    final unrealizedPnl = AnalyticsService.totalUnrealizedPnlRub();
    final realizedPnl = AnalyticsService.totalRealizedPnlRub();
    final holdings = AnalyticsService.currentHoldings();
    final cash = CashService.summary();
    final periodCash = CashService.periodSummary(
      cash,
      from: AnalyticsService.periodStart(_period),
    );
    // Прогноз считается всегда: с биржевыми графиками он точнее, без них —
    // по прошлым выплатам.
    final payoutSummary = PayoutForecastService.portfolioForecast();
    final payoutForecast = payoutSummary.total;
    final payoutYield = PayoutForecastService.yieldPct();
    final hasPayouts = payoutForecast > 0;
    final hasHoldings = holdings.isNotEmpty;
    final periodProfit = AnalyticsService.profitForPeriod(_period);
    final totalIncome = AnalyticsService.totalIncome(f: PeriodFilter.all);
    final totalProfit = unrealizedPnl + realizedPnl + totalIncome;
    final bySector = AnalyticsService.currentValueBySector();
    final byTicker = AnalyticsService.currentValueByTicker();
    final xirr = AnalyticsService.xirrPercent();
    final twr = AnalyticsService.twrPercent();
    final benchmark = BenchmarkService.returnPercent.value;
    final benchmarkError = BenchmarkService.error.value;
    final taxDue = TaxService.enabled ? TaxService.totalTaxDue() : 0.0;
    final periodChange = AnalyticsService.portfolioChangeForPeriod(_period);
    final dayChange = AnalyticsService.portfolioDayChange();
    final accent = context.accent;
    final isEmpty = holdings.isEmpty && totalIncome == 0 && realizedPnl == 0;
    // Плашка в углу — изменение за выбранный период графика, в том числе
    // за всё время.
    final showPeriodChip = periodChange != null;
    final summary = _heroSummary(
      today: holdings.isEmpty ? null : dayChange,
      allTimeRub: isEmpty ? null : totalProfit,
      allTimePct: _period == PeriodFilter.all
          ? periodChange?.changePct
          : AnalyticsService.portfolioChangeForPeriod(PeriodFilter.all)?.changePct,
    );

    int step = 0;

    final children = <Widget>[
      _header(context),
      const SizedBox(height: 18),

      // --- Главная карточка: стоимость, результат, график ---
      FadeSlideIn(
        delay: Duration(milliseconds: 40 * step++),
        child: TourSpot(
          id: 'hero',
          child: TiltShineCard(
          child: GlassCard(
            glow: accent,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Пока палец на графике, сумма над ним показывает разглядываемую
                // точку или итог замера — сам график ничем не закрыт.
                ValueListenableBuilder<ChartInspection?>(
                  valueListenable: _chartInspect,
                  builder: (context, inspect, _) {
                    if (inspect != null && inspect.fits(timeline.length)) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _inspectHeader(context, inspect, timeline, currentValue,
                            secondRow: !isEmpty,
                            summaryKeeper: summary,
                            // Невидимая копия плашки периода держит высоту
                            // первой строки — карточка не дёргается.
                            heightKeeper: !showPeriodChip
                                ? null
                                : TagChip(
                                    text: Fmt.pct(periodChange.changePct),
                                    color: AppColors.pnl(periodChange.changeAbs),
                                    icon: Icons.trending_up_rounded,
                                  )),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Стоимость портфеля',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
                            ),
                            if (showPeriodChip) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: TagChip(
                                      text: '${Fmt.pct(periodChange.changePct)} · ${_periodLabel(_period).toLowerCase()}',
                                      color: AppColors.pnl(periodChange.changeAbs),
                                      icon: periodChange.changeAbs >= 0
                                          ? Icons.trending_up_rounded
                                          : Icons.trending_down_rounded,
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        HiddenAmount.forText(
                          Fmt.money(currentValue),
                          fontSize: 36,
                          child: RollingNumber(
                            value: currentValue,
                            formatter: (v) => Fmt.money(v),
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1.5),
                          ),
                        ),
                        if (summary != null) ...[
                          const SizedBox(height: 8),
                          summary,
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                if (timeline.length > 1)
                  Sparkline(
                    values: timeline.map((e) => e.value).toList(),
                    color: accent,
                    height: 132,
                    tooltipBuilder: (i, v) => '${Fmt.date(timeline[i].key)}\n${Fmt.money(v)}',
                    inspection: AppearanceService.chartHints == ChartHints.above ? _chartInspect : null,
                    dateLabel: (i) => Fmt.date(timeline[i].key),
                    priceLabel: (v) => Fmt.money(v),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Добавьте первую сделку — здесь появится график стоимости',
                      style: TextStyle(fontSize: 12, color: context.dim),
                    ),
                  ),
                if (chartError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    chartError,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.dim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
      ),

      const SizedBox(height: 18),

      // --- Период статистики ---
      FadeSlideIn(
        delay: Duration(milliseconds: 40 * step++),
        child: PillTabs<PeriodFilter>(
          values: PeriodFilter.values,
          selected: _period,
          labelOf: _periodLabel,
          onChanged: (v) => setState(() => _period = v),
        ),
      ),

      const SizedBox(height: 14),

      // --- Показатели ---
      // Вложено, прибыль, доходность и прогноз. Как показывать — списком или
      // плитками, — выбирается в настройках оформления. Переключатели XIRR /
      // TWR и «выплаты / стоимость» — маленькой кнопкой рядом со значением.
      FadeSlideIn(
        delay: Duration(milliseconds: 40 * step++),
        child: _metricsBlock(context, [
          _Metric(
            tourId: 'invested',
            label: 'Вложено',
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.info,
            value: Fmt.money(periodCash.invested),
            money: true,
            sub: 'свободно ${Fmt.money(cash.cash)}',
            onTap: () => _cashSheet(cash),
          ),
          _Metric(
            label: 'Прибыль',
            icon: Icons.payments_outlined,
            color: AppColors.pnl(periodProfit),
            value: Fmt.money(periodProfit),
            valueColor: AppColors.pnl(periodProfit),
            money: true,
            sub: 'из них выплаты ${Fmt.money(periodCash.payouts)}',
            onTap: () => showProfitSheet(context, _period),
          ),
          if (xirr != null || twr != null) _returnMetric(context, xirr, twr, benchmark, benchmarkError),
          if (hasHoldings) _forecastMetric(context, hasPayouts, payoutForecast, payoutYield),
          if (hasHoldings) _inflationMetric(context),
          if (hasHoldings) _stressMetric(context),
        ]),
      ),

      if (taxDue > 0) ...[
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: Duration(milliseconds: 40 * step++),
          child: InfoBanner(
            icon: Icons.receipt_long_rounded,
            color: AppColors.warning,
            text: 'Налог с продаж (НДФЛ): ~${Fmt.money(taxDue)}',
          ),
        ),
      ],

    ];


    // --- Состав портфеля ---
    // Секция рисуется ВСЕГДА: если позиций нет, важно объяснить почему, а не
    // молча спрятать блок — иначе экран выглядит сломанным.
    final entries = holdings.entries.toList()..sort((a, b) => b.value.valueRub.compareTo(a.value.valueRub));
    final total = entries.fold(0.0, (s, e) => s + e.value.valueRub);
    final typeOf = _holdingTypes();
    final sectionsCollapsed = AppearanceService.collapsedGroups;
    // --- Финансовая цель и ИИС ---
    // Сразу после плиток: это «зачем» портфеля, а ниже — из чего он состоит.
    if (!isEmpty) {
      final goal = GoalService.current;
      final passive = GoalService.passive;
      children.add(const SizedBox(height: 14));
      // Цель у портфеля одна: накопить сумму или пассивный доход. Пока её
      // нет — строка «Поставить цель» с выбором вида.
      if (passive != null) {
        PassiveGoalService.refreshInBackground();
        children.add(PassiveGoalCard(
          plan: PassiveGoalService.plan(passive),
          collapsed: sectionsCollapsed.contains(_secPassive),
          onToggle: () => _toggleSection(_secPassive, sectionsCollapsed.contains(_secPassive)),
        ));
      } else {
        children.add(GoalCard(
          plan: goal == null ? null : GoalService.plan(goal),
          collapsed: sectionsCollapsed.contains(_secGoal),
          onToggle: () => _toggleSection(_secGoal, sectionsCollapsed.contains(_secGoal)),
        ));
      }
      final iis = IisService.current;
      if (iis != null) {
        children.add(const SizedBox(height: 10));
        children.add(IisCard(
          settings: iis,
          collapsed: sectionsCollapsed.contains(_secIis),
          onToggle: () => _toggleSection(_secIis, sectionsCollapsed.contains(_secIis)),
        ));
      }
    }

    // Отдельного заголовка «Состав портфеля» нет: группы (акции, облигации)
    // сами выглядят как разделы главной, а общая сумма и так видна наверху.
    children.add(const SizedBox(height: 20));
    if (entries.isEmpty) {
      children.add(TourSpot(
        id: 'holdings',
        child: InfoBanner(
        icon: Icons.inventory_2_outlined,
        color: AppColors.neutral,
        text: StorageService.purchases.isEmpty
            ? 'Сделок пока нет — добавьте первую на вкладке «Сделки».'
            : 'Сделки есть, но по всем бумагам куплено ровно столько же, сколько продано, '
                'поэтому открытых позиций не осталось. Проверьте количество в продажах и '
                'написание тикеров: «SBER» и «Sber» считаются разными бумагами.',
        ),
      ));
    }
    // Бумаги идут группами: сначала акции, потом облигации, потом фонды и
    // прочее. Внутри группы — по стоимости, как и раньше. Доля у бумаги
    // по-прежнему считается от всего портфеля.
    final grouping = AppearanceService.holdingsGrouping;
    final collapsed = grouping == HoldingsGrouping.collapsible
        ? AppearanceService.collapsedGroups
        : const <String>{};
    int tileIndex = 0;
    var anchorPlaced = false;
    for (final type in _groupOrder) {
      final group = entries.where((e) => (typeOf[e.key.toUpperCase()] ?? AssetType.other) == type).toList();
      if (group.isEmpty) continue;
      final groupValue = group.fold(0.0, (s, e) => s + e.value.valueRub);
      final groupPnl = group.fold(0.0, (s, e) => s + e.value.pnlRub);
      final groupCost = group.fold(0.0, (s, e) => s + e.value.costBasisRub);
      final isCollapsed = collapsed.contains(type.name);
      final header = _groupHeader(
        context,
        type: type,
        count: group.length,
        value: groupValue,
        share: total <= 0 ? 0 : groupValue / total,
        pnlPct: groupCost == 0 ? 0 : groupPnl / groupCost * 100,
        pnlRub: groupPnl,
        collapsible: grouping == HoldingsGrouping.collapsible,
        collapsed: isCollapsed,
      );
      // Подсказка обучения «Состав портфеля» указывает на первую группу.
      children.add(!anchorPlaced ? TourSpot(id: 'holdings', child: header) : header);
      anchorPlaced = true;
      if (isCollapsed) continue;
      for (final e in group) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FadeSlideIn.staggered(
            index: tileIndex++,
            child: _holdingTile(context, e.key, e.value, total <= 0 ? 0 : e.value.valueRub / total),
          ),
        ));
      }
    }

    // --- Распределение ---
    final allocData = _alloc == _AllocationMode.sectors ? bySector : byTicker;
    if (allocData.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      final allocCollapsed = sectionsCollapsed.contains(_secAlloc);
      final allocCount = allocData.length;
      children.add(_section(
        context,
        id: _secAlloc,
        icon: Icons.donut_large_rounded,
        title: 'Распределение',
        subtitle: 'Доли текущих позиций',
        trailing: Text(
          _alloc == _AllocationMode.sectors
              ? '$allocCount ${Fmt.plural(allocCount, 'сектор', 'сектора', 'секторов')}'
              : '$allocCount ${Fmt.papers(allocCount)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.dim),
        ),
        collapsed: allocCollapsed,
        preview: () => _sharesPreview(context, allocData),
        body: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PillTabs<_AllocationMode>(
                scrollable: false,
                values: _AllocationMode.values,
                selected: _alloc,
                labelOf: (m) => m == _AllocationMode.sectors ? 'По секторам' : 'По бумагам',
                onChanged: (m) {
                  setState(() => _alloc = m);
                  AppearanceService.setAllocationTab(m.name);
                },
              ),
            ),
            const SizedBox(height: 16),
            DonutChart(
              data: allocData,
              valueFormatter: (v) => Fmt.money(v),
              centerLabel: _alloc == _AllocationMode.sectors ? 'Всего по секторам' : 'Всего по бумагам',
            ),
            const SizedBox(height: 4),
          ],
        ),
      ));
    }

    // --- Выплаты по месяцам: календарь ---
    // Только полученное — за прошлые годы и текущий. Прогноз живёт в
    // карточке «Прогноз» и в цели по пассивному доходу.
    if (StorageService.incomes.isNotEmpty) {
      final years = PayoutCalendarService.years(withForecast: false);
      if (!years.contains(_incomeYear)) _incomeYear = DateTime.now().year;
      final cells = PayoutCalendarService.year(_incomeYear, withForecast: false);
      final yearTotal = cells.fold(0.0, (s, c) => s + c.total);
      children.add(const SizedBox(height: 20));
      final payCollapsed = sectionsCollapsed.contains(_secPayouts);
      children.add(_section(
        context,
        id: _secPayouts,
        icon: Icons.calendar_month_rounded,
        title: 'Выплаты',
        subtitle: yearTotal <= 0
            ? 'Выплат за $_incomeYear год нет'
            : 'Получено за $_incomeYear${_incomeYear == DateTime.now().year ? ' · по сегодня' : ''}',
        trailing: yearTotal <= 0 ? null : _moneyText(Fmt.money(yearTotal), color: AppColors.positive),
        collapsed: payCollapsed,
        preview: () => _monthsPreview(context, cells),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Несколько лет — график по годам; нажатие на год открывает его
            // месяцы ниже.
            if (years.length > 1) ...[
              _payoutYears(context, years),
              const SizedBox(height: 14),
              Text('$_incomeYear по месяцам', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
            ],
            PayoutCalendar(cells: cells),
          ],
        ),
      ));
    }

    if (isEmpty) {
      // В пустом портфеле показывать нечего: карточки с нулями, пустой график
      // и «состав портфеля» без позиций только создают шум. Оставляем шапку и
      // объяснение, с чего начать.
      children
        ..clear()
        ..add(_header(context))
        ..add(const SizedBox(height: 60))
        ..add(const EmptyState(
          icon: Icons.insights_rounded,
          title: 'Портфель пока пуст',
          subtitle: 'Добавьте первую сделку на вкладке «Сделки» — и здесь появятся '
              'графики, состав портфеля и вся статистика.',
        ));
    }

    children.add(const SizedBox(height: kListBottomPadding));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        profit: totalProfit,
        child: SafeArea(
          bottom: false,
          // Потянуть вниз — обновить котировки, график стоимости и выплаты.
          child: RefreshIndicator(
            onRefresh: _pullToRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final name = PortfolioService.list.isEmpty ? 'Портфель' : PortfolioService.active.name;
    return Row(
      children: [
        _circleButton(
          context,
          icon: Icons.grid_view_rounded,
          tooltip: 'Все портфели',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'МОЙ ПОРТФЕЛЬ',
                style: TextStyle(fontSize: 10, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: context.dim),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (OnlineSettingsService.enabled) ...[
                const SizedBox(height: 2),
                UpdatedAgo(style: TextStyle(fontSize: 11, color: context.dim)),
              ],
            ],
          ),
        ),
        _circleButton(
          context,
          icon: Icons.auto_awesome_rounded,
          tooltip: 'Итоги в формате сторис',
          highlight: true,
          onTap: () => Navigator.push(context, AppPageRoute(builder: (_) => const WrappedScreen())),
        ),
      ],
    );
  }

  Widget _circleButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool highlight = false,
  }) {
    final accent = context.accent;
    final button = Pressable(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: highlight ? AppGradient.accent(accent) : null,
          color: highlight ? null : (context.isDark ? Colors.white.withOpacity(0.06) : Colors.white),
          border: Border.all(color: highlight ? Colors.transparent : context.hairline),
          boxShadow: highlight
              ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))]
              : null,
        ),
        child: Icon(icon, size: 20, color: highlight ? Colors.white : context.dim),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }


  /// Окно «Доходность». Если считаются оба способа, сверху две карточки —
  /// XIRR и TWR, — и нажатие на карточку переключает объяснение ниже, а
  /// главная запоминает выбор.
  Future<void> _showReturnInfo(BuildContext context, {required bool xirr}) {
    final xirrValue = AnalyticsService.xirrPercent();
    final twrValue = AnalyticsService.twrPercent();
    final hasBoth = xirrValue != null && twrValue != null;
    var current = xirr;

    return showAppSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final x = current;
          final intro = x
              ? 'XIRR показывает личную среднегодовую доходность Ваших денег. '
                  'Он учитывает, сколько Вы вложили и в какие именно даты.'
              : 'TWR показывает, как работал сам портфель, если убрать влияние '
                  'размера и времени пополнений и выводов.';
          final calculation = x
              ? 'Покупки считаются расходами, продажи и полученные выплаты — доходами, '
                  'а текущая стоимость бумаг — итоговой суммой на сегодня. Затем приложение '
                  'находит такую годовую ставку, которая связывает все эти движения денег.'
              : 'История делится на отрезки между пополнениями и выводами. Для каждого отрезка '
                  'считается изменение общей стоимости счёта, после чего результаты соединяются. '
                  'Покупки, продажи и выплаты внутри портфеля не считаются внешними вложениями.';
          final example = x
              ? 'Например, крупная сумма, внесённая недавно, влияет на XIRR сильнее, чем небольшая. '
                  'Поэтому XIRR лучше отвечает на вопрос: «Какую доходность получили именно мои деньги?»'
              : 'Поэтому TWR удобно сравнивать с индексом МосБиржи или другим портфелем: '
                  'момент пополнения не улучшает и не ухудшает показатель.';
          final caveat = x
              ? 'Показатель является годовым. Для короткой истории он может заметно меняться '
                  'и не рассчитывается, если данных недостаточно.'
              : 'Точность зависит от истории стоимости и денежных движений. Если старых котировок '
                  'нет, приложение использует ближайшие известные цены сделок или ручные цены.';
          final subtitle = x ? 'Личная доходность Ваших денег' : 'Доходность инвестиционной стратегии';
          final value = x ? xirrValue : twrValue;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetHeader(
                    title: hasBoth ? 'Доходность' : (x ? 'Доходность XIRR' : 'Доходность TWR'),
                    subtitle: hasBoth ? null : subtitle,
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  if (hasBoth) ...[
                    const SizedBox(height: 4),
                    ChoiceCards(
                      selected: x ? 0 : 1,
                      onSelect: (i) {
                        if ((i == 0) == current) return;
                        setSheet(() => current = i == 0);
                        if (mounted) setState(() => _returnSegment = i);
                      },
                      items: [
                        ChoiceCard(
                          label: 'XIRR',
                          value: '${Fmt.pct(xirrValue!)} год.',
                          sub: 'Ваши деньги',
                          color: AppColors.pnl(xirrValue!),
                        ),
                        ChoiceCard(
                          label: 'TWR',
                          value: Fmt.pct(twrValue!),
                          sub: 'сам портфель',
                          color: AppColors.pnl(twrValue!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, color: ctx.dim)),
                    const SizedBox(height: 12),
                  ] else
                    const SizedBox(height: 16),
                  // Когда карточек нет, результат показывается отдельной
                  // плашкой; с карточками число уже видно сверху.
                  if (!hasBoth && value != null) ...[
                    AppCard(
                      glow: AppColors.pnl(value),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.pnl(value).withOpacity(0.14),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              x ? Icons.percent_rounded : Icons.query_stats_rounded,
                              color: AppColors.pnl(value),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ваш результат', style: TextStyle(fontSize: 11.5, color: ctx.dim)),
                                const SizedBox(height: 3),
                                Text(
                                  x ? '${Fmt.pct(value)} годовых' : Fmt.pct(value),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.pnl(value),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(intro, style: const TextStyle(height: 1.4)),
                        const SizedBox(height: 16),
                        const Text('Как считается', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(calculation, style: const TextStyle(height: 1.4)),
                        const SizedBox(height: 14),
                        Text(example, style: const TextStyle(height: 1.4)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoBanner(
                    icon: Icons.info_outline_rounded,
                    color: AppColors.info,
                    text: caveat,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Счёт: сколько своих денег вложено, что лежит свободными и откуда это
  /// взялось. Пополнения приложение считает само по сделкам, вывод — то
  /// единственное, что нужно записать руками.
  void _cashSheet(CashSummary cash) {
    final years = cash.moves.map((move) => move.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    int selectedYear = years.isEmpty ? DateTime.now().year : years.first;
    final recordedDeposits = cash.invested - cash.autoInvested;
    final purchases = cash.moves
        .where((move) => move.kind == CashMoveKind.buy)
        .fold(0.0, (sum, move) => sum - move.amountRub);
    final sales = cash.moves
        .where((move) => move.kind == CashMoveKind.sell)
        .fold(0.0, (sum, move) => sum + move.amountRub);

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final history = cash.moves.where((move) => move.date.year == selectedYear).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
            SheetHeader(
              title: 'Счёт',
              subtitle: 'Движение денег по портфелю',
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 16),
            Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Вложено своих',
                      icon: Icons.account_balance_wallet_outlined,
                      value: cash.invested,
                      formatter: (v) => Fmt.money(v),
                      color: AppColors.info,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Свободные деньги',
                      icon: Icons.savings_outlined,
                      value: cash.cash,
                      formatter: (v) => Fmt.money(v),
                      color: AppColors.gold,
                      compact: true,
                    ),
                  ),
                ],
            ),
            const SizedBox(height: 12),
            _cashFormulaCard(
              title: 'Как считаются вложенные деньги',
              total: cash.invested,
              color: AppColors.info,
              rows: [
                ('Записанные пополнения', recordedDeposits),
                ('Определено по покупкам', cash.autoInvested),
              ],
            ),
            const SizedBox(height: 10),
            _cashFormulaCard(
              title: 'Как считаются свободные деньги',
              total: cash.cash,
              color: AppColors.gold,
              rows: [
                ('Пополнения', cash.invested),
                ('Продажи', sales),
                ('Выплаты', cash.payouts),
                ('Покупки и комиссии', -purchases),
                ('Выводы', -cash.withdrawn),
              ],
            ),
            if (cash.autoInvested > 0) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.auto_fix_high_rounded,
                color: AppColors.info,
                text: 'Из вложенного ${Fmt.money(cash.autoInvested)} приложение определило само: '
                    'когда на покупку денег на счёте не хватало, недостающая сумма считается '
                    'пополнением в этот день.',
              ),
            ],
            if (cash.cash > 0) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.info_outline_rounded,
                color: AppColors.warning,
                text: 'На счёте числится ${Fmt.money(cash.cash)} свободными. Если этих денег '
                    'у брокера уже нет — запишите вывод, иначе следующая покупка спишется '
                    'с них и «Вложено» окажется занижено.',
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cashEntrySheet(withdrawal: true),
                    icon: const Icon(Icons.north_east_rounded, size: 17),
                    label: const Text('Вывод'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cashEntrySheet(withdrawal: false),
                    icon: const Icon(Icons.south_west_rounded, size: 17),
                    label: const Text('Пополнение'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionTitle(
              title: 'История за $selectedYear год',
              subtitle: '${history.length} ${Fmt.plural(history.length, "операция", "операции", "операций")}',
              padding: const EdgeInsets.only(bottom: 10),
            ),
            if (years.length > 1) ...[
              PillTabs<int>(
                values: years,
                selected: selectedYear,
                labelOf: (year) => '$year',
                onChanged: (year) => setSheetState(() => selectedYear = year),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 14),
            ],
            ...history.map((move) => _cashRow(ctx, move)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cashFormulaCard({
    required String title,
    required double total,
    required Color color,
    required List<(String, double)> rows,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                Fmt.money(total),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 11),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(rows[i].$1, style: TextStyle(fontSize: 11.5, color: context.dim)),
                ),
                const SizedBox(width: 10),
                Text(
                  Fmt.signedMoney(rows[i].$2),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cashRow(BuildContext ctx, CashMove m) {
    final (IconData icon, Color color) = switch (m.kind) {
      CashMoveKind.deposit => (Icons.south_west_rounded, AppColors.info),
      CashMoveKind.autoDeposit => (Icons.auto_fix_high_rounded, AppColors.info),
      CashMoveKind.withdrawal => (Icons.north_east_rounded, AppColors.warning),
      CashMoveKind.buy => (Icons.shopping_bag_outlined, AppColors.negative),
      CashMoveKind.sell => (Icons.sell_outlined, AppColors.positive),
      CashMoveKind.payout => (Icons.card_giftcard_rounded, AppColors.positive),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withOpacity(0.14),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                Text(Fmt.date(m.date), style: TextStyle(fontSize: 10.5, color: context.dim)),
              ],
            ),
          ),
          Text(
            Fmt.signedMoney(m.amountRub),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.pnl(m.amountRub),
            ),
          ),
          if (m.depositId != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded, size: 17, color: context.dim),
              onPressed: () async {
                await StorageService.deleteDeposit(m.depositId!);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  void _cashEntrySheet({required bool withdrawal}) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: withdrawal ? 'Вывод со счёта' : 'Пополнение счёта',
                subtitle: withdrawal
                    ? 'Деньги, которые Вы сняли у брокера'
                    : 'Если Вы хотите записать пополнение точно, а не использовать автоматический расчёт',
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(height: 18),
              AppTextField(controller: amountCtrl, label: 'Сумма, ₽', number: true, autofocus: true),
              const SizedBox(height: 12),
              AppDateField(
                value: date,
                label: 'Дата',
                lastDate: DateTime.now(),
                firstDate: DateTime(2000),
                onPicked: (d) => setSheetState(() => date = d),
              ),
              const SizedBox(height: 12),
              AppTextField(controller: noteCtrl, label: 'Заметка (необязательно)'),
              const SizedBox(height: 22),
              GradientButton(
                label: 'Сохранить',
                icon: Icons.check_rounded,
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                  if (amount == null || amount <= 0) return;
                  await StorageService.addDeposit(Deposit(
                    id: const Uuid().v4(),
                    date: date,
                    amount: withdrawal ? -amount : amount,
                    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
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

  /// Вторая строка в карточке бумаги — что показывать, выбирается в
  /// настройках оформления.
  String _holdingSubtitle(String ticker, HoldingInfo h, double share) {
    // Количество и текущая цена одной бумаги. Средняя цена покупки — в
    // карточке бумаги.
    return switch (AppearanceService.holdingSubtitle) {
      HoldingSubtitle.quantityAndPrice => '${Fmt.qty(h.qty)} шт · '
          '${Fmt.price(h.displayPrice, type: _holdingTypes()[ticker.toUpperCase()] ?? AssetType.stock)}',
      HoldingSubtitle.share => '${(share * 100).toStringAsFixed(1)}% портфеля · ${Fmt.qty(h.qty)} шт',
      HoldingSubtitle.profitRub => '${Fmt.signedMoney(h.pnlRub)} · ${Fmt.qty(h.qty)} шт',
      HoldingSubtitle.profitPct => '${Fmt.pct(h.pnlPct)} · ${Fmt.qty(h.qty)} шт',
    };
  }

  String _holdingName(String ticker) {
    for (final purchase in StorageService.purchases.reversed) {
      if (purchase.ticker.toUpperCase() == ticker.toUpperCase() && purchase.name.trim().isNotEmpty) {
        return purchase.name.trim();
      }
    }
    return ticker;
  }

  /// Шапка главной карточки, пока палец лежит на графике. Повторяет строки
  /// обычной шапки, чтобы карточка не прыгала по высоте.
  List<Widget> _inspectHeader(
    BuildContext context,
    ChartInspection inspect,
    List<MapEntry<DateTime, double>> timeline,
    double currentValue, {
    required bool secondRow,
    Widget? heightKeeper,
    Widget? summaryKeeper,
  }) {
    final dimStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim);
    final String caption;
    final String big;
    final Color? bigColor;
    final double from;
    final double to;
    final String detail;
    if (inspect.isRange) {
      final a = timeline[inspect.from!];
      final b = timeline[inspect.to!];
      caption = '${Fmt.date(a.key)} → ${Fmt.date(b.key)}';
      from = a.value;
      to = b.value;
      big = Fmt.signedMoney(to - from);
      bigColor = AppColors.pnl(to - from);
      detail = '${Fmt.money(from)} → ${Fmt.money(to)}';
    } else {
      final p = timeline[inspect.index!];
      caption = Fmt.date(p.key);
      from = p.value;
      to = currentValue;
      big = Fmt.money(p.value);
      bigColor = null;
      detail = 'до сегодня ${Fmt.signedMoney(to - from)}';
    }
    final diff = to - from;
    final pct = from == 0 ? 0.0 : diff / from.abs() * 100;

    final inspectRow = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.pnl(diff).withOpacity(0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            diff >= 0 ? Icons.arrow_outward_rounded : Icons.south_east_rounded,
            size: 14,
            color: AppColors.pnl(diff),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          Fmt.pct(pct, decimals: 2),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.pnl(diff)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: HiddenAmount.forText(
            detail,
            fontSize: 11.5,
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.dim),
            ),
          ),
        ),
      ],
    );

    return [
      Row(
        children: [
          Expanded(
            child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: dimStyle),
          ),
          if (heightKeeper != null)
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: heightKeeper,
            ),
        ],
      ),
      const SizedBox(height: 8),
      HiddenAmount.forText(
        big,
        fontSize: 36,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            big,
            maxLines: 1,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              color: bigColor,
            ),
          ),
        ),
      ),
      // Под суммой — невидимая табличка «Сегодня / Всё время» держит высоту,
      // а поверх неё строка с изменением за выбранную точку или замер.
      if (summaryKeeper != null) ...[
        const SizedBox(height: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: summaryKeeper,
            ),
            if (secondRow)
              Positioned.fill(
                child: Align(alignment: Alignment.topLeft, child: inspectRow),
              ),
          ],
        ),
      ] else if (secondRow) ...[
        const SizedBox(height: 10),
        inspectRow,
      ],
    ];
  }

  /// Табличка под стоимостью: «Сегодня» и «Всё время» — подписи слева в
  /// колонку, суммы с процентами выровнены. null — показывать нечего.
  Widget? _heroSummary({
    required ({double rub, double pct})? today,
    required double? allTimeRub,
    required double? allTimePct,
  }) {
    if (today == null && allTimeRub == null) return null;

    // Одна строка: слева изменение за сегодня, справа — за всё время.
    // Каждая половина при нехватке места уменьшается, а не обрезается.
    return Builder(builder: (context) {
      Widget amount(double rub) {
        final text = Fmt.signedMoney(rub);
        return HiddenAmount.forText(
          text,
          fontSize: 14,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pnl(rub)),
          ),
        );
      }

      Widget label(String text) => Text(
            text,
            maxLines: 1,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
          );

      return Row(
        children: [
          if (today != null)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [amount(today.rub), const SizedBox(width: 5), label('сегодня')],
                ),
              ),
            ),
          if (today != null && allTimeRub != null) const SizedBox(width: 12),
          if (allTimeRub != null)
            Flexible(
              child: Align(
                alignment: today == null ? Alignment.centerLeft : Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [label('за всё время'), const SizedBox(width: 5), amount(allTimeRub)],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  // --- Сворачиваемые разделы главной ---

  static const _secAlloc = 'sec_alloc';
  static const _secGoal = 'sec_goal';
  static const _secPassive = 'sec_passive';
  static const _secIis = 'sec_iis';

  Future<void> _toggleSection(String id, bool collapsed) async {
    await AppearanceService.setGroupCollapsed(id, !collapsed);
    if (mounted) setState(() {});
  }

  static const _secPayouts = 'sec_payouts';

  Widget _moneyText(String text, {Color? color}) => HiddenAmount.forText(
        text,
        fontSize: 13.5,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color),
        ),
      );

  /// Раздел главной, который сворачивается нажатием на заголовок — как
  /// группы в составе портфеля. Свёрнутый раздел — одна строка с итогом, а в
  /// варианте «с превью» ещё и маленькая картинка содержимого. Приложение
  /// запоминает, какие разделы свёрнуты.
  Widget _section(
    BuildContext context, {
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool collapsed,
    required Widget body,
    Widget? trailing,
    Widget Function()? preview,
  }) {
    final withPreview = AppearanceService.sectionPreview == SectionPreview.preview;
    final header = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: context.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: context.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.dim),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
        const SizedBox(width: 2),
        AnimatedRotation(
          turns: collapsed ? 0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.expand_more_rounded, size: 22, color: context.dim),
        ),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await AppearanceService.setGroupCollapsed(id, !collapsed);
              if (mounted) setState(() {});
            },
            child: header,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? (withPreview && preview != null
                    ? Padding(padding: const EdgeInsets.only(top: 10), child: preview())
                    : const SizedBox(width: double.infinity))
                : Padding(padding: const EdgeInsets.only(top: 14), child: body),
          ),
        ],
      ),
    );
  }

  /// Превью «Распределения»: полоса долей и три крупнейшие позиции.
  Widget _sharesPreview(BuildContext context, Map<String, double> data) {
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();
    final top = entries.take(3).map((e) {
      final name = e.key.length > 14 ? '${e.key.substring(0, 13)}…' : e.key;
      return '$name ${(e.value / total * 100).toStringAsFixed(0)}%';
    }).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (int i = 0; i < entries.length; i++)
                  Expanded(
                    flex: math.max(1, (entries[i].value / total * 1000).round()),
                    child: Container(
                      margin: EdgeInsets.only(right: i == entries.length - 1 ? 0 : 1.5),
                      color: AppColors.chartAt(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entries.length > 3 ? '$top · …' : top,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.dim),
        ),
      ],
    );
  }

  /// Превью «Выплат»: 12 квадратиков месяцев, чем ярче — тем больше выплат.
  _Metric _returnMetric(BuildContext context, double? xirr, double? twr, double? benchmark, String? benchmarkError) {
    final hasBoth = xirr != null && twr != null;
    final showXirr = !hasBoth ? xirr != null : _returnSegment == 0;
    final shown = (showXirr ? xirr : twr)!;
    return _Metric(
      label: 'Доходность',
      listLabel: hasBoth ? 'Доходность ${showXirr ? 'XIRR' : 'TWR'}' : null,
      icon: showXirr ? Icons.percent_rounded : Icons.query_stats_rounded,
      color: AppColors.pnl(shown),
      value: showXirr ? '${Fmt.pct(shown)} год.' : Fmt.pct(shown),
      valueColor: AppColors.pnl(shown),
      sub: showXirr
          ? 'с учётом дат вложений'
          : (benchmark == null ? (benchmarkError ?? 'без влияния пополнений') : 'индекс МосБиржи ${Fmt.pct(benchmark)}'),
      switchLabel: hasBoth ? (showXirr ? 'XIRR' : 'TWR') : null,
      onSwitch: hasBoth ? () => setState(() => _returnSegment = _returnSegment == 0 ? 1 : 0) : null,
      onTap: () => _showReturnInfo(context, xirr: showXirr),
    );
  }

  _Metric _forecastMetric(BuildContext context, bool hasPayouts, double payoutForecast, double payoutYield) {
    final showValue = !hasPayouts || _forecastSegment == 1;
    if (!showValue) {
      return _Metric(
        label: 'Прогноз выплат',
        icon: Icons.auto_graph_rounded,
        color: AppColors.violet,
        value: '~${Fmt.money(payoutForecast)}',
        money: true,
        sub: payoutYield > 0 ? 'за 12 месяцев · ${Fmt.pct(payoutYield)} годовых' : 'по выплатам прошлых лет',
        switchLabel: 'Выплаты',
        onSwitch: () => _onForecastSegment(1),
        onTap: () => showForecastSheet(context, initial: 0, onChanged: _onForecastSegment),
      );
    }
    final forecast = ValueForecastService.realistic(ValueForecastService.defaultHorizon);
    return _Metric(
      label: 'Прогноз стоимости',
      icon: Icons.stacked_line_chart_rounded,
      color: AppColors.info,
      value: '~${Fmt.money(forecast.result.breakdown.end)}',
      money: true,
      sub: 'через ${ValueForecastService.defaultHorizon} года · '
          '${forecast.plansApplied ? 'с учётом планов' : 'обычный сценарий'}',
      switchLabel: hasPayouts ? 'Стоимость' : null,
      onSwitch: hasPayouts ? () => _onForecastSegment(0) : null,
      onTap: () => hasPayouts
          ? showForecastSheet(context, initial: 1, onChanged: _onForecastSegment)
          : showValueForecastSheet(context),
    );
  }

  /// «Против инфляции»: на сколько портфель обогнал рост цен за период
  /// главного экрана. Инфляция и ключевая ставка — с сайта Банка России.
  _Metric _inflationMetric(BuildContext context) {
    final r = RealReturnService.forPeriod(_period);
    if (r == null) {
      final String sub;
      if (!CbrService.hasData && !OnlineSettingsService.enabled) {
        sub = 'включите загрузку данных из интернета';
      } else if (!CbrService.hasData) {
        sub = CbrService.error.value == null ? 'загружаем данные Банка России' : 'нет данных Банка России';
      } else {
        sub = 'за этот период нет вложений';
      }
      return _Metric(
        label: 'Против инфляции',
        icon: Icons.shield_outlined,
        color: AppColors.warning,
        value: '—',
        sub: sub,
        onTap: () => showRealReturnSheet(context, _period),
      );
    }
    return _Metric(
      label: 'Против инфляции',
      icon: Icons.shield_outlined,
      color: AppColors.pnl(r.vsInflation),
      value: formatPoints(r.vsInflation),
      valueColor: AppColors.pnl(r.vsInflation),
      sub: '${r.vsInflation >= 0 ? 'обогнал' : 'отстал от'} рост${r.vsInflation >= 0 ? '' : 'а'} цен ${realReturnPeriodText(_period)}',
      onTap: () => showRealReturnSheet(context, _period),
    );
  }

  /// «Стресс-тест»: насколько подешевеет портфель, если акции упадут на 20%.
  _Metric _stressMetric(BuildContext context) {
    final r = StressTestService.run(StressTestService.scenarios.first);
    return _Metric(
      label: 'Стресс-тест',
      icon: Icons.bolt_rounded,
      color: AppColors.negative,
      value: Fmt.pct(r.pct),
      valueColor: r.pct.abs() < 0.05 ? null : AppColors.pnl(r.pct),
      sub: 'если рынок акций упадёт на 20%',
      onTap: () => showStressTestSheet(
        context,
        onOpenTicker: (t) => Navigator.push(context, AppPageRoute(builder: (_) => TickerDetailScreen(ticker: t))),
      ),
    );
  }

  Widget _metricValue(_Metric m, double fontSize) {
    final text = Text(
      m.value,
      maxLines: 1,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: m.valueColor),
    );
    return m.money ? HiddenAmount.forText(m.value, fontSize: fontSize, child: text) : text;
  }

  /// [compact] — только значок ⇄: в строке списка рядом с длинным
  /// названием («Прогноз выплат») подпись на кнопке не помещается.
  Widget _switchChip(_Metric m, {bool compact = false}) {
    if (compact) {
      return Pressable(
        onTap: m.onSwitch,
        child: Container(
          width: 24,
          height: 20,
          decoration: BoxDecoration(
            color: context.accent.withOpacity(0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(Icons.swap_horiz_rounded, size: 14, color: context.accent),
        ),
      );
    }
    return Pressable(
      onTap: m.onSwitch,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: context.accent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.switchLabel!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.accent)),
            const SizedBox(width: 2),
            Icon(Icons.swap_horiz_rounded, size: 11, color: context.accent),
          ],
        ),
      ),
    );
  }

  Widget _metricsBlock(BuildContext context, List<_Metric> metrics) {
    Widget spot(_Metric m, Widget child) => m.tourId == null ? child : TourSpot(id: m.tourId!, child: child);

    if (AppearanceService.metricsLayout == MetricsLayout.list) {
      final rows = <Widget>[];
      for (int i = 0; i < metrics.length; i++) {
        final m = metrics[i];
        if (i > 0) rows.add(Container(height: 1, color: context.hairline));
        rows.add(spot(
          m,
          Pressable(
            onTap: m.onTap,
            scale: 0.99,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: m.color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(m.icon, size: 17, color: m.color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(m.listLabel ?? m.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            ),
                            if (m.switchLabel != null) ...[const SizedBox(width: 6), _switchChip(m, compact: true)],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(m.sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: context.dim)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _metricValue(m, 14.5),
                  Icon(Icons.chevron_right_rounded, size: 18, color: context.dim),
                ],
              ),
            ),
          ),
        ));
      }
      return AppCard(
        padding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      );
    }

    // Плитки: две главные — «Вложено» и «Прибыль» — крупно, остальные
    // компактными плашками по две в ряд.
    Widget bigTile(_Metric m) => spot(
          m,
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            radius: AppRadius.sm,
            border: Border.all(color: m.color.withOpacity(0.4)),
            onTap: m.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(m.icon, size: 13, color: m.color),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(m.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: m.color)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _metricValue(m, 19)),
                const SizedBox(height: 2),
                Text(m.sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, height: 1.3, color: context.dim)),
              ],
            ),
          ),
        );

    // Кнопка переключения — кружок ⇄ на значке: рядом с названием в узкой
    // плашке ей нет места.
    Widget plaque(_Metric m) {
      final icon = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: m.color.withOpacity(0.16), borderRadius: BorderRadius.circular(9)),
        child: Icon(m.icon, size: 15, color: m.color),
      );
      return spot(
        m,
        AppCard(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          radius: AppRadius.sm,
          onTap: m.onTap,
          child: Row(
            children: [
              if (m.onSwitch == null)
                icon
              else
                Pressable(
                  onTap: m.onSwitch,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(left: 0, top: 0, child: icon),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 15,
                            height: 15,
                            decoration: BoxDecoration(
                              color: context.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(Icons.swap_horiz_rounded, size: 10, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.listLabel ?? m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.dim)),
                    const SizedBox(height: 1),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _metricValue(m, 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget pairRow(List<_Metric> pair, Widget Function(_Metric) build) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: build(pair[0])),
              const SizedBox(width: 8),
              Expanded(child: pair.length > 1 ? build(pair[1]) : const SizedBox.shrink()),
            ],
          ),
        );

    final rows = <Widget>[];
    final big = metrics.take(2).toList();
    final rest = metrics.skip(2).toList();
    if (big.isNotEmpty) rows.add(pairRow(big, bigTile));
    for (int i = 0; i < rest.length; i += 2) {
      rows.add(const SizedBox(height: 8));
      rows.add(pairRow(rest.sublist(i, math.min(i + 2, rest.length)), plaque));
    }
    return Column(children: rows);
  }

  /// Выплаты по годам: линия с точками и рост к прошлому году.
  Widget _payoutYears(BuildContext context, List<int> years) {
    final now = DateTime.now();
    final totals = <(int, double)>[
      for (final y in years)
        (y, PayoutCalendarService.year(y, withForecast: false).fold(0.0, (s, c) => s + c.total)),
    ];
    double totalOf(int y) {
      for (final t in totals) {
        if (t.$1 == y) return t.$2;
      }
      return 0;
    }

    // Текущий год сравниваем с тем же периодом прошлого: январь — нынешний
    // месяц, иначе неполный год всегда выглядел бы падением.
    String? delta;
    double? change;
    final prevYear = _incomeYear - 1;
    if (years.contains(prevYear)) {
      final cur = totalOf(_incomeYear);
      double prev;
      String against;
      if (_incomeYear == now.year) {
        prev = PayoutCalendarService.year(prevYear, withForecast: false)
            .where((c) => c.month.month <= now.month)
            .fold(0.0, (s, c) => s + c.total);
        against = now.month == 1
            ? 'к январю $prevYear'
            : 'к ${Fmt.monthShort(1)}–${Fmt.monthShort(now.month)} $prevYear';
      } else {
        prev = totalOf(prevYear);
        against = 'к $prevYear';
      }
      if (prev > 0.5) {
        change = (cur / prev - 1) * 100;
        delta = against;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('По годам', style: TextStyle(fontSize: 12, color: context.dim))),
            if (change != null && delta != null)
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${change >= 0 ? '▲ +' : '▼ −'}${change.abs().round()}%',
                    style: TextStyle(
                      color: change >= 0 ? AppColors.positive : AppColors.negative,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' $delta', style: TextStyle(color: context.dim)),
                ]),
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 6),
        PayoutYearsChart(
          years: totals,
          selected: _incomeYear,
          partialYear: years.contains(now.year) ? now.year : null,
          onSelect: (y) => setState(() => _incomeYear = y),
        ),
      ],
    );
  }

  Widget _monthsPreview(BuildContext context, List<PayoutMonthCell> cells) {
    final maxTotal = cells.fold(0.0, (m, c) => math.max(m, c.total));
    final empty = context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (int i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: cells[i].isEmpty
                        ? empty
                        : AppColors.positive.withOpacity(
                            0.12 + 0.6 * (maxTotal <= 0 ? 0 : cells[i].total / maxTotal)),
                    borderRadius: BorderRadius.circular(3),
                    border: cells[i].hasForecast
                        ? Border.all(color: AppColors.positive.withOpacity(0.7), width: 1)
                        : null,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('январь', style: TextStyle(fontSize: 10, color: context.dim)),
            Text('по месяцам', style: TextStyle(fontSize: 10, color: context.dim)),
            Text('декабрь', style: TextStyle(fontSize: 10, color: context.dim)),
          ],
        ),
      ],
    );
  }

  /// Порядок групп в составе портфеля.
  static const _groupOrder = [
    AssetType.stock,
    AssetType.bond,
    AssetType.etf,
    AssetType.currency,
    AssetType.other,
  ];

  /// Тип каждой бумаги — по последней сделке с ней.
  Map<String, AssetType> _holdingTypes() {
    final result = <String, AssetType>{};
    for (final p in StorageService.purchases) {
      result[p.ticker.toUpperCase()] = p.type;
    }
    return result;
  }

  static String _groupTitle(AssetType type) => switch (type) {
        AssetType.stock => 'Акции',
        AssetType.bond => 'Облигации',
        AssetType.etf => 'Фонды',
        AssetType.currency => 'Валюта',
        AssetType.other => 'Прочее',
      };

  static Color _groupColor(AssetType type) => switch (type) {
        AssetType.stock => AppColors.info,
        AssetType.bond => AppColors.violet,
        AssetType.etf => AppColors.cyan,
        AssetType.currency => AppColors.gold,
        AssetType.other => AppColors.neutral,
      };

  /// Заголовок группы: тип, число бумаг, сумма и доля в портфеле. В режиме
  /// сворачивания это карточка со стрелкой, нажатие по ней прячет бумаги.
  Widget _groupHeader(
    BuildContext context, {
    required AssetType type,
    required int count,
    required double value,
    required double share,
    required double pnlPct,
    required double pnlRub,
    required bool collapsible,
    required bool collapsed,
  }) {
    final color = _groupColor(type);
    final money = Fmt.money(value);
    final pnlText = '${Fmt.signedMoney(pnlRub)} · ${Fmt.pct(pnlPct)}';
    // Группа выглядит так же, как разделы «Распределение» и «Дивиденды и
    // купоны»: иконка в цветном квадрате, название, итог справа.
    final row = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_groupIcon(type), size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_groupTitle(type)} · $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 1),
              HiddenAmount.forText(
                pnlText,
                fontSize: 11.5,
                child: Text(
                  pnlText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.pnl(pnlRub)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        HiddenAmount.forText(
          money,
          fontSize: 13.5,
          child: Text(money, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ),
        if (collapsible) ...[
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: collapsed ? 0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more_rounded, size: 22, color: context.dim),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        onTap: collapsible
            ? () async {
                await AppearanceService.setGroupCollapsed(type.name, !collapsed);
                if (mounted) setState(() {});
              }
            : null,
        child: row,
      ),
    );
  }

  static IconData _groupIcon(AssetType type) => switch (type) {
        AssetType.stock => Icons.show_chart_rounded,
        AssetType.bond => Icons.receipt_long_rounded,
        AssetType.etf => Icons.pie_chart_outline_rounded,
        AssetType.currency => Icons.currency_exchange_rounded,
        AssetType.other => Icons.category_outlined,
      };

  /// Плашки прибыли в списке бумаг: в рублях или в процентах. Запоминается.
  bool _pnlUnitsRub = AppearanceService.pnlInRub;

  void _togglePnlUnits() {
    setState(() => _pnlUnitsRub = !_pnlUnitsRub);
    AppearanceService.setPnlInRub(_pnlUnitsRub);
  }

  /// Строка бумаги в составе портфеля.
  ///
  /// Компактная: аватар поменьше и без звёздочки избранного (она есть в
  /// карточке бумаги) — иначе с мини-графиком рядом названию не хватало места.
  /// Доли бумаг здесь не показываются, они есть в «Распределении».
  Widget _holdingTile(BuildContext context, String ticker, HoldingInfo h, double weight) {
    final pnlColor = AppColors.pnl(h.pnlRub);
    final density = AppearanceService.density.scale;
    final mini = MiniHistoryService.pointsFor(ticker);
    final day = AnalyticsService.dayChangeFor(ticker, h);
    return AppCard(
      padding: EdgeInsets.fromLTRB(12, 11 * density, 12, 11 * density),
      onTap: () => Navigator.push(
        context,
        AppPageRoute(builder: (_) => TickerDetailScreen(ticker: ticker)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Hero(tag: 'logo-$ticker', child: TickerAvatar(ticker: ticker, size: 36)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _holdingName(ticker),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    // Количество и цена. Изменение за сегодня — под мини-графиком.
                    Text(
                      _holdingSubtitle(ticker, h, weight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: context.dim, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              // Столбик: график за 30 дней, под ним — изменение за сегодня.
              // Без графика «сегодня» стоит на его месте. Следует тому же
              // переключателю «% / ₽», что и плашка справа.
              if (mini != null || day != null) ...[
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mini != null) MiniSparkline(values: mini, width: 44, height: 20),
                    if (mini != null && day != null) const SizedBox(height: 3),
                    if (day != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 72),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${day.rub >= 0 ? '▲' : '▼'}'
                            '${_pnlUnitsRub ? (AppearanceService.amountsHidden ? '•••' : Fmt.money(day.rub.abs())) : '${day.pct.abs().toStringAsFixed(1)}%'}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.pnl(day.rub),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(width: 8),
              // Сумма и плашка прибыли. Нажатие сюда переключает весь список
              // между процентами и рублями, остальная строка открывает
              // карточку. Ширина ограничена, чтобы длинное число не съело
              // название; если не влезает — шрифт чуть уменьшается, но число
              // никогда не обрезается.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePnlUnits,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        HiddenAmount.forText(
                          Fmt.money(h.valueRub),
                          fontSize: 14,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              Fmt.money(h.valueRub),
                              maxLines: 1,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        _pnlUnitsRub
                            ? HiddenAmount.forText(
                                Fmt.signedMoney(h.pnlRub),
                                fontSize: 10.5,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: TagChip(text: Fmt.signedMoney(h.pnlRub), color: pnlColor, fontSize: 10.5),
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: TagChip(text: Fmt.pct(h.pnlPct), color: pnlColor, fontSize: 10.5),
                              ),
                      ],
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
}

/// Показатель на главной: вложено, прибыль, доходность, прогноз.
class _Metric {
  final String label;
  final IconData icon;
  final Color color;
  final String value;
  final Color? valueColor;
  final String sub;
  final VoidCallback onTap;

  /// Сумма в рублях — прячется вместе с остальными суммами.
  final bool money;

  /// Кнопка переключения способа расчёта: «XIRR ⇄», «Выплаты ⇄».
  final String? switchLabel;
  final VoidCallback? onSwitch;

  final String? tourId;

  /// Название для вида «Список», где кнопка переключения — только значок и
  /// способ расчёта приходится писать в названии: «Доходность XIRR».
  final String? listLabel;

  const _Metric({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.sub,
    required this.onTap,
    this.valueColor,
    this.money = false,
    this.switchLabel,
    this.onSwitch,
    this.tourId,
    this.listLabel,
  });
}
