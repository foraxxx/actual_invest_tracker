import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'currency_service.dart';
import 'moex_service.dart';
import 'moex_sync_service.dart';
import 'online_settings_service.dart';

/// Прогноз выплат по портфелю на 12 месяцев вперёд — по объявленным биржей
/// купонам и дивидендам, а не по прошлым выплатам.
///
/// Для облигаций это почти точный расчёт: график купонов известен заранее на
/// весь срок. Для акций честно только то, что уже объявлено, — поэтому если по
/// бумаге объявленных дивидендов нет, берётся оценка по выплатам за прошлый
/// год (так же, как считалось раньше).
class PayoutForecastService {
  PayoutForecastService._();

  static final ValueNotifier<int> version = ValueNotifier(0);
  static final ValueNotifier<bool> loading = ValueNotifier(false);

  /// Тикер -> выплаты с биржи. Живёт в памяти: график купонов меняется редко,
  /// но и хранить его между запусками смысла нет.
  static final Map<String, List<MoexPayout>> _payouts = {};

  static bool get hasData => _payouts.isNotEmpty;

  static List<MoexPayout> payoutsFor(String ticker) => _payouts[ticker] ?? const [];

  /// Загружает графики выплат для бумаг портфеля.
  static Future<void> refresh() async {
    if (!OnlineSettingsService.enabled || loading.value) return;
    loading.value = true;
    try {
      final holdings = AnalyticsService.currentHoldings();
      final snapshot = MoexSyncService.marketSnapshot.value;
      for (final ticker in holdings.keys) {
        if (_payouts.containsKey(ticker)) continue;
        try {
          _payouts[ticker] = await MoexService.fetchPayouts(
            ticker,
            isBond: snapshot[ticker.toUpperCase()]?.isBond ?? false,
          );
        } catch (_) {
          _payouts[ticker] = const [];
        }
      }
      version.value++;
    } finally {
      loading.value = false;
    }
  }

  static void clear() {
    _payouts.clear();
    version.value++;
  }

  /// Ожидаемые выплаты по одной бумаге за ближайшие 12 месяцев — в рублях на
  /// всю текущую позицию.
  static ({double rub, String source}) forecastForTicker(String ticker) {
    final holding = AnalyticsService.currentHoldings()[ticker];
    if (holding == null || holding.qty <= 0) return (rub: 0, source: 'нет позиции');

    final list = _payouts[ticker] ?? const <MoexPayout>[];
    final coupons = list.where((p) => p.kind == 'Купон').toList();

    final perUnit = coupons.isNotEmpty
        ? _bondPerUnit(coupons)
        : _sharePerUnit(list.where((p) => p.kind == 'Дивиденд').toList());

    if (perUnit.value > 0) {
      final currency = _payoutCurrency(list);
      // Умножаем на количество бумаг, которое есть сейчас, а не на прошлое.
      return (rub: CurrencyService.toRub(perUnit.value * holding.qty, currency), source: perUnit.source);
    }

    // Запасной вариант — только когда биржевой истории по бумаге нет вообще
    // (нет интернета или бумага не торгуется). Считаем по выплатам, которые
    // получил сам пользователь; это менее точно, потому что зависит от того,
    // когда именно он купил бумагу.
    if (list.isEmpty) {
      final history = AnalyticsService.dividendForecastByTicker()[ticker];
      return (rub: history?.last12mRub ?? 0, source: 'по моим выплатам');
    }
    return (rub: 0, source: 'выплат не ожидается');
  }

