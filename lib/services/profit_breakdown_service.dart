import '../models/income.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'storage_service.dart';

/// Из чего сложилась прибыль за период.
///
/// Части всегда в сумме дают ровно ту же прибыль, что на плитке «Прибыль»
/// (AnalyticsService.profitForPeriod):
/// рост цен + купоны + дивиденды − комиссии и НКД − налог с выплат.
class ProfitBreakdown {
  final double total;

  /// Переоценка бумаг и результат продаж — всё, что не выплаты и не
  /// комиссии.
  final double priceGrowth;

  /// Купоны и дивиденды до налога.
  final double coupons;
  final double dividends;

  /// Комиссии брокера вместе с НКД облигаций: в отчёте брокера они идут одной
  /// суммой, и разделить их задним числом нельзя. Уплаченный при покупке НКД
  /// возвращается в ближайшем купоне.
  final double feesAndAccrued;

  /// Налог, удержанный с купонов и дивидендов.
  final double tax;

  /// Уже получено деньгами: выплаты после налога и результат продаж.
  final double inPocket;

  /// Остальное — рост того, что ещё держите.
  double get onPaper => total - inPocket;

  /// Начало периода; null — с первой сделки.
  final DateTime? from;

  const ProfitBreakdown({
    required this.total,
    required this.priceGrowth,
    required this.coupons,
    required this.dividends,
    required this.feesAndAccrued,
    required this.tax,
    required this.inPocket,
    required this.from,
  });
}

class ProfitBreakdownService {
  ProfitBreakdownService._();

  static ProfitBreakdown forPeriod(PeriodFilter f) {
    final end = DateTime.now();
    final start = AnalyticsService.periodStart(f, now: end);
    final total = AnalyticsService.profitForPeriod(f);

    bool inPeriod(DateTime d) => (start == null || d.isAfter(start)) && !d.isAfter(end);

    double coupons = 0, dividends = 0, tax = 0;
    for (final i in StorageService.incomes) {
      if (!inPeriod(i.date)) continue;
      final gross = CurrencyService.toRub(i.amountGross, i.currency, date: i.date);
      final paid = CurrencyService.toRub(i.taxPaid, i.currency, date: i.date);
      if (i.type == IncomeType.coupon) {
        coupons += gross;
      } else {
        dividends += gross;
      }
      tax += paid;
    }

    double fees = 0;
    for (final p in StorageService.purchases) {
      if (!inPeriod(p.date)) continue;
      fees += CurrencyService.toRub(p.fee, p.currency, date: p.date);
    }

    final payoutsNet = coupons + dividends - tax;
    // Всё остальное — изменение цен (включая результат продаж). Комиссии в
    // прибыли уже вычтены, поэтому возвращаем их сюда, чтобы показать
    // отдельной строкой.
    final price = total - payoutsNet + fees;

    return ProfitBreakdown(
      total: total,
      priceGrowth: price,
      coupons: coupons,
      dividends: dividends,
      feesAndAccrued: fees,
      tax: tax,
      inPocket: payoutsNet + realizedPnlRub(from: start, to: end),
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

  /// Результат продаж за период по средней цене входа — тот же метод, что в
  /// AnalyticsService.totalRealizedPnlRub, только продажи берутся из периода.
  static double realizedPnlRub({DateTime? from, DateTime? to}) {
    final purchases = [...StorageService.purchases]..sort(AnalyticsService.compareTrades);
    final qty = <String, double>{};
    final costBasisRub = <String, double>{};
    double realized = 0;
    for (final p in purchases) {
      final t = p.ticker;
      qty.putIfAbsent(t, () => 0);
      costBasisRub.putIfAbsent(t, () => 0);
      if (p.isSell) {
        final curQty = qty[t]!;
        final sellQty = p.quantity > curQty ? curQty : p.quantity;
        if (curQty > 0) {
          final avg = costBasisRub[t]! / curQty;
          final cost = sellQty * avg;
          final counted = (from == null || p.date.isAfter(from)) && (to == null || !p.date.isAfter(to));
          if (counted) {
            final proceeds = CurrencyService.toRub(sellQty * p.pricePerUnit - p.fee, p.currency, date: p.date);
            realized += proceeds - cost;
          }
          costBasisRub[t] = costBasisRub[t]! - cost;
        }
        final newQty = curQty - sellQty;
        qty[t] = newQty < 0 ? 0 : newQty;
      } else {
        costBasisRub[t] = costBasisRub[t]! +
            CurrencyService.toRub(p.quantity * p.pricePerUnit + p.fee, p.currency, date: p.date);
        qty[t] = qty[t]! + p.quantity;
      }
    }
    return realized;
  }
}
