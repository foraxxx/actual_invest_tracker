import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/currency_service.dart';
import '../services/favorites_service.dart';
import '../services/market_filter_service.dart';
import '../services/moex_service.dart';
import '../services/network_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_price_service.dart';
import '../services/online_settings_service.dart';
import '../widgets/ticker_avatar.dart';
import 'home_screen.dart';
import 'ticker_detail_screen.dart';

/// Все бумаги, которые торгуются на Мосбирже, с котировками. Список приходит
/// из того же цикла обновления, что и цены портфеля, поэтому экран не ходит в
/// сеть отдельно — он просто показывает последний снимок рынка.
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  MarketFilter _filter = const MarketFilter();

  /// Что показываем на графике: индекс МосБиржи или курс валюты.
  String _chartKey = 'IMOEX';
  List<MapEntry<DateTime, double>> _chartPoints = const [];
  bool _chartLoading = false;
  String? _chartError;
  ChartRange _range = ChartRange.year;

  /// На дневных свечах время всегда полночь — показывать его незачем.
  bool get _intraday => _range == ChartRange.day || _range == ChartRange.week;

  /// Окно просмотра внутри загруженного отрезка. Дробное — за счёт этого
  /// линия едет плавно, а не прыгает от точки к точке. Данные при листании не
  /// перезапрашиваются: график грузится с запасом вокруг выбранного периода.
  double _viewStart = 0;
  int _viewSize = 0;

  void _panChart(double deltaPoints) {
    final maxStart = (_chartPoints.length - _viewSize).toDouble();
    if (maxStart <= 0) return;
    setState(() => _viewStart = (_viewStart + deltaPoints).clamp(0.0, maxStart).toDouble());
  }

  @override
  void initState() {
    super.initState();
    if (OnlineSettingsService.enabled) _loadChart();
    // Загрузку могли включить уже после открытия экрана — тогда график должен
    // подтянуться сам, без нажатия обновления.
    OnlineSettingsService.version.addListener(_onOnlineChanged);
  }

  void _onOnlineChanged() {
    if (!mounted) return;
    if (OnlineSettingsService.enabled && _chartPoints.isEmpty && !_chartLoading) {
      _loadChart();
    }
  }

  @override
  void dispose() {
    OnlineSettingsService.version.removeListener(_onOnlineChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  /// История для графика грузится отдельно от котировок и редко: она меняется
  /// раз в день, тянуть её каждые десять секунд смысла нет.
  /// Запасная загрузка для режима «День»: сегодня может быть выходной или
  /// торги ещё не начались.
  Future<List<MapEntry<DateTime, double>>> _loadDayFallback() async {
    try {
      if (_chartKey == 'IMOEX') {
        return await MoexService.fetchCandles(
          engine: 'stock',
          market: 'index',
          secId: 'IMOEX',
          from: ChartRange.day.fallbackFrom,
          interval: ChartRange.day.interval,
          maxRows: ChartRange.day.maxRows,
        );
      }
      final secId = MoexService.resolvedCurrencySecIds[_chartKey];
      if (secId == null) return const [];
      return await MoexService.fetchCandles(
        engine: 'currency',
        market: 'selt',
        secId: secId,
        from: ChartRange.day.fallbackFrom,
        interval: ChartRange.day.interval,
        maxRows: ChartRange.day.maxRows,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadChart() async {
    setState(() {
      _chartLoading = true;
      _chartError = null;
    });
    try {
      final List<MapEntry<DateTime, double>> points;
      if (_chartKey == 'IMOEX') {
        points = await MoexService.fetchCandles(
          engine: 'stock',
          market: 'index',
          secId: 'IMOEX',
          from: _range.bufferFrom,
          interval: _range.interval,
          maxRows: _range.maxRows,
        );
      } else {
        // Инструмент валютной пары определяется по ответу биржи; если его ещё
        // не спрашивали, курс подтянет его заодно.
        if (!MoexService.resolvedCurrencySecIds.containsKey(_chartKey)) {
          await MoexService.fetchCurrencyRates();
        }
        final secId = MoexService.resolvedCurrencySecIds[_chartKey];
        points = secId == null
            ? const []
            : await MoexService.fetchCandles(
                engine: 'currency',
                market: 'selt',
                secId: secId,
                from: _range.bufferFrom,
                interval: _range.interval,
                maxRows: _range.maxRows,
              );
      }
      var result = points;
      if (_range == ChartRange.day && result.isEmpty) {
        result = await _loadDayFallback();
      }

      if (!mounted) return;
      setState(() {
        _chartPoints = result;
        _chartError =
            result.isEmpty ? 'Нет данных за выбранный период' : null;
        // Показываем правый край — свежий период, а слева остаётся запас для
        // листания.
        _viewSize = result.isEmpty
            ? 0
            : (result.length / _range.bufferFactor).round().clamp(2, result.length);
        _viewStart = math.max(0, result.length - _viewSize).toDouble();
        _chartLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chartError = 'Нет связи с MOEX. Попробуйте позже';
        _chartLoading = false;
      });
    }
  }

  static String _typeOf(String board) => switch (board) {
        'TQBR' => 'Акция',
        'TQTF' => 'Фонд',
        'TQCB' => 'Облигация',
        'TQOB' => 'ОФЗ',
        _ => 'Бумага',
      };

  static Color _typeColor(String board) => switch (board) {
        'TQBR' => AppColors.info,
        'TQTF' => AppColors.violet,
        'TQCB' => AppColors.gold,
        'TQOB' => AppColors.cyan,
        _ => AppColors.neutral,
      };

  /// Бумага проходит отбор, если удовлетворяет всем включённым условиям.
  /// Пустой фильтр пропускает всё.
  bool _matchesFilter(MoexQuote q, Set<String> owned) {
    if (_filter.kinds.isNotEmpty) {
      final kind = MarketKindX.fromBoard(q.board);
      if (kind == null || !_filter.kinds.contains(kind)) return false;
    }
    if (_filter.ownedOnly && !owned.contains(q.ticker)) return false;
    if (_filter.favoritesOnly && !FavoritesService.isFavorite(q.ticker)) return false;

    switch (_filter.currency) {
      case CurrencyMode.rubles:
        if (q.isForeignCurrency) return false;
      case CurrencyMode.foreign:
        if (!q.isForeignCurrency) return false;
      case CurrencyMode.any:
        break;
    }

    // Условия по купону касаются только облигаций — акции они не отсекают.
    if (q.isBond) {
      switch (_filter.coupon) {
        case CouponMode.fixed:
          if (q.isFloater) return false;
        case CouponMode.floating:
          if (!q.isFloater) return false;
        case CouponMode.any:
          break;
      }
      if (_filter.couponsPerYear.isNotEmpty) {
        final perYear = q.couponsPerYear;
        if (perYear == null || !_filter.couponsPerYear.contains(perYear)) return false;
      }
      final minYield = _filter.minYield;
      if (minYield != null && (q.yieldPct ?? -1) < minYield) return false;
    } else if (_filter.coupon != CouponMode.any ||
        _filter.couponsPerYear.isNotEmpty ||
        _filter.minYield != null) {
      // Спрашивают про купоны — значит, акции не интересуют.
      return false;
    }

    final minTurnover = _filter.minTurnover;
    if (minTurnover != null && q.turnover < minTurnover) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PageTour(
      pageId: 'market',
      steps: const [
        PageTourStep(
          anchor: 'rates',
          title: 'Курсы валют',
          text: 'Приходят с валютного рынка Мосбиржи вместе с котировками. По ним же '
              'пересчитываются твои валютные сделки.',
        ),
        PageTourStep(
          anchor: 'chart',
          title: 'Графики',
          text: 'Индекс Мосбиржи и курсы валют за день, неделю, месяц, год, пять лет или всё '
              'время. Палец по графику показывает дату и значение.',
        ),
        PageTourStep(
          anchor: 'search',
          title: 'Поиск и фильтры',
          text: 'Найди бумагу по тикеру или названию, отфильтруй по типу. Тап по строке '
              'открывает карточку — купить можно прямо оттуда, даже если бумаги у тебя нет.',
        ),
      ],
      child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<int>(
          valueListenable: OnlineSettingsService.version,
          builder: (context, _, __) {
            if (!OnlineSettingsService.enabled) {
              return EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Загрузка с биржи выключена',
                subtitle: 'Включи её в настройках — и здесь появятся все бумаги Мосбиржи с котировками.',
                action: GradientButton(
                  label: 'Открыть настройки',
                  icon: Icons.tune_rounded,
                  expand: false,
                  onPressed: () => HomeScreen.goToSettings(context),
                ),
              );
            }

            return ValueListenableBuilder<Map<String, MoexQuote>>(
              valueListenable: MoexSyncService.marketSnapshot,
              builder: (context, snapshot, __) {
                final quotes = snapshot.isNotEmpty
                    ? snapshot.values.toList()
                    : OnlinePriceService.all.entries
                        .map((e) => MoexQuote(
                              ticker: e.key,
                              shortName: e.value.shortName,
                              price: e.value.price,
                              sourceField: 'cache',
                              board: e.value.board,
                              market: '',
                              fetchedAt: e.value.fetchedAt,
                            ))
                        .toList();

                return _body(quotes);
              },
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _body(List<MoexQuote> quotes) {
    // Именно текущие позиции: полностью проданная бумага в портфеле больше
    // не числится.
    final owned = AnalyticsService.currentHoldings().keys.toSet();
    final q = _query.trim().toUpperCase();

    final list = quotes.where((e) {
      if (!_matchesFilter(e, owned)) return false;
      if (q.isEmpty) return true;
      return e.ticker.toUpperCase().contains(q) || e.shortName.toUpperCase().contains(q);
    }).toList();

    list.sort(switch (_filter.sort) {
      MarketSort.turnoverDesc => (a, b) => b.turnover.compareTo(a.turnover),
      MarketSort.yieldDesc => (a, b) => (b.yieldPct ?? -1).compareTo(a.yieldPct ?? -1),
      MarketSort.name => (a, b) => a.ticker.compareTo(b.ticker),
      MarketSort.priceDesc => (a, b) => b.price.compareTo(a.price),
      MarketSort.priceAsc => (a, b) => a.price.compareTo(b.price),
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Биржа', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 2),
                    ValueListenableBuilder<bool>(
                      valueListenable: MoexSyncService.refreshing,
                      builder: (context, refreshing, _) {
                        final last = OnlineSettingsService.lastSyncAt;
                        return Row(
                          children: [
                            if (refreshing) ...[
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(strokeWidth: 1.6, color: context.accent),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              refreshing
                                  ? 'Обновляю…'
                                  : last == null
                                      ? '${quotes.length} бумаг'
                                      : '${quotes.length} бумаг · '
                                          '${last.hour.toString().padLeft(2, '0')}:'
                                          '${last.minute.toString().padLeft(2, '0')}:'
                                          '${last.second.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 12, color: context.dim),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Обновить сейчас',
                onPressed: () => MoexSyncService.instance.refreshNow(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: kListBottomPadding),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: [
              _vpnBanner(),
              TourSpot(id: 'rates', child: _ratesCard()),
              TourSpot(id: 'chart', child: _chartCard()),
              const SizedBox(height: 6),
              _listHeader(list.length),
              for (int i = 0; i < list.length; i++)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, i == list.length - 1 ? 0 : 8),
                  child: _row(list[i], owned.contains(list[i].ticker)),
                ),
              if (list.isEmpty)
                EmptyState(
                  icon: quotes.isEmpty ? Icons.cloud_sync_outlined : Icons.search_off_rounded,
                  title: quotes.isEmpty ? 'Жду первую загрузку' : 'Ничего не нашлось',
                  subtitle: quotes.isEmpty
                      ? 'Котировки подтянутся через несколько секунд после запуска.'
                      : 'Попробуй другой запрос или сними фильтр.',
                ),
            ],
          ),
        ),
      ],
    );
  }


  /// Плашка появляется, только если загрузка сорвалась. Частая причина — VPN:
  /// Мосбиржа ограничивает доступ из-за рубежа.
  Widget _vpnBanner() {
    return ValueListenableBuilder<int>(
      valueListenable: OnlineSettingsService.version,
      builder: (context, _, __) {
        final error = OnlineSettingsService.lastError;
        if (error == null) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: NetworkService.vpnDetected,
          builder: (context, vpn, __) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: InfoBanner(
              icon: vpn ? Icons.vpn_key_off_rounded : Icons.cloud_off_rounded,
              color: AppColors.warning,
              text: vpn
                  ? 'Похоже, включён VPN — из-за него запросы к бирже не проходят. '
                      'Мосбиржа ограничивает доступ из-за рубежа, так что котировки, курсы и '
                      'графики не загрузятся, пока VPN активен.'
                  : 'Данные с биржи не загрузились: $error\n'
                      'Частая причина — включённый VPN: Мосбиржа ограничивает доступ '
                      'из-за рубежа. Если он включён, попробуй выключить.',
            ),
          ),
        );
      },
    );
  }

  Widget _ratesCard() {
    const visibleCurrencies = ['USD', 'EUR', 'CNY'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: ValueListenableBuilder<int>(
        valueListenable: CurrencyService.version,
        builder: (context, _, __) => ValueListenableBuilder<Map<String, double>>(
          valueListenable: MoexSyncService.currencyRates,
          builder: (context, online, __) => AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                for (final c in visibleCurrencies) ...[
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          c,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.dim),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (online[c] ?? CurrencyService.currentRate(c)).toStringAsFixed(2),
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  if (c != visibleCurrencies.last)
                    Container(width: 1, height: 18, color: context.hairline),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chartCard() {
    final all = _chartPoints;
    final size = _viewSize == 0 ? all.length : _viewSize;
    final int startIndex = _viewStart.round().clamp(0, all.isEmpty ? 0 : all.length - 1).toInt();
    final int endIndex = math.min<int>(all.length, startIndex + size);
    // Видимый отрезок нужен для заголовка и подписей по краям, а сама линия
    // получает весь загруженный набор и своё окно.
    final points = all.isEmpty ? all : all.sublist(startIndex, endIndex);
    final values = all.map((e) => e.value).toList();
    final visibleValues = points.map((e) => e.value).toList();
    final change = visibleValues.length > 1 ? visibleValues.last - visibleValues.first : 0.0;
    final changePct = visibleValues.length > 1 && visibleValues.first != 0
        ? change / visibleValues.first * 100
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              title: _chartKey == 'IMOEX' ? 'Индекс МосБиржи' : 'Курс $_chartKey',
              subtitle: points.length > 1
                  ? '${Fmt.date(points.first.key)} — ${Fmt.date(points.last.key)}'
                  : _range.label,
              padding: const EdgeInsets.only(bottom: 10),
              trailing: values.length > 1
                  ? TagChip(
                      text: '${change >= 0 ? "+" : ""}${changePct.toStringAsFixed(1)}%',
                      color: AppColors.pnl(change),
                    )
                  : null,
            ),
            PillTabs<String>(
              values: const ['IMOEX', 'USD', 'CNY'],
              selected: _chartKey,
              labelOf: (k) => k == 'IMOEX' ? 'Индекс' : k,
              onChanged: (k) {
                setState(() => _chartKey = k);
                _loadChart();
              },
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            PillTabs<ChartRange>(
              values: ChartRange.values,
              selected: _range,
              labelOf: (r) => r.label,
              onChanged: (r) {
                setState(() => _range = r);
                _loadChart();
              },
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 140,
              child: _chartLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _chartError != null
                      ? Center(
                          child: Text(
                            _chartError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: context.dim),
                          ),
                        )
                      : visibleValues.length < 2
                          ? Center(
                              child: Text('Нет данных', style: TextStyle(fontSize: 12, color: context.dim)),
                            )
                          : Sparkline(
                              values: values,
                              windowSize: _viewSize == 0 ? null : _viewSize,
                              windowStart: _viewStart,
                              color: AppColors.pnl(change),
                              height: 140,
                              // Сверху дата и время, снизу значение — один и
                              // тот же вид у всех графиков в приложении.
                              tooltipBuilder: (i, v) =>
                                  '${Fmt.dateTime(all[i].key, withTime: _intraday)}\n${Fmt.price(v)}',
                              dateLabel: (i) => Fmt.dateTime(all[i].key, withTime: _intraday),
                              priceLabel: (v) => Fmt.price(v),
                              onPan: _viewSize < all.length ? _panChart : null,
                            ),
            ),
            if (visibleValues.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(Fmt.date(points.first.key), style: TextStyle(fontSize: 10.5, color: context.dim)),
                  Text(
                    Fmt.price(visibleValues.last),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  Text(Fmt.date(points.last.key), style: TextStyle(fontSize: 10.5, color: context.dim)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _listHeader(int count) {
    final active = _filter.activeCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title: 'Бумаги', subtitle: '$count в списке'),
          Row(
            children: [
              Expanded(
                child: TourSpot(
                  id: 'search',
                  child: AppSearchField(
                    controller: _searchCtrl,
                    hint: 'Тикер или название',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Один вход в фильтры вместо двух рядов пилюль: на экране стало
              // тише, а условий можно задать больше.
              Pressable(
                onTap: _openFilterSheet,
                child: Container(
                  width: 52,
                  height: 52,
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
                      Icon(
                        Icons.tune_rounded,
                        size: 21,
                        color: active > 0 ? context.accent : context.dim,
                      ),
                      if (active > 0)
                        Positioned(
                          top: 6,
                          right: 6,
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
                                fontWeight: FontWeight.w800,
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
          ),
          if (active > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final kind in _filter.kinds)
                  _activeChip(kind.title, () => setState(() {
                        _filter = _filter.copyWith(kinds: <MarketKind>{..._filter.kinds}..remove(kind));
                      })),
                if (_filter.ownedOnly)
                  _activeChip('В портфеле', () => setState(() {
                        _filter = _filter.copyWith(ownedOnly: false);
                      })),
                if (_filter.favoritesOnly)
                  _activeChip('Избранное', () => setState(() {
                        _filter = _filter.copyWith(favoritesOnly: false);
                      })),
                if (_filter.currency != CurrencyMode.any)
                  _activeChip(_filter.currency.title, () => setState(() {
                        _filter = _filter.copyWith(currency: CurrencyMode.any);
                      })),
                if (_filter.coupon != CouponMode.any)
                  _activeChip('Купон: ${_filter.coupon.title.toLowerCase()}', () => setState(() {
                        _filter = _filter.copyWith(coupon: CouponMode.any);
                      })),
                for (final perYear in _filter.couponsPerYear)
                  _activeChip('$perYear раз в год', () => setState(() {
                        _filter = _filter.copyWith(
                          couponsPerYear: <int>{..._filter.couponsPerYear}..remove(perYear),
                        );
                      })),
                if (_filter.minYield != null)
                  _activeChip('от ${_filter.minYield}%', () => setState(() {
                        _filter = _filter.copyWith(clearYield: true);
                      })),
                if (_filter.minTurnover != null)
                  _activeChip('оборот от ${Fmt.compact(_filter.minTurnover!)}', () => setState(() {
                        _filter = _filter.copyWith(clearTurnover: true);
                      })),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Включённое условие видно прямо в списке — и снимается одним нажатием.
  Widget _activeChip(String label, VoidCallback onRemove) {
    return Pressable(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.accent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.accent.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.accent),
            ),
            const SizedBox(width: 5),
            Icon(Icons.close_rounded, size: 13, color: context.accent),
          ],
        ),
      ),
    );
  }


  /// Форма фильтров: типы бумаг, признаки, сортировка и сохранённые наборы.
  void _openFilterSheet() {
    // Правим копию: закрыл лист крестиком — ничего не изменилось.
    MarketFilter draft = _filter;
    final yieldCtrl = TextEditingController(text: _filter.minYield?.toString() ?? '');
    final turnoverCtrl = TextEditingController(
      text: _filter.minTurnover == null ? '' : _filter.minTurnover!.round().toString(),
    );

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Фильтры',
                subtitle: 'Можно сохранить набор и вызывать его одним нажатием',
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),

              ValueListenableBuilder<int>(
                valueListenable: MarketFilterService.version,
                builder: (context, _, __) {
                  final presets = MarketFilterService.presets;
                  if (presets.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сохранённые',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: context.dim,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in presets.entries)
                              Pressable(
                                onTap: () => setSheetState(() => draft = entry.value),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                                  decoration: BoxDecoration(
                                    color: context.isDark
                                        ? Colors.white.withOpacity(0.05)
                                        : AppColors.lightSurfaceHigh,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: context.hairline),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.bookmark_outline_rounded,
                                          size: 14, color: context.accent),
                                      const SizedBox(width: 6),
                                      Text(entry.key,
                                          style: const TextStyle(
                                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => MarketFilterService.remove(entry.key),
                                        child: Icon(Icons.close_rounded,
                                            size: 14, color: context.dim),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              Text(
                'Тип бумаги',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in MarketKind.values)
                    _choice(
                      label: kind.title,
                      selected: draft.kinds.contains(kind),
                      onTap: () => setSheetState(() {
                        final kinds = <MarketKind>{...draft.kinds};
                        kinds.contains(kind) ? kinds.remove(kind) : kinds.add(kind);
                        draft = draft.copyWith(kinds: kinds);
                      }),
                    ),
                ],
              ),

              const SizedBox(height: 18),
              AppCheckRow(
                value: draft.ownedOnly,
                title: 'Только в портфеле',
                onChanged: (v) => setSheetState(() => draft = draft.copyWith(ownedOnly: v)),
              ),
              AppCheckRow(
                value: draft.favoritesOnly,
                title: 'Только избранное',
                onChanged: (v) => setSheetState(() => draft = draft.copyWith(favoritesOnly: v)),
              ),

              const SizedBox(height: 18),
              Text(
                'Валюта выпуска',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in CurrencyMode.values)
                    _choice(
                      label: mode.title,
                      selected: draft.currency == mode,
                      onTap: () => setSheetState(() => draft = draft.copyWith(currency: mode)),
                    ),
                ],
              ),

              const SizedBox(height: 18),
              Text(
                'Купон облигаций',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in CouponMode.values)
                    _choice(
                      label: mode.title,
                      selected: draft.coupon == mode,
                      onTap: () => setSheetState(() => draft = draft.copyWith(coupon: mode)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in const {12: 'Ежемесячно', 4: 'Ежеквартально', 2: 'Раз в полгода', 1: 'Раз в год'}.entries)
                    _choice(
                      label: entry.value,
                      selected: draft.couponsPerYear.contains(entry.key),
                      onTap: () => setSheetState(() {
                        final set = <int>{...draft.couponsPerYear};
                        set.contains(entry.key) ? set.remove(entry.key) : set.add(entry.key);
                        draft = draft.copyWith(couponsPerYear: set);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Условия по купону касаются только облигаций — при них акции из списка уходят.',
                style: TextStyle(fontSize: 10.5, height: 1.35, color: context.dim),
              ),

              const SizedBox(height: 18),
              Text(
                'Доходность и оборот',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: yieldCtrl,
                      label: 'Доходность от, %',
                      number: true,
                      onChanged: (v) => setSheetState(() {
                        final parsed = double.tryParse(v.replaceAll(',', '.'));
                        draft = parsed == null
                            ? draft.copyWith(clearYield: true)
                            : draft.copyWith(minYield: parsed);
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      controller: turnoverCtrl,
                      label: 'Оборот от, ₽',
                      number: true,
                      onChanged: (v) => setSheetState(() {
                        final parsed = double.tryParse(v.replaceAll(',', '.'));
                        draft = parsed == null
                            ? draft.copyWith(clearTurnover: true)
                            : draft.copyWith(minTurnover: parsed);
                      }),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              Text(
                'Сортировка',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sort in MarketSort.values)
                    _choice(
                      label: sort.title,
                      selected: draft.sort == sort,
                      onTap: () => setSheetState(() => draft = draft.copyWith(sort: sort)),
                    ),
                ],
              ),

              const SizedBox(height: 22),
              GradientButton(
                label: 'Применить',
                icon: Icons.check_rounded,
                onPressed: () {
                  setState(() => _filter = draft);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: draft.isEmpty ? null : () => _savePresetDialog(draft),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                      label: const Text('Сохранить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setSheetState(() {
                        draft = const MarketFilter();
                        yieldCtrl.clear();
                        turnoverCtrl.clear();
                      }),
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: const Text('Сбросить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice({required String label, required bool selected, required VoidCallback onTap}) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? context.accent.withOpacity(0.16)
              : (context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? context.accent.withOpacity(0.55) : context.hairline,
            width: selected ? 1.4 : 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? context.accent : null,
          ),
        ),
      ),
    );
  }

  Future<void> _savePresetDialog(MarketFilter filter) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название набора'),
        content: AppTextField(controller: ctrl, label: 'Например, «Мои облигации»', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await MarketFilterService.save(ctrl.text, filter);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _row(MoexQuote q, bool isOwned) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.push(
        context,
        AppPageRoute(builder: (_) => TickerDetailScreen(ticker: q.ticker)),
      ),
      child: Row(
        children: [
          TickerAvatar(ticker: q.ticker, size: 38, glow: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        q.shortName.isNotEmpty ? q.shortName : q.ticker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    if (isOwned) ...[
                      const SizedBox(width: 6),
                      TagChip(text: 'в портфеле', color: AppColors.positive, fontSize: 9),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  q.ticker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.dim),
                ),
                if (q.turnover > 0 || q.yieldPct != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (q.turnover > 0) 'оборот ${Fmt.compact(q.turnover)}',
                      if (q.yieldPct != null) 'доходность ${q.yieldPct!.toStringAsFixed(1)}%',
                      if (q.isBond && q.couponsPerYear != null)
                        'купон ${q.isFloater ? "переменный" : "постоянный"}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: context.dim),
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
                Fmt.price(q.price, currency: '₽'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 3),
              TagChip(text: _typeOf(q.board), color: _typeColor(q.board), fontSize: 9),
            ],
          ),
          ValueListenableBuilder<int>(
            valueListenable: FavoritesService.version,
            builder: (context, _, __) {
              final fav = FavoritesService.isFavorite(q.ticker);
              return IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  fav ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 20,
                  color: fav ? AppColors.gold : context.dim,
                ),
                onPressed: () => FavoritesService.toggle(q.ticker),
              );
            },
          ),
        ],
      ),
    );
  }
}
