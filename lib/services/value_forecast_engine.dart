import 'dart:math' as math;

/// Расчёт прогноза стоимости портфеля.
///
/// Файл намеренно не знает ни о хранилище, ни о бирже, ни о Flutter: на вход
/// — позиции и допущения, на выход — траектория и разбивка. Так всю денежную
/// логику можно проверить тестами, не поднимая Hive и не выходя в сеть.
///
/// Модель
/// ------
/// Шаг — календарный месяц, точки стоят в последний день месяца.
///
/// Облигации рассчитываются почти точно: купоны и погашения известны из
/// графика биржи, а цена к погашению линейно сходится к номиналу. Во всех трёх
/// сценариях облигации одинаковы — различается только доходность, под
/// которую вкладываются деньги ПОСЛЕ погашения: вложить их «в ту же бумагу»
/// уже нельзя.
///
/// Акции идут по логнормальной модели: логарифм цены через t лет распределён
/// нормально со средним μt и отклонением σ√t. Реалистичный сценарий — медиана,
/// пессимистичный и оптимистичный — 10-й и 90-й процентили. Поэтому веер
/// расширяется со временем, а не расходится с первого месяца под постоянными
/// ставками: неопределённость через год и через десять лет — разная.
///
/// Дивиденды повторяют выплаты последних 12 месяцев в те же месяцы каждого
/// следующего года и масштабируются вместе с ценой акции в сценарии.
///
/// Купоны и дивиденды реинвестируются в ту же бумагу целыми штуками; остаток,
/// которого не хватило на штуку, копится до следующей выплаты. Суммы — до
/// налогов.

enum ForecastScenario { pessimistic, realistic, optimistic }

enum ForecastAssetKind { bond, equity, flat }

/// Выплата или погашение на одну бумагу в рублях.
class CashEvent {
  final DateTime date;
  final double perUnit;

  const CashEvent(this.date, this.perUnit);
}

class ForecastAsset {
  final String ticker;
  final ForecastAssetKind kind;
  final double qty;

  /// Текущая цена одной бумаги в рублях.
  final double price;

  /// Облигации: текущий непогашенный номинал одной бумаги в рублях.
  final double? face;

  /// Облигации: дата погашения.
  final DateTime? maturity;

  /// Облигации: будущие купоны. Нулевая сумма означает, что размер купона
  /// ещё не объявлен (так биржа отдаёт будущие купоны флоатеров) — тогда
  /// берётся последний известный.
  final List<CashEvent> coupons;

  /// Облигации: частичные погашения номинала до даты погашения.
  final List<CashEvent> amortizations;

  /// Акции: дивиденды на одну бумагу за последние 12 месяцев.
  final List<CashEvent> dividendsLastYear;

  const ForecastAsset({
    required this.ticker,
    required this.kind,
    required this.qty,
    required this.price,
    this.face,
    this.maturity,
    this.coupons = const [],
    this.amortizations = const [],
    this.dividendsLastYear = const [],
  });
}

class MarketAssumptions {
  /// Годовой дрейф логарифма цены акций (медиана роста).
  final double stockDrift;

  /// Годовая волатильность акций.
  final double stockVolatility;

  /// Годовая доходность денег после погашения облигаций, по сценариям.
  final Map<ForecastScenario, double> reinvestYield;

  /// Откуда взяты числа — для подписи в интерфейсе.
  final String source;

  const MarketAssumptions({
    required this.stockDrift,
    required this.stockVolatility,
    required this.reinvestYield,
    required this.source,
  });

  /// Медианный годовой рост акций в процентах — для подписей.
  double get stockMedianGrowthPct => (math.exp(stockDrift) - 1) * 100;
}

class ForecastPoint {
  final DateTime date;
  final double value;

  const ForecastPoint(this.date, this.value);
}

/// Из чего складывается итог. Сумма всех статей всегда в точности равна
/// [end]: эффект реинвестирования считается как остаток, а не отдельно.
class ForecastBreakdown {
  final double start;

  /// Купоны, которые принесли бы бумаги, купленные к сегодняшнему дню.
  final double coupons;

  /// Дивиденды на бумаги, купленные к сегодняшнему дню.
  final double dividends;

  /// Изменение цены облигаций к номиналу на исходных бумагах. Может быть
  /// отрицательным, если облигация куплена дороже номинала.
  final double bondsToPar;

  /// Изменение цены акций на исходных бумагах.
  final double stockGrowth;

  /// Всё, что появилось благодаря реинвестированию: выплаты с докупленных
  /// бумаг, изменение их цены и доход на деньги после погашения облигаций.
  final double reinvestment;

  final double end;

  const ForecastBreakdown({
    required this.start,
    required this.coupons,
    required this.dividends,
    required this.bondsToPar,
    required this.stockGrowth,
    required this.reinvestment,
    required this.end,
  });
}

class ForecastResult {
  final ForecastScenario scenario;
  final List<ForecastPoint> points;
  final ForecastBreakdown breakdown;

  const ForecastResult({
    required this.scenario,
    required this.points,
    required this.breakdown,
  });
}

class ValueForecastEngine {
  ValueForecastEngine._();

