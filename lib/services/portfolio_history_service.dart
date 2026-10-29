import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'currency_service.dart';
import 'moex_sync_service.dart';
import 'payout_forecast_service.dart';
import 'price_history_cache.dart';
import 'online_settings_service.dart';
import 'portfolio_service.dart';
import 'storage_service.dart';
import '../models/purchase.dart';

/// Загружает дневную историю MOEX и собирает реальную историческую стоимость
/// портфеля. При отсутствии сети UI продолжает использовать локальную историю
/// ручных цен и сделок из [AnalyticsService.portfolioValueTimeline].
class PortfolioHistoryService {
  PortfolioHistoryService._();

  static final ValueNotifier<List<MapEntry<DateTime, double>>> timeline =
      ValueNotifier(const []);
  static final ValueNotifier<bool> loading = ValueNotifier(false);
  static final ValueNotifier<String?> error = ValueNotifier(null);

  /// Возвращает историю с гарантированно актуальной последней точкой.
  /// Исторические значения приходят с MOEX, а точка «сейчас» должна всегда
  /// совпадать с суммой, показанной над графиком.
  static List<MapEntry<DateTime, double>> withCurrentPoint(
    List<MapEntry<DateTime, double>> source,
    double currentValue, {
    DateTime? now,
  }) {
    final currentDate = now ?? DateTime.now();
    final result = [...source]..sort((a, b) => a.key.compareTo(b.key));
    if (result.isNotEmpty && _sameDay(result.last.key, currentDate)) {
      result[result.length - 1] = MapEntry(currentDate, currentValue);
    } else {
      result.add(MapEntry(currentDate, currentValue));
    }
    return result;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Цены облигации в прошлом — в валюте сделки за одну бумагу.
  ///
  /// Биржа даёт цену в процентах от номинала. Номинал на каждую дату — это
  /// сегодняшний номинал плюс всё, что было погашено после этой даты
  /// (у облигаций с амортизацией он уменьшается частями).
  static Future<List<MapEntry<DateTime, double>>> _bondHistory(String ticker, DateTime from) async {
    final quote = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()];
    final face = quote?.faceValue;
    if (face == null || face <= 0) return const [];
    final raw = await PriceHistoryCache.history(ticker, from: from, market: 'bonds', board: quote!.board);
    if (raw.isEmpty) return const [];

    final now = DateTime.now();
    final amortizations = [
      for (final p in PayoutForecastService.payoutsFor(ticker))
        if (p.kind == 'Погашение номинала' && !p.date.isAfter(now)) p,
    ];
    final unit = quote.faceUnit.toUpperCase();
    final faceCurrency = unit == 'SUR' ? 'RUB' : unit;
    String tradeCurrency = 'RUB';
    for (final t in StorageService.purchases) {
      if (t.ticker.toUpperCase() == ticker.toUpperCase()) tradeCurrency = t.currency;
    }

    return [
      for (final p in raw)
        () {
          var faceAt = face;
          for (final a in amortizations) {
            if (a.date.isAfter(p.key)) faceAt += a.amount;
          }
          final inFace = p.value / 100 * faceAt;
          if (faceCurrency == tradeCurrency) return MapEntry(p.key, inFace);
          final rub = CurrencyService.toRub(inFace, faceCurrency, date: p.key);
          final perTrade = tradeCurrency == 'RUB' ? 1.0 : CurrencyService.toRub(1, tradeCurrency, date: p.key);
          return MapEntry(p.key, perTrade <= 0 ? rub : rub / perTrade);
        }(),
    ];
  }

  /// Цены бумаг по дням с биржи — в валюте сделки за одну бумагу. Нужны
  /// для оценки портфеля на прошлую дату: прибыль за месяц, доходность.
  static Map<String, List<MapEntry<DateTime, double>>> _prices = const {};

