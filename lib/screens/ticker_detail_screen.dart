import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/income.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import '../services/currency_service.dart';
import '../services/favorites_service.dart';
import '../services/logo_service.dart';
import '../services/manual_price_service.dart';
import '../services/moex_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_settings_service.dart';
import '../services/plan_apply_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/sector_service.dart';
import '../services/storage_service.dart';
import '../services/tax_service.dart';
import '../widgets/ticker_avatar.dart';

/// Карточка одной бумаги: сводка позиции, история цены, льгота ЛДВ,
/// полученные выплаты и все сделки — плюс быстрые кнопки «купить/продать».
class TickerDetailScreen extends StatefulWidget {
  final String ticker;
  const TickerDetailScreen({super.key, required this.ticker});

  @override
  State<TickerDetailScreen> createState() => _TickerDetailScreenState();
}

class _TickerDetailScreenState extends State<TickerDetailScreen> {
  /// История цены с биржи. Грузится один раз при открытии карточки и работает
  /// для любой бумаги, даже если ты её никогда не покупал.
  List<MapEntry<DateTime, double>> _exchangeHistory = const [];
  bool _exchangeLoading = false;
  bool _loadingOlderHistory = false;
  String? _exchangeError;
  ChartRange _range = ChartRange.year;

  /// Дивиденды или купоны с биржи и состояние их разворачивания.
  List<MoexPayout> _payouts = const [];
  bool _payoutsLoading = false;
  bool _upcomingExpanded = false;
  bool _pastExpanded = false;

  bool get _intraday => _range == ChartRange.day || _range == ChartRange.week;

  /// Окно просмотра внутри загруженного отрезка: дробный сдвиг даёт плавное
  /// листание без повторных запросов к бирже.
  double _viewStart = 0;
  int _viewSize = 0;

  void _panChart(double deltaPoints) {
    final maxStart = (_exchangeHistory.length - _viewSize).toDouble();
    if (maxStart <= 0) return;
    setState(() => _viewStart = (_viewStart + deltaPoints).clamp(0.0, maxStart).toDouble());
  }

  List<MapEntry<DateTime, double>> _scaleBondHistory(
    List<MapEntry<DateTime, double>> points,
  ) {
    final quote = MoexSyncService.marketSnapshot.value[widget.ticker.toUpperCase()];
    final face = quote?.faceValue;
    return quote?.isBond == true && face != null && face > 0
        ? points.map((e) => MapEntry(e.key, e.value * face / 100)).toList()
        : points;
  }

