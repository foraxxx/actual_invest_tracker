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
import '../services/favorites_service.dart';
import '../services/manual_price_service.dart';
import '../services/online_price_service.dart';
import '../services/portfolio_service.dart';
import '../services/tax_service.dart';
import '../services/benchmark_service.dart';
import '../services/portfolio_history_service.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/payout_forecast_sheet.dart';
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
  PeriodFilter _incomePeriod = PeriodFilter.year1;
  _AllocationMode _alloc = _AllocationMode.sectors;

  @override
  void initState() {
    super.initState();
    // Графики купонов и дивидендов могли ещё не загрузиться к моменту, когда
    // появились бумаги, — просим догрузить при входе на вкладку.
    PayoutForecastService.refresh();
    BenchmarkService.refresh();
    PortfolioHistoryService.refresh();
    StorageService.dataVersion.addListener(_onDataChanged);
    ManualPriceService.version.addListener(_onDataChanged);
    OnlinePriceService.version.addListener(_onPriceChanged);
    BenchmarkService.returnPercent.addListener(_onDataChanged);
    BenchmarkService.error.addListener(_onDataChanged);
    PortfolioHistoryService.timeline.addListener(_onDataChanged);
    PortfolioHistoryService.error.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    StorageService.dataVersion.removeListener(_onDataChanged);
    ManualPriceService.version.removeListener(_onDataChanged);
    OnlinePriceService.version.removeListener(_onPriceChanged);
    BenchmarkService.returnPercent.removeListener(_onDataChanged);
    BenchmarkService.error.removeListener(_onDataChanged);
    PortfolioHistoryService.timeline.removeListener(_onDataChanged);
    PortfolioHistoryService.error.removeListener(_onDataChanged);
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
          text: 'Сколько сейчас стоят бумаги и сколько ты на них заработал. График показывает, '
              'как менялась стоимость. Проведи по нему пальцем — покажет дату и сумму.',
        ),
        PageTourStep(
          anchor: 'invested',
          title: 'Вложено своих',
          text: 'Только твои деньги, пришедшие извне. Пополнения приложение считает само по '
              'сделкам: продал бумаги и купил новые — вложено не вырастет. Нажми, чтобы открыть счёт.',
        ),
        PageTourStep(
          anchor: 'cash',
          title: 'Свободные деньги',
          text: 'Деньги на счёте, ещё не вложенные в бумаги. Если ты снял их у брокера — запиши '
              'вывод, иначе следующая покупка спишется с них и вложения окажутся занижены.',
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
    final periodProfit = AnalyticsService.profitForPeriod(_period);
    final totalIncome = AnalyticsService.totalIncome(f: PeriodFilter.all);
    final totalProfit = unrealizedPnl + realizedPnl + totalIncome;
    final bySector = AnalyticsService.currentValueBySector();
    final byTicker = AnalyticsService.currentValueByTicker();
    final incomeByMonth = AnalyticsService.incomeByMonth(f: _incomePeriod);
    final concentration = AnalyticsService.topHoldingConcentrationPct();
    final topTicker = AnalyticsService.topHoldingTicker();
    final xirr = AnalyticsService.xirrPercent();
    final twr = AnalyticsService.twrPercent();
    final benchmark = BenchmarkService.returnPercent.value;
    final benchmarkError = BenchmarkService.error.value;
    final taxDue = TaxService.enabled ? TaxService.totalTaxDue() : 0.0;
    final periodChange = AnalyticsService.portfolioChangeForPeriod(_period);

    final accent = context.accent;
    final isEmpty = holdings.isEmpty && totalIncome == 0 && realizedPnl == 0;

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
                Row(
                  children: [
                    Text(
                      'Стоимость портфеля',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
                    ),
                    if (periodChange != null) ...[
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
                if (!isEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.pnl(totalProfit).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          totalProfit >= 0 ? Icons.arrow_outward_rounded : Icons.south_east_rounded,
                          size: 14,
                          color: AppColors.pnl(totalProfit),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: RollingNumber(
                          value: totalProfit,
                          formatter: (v) => Fmt.signedMoney(v),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.pnl(totalProfit),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('общая прибыль', style: TextStyle(fontSize: 11.5, color: context.dim)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'по текущим бумагам ${Fmt.signedMoney(unrealizedPnl)} · '
                    'по продажам ${Fmt.signedMoney(realizedPnl)} · '
                    'выплаты ${Fmt.signedMoney(totalIncome)}',
                    style: TextStyle(fontSize: 10.8, color: context.dim, height: 1.3),
                  ),
                ],
                const SizedBox(height: 14),
                if (timeline.length > 1)
                  Sparkline(
                    values: timeline.map((e) => e.value).toList(),
                    color: accent,
                    height: 132,
                    tooltipBuilder: (i, v) => '${Fmt.date(timeline[i].key)}\n${Fmt.money(v)}',
                    dateLabel: (i) => Fmt.date(timeline[i].key),
                    priceLabel: (v) => Fmt.money(v),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Добавь первую сделку — здесь появится график стоимости',
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
      FadeSlideIn(
        delay: Duration(milliseconds: 40 * step++),
        child: IntrinsicHeight(
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TourSpot(
                id: 'invested',
                child: StatTile(
                label: 'Вложено за период',
                icon: Icons.account_balance_wallet_outlined,
                value: periodCash.invested,
                formatter: (v) => Fmt.money(v),
                hint: 'пополнения − выводы',
                color: AppColors.info,
                onTap: () => _cashSheet(cash),
              ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Прибыль за период',
                icon: Icons.payments_outlined,
                value: periodProfit,
                formatter: (v) => Fmt.money(v),
                hint: 'рост + продажи + выплаты',
                color: AppColors.pnl(periodProfit),
              ),
            ),
          ],
        ),
          ),
      ),

      const SizedBox(height: 10),
      FadeSlideIn(
        delay: Duration(milliseconds: 40 * step++),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                    label: 'Свободные деньги',
                    icon: Icons.savings_outlined,
                    value: cash.cash,
                    formatter: (v) => Fmt.money(v),
                    hint: 'на счёте, не в бумагах',
                    color: AppColors.gold,
                    onTap: () => _cashSheet(cash),
                  ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: 'Выплаты за период',
                  icon: Icons.card_giftcard_rounded,
                  value: periodCash.payouts,
                  formatter: (v) => Fmt.money(v),
                  hint: 'дивиденды и купоны',
                  color: AppColors.positive,
                ),
              ),
            ],
          ),
        ),
      ),

      if (xirr != null || twr != null || payoutForecast > 0) ...[
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: Duration(milliseconds: 40 * step++),
          child: LayoutBuilder(
            builder: (context, _) {
              final tiles = <Widget>[
                if (xirr != null)
                  StatTile(
                    label: 'Доходность (XIRR)',
                    icon: Icons.percent_rounded,
                    text: '${Fmt.pct(xirr)} год.',
                    hint: 'с учётом дат вложений',
                    color: AppColors.pnl(xirr),
                    onTap: () => _showReturnInfo(context, xirr: true),
                  ),
                if (twr != null)
                  StatTile(
                    label: 'Доходность (TWR)',
                    icon: Icons.query_stats_rounded,
                    text: Fmt.pct(twr),
                    hint: benchmark == null
                        ? (benchmarkError ?? 'без влияния пополнений')
                        : 'IMOEX ${Fmt.pct(benchmark)}',
                    color: AppColors.pnl(twr),
                    onTap: () => _showReturnInfo(context, xirr: false),
                  ),
                if (payoutForecast > 0)
                  StatTile(
                    label: 'Прогноз выплат',
                    icon: Icons.auto_graph_rounded,
                    value: payoutForecast,
                    formatter: (v) => '~${Fmt.money(v)}',
                    hint: payoutYield > 0
                        ? '${Fmt.pct(payoutYield)} годовых'
                        : 'по прошлым выплатам',
                    color: AppColors.violet,
                    onTap: () => showPayoutForecastSheet(context),
                  ),
              ];
              return Column(
                children: [
                  for (int i = 0; i < tiles.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tiles[i]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: i + 1 < tiles.length
                                ? tiles[i + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],

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

      if (concentration > 40 && topTicker != null) ...[
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: Duration(milliseconds: 40 * step++),
          child: InfoBanner(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            text: '$topTicker занимает ${concentration.toStringAsFixed(0)}% портфеля — '
                'диверсификация низкая',
          ),
        ),
      ],
    ];

    // --- Избранное ---
    children.addAll([
      ValueListenableBuilder<int>(
        valueListenable: FavoritesService.version,
        builder: (context, _, __) {
          final favs = FavoritesService.all;
          if (favs.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(title: 'Избранное', subtitle: 'Быстрый доступ к бумагам'),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: favs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final t = favs[i];
                      final name = _favoriteName(t);
                      return Pressable(
                        onTap: () => Navigator.push(
                          context,
                          AppPageRoute(builder: (_) => TickerDetailScreen(ticker: t)),
                        ),
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          decoration: BoxDecoration(
                            color: context.isDark ? Colors.white.withOpacity(0.04) : Colors.white,
                            borderRadius: AppRadius.all(AppRadius.md),
                            border: Border.all(color: context.hairline),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TickerAvatar(ticker: t, size: 30, glow: false),
                              const SizedBox(height: 5),
                              Text(
                                name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ]);

    // --- Состав портфеля ---
    // Секция рисуется ВСЕГДА: если позиций нет, важно объяснить почему, а не
    // молча спрятать блок — иначе экран выглядит сломанным.
    final entries = holdings.entries.toList()..sort((a, b) => b.value.valueRub.compareTo(a.value.valueRub));
    final total = entries.fold(0.0, (s, e) => s + e.value.valueRub);
    children.add(const SizedBox(height: 26));
    children.add(TourSpot(
      id: 'holdings',
      child: SectionTitle(
      title: 'Состав портфеля',
      subtitle: entries.isEmpty
          ? 'Открытых позиций нет'
          : '${entries.length} ${Fmt.papers(entries.length)} · ${Fmt.money(total)}',
    ),
    ));
    if (entries.isEmpty) {
      children.add(InfoBanner(
        icon: Icons.inventory_2_outlined,
        color: AppColors.neutral,
        text: StorageService.purchases.isEmpty
            ? 'Сделок пока нет — добавь первую на вкладке «Сделки».'
            : 'Сделки есть, но по всем бумагам куплено ровно столько же, сколько продано, '
                'поэтому открытых позиций не осталось. Проверь количество в продажах и '
                'написание тикеров: «SBER» и «Sber» считаются разными бумагами.',
      ));
    }
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FadeSlideIn.staggered(
          index: i,
          child: _holdingTile(context, e.key, e.value, total <= 0 ? 0 : e.value.valueRub / total),
        ),
      ));
    }

    // --- Распределение ---
    final allocData = _alloc == _AllocationMode.sectors ? bySector : byTicker;
    if (allocData.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(AppCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          children: [
            const SectionTitle(
              title: 'Распределение',
              subtitle: 'Доли текущих позиций',
              padding: EdgeInsets.only(bottom: 12),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: PillTabs<_AllocationMode>(
                scrollable: false,
                values: _AllocationMode.values,
                selected: _alloc,
                labelOf: (m) => m == _AllocationMode.sectors ? 'По секторам' : 'По бумагам',
                onChanged: (m) => setState(() => _alloc = m),
              ),
            ),
            const SizedBox(height: 16),
            DonutChart(
              data: allocData,
              valueFormatter: (v) => Fmt.money(v),
              centerLabel: _alloc == _AllocationMode.sectors ? 'Всего по секторам' : 'Всего по бумагам',
            ),
          ],
        ),
      ));
    }

    // --- Доход по месяцам ---
    if (StorageService.incomes.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(AppCard(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              title: 'Дивиденды и купоны',
              subtitle: 'Полученные выплаты по месяцам',
              padding: EdgeInsets.only(bottom: 12, left: 2),
            ),
            PillTabs<PeriodFilter>(
              values: const [PeriodFilter.month6, PeriodFilter.year1, PeriodFilter.all],
              selected: _incomePeriod,
              labelOf: _periodLabel,
              onChanged: (v) => setState(() => _incomePeriod = v),
            ),
            const SizedBox(height: 14),
            BarsChart(
              values: incomeByMonth.values.toList(),
              labels: incomeByMonth.keys.map(Fmt.monthKeyLabel).toList(),
              color: AppColors.positive,
              valueFormatter: Fmt.money,
            ),
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
          subtitle: 'Добавь первую сделку на вкладке «Сделки» — и здесь появятся '
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: children,
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


  Future<void> _showReturnInfo(BuildContext context, {required bool xirr}) {
    final title = xirr ? 'Доходность XIRR' : 'Доходность TWR';
    final intro = xirr
        ? 'XIRR показывает личную среднегодовую доходность ваших денег. '
            'Он учитывает, сколько вы вложили и в какие именно даты.'
        : 'TWR показывает, как работал сам портфель, если убрать влияние '
            'размера и времени пополнений и выводов.';
    final calculation = xirr
        ? 'Покупки считаются расходами, продажи и полученные выплаты — доходами, '
            'а текущая стоимость бумаг — итоговой суммой на сегодня. Затем приложение '
            'находит такую годовую ставку, которая связывает все эти движения денег.'
        : 'История делится на отрезки между пополнениями и выводами. Для каждого отрезка '
            'считается изменение общей стоимости счёта, после чего результаты соединяются. '
            'Покупки, продажи и выплаты внутри портфеля не считаются внешними вложениями.';
    final example = xirr
        ? 'Например, крупная сумма, внесённая недавно, влияет на XIRR сильнее, чем небольшая. '
            'Поэтому XIRR лучше отвечает на вопрос: «Какую доходность получили именно мои деньги?»'
        : 'Поэтому TWR удобно сравнивать с индексом МосБиржи или другим портфелем: '
            'момент пополнения не улучшает и не ухудшает показатель.';
    final caveat = xirr
        ? 'Показатель является годовым. Для короткой истории он может заметно меняться '
            'и не рассчитывается, если данных недостаточно.'
        : 'Точность зависит от истории стоимости и денежных движений. Если старых котировок '
            'нет, приложение использует ближайшие известные цены сделок или ручные цены.';

    final value = xirr ? AnalyticsService.xirrPercent() : AnalyticsService.twrPercent();

    return showAppSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                title: title,
                subtitle: xirr ? 'Личная доходность ваших денег' : 'Доходность инвестиционной стратегии',
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(height: 16),
              if (value != null) ...[
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
                          xirr ? Icons.percent_rounded : Icons.query_stats_rounded,
                          color: AppColors.pnl(value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ваш результат', style: TextStyle(fontSize: 11.5, color: context.dim)),
                            const SizedBox(height: 3),
                            Text(
                              xirr ? '${Fmt.pct(value)} годовых' : Fmt.pct(value),
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
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Вложено своих',
                      icon: Icons.account_balance_wallet_outlined,
                      value: cash.invested,
                      formatter: (v) => Fmt.money(v),
                      color: AppColors.info,
                      marqueeLabel: true,
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
                    ),
                  ),
                ],
              ),
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
                    'у брокера уже нет — запиши вывод, иначе следующая покупка спишется '
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
                    ? 'Деньги, которые ты снял у брокера'
                    : 'Если хочешь записать пополнение точно, а не доверять расчёту',
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
    final type = _holdingType(ticker);
    return switch (AppearanceService.holdingSubtitle) {
      HoldingSubtitle.quantityAndPrice =>
        '${Fmt.qty(h.qty)} шт · ${Fmt.price(h.avgCost, type: type)} → ${Fmt.price(h.displayPrice, type: type)}',
      HoldingSubtitle.share => '${(share * 100).toStringAsFixed(1)}% портфеля · ${Fmt.qty(h.qty)} шт',
      HoldingSubtitle.profitRub => '${Fmt.signedMoney(h.pnlRub)} · ${Fmt.qty(h.qty)} шт',
      HoldingSubtitle.profitPct => '${Fmt.pct(h.pnlPct)} · ${Fmt.qty(h.qty)} шт',
    };
  }

  AssetType _holdingType(String ticker) {
    for (final purchase in StorageService.purchases.reversed) {
      if (purchase.ticker.toUpperCase() == ticker.toUpperCase()) {
        return purchase.type;
      }
    }
    return AssetType.stock;
  }

  String _holdingName(String ticker) {
    for (final purchase in StorageService.purchases.reversed) {
      if (purchase.ticker.toUpperCase() == ticker.toUpperCase() && purchase.name.trim().isNotEmpty) {
        return purchase.name.trim();
      }
    }
    return ticker;
  }

  String _favoriteName(String ticker) {
    final holdingName = _holdingName(ticker);
    if (holdingName != ticker) return holdingName;

    for (final income in StorageService.incomes.reversed) {
      if (income.ticker.toUpperCase() == ticker.toUpperCase() && income.name.trim().isNotEmpty) {
        return income.name.trim();
      }
    }

    final onlineName = OnlinePriceService.get(ticker)?.shortName.trim();
    return onlineName == null || onlineName.isEmpty ? ticker : onlineName;
  }

  Widget _holdingTile(BuildContext context, String ticker, HoldingInfo h, double weight) {
    final pnlColor = AppColors.pnl(h.pnlRub);
    final density = AppearanceService.density.scale;
    return AppCard(
      padding: EdgeInsets.fromLTRB(12, 12 * density, 12, 12 * density),
      onTap: () => Navigator.push(
        context,
        AppPageRoute(builder: (_) => TickerDetailScreen(ticker: ticker)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Hero(tag: 'logo-$ticker', child: TickerAvatar(ticker: ticker, size: 42)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _holdingName(ticker),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (h.hasManualPrice) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.edit_rounded, size: 11, color: context.dim),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    MarqueeText(
                      _holdingSubtitle(ticker, h, weight),
                      style: TextStyle(fontSize: 11.5, color: context.dim, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  HiddenAmount.forText(
                    Fmt.money(h.valueRub),
                    fontSize: 14.5,
                    child: Text(
                      Fmt.money(h.valueRub),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 3),
                  TagChip(text: Fmt.pct(h.pnlPct), color: pnlColor, fontSize: 10.5),
                ],
              ),
              ValueListenableBuilder<int>(
                valueListenable: FavoritesService.version,
                builder: (context, _, __) {
                  final isFav = FavoritesService.isFavorite(ticker);
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 20,
                      color: isFav ? AppColors.gold : context.dim,
                    ),
                    onPressed: () => FavoritesService.toggle(ticker),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MiniProgressBar(value: weight, color: context.accent)),
              const SizedBox(width: 8),
              Text(
                '${(weight * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