  /// Квантиль нормального распределения для 10-го и 90-го процентиля.
  static const double _z80 = 1.2815515655446004;

  static double zOf(ForecastScenario s) {
    switch (s) {
      case ForecastScenario.pessimistic:
        return -_z80;
      case ForecastScenario.realistic:
        return 0;
      case ForecastScenario.optimistic:
        return _z80;
    }
  }

  /// Во сколько раз изменится цена акции через [years] лет в сценарии.
  static double stockFactor(MarketAssumptions m, ForecastScenario s, double years) {
    if (years <= 0) return 1;
    return math.exp(m.stockDrift * years + zOf(s) * m.stockVolatility * math.sqrt(years));
  }

  /// Последний день месяца, отстоящего от [start] на [offset] месяцев.
  static DateTime monthEnd(DateTime start, int offset) =>
      DateTime(start.year, start.month + offset + 1, 0);

  /// Прогноз для одного сценария.
  ///
  /// [reinvest] — только для тестов: без реинвестирования выплаты копятся
  /// деньгами, которые ничего не приносят, и тогда эффект реинвестирования
  /// обязан быть ровно нулём. Это главный инвариант разбивки.
  static ForecastResult simulate({
    required List<ForecastAsset> assets,
    required MarketAssumptions market,
    required ForecastScenario scenario,
    required DateTime start,
    required int months,
    double freeCash = 0,
    bool reinvest = true,
  }) {
    final today = DateTime(start.year, start.month, start.day);
    final states = [for (final a in assets) _AssetState(a, today)];
    final poolMonthly = reinvest
        ? math.pow(1 + (market.reinvestYield[scenario] ?? 0), 1 / 12).toDouble() - 1
        : 0.0;

    double pool = 0;
    double origCoupons = 0;
    double origDividends = 0;
    double bondsToPar = 0;

    double startValue = freeCash;
    for (final s in states) {
      startValue += s.units * s.asset.price;
    }

    final points = <ForecastPoint>[ForecastPoint(today, startValue)];
    DateTime prev = today;

    for (int k = 0; k < months; k++) {
      final date = monthEnd(today, k);
      final years = date.difference(today).inDays / 365.25;
      final factor = stockFactor(market, scenario, years);

      // Деньги после погашения растут до того, как к ним добавятся новые:
      // погашение этого месяца начинает приносить доход со следующего.
      pool += pool * poolMonthly;

      for (final s in states) {
        switch (s.asset.kind) {
          case ForecastAssetKind.bond:
            if (!s.alive) break;
            final r = s.stepBond(prev, date);
            origCoupons += r.origCoupons;
            if (r.matured) {
              pool += r.cash + s.leftover;
              s.leftover = 0;
              bondsToPar += s.bondsToParOnOriginal(s.redeemedFace);
            } else if (reinvest) {
              s.buy(r.cash, s.bondPrice(date));
            } else {
              pool += r.cash;
            }
            break;
          case ForecastAssetKind.equity:
            final r = s.stepDividends(prev, date, factor);
            origDividends += r.origDividends;
            if (reinvest) {
              s.buy(r.cash, s.asset.price * factor);
            } else {
              pool += r.cash;
            }
            break;
          case ForecastAssetKind.flat:
            break;
        }
      }

      points.add(ForecastPoint(date, _value(states, date, factor) + pool + freeCash));
      prev = date;
    }

    final end = points.last.value;
    final endYears = prev.difference(today).inDays / 365.25;
    final endFactor = stockFactor(market, scenario, endYears);

    double stockGrowth = 0;
    for (final s in states) {
      if (s.asset.kind == ForecastAssetKind.equity) {
        stockGrowth += s.origUnits * s.asset.price * (endFactor - 1);
      } else if (s.asset.kind == ForecastAssetKind.bond && s.alive) {
        bondsToPar += s.bondsToParOnOriginal(s.bondPrice(prev));
      }
    }

    return ForecastResult(
      scenario: scenario,
      points: points,
      breakdown: ForecastBreakdown(
        start: startValue,
        coupons: origCoupons,
        dividends: origDividends,
        bondsToPar: bondsToPar,
        stockGrowth: stockGrowth,
        reinvestment: end - startValue - origCoupons - origDividends - bondsToPar - stockGrowth,
        end: end,
      ),
    );
  }

  static double _value(List<_AssetState> states, DateTime date, double factor) {
    double v = 0;
    for (final s in states) {
      switch (s.asset.kind) {
        case ForecastAssetKind.bond:
          if (s.alive) v += s.units * s.bondPrice(date) + s.leftover;
          break;
        case ForecastAssetKind.equity:
          v += s.units * s.asset.price * factor + s.leftover;
          break;
        case ForecastAssetKind.flat:
          v += s.units * s.asset.price;
          break;
      }
    }
    return v;
  }

  /// Даты погашения облигаций в пределах горизонта — для пометок на графике.
  static List<DateTime> maturitiesWithin(List<ForecastAsset> assets, DateTime start, int months) {
    final end = monthEnd(start, months - 1);
    final result = <DateTime>[];
    for (final a in assets) {
      final m = a.maturity;
      if (a.kind == ForecastAssetKind.bond && m != null && m.isAfter(start) && !m.isAfter(end)) {
        result.add(m);
      }
    }
    result.sort();
    return result;
  }
}

