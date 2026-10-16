import '../models/income.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'storage_service.dart';

/// Из чего сложилась прибыль за период — в целом и по каждой бумаге.
///
/// Части всегда в сумме дают ровно ту же прибыль, что на плитке «Прибыль»
/// (AnalyticsService.profitForPeriod):
/// рост цен + купоны + дивиденды − комиссии и НКД − налог с выплат.
class ProfitBreakdown {
  final double total;

  /// Бумага → переоценка и результат продаж за период.
  final Map<String, double> priceByTicker;

  /// Бумага → купоны / дивиденды до налога.
  final Map<String, double> couponsByTicker;
  final Map<String, double> dividendsByTicker;

  /// Бумага → комиссии брокера вместе с НКД облигаций (в отчёте брокера они
  /// идут одной суммой). Положительное число — расход.
  final Map<String, double> feesByTicker;

  /// Бумага → налог, удержанный с купонов и дивидендов.
  final Map<String, double> taxByTicker;

  /// Начало периода; null — неизвестно (нет сделок).
  final DateTime? from;

  const ProfitBreakdown({
    required this.total,
    required this.priceByTicker,
    required this.couponsByTicker,
    required this.dividendsByTicker,
    required this.feesByTicker,
    required this.taxByTicker,
    required this.from,
  });

  static double _sum(Map<String, double> m) => m.values.fold(0.0, (a, v) => a + v);

  double get priceGrowth => _sum(priceByTicker);
  double get coupons => _sum(couponsByTicker);
  double get dividends => _sum(dividendsByTicker);
  double get feesAndAccrued => _sum(feesByTicker);
  double get tax => _sum(taxByTicker);
}

class ProfitBreakdownService {
  ProfitBreakdownService._();

  static ProfitBreakdown forPeriod(PeriodFilter f) {
    final end = DateTime.now();
    final start = AnalyticsService.periodStart(f, now: end);
    final total = AnalyticsService.profitForPeriod(f);

    bool inPeriod(DateTime d) => (start == null || d.isAfter(start)) && !d.isAfter(end);
    String key(String t) => t.toUpperCase();
    void add(Map<String, double> m, String t, double v) => m[key(t)] = (m[key(t)] ?? 0) + v;

    final coupons = <String, double>{};
    final dividends = <String, double>{};
    final tax = <String, double>{};
    for (final i in StorageService.incomes) {
      if (!inPeriod(i.date)) continue;
      final gross = CurrencyService.toRub(i.amountGross, i.currency, date: i.date);
      final paid = CurrencyService.toRub(i.taxPaid, i.currency, date: i.date);
      add(i.type == IncomeType.coupon ? coupons : dividends, i.ticker, gross);
      if (paid.abs() > 0.005) add(tax, i.ticker, paid);
    }

    // Рост цен по бумаге: стоимость в конце − в начале + деньги от сделок
    // (продажи плюсом, покупки минусом) + комиссии, которые показываем
    // отдельной строкой. Так части по всем бумагам складываются ровно в
    // прибыль за период.
    final fees = <String, double>{};
    final price = <String, double>{};
    for (final p in StorageService.purchases) {
      if (!inPeriod(p.date)) continue;
      final amount = CurrencyService.toRub(p.settlementAmount, p.currency, date: p.date);
      add(price, p.ticker, p.isSell ? amount : -amount);
      final fee = CurrencyService.toRub(p.fee, p.currency, date: p.date);
      if (fee.abs() > 0.005) {
        add(fees, p.ticker, fee);
        add(price, p.ticker, fee);
      }
    }
    for (final e in AnalyticsService.currentHoldings().entries) {
      add(price, e.key, e.value.valueRub);
    }
    if (start != null) {
      for (final e in AnalyticsService.holdingsAt(date: start).entries) {
        add(price, e.key, -e.value.valueRub);
      }
    }
    price.removeWhere((_, v) => v.abs() < 0.5);

    // Погрешность округления курсов кладём в самую крупную строку, чтобы
    // итог буквально совпадал с плиткой «Прибыль».
    final parts = price.values.fold(0.0, (a, v) => a + v) +
        coupons.values.fold(0.0, (a, v) => a + v) +
        dividends.values.fold(0.0, (a, v) => a + v) -
        fees.values.fold(0.0, (a, v) => a + v) -
        tax.values.fold(0.0, (a, v) => a + v);
    final diff = total - parts;
    if (diff.abs() >= 0.5) {
      if (price.isEmpty) {
        price['—'] = diff;
      } else {
        final biggest = price.entries.reduce((a, b) => a.value.abs() >= b.value.abs() ? a : b).key;
        price[biggest] = price[biggest]! + diff;
      }
    }

    return ProfitBreakdown(
      total: total,
      priceByTicker: price,
      couponsByTicker: coupons,
      dividendsByTicker: dividends,
      feesByTicker: fees,
      taxByTicker: tax,
      from: start ?? _firstTradeDate(),
    );
  }

  static DateTime? _firstTradeDate() {
    DateTime? first;
    for (final p in StorageService.purchases) {
      if (first == null || p.date.isBefore(first)) first = p.date;
    }
    return first;
  }
}