  Future<void> _loadOlderExchangeHistory() async {
    final span = _range.span;
    if (_loadingOlderHistory || span == null || _exchangeHistory.isEmpty || _viewStart > _viewSize * 0.25) return;
    _loadingOlderHistory = true;
    final first = _exchangeHistory.first.key;
    final quote = MoexSyncService.marketSnapshot.value[widget.ticker.toUpperCase()];
    try {
      final raw = await MoexService.fetchSecurityCandles(
        widget.ticker,
        from: first.subtract(span * _range.bufferFactor),
        till: first.subtract(const Duration(seconds: 1)),
        interval: _range.interval,
        maxRows: _range.maxRows,
        market: quote?.market,
      );
      if (!mounted || raw.isEmpty) return;
      final older = _scaleBondHistory(raw);
      final existing = _exchangeHistory.map((e) => e.key).toSet();
      final added = older.where((e) => !existing.contains(e.key)).toList();
      if (added.isEmpty) return;
      setState(() {
        _exchangeHistory = [...added, ..._exchangeHistory]
          ..sort((a, b) => a.key.compareTo(b.key));
        _viewStart += added.length;
      });
    } catch (_) {
      // Оставляем уже загруженный участок и повторяем при следующем жесте.
    } finally {
      _loadingOlderHistory = false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (OnlineSettingsService.enabled) {
      _loadExchangeHistory();
      _loadPayouts();
    }
    OnlineSettingsService.version.addListener(_onOnlineChanged);
  }

  /// Загрузку могли включить, пока карточка уже открыта: подтягиваем данные
  /// сами, не заставляя нажимать обновление.
  void _onOnlineChanged() {
    if (!mounted || !OnlineSettingsService.enabled) return;
    if (_exchangeHistory.isEmpty && !_exchangeLoading) _loadExchangeHistory();
    if (_payouts.isEmpty && !_payoutsLoading) _loadPayouts();
  }

  @override
  void dispose() {
    OnlineSettingsService.version.removeListener(_onOnlineChanged);
    super.dispose();
  }

  Future<void> _loadExchangeHistory() async {
    setState(() {
      _exchangeLoading = true;
      _exchangeError = null;
    });
    final quote = MoexSyncService.marketSnapshot.value[widget.ticker.toUpperCase()];
    try {
      final points = await MoexService.fetchSecurityCandles(
        widget.ticker,
        from: _range.bufferFrom,
        interval: _range.interval,
        maxRows: _range.maxRows,
        market: quote?.market,
      );
      // Облигации на бирже котируются в процентах от номинала — приводим к
      // рублям, иначе график покажет 110 вместо 1105 и не сойдётся с ценой
      // в карточке.
      final scaled = _scaleBondHistory(points);

      if (!mounted) return;
      setState(() {
        _exchangeHistory = scaled;
        _exchangeError =
            scaled.isEmpty ? 'Нет данных за выбранный период' : null;
        final window = chartWindowForDates(scaled.map((e) => e.key).toList(), _range);
        _viewSize = window.size;
        _viewStart = window.start.toDouble();
        _exchangeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exchangeError = 'Нет связи с MOEX. Попробуйте позже';
        _exchangeLoading = false;
      });
    }
  }

  /// Дивиденды по акции или купоны и амортизация по облигации — прямо с
  /// биржи, независимо от того, покупал ты бумагу или нет.
  /// Облигация ли это — по данным биржи. Влияет на подписи: у акции не бывает
  /// купонов, у облигации — дивидендов.
  bool get _isBond =>
      MoexSyncService.marketSnapshot.value[widget.ticker.toUpperCase()]?.isBond ?? false;

  Future<void> _loadPayouts() async {
    setState(() => _payoutsLoading = true);
    final quote = MoexSyncService.marketSnapshot.value[widget.ticker.toUpperCase()];
    try {
      final list = await MoexService.fetchPayouts(widget.ticker, isBond: quote?.isBond ?? false);
      if (!mounted) return;
      setState(() {
        _payouts = list;
        _payoutsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _payoutsLoading = false);
    }
  }

  Widget _payoutsCard() {
    if (!OnlineSettingsService.enabled) return const SizedBox.shrink();
    if (_payoutsLoading && _payouts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_payouts.isEmpty) return const SizedBox.shrink();

    final upcoming = _payouts.where((p) => p.isFuture).toList().reversed.toList();
    final past = _payouts.where((p) => !p.isFuture).toList();
    final isBond = _payouts.first.kind != 'Дивиденд';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isBond ? 'Купоны' : 'Дивиденды',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            isBond
                ? 'Полный график выплат по данным биржи, на одну облигацию'
                : 'По данным биржи, на одну акцию',
            style: TextStyle(fontSize: 11, color: context.dim),
          ),
          const SizedBox(height: 12),
          if (upcoming.isNotEmpty)
            _payoutGroup(
              title: 'Ожидаются',
              items: upcoming,
              upcoming: true,
              showTotal: isBond,
              expanded: _upcomingExpanded,
              // Ближайшие выплаты интереснее всего, поэтому пара первых видна
              // сразу, а остальной график прячется.
              preview: 3,
              onToggle: () => setState(() => _upcomingExpanded = !_upcomingExpanded),
            ),
          if (past.isNotEmpty)
            _payoutGroup(
              title: 'Выплачено',
              items: past,
              upcoming: false,
              showTotal: isBond,
              expanded: _pastExpanded,
              preview: 3,
              onToggle: () => setState(() => _pastExpanded = !_pastExpanded),
            ),
        ],
      ),
    );
  }

  /// Группа выплат: несколько строк видно всегда, полный список
  /// разворачивается по нажатию. У длинных облигаций купонов бывает под сотню,
  /// и вываливать их сразу бессмысленно.
  Widget _payoutGroup({
    required String title,
    required List<MoexPayout> items,
    required bool upcoming,
    required bool expanded,
    required int preview,
    required VoidCallback onToggle,
    // Сумма выплат на одну акцию смысла не имеет — её показываем только для
    // облигаций, где важно, сколько всего принесёт выпуск.
    bool showTotal = false,
  }) {
    final visible = expanded ? items : items.take(preview).toList();
    final hidden = items.length - visible.length;
    final total = items.fold(0.0, (sum, p) => sum + p.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              // У акций счётчик и сумма на одну бумагу ничего не говорят —
              // показываем их только по облигациям, где важен весь график.
              if (showTotal) ...[
                const SizedBox(width: 6),
                Text(
                  '${items.length} · ${Fmt.price(total)}',
                  style: TextStyle(fontSize: 10.5, color: context.dim),
                ),
              ],
            ],
          ),
        ),
        ...visible.map((p) => _payoutRow(p, upcoming: upcoming)),
        if (hidden > 0 || expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              onTap: onToggle,
              child: Row(
                children: [
                  Text(
                    expanded ? 'Свернуть' : 'Показать все ($hidden ещё)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.accent),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 17,
                    color: context.accent,
                  ),
                ],
              ),
            ),
          )
        else
          const SizedBox(height: 10),
      ],
    );
  }

  Widget _payoutRow(MoexPayout p, {required bool upcoming}) {
    final color = upcoming ? context.accent : AppColors.positive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.8)),
          ),
          SizedBox(
            width: 82,
            child: Text(Fmt.date(p.date), style: TextStyle(fontSize: 11.5, color: context.dim)),
          ),
          Expanded(
            child: Text(
              p.extra ?? p.kind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.dim),
            ),
          ),
          Text(
            Fmt.price(p.amount, currency: p.currency == 'SUR' ? '₽' : p.currency),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  /// Сделки, привязанные к точкам графика. Сопоставляем строго по дате:
  /// цена в сделке может отличаться от биржевого закрытия, и искать по ней
  /// было бы неверно.
  ({List<SparkMarker> markers, Map<int, String> labels}) _tradeMarkers(
    List<MapEntry<DateTime, double>> points,
  ) {
    final markers = <SparkMarker>[];
    final labels = <int, String>{};
    if (points.isEmpty) return (markers: markers, labels: labels);

    final trades = StorageService.purchases.where((p) => p.ticker == widget.ticker).toList();
    if (trades.isEmpty) return (markers: markers, labels: labels);
    final assetType = trades.first.type;

    // Одна точка графика может покрывать несколько дней (неделя, месяц) —
    // ищем ближайшую точку не позже даты сделки.
    int indexFor(DateTime date) {
      int best = -1;
      for (int i = 0; i < points.length; i++) {
        if (!points[i].key.isAfter(date)) {
          best = i;
        } else {
          break;
        }
      }
      return best;
    }

    // Несколько сделок в одной точке складываем: количество суммируем,
    // цену показываем среднюю по объёму.
    final grouped = <int, ({double buyQty, double buySum, double sellQty, double sellSum, DateTime date})>{};
    for (final t in trades) {
      final i = indexFor(t.date);
      if (i < 0) continue;
      final g = grouped[i] ??
          (buyQty: 0.0, buySum: 0.0, sellQty: 0.0, sellSum: 0.0, date: t.date);
      grouped[i] = (
        buyQty: g.buyQty + (t.isSell ? 0 : t.quantity),
        buySum: g.buySum + (t.isSell ? 0 : t.quantity * t.pricePerUnit),
        sellQty: g.sellQty + (t.isSell ? t.quantity : 0),
        sellSum: g.sellSum + (t.isSell ? t.quantity * t.pricePerUnit : 0),
        date: t.date.isBefore(g.date) ? t.date : g.date,
      );
    }

    grouped.forEach((i, g) {
      final hasBuy = g.buyQty > 0;
      final hasSell = g.sellQty > 0;
      markers.add(SparkMarker(
        index: i,
        color: hasSell && !hasBuy ? AppColors.negative : AppColors.positive,
      ));
      // Каждая строка отдельно: окно на графике рисует их в столбик.
      labels[i] = [
        Fmt.date(g.date),
        if (hasBuy) 'куплено ${Fmt.qty(g.buyQty)} шт',
        if (hasBuy) 'по ${Fmt.price(g.buySum / g.buyQty, type: assetType)}',
        if (hasSell) 'продано ${Fmt.qty(g.sellQty)} шт',
        if (hasSell) 'по ${Fmt.price(g.sellSum / g.sellQty, type: assetType)}',
      ].join('\n');
    });

    return (markers: markers, labels: labels);
  }

  @override
  Widget build(BuildContext context) {
    final ticker = widget.ticker;
    final purchases = StorageService.purchases.where((p) => p.ticker == ticker).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final assetType = purchases.isNotEmpty
        ? purchases.first.type
        : (MoexSyncService.marketSnapshot.value[ticker]?.isBond == true
            ? AssetType.bond
            : AssetType.stock);
    final holding = AnalyticsService.currentHoldings()[ticker];
    // Тот же расчёт, что и на главной: по истории выплат самой бумаги, а не
    // по тому, что успел получить владелец.
    final forecast = holding != null ? PayoutForecastService.forecastForTicker(ticker) : null;
    final forecastYield = (forecast != null && forecast.rub > 0 && holding != null && holding.valueRub > 0)
        ? forecast.rub / holding.valueRub * 100
        : 0.0;
    final incomes = StorageService.incomes.where((i) => i.ticker == ticker).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final incomeTotal = incomes.fold<double>(0, (s, i) => s + i.amountNet);
    final openLots = (holding != null && TaxService.enabled)
        ? TaxService.openLotsForTicker(ticker)
        : <OpenLotInfo>[];
    final taxBreakdown = TaxService.enabled ? TaxService.saleTaxBreakdown() : <String, SaleTaxResult>{};
    final name = purchases.isNotEmpty ? purchases.first.name : ticker;
    final sector = SectorService.sectorFor(ticker);

    final pnlColor = AppColors.pnl(holding?.pnlRub ?? 0);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          _appBar(context, ticker, name, sector, holding, pnlColor),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (holding != null) ...[
                  FadeSlideIn(
                    child: IntrinsicHeight(
                        child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'В портфеле',
                            icon: Icons.inventory_2_outlined,
                            text: '${Fmt.qty(holding.qty)} шт',
                            color: AppColors.info,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatTile(
                            label: 'Средняя цена',
                            icon: Icons.straighten_rounded,
                            text: Fmt.price(holding.avgCost, type: assetType),
                            color: AppColors.violet,
                          ),
                        ),
                      ],
                    ),
                      ),
                  ),
                  const SizedBox(height: 10),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 60),
                    child: IntrinsicHeight(
                        child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: StatTile(
                            label: holding.hasManualPrice ? 'Текущая цена' : 'Последняя цена',
                            icon: Icons.edit_rounded,
                            text: Fmt.price(holding.displayPrice, type: assetType),
                            hint: 'нажмите, чтобы уточнить',
                            color: context.accent,
                            onTap: () => _showSetPriceDialog(context, ticker, holding),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatTile(
                            label: 'Прибыль / убыток',
                            icon: holding.pnlRub >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                            text: Fmt.signedMoney(holding.pnlRub),
                            hint: Fmt.pct(holding.pnlPct),
                            color: pnlColor,
                          ),
                        ),
                      ],
                    ),
                      ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (openLots.isNotEmpty) ...[
                  _ldvCard(openLots),
                  const SizedBox(height: 14),
                ],

                _bondCard(),
                _exchangeHistoryCard(),

                const SizedBox(height: 14),
                _payoutsCard(),

                if (incomes.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SectionTitle(
                    title: _isBond ? 'Купоны' : 'Дивиденды',
                    subtitle: '${incomes.length} ${Fmt.payouts(incomes.length)}',
                    trailing: Text(
                      Fmt.signedMoney(incomeTotal),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.positive),
                    ),
                  ),
                  if (forecast != null && forecast.rub > 0) ...[
                    InfoBanner(
                      icon: Icons.auto_graph_rounded,
                      color: AppColors.violet,
                      text: 'Ожидаемый доход за 12 мес со следующего месяца: ~${Fmt.money(forecast.rub)} '
                          '(доходность ~${forecastYield.toStringAsFixed(1)}%) — ${forecast.source}. Не гарантия.',
                    ),
                    const SizedBox(height: 10),
                  ],
                  ...incomes.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.all(13),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: AppColors.positive.withOpacity(0.14),
                                ),
                                child: Icon(
                                  i.type == IncomeType.dividend
                                      ? Icons.trending_up_rounded
                                      : Icons.receipt_long_rounded,
                                  size: 18,
                                  color: AppColors.positive,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i.type == IncomeType.dividend ? 'Дивиденд' : 'Купон',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      Fmt.date(i.date),
                                      style: TextStyle(fontSize: 11.5, color: context.dim),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '+${Fmt.price(i.amountNet, currency: i.currency == 'RUB' ? '₽' : i.currency)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: AppColors.positive,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],

                const SizedBox(height: 22),
                SectionTitle(
                  title: 'Сделки по бумаге',
                  subtitle: '${purchases.length} ${Fmt.deals(purchases.length)}',
                ),
                if (purchases.isEmpty)
                  Text('Сделок по этой бумаге пока нет', style: TextStyle(fontSize: 13, color: context.dim))
                else
                  ...purchases.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _tradeRow(p, p.isSell ? taxBreakdown[p.id] : null),
                      )),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'Продать',
                  icon: Icons.arrow_upward_rounded,
                  colors: const [Color(0xFFE23A5B), Color(0xFFFF6B85)],
                  onPressed: () => _quickTradeSheet(context, ticker, name, true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Купить',
                  icon: Icons.arrow_downward_rounded,
                  colors: const [Color(0xFF0FA97E), Color(0xFF16D796)],
                  onPressed: () => _quickTradeSheet(context, ticker, name, false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Шапка-«обложка»: аватарка бумаги, название, сектор и крупная текущая
  /// цена. При прокрутке сжимается в обычный компактный заголовок.
  Widget _appBar(
    BuildContext context,
    String ticker,
    String name,
    String sector,
    HoldingInfo? holding,
    Color pnlColor,
  ) {
    final accent = context.accent;
    final isFav = FavoritesService.isFavorite(ticker);

    return SliverAppBar(
      pinned: true,
      expandedHeight: 244,
      backgroundColor: context.isDark ? AppColors.darkBg : AppColors.lightBg,
      surfaceTintColor: Colors.transparent,
      title: Text(ticker, style: const TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
          icon: Icon(
            isFav ? Icons.star_rounded : Icons.star_border_rounded,
            color: isFav ? AppColors.gold : null,
          ),
          onPressed: () async {
            await FavoritesService.toggle(ticker);
            if (mounted) setState(() {});
          },
        ),
        IconButton(
          tooltip: 'Иконка бумаги',
          icon: const Icon(Icons.image_outlined),
          onPressed: () => _showLogoOptions(context, ticker),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withOpacity(context.isDark ? 0.34 : 0.20),
                    (context.isDark ? AppColors.darkBg : AppColors.lightBg).withOpacity(0.1),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickLogo(context, ticker),
                          onLongPress: () => _showLogoOptions(context, ticker),
                          child: Hero(tag: 'logo-$ticker', child: TickerAvatar(ticker: ticker, size: 56)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              // Тап по сектору открывает выбор — привязка
                              // бумаги живёт здесь, а не в общем списке настроек.
                              Pressable(
                                onTap: () => _sectorSheet(ticker),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TagChip(text: sector, color: accent, fontSize: 10),
                                    const SizedBox(width: 4),
                                    Icon(Icons.edit_rounded, size: 12, color: context.dim),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (holding != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: RollingNumber(
                              value: holding.valueRub,
                              formatter: (v) => Fmt.money(v),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1),
                            ),
                          ),
                          const SizedBox(height: 7),
                          SizedBox(
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: TagChip(
                                  text: '${Fmt.pct(holding.pnlPct)} · ${Fmt.signedMoney(holding.pnlRub)}',
                                  color: pnlColor,
                                  icon: holding.pnlRub >= 0
                                      ? Icons.trending_up_rounded
                                      : Icons.trending_down_rounded,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Бумаги нет в портфеле',
                        style: TextStyle(fontSize: 13, color: context.dim, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// График цены по датам. Точки берутся из истории ручных цен — туда же
  /// автоматически попадает цена каждой сделки, так что даже без ручного
  /// ввода график показывает реальную динамику по сделкам.

  /// Сектор бумаги правится прямо здесь: искать нужный тикер в общем списке
  /// настроек было неудобно.
  void _sectorSheet(String ticker) {
    showAppSheet(
      context: context,
      builder: (ctx) {
        final sectors = SectorService.allAvailableSectors;
        final current = SectorService.sectorFor(ticker);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Сектор',
                subtitle: 'Влияет на диаграмму распределения',
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(height: 14),
              for (final sector in ['Без сектора', ...sectors])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    onTap: () async {
                      await SectorService.assignSector(
                        ticker,
                        sector == 'Без сектора' ? null : sector,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sector,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: sector == current ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (sector == current)
                          Icon(Icons.check_rounded, size: 19, color: context.accent),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Новые секторы создаются в разделе «Настройки → Портфель».',
                style: TextStyle(fontSize: 11.5, color: context.dim),
              ),
            ],
          ),
        );
      },
    );
  }



  /// Параметры облигации: когда гасится и какой номинал. У части выпусков
  /// номинал в валюте, хотя торгуется бумага за рубли, — показываем оба
  /// значения.
  /// «через 2 года» или «через 45 дней» — до года считаем днями, дальше
  /// годами: точность в днях на длинном горизонте только мешает.
  String _timeLeft(int days) {
    if (days < 365) return 'через $days ${Fmt.plural(days, "день", "дня", "дней")}';
    final years = days ~/ 365;
    return 'через $years ${Fmt.plural(years, "год", "года", "лет")}';
  }

  Widget _bondCard() {
    final quote = MoexSyncService.marketSnapshot.value[widget.ticker.toUpperCase()];
    if (quote == null || !quote.isBond) return const SizedBox.shrink();

    final face = quote.faceValue ?? 0;
    final currency = quote.faceUnit.toUpperCase() == 'SUR' ? 'RUB' : quote.faceUnit.toUpperCase();
    final faceRub = CurrencyService.toRub(face, currency);
    final matDate = quote.matDate;
    final daysLeft = matDate?.difference(DateTime.now()).inDays;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Погашение', style: TextStyle(fontSize: 11, color: context.dim)),
                  const SizedBox(height: 3),
                  Text(
                    matDate == null ? 'бессрочная' : Fmt.date(matDate),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                  if (daysLeft != null && daysLeft > 0)
                    Text(_timeLeft(daysLeft), style: TextStyle(fontSize: 10.5, color: context.dim)),
                ],
              ),
            ),
            Container(width: 1, height: 40, color: context.hairline),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Номинал', style: TextStyle(fontSize: 11, color: context.dim)),
                  const SizedBox(height: 3),
                  Text(
                    Fmt.price(
                      face,
                      currency: currency == 'RUB' ? '₽' : currency,
                      isBond: true,
                    ),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                  if (currency != 'RUB')
                    Text(
                      '≈ ${Fmt.money(faceRub)}',
                      style: TextStyle(fontSize: 10.5, color: context.dim),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exchangeHistoryCard() {
    final all = _exchangeHistory;
    final assetType = _assetTypeFor(widget.ticker);
    final size = _viewSize == 0 ? all.length : _viewSize;
    final int startIndex = _viewStart.round().clamp(0, all.isEmpty ? 0 : all.length - 1).toInt();
    final int endIndex = math.min<int>(all.length, startIndex + size);
    final points = all.isEmpty ? all : all.sublist(startIndex, endIndex);
    final values = all.map((e) => e.value).toList();
    final visibleValues = points.map((e) => e.value).toList();
    final change = visibleValues.length > 1 ? visibleValues.last - visibleValues.first : 0.0;
    final changePct = visibleValues.length > 1 && visibleValues.first != 0
        ? change / visibleValues.first * 100
        : 0.0;
    final online = OnlineSettingsService.enabled;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Цена на бирже',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      visibleValues.length > 1
                          ? '${Fmt.date(points.first.key)} — ${Fmt.date(points.last.key)}'
                          : _statusText(),
                      style: TextStyle(fontSize: 11, color: context.dim),
                    ),
                  ],
                ),
              ),
              if (visibleValues.length > 1)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: TagChip(
                      text: '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} · ${Fmt.pct(changePct)}',
                      color: AppColors.pnl(change),
                    ),
                  ),
                )
              else if (online && !_exchangeLoading)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  tooltip: 'Загрузить заново',
                  onPressed: _loadExchangeHistory,
                ),
            ],
          ),
          const SizedBox(height: 10),
          PillTabs<ChartRange>(
            values: ChartRange.values,
            selected: _range,
            labelOf: (r) => r.label,
            onChanged: (r) {
              setState(() => _range = r);
              _loadExchangeHistory();
            },
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: _exchangeLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : values.length < 2
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _emptyText(),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
                          ),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final trades = _tradeMarkers(all);
                          return Sparkline(
                            values: values,
                            windowSize: _viewSize == 0 ? null : _viewSize,
                            windowStart: _viewStart,
                            color: AppColors.pnl(change),
                            height: 150,
                            markers: trades.markers,
                            markerLabel: (i) => trades.labels[i] ?? '',
                            onPan: _viewSize < all.length ? _panChart : null,
                            onPanEnd: _loadOlderExchangeHistory,
                            dateLabel: (i) => Fmt.dateTime(all[i].key, withTime: _intraday),
                            priceLabel: (v) => Fmt.price(v, type: assetType),
                            tooltipBuilder: (i, v) =>
                                '${Fmt.dateTime(all[i].key, withTime: _intraday)}\n${Fmt.price(v, type: assetType)}',
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _statusText() {
    if (_exchangeLoading) return 'Загружаю…';
    if (!OnlineSettingsService.enabled) return 'Загрузка с биржи выключена';
    if (_exchangeError != null) return 'Не загрузилось';
    return 'Нет данных за этот период';
  }

  String _emptyText() {
    if (!OnlineSettingsService.enabled) {
      return 'Включите загрузку с биржи в разделе «Настройки → Биржа и котировки», '
          'и здесь появится история цены.';
    }
    if (_exchangeError != null) {
      return '$_exchangeError\nНажмите обновление в углу карточки.';
    }
    return 'Биржа не отдала историю за «${_range.label}». Попробуйте другой период — '
        'по редким бумагам данных за короткий срок может не быть.';
  }


  Widget _ldvCard(List<OpenLotInfo> lots) {
    final waiting = lots.where((l) => !l.ldvActive).toList();
    if (waiting.isEmpty) {
      return const InfoBanner(
        icon: Icons.verified_rounded,
        color: AppColors.positive,
        text: 'Льгота на долгосрочное владение (ЛДВ) действует на всю позицию — '
            'прибыль с продажи не облагается налогом',
      );
    }
    waiting.sort((a, b) => a.daysUntilLdv.compareTo(b.daysUntilLdv));
    final nearest = waiting.first;
    return InfoBanner(
      icon: Icons.hourglass_bottom_rounded,
      color: AppColors.warning,
      text: 'До льготы ЛДВ по части позиции (${Fmt.qty(nearest.qty)} шт) '
          'осталось ${nearest.daysUntilLdv} дн.',
    );
  }

  Widget _tradeRow(Purchase p, SaleTaxResult? tax) {
    final color = p.isSell ? AppColors.negative : AppColors.positive;
    return AppCard(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: color.withOpacity(0.14),
            ),
            child: Icon(
              p.isSell ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.isSell ? 'Продажа' : 'Покупка'} · ${Fmt.qty(p.quantity)} шт × ${Fmt.price(p.pricePerUnit, type: p.type)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(Fmt.date(p.date), style: TextStyle(fontSize: 11.5, color: context.dim)),
                if (tax != null && _taxLabel(tax) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: TagChip(text: _taxLabel(tax)!, color: AppColors.warning, fontSize: 9.5),
                  ),
              ],
            ),
          ),
          Text(
            '${p.isSell ? '+' : '−'}${Fmt.group(p.settlementAmount)} ${p.currency == 'RUB' ? '₽' : p.currency}',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: p.isSell ? color : null),
          ),
        ],
      ),
    );
  }

  String? _taxLabel(SaleTaxResult r) {
    if (r.realizedGainRub <= 0) return 'без налога (убыток)';
    if (r.taxableGainRub <= 0 && r.hasLdvPortion) return 'без налога (ЛДВ)';
    if (r.taxRub > 0) return 'налог ~${Fmt.money(r.taxRub)}';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Действия
  // ---------------------------------------------------------------------------

  /// Быстрая сделка прямо со страницы бумаги: тикер, тип, валюта и сектор
  /// берутся из последней сделки, чтобы не вводить их заново.
  Future<void> _quickTradeSheet(BuildContext context, String ticker, String name, bool isSell) async {
    final prior = StorageService.purchases.where((p) => p.ticker == ticker).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final type = prior.isNotEmpty ? prior.first.type : AssetType.stock;
    final currency = prior.isNotEmpty ? prior.first.currency : 'RUB';
    final sector = prior.isNotEmpty ? prior.first.sector : '';

    final quote = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()];
    final lotSize = quote?.lotSize ?? 1;
    final qtyCtrl = TextEditingController(text: '1');

    // Подставляем актуальную цену: сначала биржевая, потом ручная, потом цена
    // последней сделки. Поле остаётся обычным — своё значение можно вписать.
    final onlinePrice = quote?.price ?? AnalyticsService.priceFor(ticker);
    final knownPrice = onlinePrice ??
        ManualPriceService.get(ticker) ??
        (prior.isNotEmpty ? prior.first.pricePerUnit : null);
    final priceSource = onlinePrice != null
        ? 'цена с биржи'
        : ManualPriceService.get(ticker) != null
            ? 'цена, указанная вручную'
            : prior.isNotEmpty
                ? 'цена последней сделки'
                : null;
    final priceCtrl = TextEditingController(
      // Без разрядных пробелов и с точкой — значение должно оставаться
      // редактируемым числом, а не подписью.
      text: knownPrice != null ? (knownPrice * lotSize).toStringAsFixed(2) : '',
    );
    final feeCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();
    // Галка появляется только если по бумаге есть план на этот месяц.
    final hasPlan = !isSell && PlanApplyService.hasPlanThisMonth(ticker);
    bool applyToPlan = hasPlan;

    await showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
          final lots = int.tryParse(qtyCtrl.text) ?? 0;
          final qty = lots * lotSize.toDouble();
          final totalPrice = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
          final fee = double.tryParse(feeCtrl.text.replaceAll(',', '.')) ?? 0;
          final sum = totalPrice + (isSell ? -fee : fee);

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: isSell ? 'Продать $ticker' : 'Купить $ticker',
                  subtitle: name,
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Уменьшить на один лот',
                      icon: const Icon(Icons.remove_rounded),
                      onPressed: () => setSheetState(() {
                        final oldLots = int.tryParse(qtyCtrl.text) ?? 1;
                        final next = (oldLots - 1).clamp(1, 1000000);
                        if (totalPrice > 0 && oldLots > 0) {
                          priceCtrl.text = (totalPrice / oldLots * next).toStringAsFixed(2);
                        }
                        qtyCtrl.text = '$next';
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
                        autofocus: true,
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Добавить один лот',
                      icon: const Icon(Icons.add_rounded),
                      onPressed: () => setSheetState(() {
                        final oldLots = int.tryParse(qtyCtrl.text) ?? 1;
                        final next = (oldLots + 1).clamp(1, 1000000);
                        if (totalPrice > 0 && oldLots > 0) {
                          priceCtrl.text = (totalPrice / oldLots * next).toStringAsFixed(2);
                        }
                        qtyCtrl.text = '$next';
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
                  label: 'Стоимость всех выбранных бумаг ($currency)',
                  number: true,
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: feeCtrl,
                        label: 'Комиссия',
                        number: true,
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppDateField(
                        value: date,
                        label: 'Дата',
                        lastDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        onPicked: (d) => setSheetState(() => date = d),
                      ),
                    ),
                  ],
                ),
                if (sum > 0) ...[
                  const SizedBox(height: 12),
                  InfoBanner(
                    icon: Icons.calculate_outlined,
                    color: isSell ? AppColors.negative : AppColors.positive,
                    text: isSell
                        ? 'К зачислению примерно ${Fmt.group(sum)} $currency'
                        : 'Списание примерно ${Fmt.group(sum)} $currency',
                  ),
                ],
                if (priceSource != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Подставлена $priceSource — можно изменить',
                    style: TextStyle(fontSize: 11, color: context.dim),
                  ),
                ],
                if (hasPlan) ...[
                  const SizedBox(height: 12),
                  AppCheckRow(
                    value: applyToPlan,
                    title: 'Учитывать в ближайшем плане этого месяца',
                    onChanged: (v) => setSheetState(() => applyToPlan = v),
                  ),
                ],
                const SizedBox(height: 12),
                AppTextField(controller: noteCtrl, label: 'Заметка (необязательно)'),
                const SizedBox(height: 22),
                GradientButton(
                  label: isSell ? 'Записать продажу' : 'Записать покупку',
                  icon: Icons.check_rounded,
                  colors: isSell
                      ? const [Color(0xFFE23A5B), Color(0xFFFF6B85)]
                      : const [Color(0xFF0FA97E), Color(0xFF16D796)],
                  onPressed: () async {
                    final enteredLots = int.tryParse(qtyCtrl.text);
                    final enteredTotal = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
                    if (enteredLots == null || enteredTotal == null || enteredLots <= 0 || enteredTotal <= 0) return;
                    final q = enteredLots * lotSize.toDouble();
                    final pr = enteredTotal / q;
                    final f = double.tryParse(feeCtrl.text.replaceAll(',', '.')) ?? 0;
                    await StorageService.addPurchase(Purchase(
                      id: const Uuid().v4(),
                      date: date,
                      ticker: ticker,
                      name: name,
                      type: type,
                      quantity: q,
                      pricePerUnit: pr,
                      fee: f,
                      currency: currency,
                      sector: sector,
                      isSell: isSell,
                      note: noteCtrl.text.isEmpty ? null : noteCtrl.text,
                    ));
                    // Цена сделки — реальное наблюдение цены на эту дату.
                    await ManualPriceService.setAt(ticker, date, pr);
                    if (applyToPlan && !isSell) {
                      await PlanApplyService.applyToNearestPlanThisMonth(ticker, q, pr);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
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

  Future<void> _pickLogo(BuildContext context, String ticker) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;
    await LogoService.setLogo(ticker, File(picked.path));
    if (mounted) setState(() {});
  }

  Future<void> _showLogoOptions(BuildContext context, String ticker) async {
    final hasLogo = LogoService.getPath(ticker) != null;
    await showAppSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(title: 'Иконка бумаги', subtitle: 'Своя картинка вместо инициалов'),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(hasLogo ? 'Заменить иконку' : 'Загрузить иконку'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickLogo(context, ticker);
                },
              ),
              if (hasLogo)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.negative),
                  title: const Text('Удалить иконку', style: TextStyle(color: AppColors.negative)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await LogoService.removeLogo(ticker);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  AssetType _assetTypeFor(String ticker) {
    for (final purchase in StorageService.purchases.reversed) {
      if (purchase.ticker.toUpperCase() == ticker.toUpperCase()) {
        return purchase.type;
      }
    }
    return MoexSyncService.marketSnapshot.value[ticker.toUpperCase()]?.isBond == true
        ? AssetType.bond
        : AssetType.stock;
  }

  Future<void> _showSetPriceDialog(BuildContext context, String ticker, HoldingInfo holding) async {
    final ctrl = TextEditingController(
      text: holding.hasManualPrice
          ? Fmt.priceInput(holding.displayPrice, type: _assetTypeFor(ticker))
          : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Текущая цена'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Приложение офлайн и не тянет котировки, поэтому по умолчанию берётся цена последней '
              'сделки. Укажите актуальную цену вручную — стоимость портфеля и графики будут пересчитаны.',
              style: TextStyle(color: context.dim, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: ctrl,
              label: 'Цена, ${holding.currency}',
              number: true,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          if (holding.hasManualPrice)
            TextButton(
              onPressed: () async {
                await ManualPriceService.clear(ticker);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Сбросить'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final price = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (price == null || price <= 0) return;
              await ManualPriceService.set(ticker, price);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
