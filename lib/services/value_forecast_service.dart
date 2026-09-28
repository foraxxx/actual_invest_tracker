import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/income.dart';
import '../models/plan.dart';
import '../models/purchase.dart';
import 'analytics_service.dart';
import 'appearance_service.dart';
import 'cash_service.dart';
import 'currency_service.dart';
import 'moex_service.dart';
import 'moex_sync_service.dart';
import 'online_price_service.dart';
import 'online_settings_service.dart';
import 'plan_apply_service.dart';
import 'payout_forecast_service.dart';
import 'storage_service.dart';
import 'value_forecast_engine.dart';

/// Прогноз стоимости портфеля: собирает позиции и допущения из данных
/// приложения и отдаёт их в [ValueForecastEngine].
///
/// Вся арифметика живёт в движке и покрыта тестами. Здесь только сбор
/// данных, поэтому сюда не стоит добавлять расчёты — их не на чем проверить.
class ValueForecastService {
  ValueForecastService._();

  static const List<int> horizons = [1, 3, 5, 10];
  static const int defaultHorizon = 3;

  /// Меняется, когда подгрузилась история индекса и допущения уточнились.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static MarketAssumptions? _fromHistory;
  static Future<void>? _loading;

  /// Доходность денег после погашения облигаций.
  ///
  /// Это единственное место прогноза, где число задано, а не выведено из
  /// данных: будущую ставку по облигациям взять неоткуда. Поэтому оно
  /// показывается в форме рядом с графиком, а не прячется.
  static const Map<ForecastScenario, double> _reinvestYield = {
    ForecastScenario.pessimistic: 0.08,
    ForecastScenario.realistic: 0.12,
    ForecastScenario.optimistic: 0.16,
  };

  /// Запасные допущения, пока история индекса не загружена или недоступна.
  static final MarketAssumptions fallback = MarketAssumptions(
    stockDrift: math.log(1.06),
    stockVolatility: 0.25,
    reinvestYield: _reinvestYield,
    source: 'допущения по умолчанию',
  );

  static MarketAssumptions get assumptions => _fromHistory ?? fallback;

  /// Загружает историю IMOEX и выводит из неё рост и разброс акций.
  ///
  /// Берутся МЕСЯЧНЫЕ свечи: дневная история торгов отдаётся страницами с
  /// потолком в тысячу строк — это около четырёх лет. Запрос на десять лет
  /// вернул бы самые старые четыре года без единого свежего дня, и сценарии
  /// тихо считались бы по давно прошедшему рынку.
  ///
  /// Индекс ценовой, без дивидендов, — и это намеренно: дивиденды в прогнозе
  /// считаются отдельно, по реальным выплатам. Индекс полной доходности учёл
  /// бы их второй раз.
  static Future<void> loadMarketHistory() {
    if (_fromHistory != null || !OnlineSettingsService.enabled) return Future.value();
    return _loading ??= _load().whenComplete(() {
      _loading = null;
    });
  }

  static Future<void> _load() async {
    try {
      final now = DateTime.now();
      final points = await MoexService.fetchCandles(
        engine: 'stock',
        market: 'index',
        secId: 'IMOEX',
        from: DateTime(now.year - 10, now.month, 1),
        interval: 31,
      );
      final stats = monthlyStats([for (final p in points) p.value]);
      if (stats == null) return;
      _fromHistory = MarketAssumptions(
        stockDrift: stats.drift,
        stockVolatility: stats.volatility,
        reinvestYield: _reinvestYield,
        source: 'по истории IMOEX за ${stats.years} ${_years(stats.years)}',
      );
      version.value++;
    } catch (_) {
      // Без сети остаются допущения по умолчанию: прогноз всё равно
      // строится, а в форме написано, на чём именно.
    }
  }

