import '../models/income.dart';
import '../models/purchase.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'memo.dart';
import 'storage_service.dart';

/// Какие выплаты считать.
enum PayoutKind { all, dividends, coupons }

/// Доходность выплат одной бумаги.
class PayoutYieldRow {
  final String ticker;
  final bool isBond;

  /// Пришло за 12 месяцев, ₽ после налога.
  final double income;

  /// Сколько потрачено на нынешнюю позицию, ₽.
  final double cost;

  /// Сколько позиция стоит сейчас, ₽.
  final double value;

  const PayoutYieldRow({
    required this.ticker,
    required this.isBond,
    required this.income,
    required this.cost,
    required this.value,
  });

  double get toCost => cost > 0 ? income / cost * 100 : 0;
  double get toValue => value > 0 ? income / value * 100 : 0;
}

/// Доходность выплат портфеля: сколько процентов в год вложенные деньги
/// приносят живыми деньгами на счёт.
class PayoutYieldSummary {
  final double income;
  final double cost;
  final double value;

  /// Доходность за прошлый календарный год. null — данных нет.
  final double? lastYear;
  final int lastYearNumber;

  /// Пришло по годам, ₽ после налога.
  final Map<int, double> byYear;

  /// По бумагам, от большей доходности к меньшей.
  final List<PayoutYieldRow> rows;

  /// Бумаги без выплат за 12 месяцев — в расчёт не входят.
  final List<String> without;

  const PayoutYieldSummary({
    required this.income,
    required this.cost,
    required this.value,
    required this.lastYear,
    required this.lastYearNumber,
    required this.byYear,
    required this.rows,
    required this.without,
  });

  double? get toCost => cost > 0 && income > 0 ? income / cost * 100 : null;
  double? get toValue => value > 0 && income > 0 ? income / value * 100 : null;
}

class PayoutYieldService {
  PayoutYieldService._();

  static PayoutYieldSummary summary(PayoutKind kind) => Memo.get('payoutYield:${kind.name}', () => _summary(kind));

  static bool _fits(PayoutKind kind, bool isBond) => switch (kind) {
        PayoutKind.all => true,
        PayoutKind.dividends => !isBond,
        PayoutKind.coupons => isBond,
      };

  static PayoutYieldSummary _summary(PayoutKind kind) {
    final now = DateTime.now();
    final from = DateTime(now.year - 1, now.month, now.day);
    final bondTickers = <String>{
      for (final p in StorageService.purchases)
        if (p.type == AssetType.bond) p.ticker,
    };
    bool isBond(String t) => bondTickers.contains(t);
    bool incomeIsBond(Income i) => i.type == IncomeType.coupon || isBond(i.ticker);

    final income12 = <String, double>{};
    final byYear = <int, double>{};
    final prevYearIncome = <String, double>{};
    final prevYear = now.year - 1;
    for (final i in StorageService.incomes) {
      if (!_fits(kind, incomeIsBond(i))) continue;
      final rub = CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
      byYear[i.date.year] = (byYear[i.date.year] ?? 0) + rub;
      if (i.date.isAfter(from)) income12[i.ticker] = (income12[i.ticker] ?? 0) + rub;
      if (i.date.year == prevYear) prevYearIncome[i.ticker] = (prevYearIncome[i.ticker] ?? 0) + rub;
    }

    final rows = <PayoutYieldRow>[];
    final without = <String>[];
    double income = 0, cost = 0, value = 0;
    AnalyticsService.currentHoldings().forEach((t, h) {
      if (h.qty <= 1e-9 || !_fits(kind, isBond(t))) return;
      final got = income12[t] ?? 0;
      if (got <= 0) {
        without.add(t);
        return;
      }
      rows.add(PayoutYieldRow(ticker: t, isBond: isBond(t), income: got, cost: h.costBasisRub, value: h.valueRub));
      income += got;
      cost += h.costBasisRub;
      value += h.valueRub;
    });
    rows.sort((a, b) => b.toCost.compareTo(a.toCost));

    // Прошлый год: выплаты года к деньгам, вложенным в эти бумаги на его конец.
    double? lastYear;
    if (prevYearIncome.isNotEmpty) {
      final atEnd = AnalyticsService.holdingsAt(date: DateTime(prevYear, 12, 31, 23, 59, 59));
      double got = 0, base = 0;
      prevYearIncome.forEach((t, rub) {
        final h = atEnd[t];
        if (h == null || h.costBasisRub <= 0) return;
        got += rub;
        base += h.costBasisRub;
      });
      if (base > 0) lastYear = got / base * 100;
    }

    return PayoutYieldSummary(
      income: income,
      cost: cost,
      value: value,
      lastYear: lastYear,
      lastYearNumber: prevYear,
      byYear: byYear,
      rows: rows,
      without: without,
    );
  }
}