  /// Цена закрытия последнего торгового дня, который закончился не позже
  /// [date]. null — истории по бумаге нет.
  static double? priceAt(String ticker, DateTime date) {
    final points = _prices[ticker];
    if (points == null || points.isEmpty) return null;
    var lo = 0;
    var hi = points.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final k = points[mid].key;
      final close = DateTime(k.year, k.month, k.day, 23, 59, 59);
      if (close.isAfter(date)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo == 0 ? null : points[lo - 1].value;
  }

  /// Код валюты валютной позиции: «USDRUB» → «USD».
  static String? _currencyOfPosition(String ticker) {
    final t = ticker.toUpperCase();
    for (final c in CurrencyService.trackedCurrencies) {
      if (t.startsWith(c)) return c;
    }
    return null;
  }

  /// Подгружает с биржи курсы валют, которые встречаются в портфеле, и
  /// отдаёт их пересчёту в рубли: прошлые суммы считаются по курсу своей даты.
  static Future<Map<String, List<MapEntry<DateTime, double>>>> _loadCurrencies(
    List<Purchase> trades,
    DateTime from,
  ) async {
    final codes = <String>{};
    for (final t in trades) {
      final cur = t.currency.toUpperCase();
      if (cur != 'RUB' && CurrencyService.trackedCurrencies.contains(cur)) codes.add(cur);
      if (t.type == AssetType.currency) {
        final c = _currencyOfPosition(t.ticker);
        if (c != null) codes.add(c);
      }
      if (t.type == AssetType.bond) {
        final unit = MoexSyncService.marketSnapshot.value[t.ticker.toUpperCase()]?.faceUnit.toUpperCase();
        if (unit != null && CurrencyService.trackedCurrencies.contains(unit)) codes.add(unit);
      }
    }
    final result = <String, List<MapEntry<DateTime, double>>>{};
    for (final c in codes) {
      final points = await PriceHistoryCache.currency(c, from: from);
      if (points.isNotEmpty) {
        result[c] = points;
        CurrencyService.setMarketHistory(c, points);
      }
    }
    return result;
  }

  /// Курсы с биржи из памяти телефона — сразу при запуске, ещё до сети.
  static void loadCachedCurrencies() {
    for (final c in CurrencyService.trackedCurrencies) {
      final points = PriceHistoryCache.cachedCurrency(c);
      if (points.isNotEmpty) CurrencyService.setMarketHistory(c, points);
    }
  }

  /// Чей график сейчас в [timeline] и для какого портфеля идёт загрузка.
  /// У каждого портфеля график свой: при переключении старый сбрасывается,
  /// а загрузка, закончившаяся уже после переключения, отбрасывается.
  static String? _owner;
  static String? _loadingFor;

  static String? _activeId() {
    try {
      return PortfolioService.activeId;
    } catch (_) {
      return null;
    }
  }

  static Future<void> refresh() async {
    final id = _activeId();
    if (_owner != id) {
      _owner = id;
      timeline.value = const [];
      error.value = null;
    }
    if (StorageService.purchases.isEmpty) {
      if (timeline.value.isNotEmpty) timeline.value = const [];
      return;
    }
    if (loading.value && _loadingFor == id) {
      return;
    }
    _loadingFor = id;
    if (!OnlineSettingsService.enabled) {
      error.value = 'Онлайн-история выключена — показаны локальные данные';
      return;
    }
    loading.value = true;
    error.value = null;
    try {
      final result = await valueHistory(StorageService.purchases, remember: true);
      // Пока грузилось, переключили портфель — этот график уже не нужен.
      if (_activeId() != id) return;
      if (result == null) {
        error.value = 'История MOEX недоступна — показаны локальные данные';
        return;
      }
      if (result.isNotEmpty) {
        result.add(MapEntry(
          DateTime.now(),
          AnalyticsService.currentPortfolioValueRub(),
        ));
        timeline.value = result;
      } else {
        error.value = 'Не удалось построить онлайн-график';
      }
    } catch (_) {
      error.value = 'Нет связи с MOEX — показаны локальные данные';
    } finally {
      if (_loadingFor == id) {
        _loadingFor = null;
        loading.value = false;
      }
    }
  }

  /// Стоимость в рублях на закрытие каждого торгового дня для любых сделок —
  /// одного портфеля или нескольких сразу. [from] — с какого дня нужны точки
  /// (по умолчанию с первой сделки). Цены берутся из сохранённой на телефоне
  /// истории; с биржи докачиваются только новые дни, не чаще раза в день.
  /// null — истории с биржи нет ни по одной бумаге.
  static Future<List<MapEntry<DateTime, double>>?> valueHistory(
    List<Purchase> purchases, {
    DateTime? from,
    bool remember = false,
  }) async {
    if (purchases.isEmpty) return const [];
    final trades = [...purchases]..sort(AnalyticsService.compareTrades);
    final first = trades.first.date;
    final since = from == null || from.isBefore(first) ? first : from;
    final sinceDay = DateTime(since.year, since.month, since.day);
    final tickers = trades.map((p) => p.ticker).toSet();
    final typeByTicker = <String, AssetType>{};
    for (final trade in trades) {
      typeByTicker[trade.ticker] = trade.type;
    }
    final fx = await _loadCurrencies(trades, since);
    final entries = await Future.wait(tickers.map((ticker) async {
      final type = typeByTicker[ticker];
      if (type == AssetType.bond) {
        return MapEntry(ticker, await _bondHistory(ticker, since));
      }
      if (type == AssetType.currency) {
        final c = _currencyOfPosition(ticker);
        return MapEntry(ticker, c == null ? const <MapEntry<DateTime, double>>[] : (fx[c] ?? const []));
      }
      if (type != AssetType.stock && type != AssetType.etf) {
        return MapEntry(ticker, const <MapEntry<DateTime, double>>[]);
      }
      final points = await PriceHistoryCache.history(ticker, from: since, market: 'shares');
      return MapEntry(ticker, points);
    }));
    final histories = Map<String, List<MapEntry<DateTime, double>>>.fromEntries(
      entries.where((entry) => entry.value.isNotEmpty),
    );
    if (histories.isEmpty) return null;
    if (remember) _prices = histories;

    final dates = histories.values
        .expand((points) => points.map((point) => point.key))
        .where((d) => !d.isBefore(sinceDay))
        .toSet()
        .toList()
      ..sort();

    // Каждая бумага проходится один раз: для неё по порядку двигаются
    // указатели на сделки и на цены. Раньше для каждого дня заново
    // перебирались все сделки всех бумаг — на длинной истории это были
    // миллионы шагов.
    final tradesByTicker = <String, List<Purchase>>{};
    for (final trade in trades) {
      (tradesByTicker[trade.ticker] ??= []).add(trade);
    }
    final totals = List<double>.filled(dates.length, 0);
    for (final ticker in tickers) {
      final list = tradesByTicker[ticker]!;
      final points = histories[ticker] ?? const <MapEntry<DateTime, double>>[];
      final currency = list.last.currency;
      var ti = 0;
      var pi = 0;
      double quantity = 0;
      double? lastTradePrice;
      double? historyPrice;
      for (int di = 0; di < dates.length; di++) {
        final date = dates[di];
        // Цена — закрытие дня, поэтому и сделки берём все за этот день, с
        // любым временем. Иначе бумаги, купленные днём, не попадали в
        // стоимость, хотя деньги на них уже ушли со счёта.
        final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);
        while (ti < list.length && !list[ti].date.isAfter(dayEnd)) {
          quantity += list[ti].signedQuantity;
          lastTradePrice = list[ti].pricePerUnit;
          ti++;
        }
        while (pi < points.length && !points[pi].key.isAfter(date)) {
          historyPrice = points[pi].value;
          pi++;
        }
        if (quantity <= 1e-9) continue;
        final price = historyPrice ?? lastTradePrice;
        if (price == null) continue;
        totals[di] += CurrencyService.toRub(quantity * price, currency, date: date);
      }
    }

    return <MapEntry<DateTime, double>>[
      for (int di = 0; di < dates.length; di++)
        if (totals[di] > 0) MapEntry(dates[di], totals[di]),
    ];
  }
}