class _AssetState {
  final ForecastAsset asset;
  final DateTime today;

  /// Бумаги сейчас, включая докупленные на выплаты.
  double units;

  /// Бумаги на сегодняшний день — от них считаются купоны, дивиденды и
  /// изменение цены в разбивке. Всё, что пришло с докупленных, относится к
  /// эффекту реинвестирования.
  final double origUnits;

  /// Деньги с выплат, которых пока не хватает на целую бумагу.
  double leftover = 0;

  bool alive = true;
  double remainingFace;

  /// Сколько номинала на одну бумагу уже вернулось частичными погашениями.
  /// Это возврат вложенного, а не доход: при подсчёте изменения цены к
  /// номиналу эти деньги считаются частью стоимости бумаги.
  double principalReturnedPerUnit = 0;

  /// Непогашенный номинал на момент погашения.
  double redeemedFace = 0;

  double _lastCoupon = 0;

  /// Купоны и погашения по возрастанию даты. Биржа отдаёт график в обратном
  /// порядке, а подстановка последнего известного купона флоатера требует
  /// идти от ранних к поздним.
  final List<CashEvent> _coupons;
  final List<CashEvent> _amortizations;

  _AssetState(this.asset, this.today)
      : units = asset.qty,
        origUnits = asset.qty,
        remainingFace = asset.face ?? 0,
        _coupons = [...asset.coupons]..sort((a, b) => a.date.compareTo(b.date)),
        _amortizations = [...asset.amortizations]..sort((a, b) => a.date.compareTo(b.date));

  bool get _hasBondModel =>
      asset.face != null && asset.face! > 0 && asset.maturity != null && asset.maturity!.isAfter(today);

  /// Цена облигации: доля от номинала линейно сходится от текущей к единице
  /// к дате погашения и умножается на непогашенный номинал.
  double bondPrice(DateTime date) {
    if (!_hasBondModel) return asset.price;
    final face0 = asset.face!;
    final ratio0 = asset.price / face0;
    final total = asset.maturity!.difference(today).inDays;
    final passed = date.difference(today).inDays;
    final frac = total <= 0 ? 1.0 : (passed / total).clamp(0.0, 1.0);
    final ratio = ratio0 + (1 - ratio0) * frac;
    return remainingFace * ratio;
  }

  /// Изменение стоимости исходных бумаг относительно покупки сегодня, с
  /// учётом уже вернувшегося номинала.
  double bondsToParOnOriginal(double pricePerUnitNow) =>
      origUnits * (pricePerUnitNow + principalReturnedPerUnit - asset.price);

  ({double cash, double origCoupons, bool matured}) stepBond(DateTime from, DateTime to) {
    double cash = 0;
    double orig = 0;

    for (final c in _coupons) {
      if (c.date.isAfter(from) && !c.date.isAfter(to)) {
        // Нулевой купон — не объявленный ещё купон флоатера. Считать его
        // нулём значило бы молча занизить прогноз.
        final perUnit = c.perUnit > 0 ? c.perUnit : _lastCoupon;
        if (c.perUnit > 0) _lastCoupon = c.perUnit;
        cash += units * perUnit;
        orig += origUnits * perUnit;
      } else if (!c.date.isAfter(from) && c.perUnit > 0) {
        _lastCoupon = c.perUnit;
      }
    }

    if (_hasBondModel) {
      for (final a in _amortizations) {
        if (a.date.isAfter(from) && !a.date.isAfter(to) && a.date.isBefore(asset.maturity!)) {
          final part = math.min(a.perUnit, remainingFace);
          remainingFace -= part;
          principalReturnedPerUnit += part;
          cash += units * part;
        }
      }

      final m = asset.maturity!;
      if (m.isAfter(from) && !m.isAfter(to)) {
        redeemedFace = remainingFace;
        cash += units * remainingFace;
        units = 0;
        alive = false;
        return (cash: cash, origCoupons: orig, matured: true);
      }
    }

    return (cash: cash, origCoupons: orig, matured: false);
  }

  ({double cash, double origDividends}) stepDividends(DateTime from, DateTime to, double factor) {
    double cash = 0;
    double orig = 0;
    for (final d in asset.dividendsLastYear) {
      // Выплата прошлого года повторяется в тот же день каждого следующего.
      for (int year = 1; year <= 60; year++) {
        final when = DateTime(d.date.year + year, d.date.month, d.date.day);
        if (when.isAfter(to)) break;
        if (!when.isAfter(from)) continue;
        final perUnit = d.perUnit * factor;
        cash += units * perUnit;
        orig += origUnits * perUnit;
      }
    }
    return (cash: cash, origDividends: orig);
  }

  /// Покупка целых бумаг на выплату; остаток ждёт следующей.
  void buy(double cash, double price) {
    leftover += cash;
    if (price <= 0) return;
    final whole = (leftover / price).floorToDouble();
    if (whole <= 0) return;
    units += whole;
    leftover -= whole * price;
  }
}