  /// Купоны: важна периодичность. По расстоянию между соседними выплатами
  /// определяем, сколько их в году, и берём годовую сумму — иначе бумага с
  /// полугодовым купоном выглядела бы вдвое доходнее квартальной при равном
  /// размере выплаты.
  static ({double value, String source}) _bondPerUnit(List<MoexPayout> coupons) {
    final sorted = coupons.toList()..sort((a, b) => a.date.compareTo(b.date));
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 365));
    final upcoming = sorted.where((c) => c.date.isAfter(now)).toList();
    if (upcoming.isEmpty) return (value: 0, source: '');

    final withinYear = upcoming.where((c) => c.date.isBefore(horizon)).toList();

    // Если известный график заканчивается раньше горизонта (погашение или
    // биржа отдала не весь график), достраиваем год по периодичности.
    final gaps = <int>[];
    for (int i = 1; i < sorted.length; i++) {
      final days = sorted[i].date.difference(sorted[i - 1].date).inDays;
      if (days > 20 && days < 400) gaps.add(days);
    }
    final medianGap = gaps.isEmpty ? 182 : (gaps..sort())[gaps.length ~/ 2];
    final perYear = (365 / medianGap).clamp(1.0, 12.0);

    final lastCoupon = upcoming.first.amount;
    final scheduled = withinYear.fold(0.0, (sum, c) => sum + c.amount);
    final byPeriodicity = lastCoupon * perYear;

    // Погашение внутри года — дальше купонов не будет, берём фактический
    // график. В остальных случаях — расчёт по периодичности.
    final matures = upcoming.last.date.isBefore(horizon);
    final value = matures ? scheduled : (scheduled > 0 ? scheduled : byPeriodicity);

    final perYearLabel = perYear >= 11
        ? 'ежемесячно'
        : perYear >= 3.5
            ? 'ежеквартально'
            : perYear >= 1.8
                ? 'дважды в год'
                : 'раз в год';
    return (value: value, source: 'купоны $perYearLabel');
  }

  /// Дивиденды: считаем по годовой динамике самой бумаги.
  ///
  /// Раньше бралась сумма за последние 365 дней, а если её не было — среднее
  /// за три года. На растущем дивиденде это давало заниженный прогноз: у
  /// бумаги с выплатами 25 → 33 → 34 среднее равно 30, хотя следующая выплата
  /// заведомо больше последней. Теперь считается темп роста и переносится
  /// вперёд.
  static ({double value, String source}) _sharePerUnit(List<MoexPayout> dividends) {
    if (dividends.isEmpty) return (value: 0, source: '');
    final now = DateTime.now();

    // Суммы по календарным годам: компания может платить в несколько заходов,
    // и сравнивать надо годовые суммы, а не отдельные выплаты.
    final byYear = <int, double>{};
    for (final d in dividends) {
      if (d.amount <= 0) continue;
      byYear[d.date.year] = (byYear[d.date.year] ?? 0) + d.amount;
    }
    if (byYear.isEmpty) return (value: 0, source: '');

    final years = byYear.keys.toList()..sort();
    final lastYear = years.last;
    final lastValue = byYear[lastYear]!;

    // Уже объявленные будущие выплаты — самая точная часть прогноза.
    final announced = dividends
        .where((d) => d.date.isAfter(now) && d.date.isBefore(now.add(const Duration(days: 365))))
        .fold(0.0, (sum, d) => sum + d.amount);

    // Темп роста — среднее геометрическое отношений соседних лет. Оно устойчивее
    // к одному аномальному году, чем простое отношение первого к последнему.
    final ratios = <double>[];
    for (int i = 1; i < years.length; i++) {
      final prev = byYear[years[i - 1]]!;
      final cur = byYear[years[i]]!;
      // Пропущенный год (компания не платила) ломает темп — такие пары не берём.
      if (prev <= 0 || cur <= 0) continue;
      if (years[i] - years[i - 1] != 1) continue;
      ratios.add(cur / prev);
    }

    double growth = 1;
    if (ratios.isNotEmpty) {
      double product = 1;
      for (final r in ratios) {
        product *= r;
      }
      growth = math.pow(product, 1 / ratios.length).toDouble();
      // Ограничиваем: один щедрый год не должен обещать вечный рост, а один
      // пропуск — вечное падение.
      growth = growth.clamp(0.75, 1.45);
    }

    // На сколько шагов роста смотрим вперёд. Если последняя известная выплата
    // была в прошлом году, следующая ожидается в этом — это один шаг, а не два.
    final yearsAhead = (now.year - lastYear).clamp(1, 3);
    final projected = lastValue * math.pow(growth, yearsAhead).toDouble();

    // Если выплату уже объявили, а она больше расчёта — доверяем бирже.
    final value = announced > projected ? announced : projected;
    if (value <= 0) return (value: 0, source: '');

    final growthPct = ((growth - 1) * 100).round();
    final source = announced > projected
        ? 'объявленные дивиденды'
        : ratios.isEmpty
            ? 'по прошлой выплате'
            : growthPct > 1
                ? 'рост ~$growthPct% в год'
                : growthPct < -1
                    ? 'снижение ~${growthPct.abs()}% в год'
                    : 'на уровне прошлых лет';
    return (value: value, source: source);
  }

  static String _payoutCurrency(List<MoexPayout> list) {
    if (list.isEmpty) return 'RUB';
    final raw = list.first.currency.toUpperCase();
    return (raw == 'SUR' || raw.isEmpty) ? 'RUB' : raw;
  }

  /// Прогноз по всему портфелю.
  static ({double total, int fromExchange, int fromHistory}) portfolioForecast() {
    double total = 0;
    int fromExchange = 0;
    int fromHistory = 0;

    for (final ticker in AnalyticsService.currentHoldings().keys) {
      final r = forecastForTicker(ticker);
      if (r.rub <= 0) continue;
      total += r.rub;
      if (r.source == 'по моим выплатам') {
        fromHistory++;
      } else {
        fromExchange++;
      }
    }
    return (total: total, fromExchange: fromExchange, fromHistory: fromHistory);
  }

  /// Прогнозная доходность портфеля: ожидаемые выплаты к текущей стоимости.
  static double yieldPct() {
    final value = AnalyticsService.currentPortfolioValueRub();
    if (value <= 0) return 0;
    return portfolioForecast().total / value * 100;
  }

  /// Прогноз считается всегда: без интернета и без биржевых графиков он просто
  /// целиком опирается на прошлые выплаты.
  static bool get isReady => AnalyticsService.currentHoldings().isNotEmpty;
}