  /// Годовой дрейф и волатильность по ряду месячных закрытий.
  ///
  /// Меньше трёх лет истории не берём: на коротком отрезке одно падение или
  /// один рывок задают весь прогноз на десятилетие вперёд. Границы — защита
  /// от явно испорченных данных, а не попытка подогнать результат.
  @visibleForTesting
  static ({double drift, double volatility, int years})? monthlyStats(List<double> closes) {
    final returns = <double>[];
    for (int i = 1; i < closes.length; i++) {
      if (closes[i - 1] > 0 && closes[i] > 0) returns.add(math.log(closes[i] / closes[i - 1]));
    }
    if (returns.length < 36) return null;
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    double sq = 0;
    for (final r in returns) {
      sq += (r - mean) * (r - mean);
    }
    final monthlyVol = math.sqrt(sq / (returns.length - 1));
    return (
      drift: (mean * 12).clamp(-0.15, 0.30).toDouble(),
      volatility: (monthlyVol * math.sqrt(12)).clamp(0.05, 0.80).toDouble(),
      years: (returns.length / 12).round(),
    );
  }

  static String _years(int n) => n % 10 == 1 && n % 100 != 11
      ? 'год'
      : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) ? 'года' : 'лет');

  /// Позиции портфеля в том виде, в каком их понимает движок.
  static List<ForecastAsset> currentAssets({DateTime? now}) {
    final today = now ?? DateTime.now();
    final result = <ForecastAsset>[];
    for (final entry in AnalyticsService.currentHoldings().entries) {
      final ticker = entry.key;
      final holding = entry.value;
      if (holding.qty <= 0 || holding.valueRub <= 0) continue;
      // Цена — из той же оценки, что и стоимость портфеля на главной: иначе
      // «Сейчас» в прогнозе не совпадало бы с числом, которое человек видит.
      final price = holding.valueRub / holding.qty;
      switch (_typeOf(ticker)) {
        case AssetType.bond:
          result.add(_bond(ticker, holding.qty, price, today));
          break;
        case AssetType.currency:
          result.add(ForecastAsset(
            ticker: ticker,
            kind: ForecastAssetKind.flat,
            qty: holding.qty,
            price: price,
          ));
          break;
        default:
          result.add(ForecastAsset(
            ticker: ticker,
            kind: ForecastAssetKind.equity,
            qty: holding.qty,
            price: price,
            dividendsLastYear: _dividendsLastYear(ticker, today),
          ));
      }
    }
    return result;
  }

  static AssetType _typeOf(String ticker) {
    final key = ticker.toUpperCase();
    for (final p in StorageService.purchases.reversed) {
      if (p.ticker.toUpperCase() == key) return p.type;
    }
    return MoexSyncService.marketSnapshot.value[key]?.isBond == true ? AssetType.bond : AssetType.stock;
  }

  /// Облигация: купоны и погашения из графика биржи.
  ///
  /// Номинал и дата погашения берутся из того же графика, а котировка —
  /// только запасной источник: график лежит в кэше, а котировки бывают лишь
  /// при живой связи, и без сети прогноз облигаций не должен разваливаться.
  static ForecastAsset _bond(String ticker, double qty, double price, DateTime today) {
    final schedule = PayoutForecastService.payoutsFor(ticker);
    final coupons = <CashEvent>[];
    final amortizations = <CashEvent>[];
    for (final p in schedule) {
      final perUnit = CurrencyService.toRub(p.amount, p.currency);
      if (p.kind == 'Купон') {
        // Прошлые купоны тоже нужны: по последнему из них движок оценит
        // будущие купоны флоатера, которые биржа ещё не объявила.
        coupons.add(CashEvent(p.date, perUnit));
      } else if (p.kind == 'Погашение номинала' && p.date.isAfter(today)) {
        amortizations.add(CashEvent(p.date, perUnit));
      }
    }
    amortizations.sort((a, b) => a.date.compareTo(b.date));

    final quote = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()];
    final maturity = quote?.matDate ?? (amortizations.isEmpty ? null : amortizations.last.date);
    double? face;
    if (quote?.faceValue != null && quote!.faceValue! > 0) {
      face = CurrencyService.toRub(quote.faceValue!, quote.faceUnit);
    } else if (amortizations.isNotEmpty) {
      // Сумма будущих погашений и есть непогашенный номинал.
      face = amortizations.fold<double>(0, (sum, a) => sum + a.perUnit);
    }

    return ForecastAsset(
      ticker: ticker,
      kind: ForecastAssetKind.bond,
      qty: qty,
      price: price,
      face: face,
      maturity: maturity,
      coupons: coupons,
      amortizations: amortizations,
    );
  }

  /// Дивиденды на одну бумагу за последние 12 месяцев — по собственным
  /// записям о полученных выплатах.
  ///
  /// Биржа закрыла бесплатный доступ к истории дивидендов, а свои записи
  /// есть всегда. Сумма делится на количество бумаг на дату выплаты, а не на
  /// сегодняшнее: иначе после докупки прошлый дивиденд на бумагу занизился бы.
  static List<CashEvent> _dividendsLastYear(String ticker, DateTime today) {
    final key = ticker.toUpperCase();
    final since = today.subtract(const Duration(days: 365));
    final result = <CashEvent>[];
    for (final income in StorageService.incomes) {
      if (income.type != IncomeType.dividend) continue;
      if (income.ticker.toUpperCase() != key) continue;
      if (!income.date.isAfter(since) || income.date.isAfter(today)) continue;
      final held = _qtyOn(key, income.date);
      if (held <= 0) continue;
      final gross = CurrencyService.toRub(income.amountGross, income.currency, date: income.date);
      result.add(CashEvent(income.date, gross / held));
    }
    return result;
  }

  static double _qtyOn(String ticker, DateTime date) {
    double qty = 0;
    for (final p in StorageService.purchases) {
      if (p.ticker.toUpperCase() != ticker) continue;
      if (p.date.isAfter(date)) continue;
      qty += p.isSell ? -p.quantity : p.quantity;
    }
    return qty;
  }

  static double get _freeCash => math.max(0.0, CashService.summary().cash);

  /// Учитывать ли плановые покупки. Хранится между запусками, и карточка на
  /// главной следует тому же значению, что и форма: иначе число на карточке и
  /// в форме расходились бы.
  static bool get withPlans => AppearanceService.forecastWithPlans;

  static Future<void> setWithPlans(bool value) async {
    await AppearanceService.setForecastWithPlans(value);
    version.value++;
  }

  /// Плановые покупки, разложенные по бумагам, и сводка о том, что вошло.
  ///
  /// Правила отбора:
  /// - берутся только активные планы, по которым что-то осталось докупить;
  /// - план без срока не учитывается: месяц покупки у него неизвестен;
  /// - план позже горизонта прогноза не учитывается;
  /// - просроченный план покупается в первый месяц — он ещё активен;
  /// - бумага, по которой нет ни цены, ни данных, пропускается, и это видно в
  ///   сводке, а не теряется молча.
  static ({List<ForecastAsset> assets, PlanCoverage coverage}) _withPlans(
    List<ForecastAsset> held,
    int months,
    DateTime now,
  ) {
    final byTicker = <String, ForecastAsset>{for (final a in held) a.ticker.toUpperCase(): a};
    final fresh = <String, ForecastAsset>{};
    final buys = <String, List<PlannedBuy>>{};
    int included = 0, undated = 0, beyond = 0, noData = 0;
    DateTime? last;

    for (final plan in StorageService.plans) {
      if (plan.status != PlanStatus.active) continue;
      final qty = PlanApplyService.remaining(plan);
      if (qty <= 0) continue;
      final date = plan.targetDate;
      if (date == null) {
        undated++;
        continue;
      }
      if (ValueForecastEngine.stepOf(date, now) >= months) {
        beyond++;
        continue;
      }
      final key = plan.ticker.toUpperCase();
      var asset = byTicker[key] ?? fresh[key];
      if (asset == null) {
        asset = _freshAsset(plan, now);
        if (asset == null) {
          noData++;
          continue;
        }
        fresh[key] = asset;
      }
      (buys[key] ??= []).add(PlannedBuy(date, qty));
      included++;
      // Просроченный план покупается сейчас, поэтому «до какого месяца» для
      // него считается от сегодняшней даты, а не от давно прошедшей.
      final effective = date.isBefore(now) ? now : date;
      if (last == null || effective.isAfter(last)) last = effective;
    }

    final assets = <ForecastAsset>[
      for (final a in held) a.withPlannedBuys(buys[a.ticker.toUpperCase()] ?? const []),
      for (final e in fresh.entries) e.value.withPlannedBuys(buys[e.key] ?? const []),
    ];
    return (
      assets: assets,
      coverage: PlanCoverage(
        included: included,
        undated: undated,
        beyond: beyond,
        noData: noData,
        lastDate: last,
      ),
    );
  }

  /// Бумага из плана, которой ещё нет в портфеле: позиция с нулевым
  /// количеством, на которую придут плановые покупки.
  ///
  /// Цена — котировка, затем сохранённая цена, затем цена из самого плана.
  /// Для облигации без графика выплат и без даты погашения позицию не
  /// заводим: купленная «пустой», она молча не приносила бы дохода и занижала
  /// прогноз. Пока график не подгрузился, такой план числится в «без данных».
  static ForecastAsset? _freshAsset(Plan plan, DateTime now) {
    final key = plan.ticker.toUpperCase();
    final quote = MoexSyncService.marketSnapshot.value[key];
    double? price;
    if (quote != null && quote.price > 0) {
      price = plan.type == AssetType.bond ? CurrencyService.toRub(quote.price, quote.faceUnit) : quote.price;
    }
    price ??= OnlinePriceService.get(key)?.price;
    if (price == null || price <= 0) price = plan.targetPrice;
    if (price == null || price <= 0) return null;

    switch (plan.type) {
      case AssetType.bond:
        final bond = _bond(key, 0, price, now);
        if (bond.coupons.isEmpty && bond.maturity == null) return null;
        return bond;
      case AssetType.currency:
        return ForecastAsset(ticker: key, kind: ForecastAssetKind.flat, qty: 0, price: price);
      default:
        // Дивидендов у новой акции в прогнозе нет: свои выплаты по ней ещё не
        // записаны, а биржевая история дивидендов закрыта подпиской.
        return ForecastAsset(ticker: key, kind: ForecastAssetKind.equity, qty: 0, price: price);
    }
  }

  /// Всё, что нужно форме прогноза, за один проход: три сценария, даты
  /// погашения для пометок и сводка по планам.
  ///
  /// Сводка считается и при выключенной галке — форме нужно сказать, сколько
  /// планов она могла бы учесть, чтобы галку имело смысл включать.
  static ForecastBundle build(int years) {
    final now = DateTime.now();
    final months = years * 12;
    final held = currentAssets(now: now);
    final planned = _withPlans(held, months, now);
    final assets = withPlans ? planned.assets : held;
    final market = assumptions;
    final cash = _freeCash;
    return ForecastBundle(
      results: {
        for (final s in ForecastScenario.values)
          s: ValueForecastEngine.simulate(
            assets: assets,
            market: market,
            scenario: s,
            start: now,
            months: months,
            freeCash: cash,
          ),
      },
      maturities: ValueForecastEngine.maturitiesWithin(assets, now, months),
      coverage: planned.coverage,
    );
  }

  /// Реалистичный сценарий для карточки на главной, где нужен один итог, а
  /// считать остальные два незачем. [plansApplied] — вошли ли в него плановые
  /// покупки: галка может стоять, а учитывать нечего.
  static ({ForecastResult result, bool plansApplied}) realistic(int years) {
    final now = DateTime.now();
    final held = currentAssets(now: now);
    var assets = held;
    var applied = false;
    if (withPlans) {
      final planned = _withPlans(held, years * 12, now);
      assets = planned.assets;
      applied = planned.coverage.included > 0;
    }
    return (
      result: ValueForecastEngine.simulate(
        assets: assets,
        market: assumptions,
        scenario: ForecastScenario.realistic,
        start: now,
        months: years * 12,
        freeCash: _freeCash,
      ),
      plansApplied: applied,
    );
  }
}

/// Что из планов вошло в прогноз и что нет.
class PlanCoverage {
  /// Планов в расчёте.
  final int included;

  /// Без срока — не учтены.
  final int undated;

  /// Позже горизонта прогноза — не учтены.
  final int beyond;

  /// Без цены или без данных по бумаге — не учтены.
  final int noData;

  /// Месяц последней учтённой покупки.
  final DateTime? lastDate;

  const PlanCoverage({
    required this.included,
    required this.undated,
    required this.beyond,
    required this.noData,
    required this.lastDate,
  });

  int get skipped => undated + beyond + noData;

  /// Есть ли вообще планы, о которых стоит говорить в форме.
  bool get hasAny => included + skipped > 0;
}

class ForecastBundle {
  final Map<ForecastScenario, ForecastResult> results;
  final List<DateTime> maturities;
  final PlanCoverage coverage;

  const ForecastBundle({
    required this.results,
    required this.maturities,
    required this.coverage,
  });
}
