import 'analytics_service.dart';
import 'cash_service.dart';
import 'currency_service.dart';
import 'sector_service.dart';
import 'storage_service.dart';

/// Строка отчёта по одной бумаге за год.
class ReportRow {
  final String ticker;
  final String name;
  final String sector;

  /// Было на начало года.
  final double qtyStart;

  /// Стало на конец года (или на сегодня, если год текущий).
  final double qtyEnd;

  final double boughtQty;
  final double boughtSumRub;
  final double soldQty;
  final double soldSumRub;

  /// Прибыль от продаж, закрытых в этом году.
  final double realizedRub;

  /// Полученные за год дивиденды и купоны.
  final double payoutsRub;

  /// Текущая стоимость позиции — только для бумаг, которые ещё в портфеле.
  final double valueRub;

  /// Незафиксированная прибыль по остатку.
  final double unrealizedRub;

  const ReportRow({
    required this.ticker,
    required this.name,
    required this.sector,
    required this.qtyStart,
    required this.qtyEnd,
    required this.boughtQty,
    required this.boughtSumRub,
    required this.soldQty,
    required this.soldSumRub,
    required this.realizedRub,
    required this.payoutsRub,
    required this.valueRub,
    required this.unrealizedRub,
  });

  /// Куплена ли бумага впервые в этом году.
  bool get isNew => qtyStart <= 1e-9 && boughtQty > 0;

  /// Позиция закрыта полностью.
  bool get isClosed => qtyEnd <= 1e-9;

  double get totalResultRub => realizedRub + payoutsRub + unrealizedRub;
}

/// Итоги года целиком.
class AnnualReport {
  final int year;
  final List<ReportRow> rows;

  final double boughtRub;
  final double soldRub;
  final double payoutsRub;
  final double realizedRub;
  final double taxPaidRub;

  /// Сколько своих денег пришло в портфель за год.
  final double investedRub;

  /// Рыночная стоимость бумаг на начало года.
  final double valueStartRub;

  /// Стоимость бумаг на конец периода.
  final double valueEndRub;

  /// Выплаты по месяцам — для графика.
  final Map<int, double> payoutsByMonth;

  /// Покупки по месяцам — для графика.
  final Map<int, double> boughtByMonth;

  /// Распределение текущей стоимости по секторам.
  final Map<String, double> bySector;

  const AnnualReport({
    required this.year,
    required this.rows,
    required this.boughtRub,
    required this.soldRub,
    required this.payoutsRub,
    required this.realizedRub,
    required this.taxPaidRub,
    required this.investedRub,
    required this.valueStartRub,
    required this.valueEndRub,
    required this.payoutsByMonth,
    required this.boughtByMonth,
    required this.bySector,
  });

  /// Бумаги, купленные впервые в этом году.
  List<ReportRow> get newRows => rows.where((r) => r.isNew).toList();

  /// Бумаги, которые были в портфеле и до этого года.
  List<ReportRow> get oldRows => rows.where((r) => !r.isNew).toList();

  /// Полный результат периода: изменение стоимости плюс чистые продажи,
  /// выплаты и покупки. В отличие от прежней формулы учитывает открытые позиции.
  double get totalResultRub =>
      valueEndRub + soldRub + payoutsRub - valueStartRub - boughtRub;

  /// Доходность за год: результат к средним вложениям. Считается только когда
  /// в портфеле вообще что-то было.
  double get yieldPct {
    // Modified Dietz без внутридневных весов — честнее прежнего деления
    // результата на стоимость в конце года. Для точного сравнения в приложении
    // отдельно показывается TWR.
    final base = valueStartRub + boughtRub * 0.5 - soldRub * 0.5;
    if (base <= 0) return 0;
    return totalResultRub / base * 100;
  }
}

/// Годовой отчёт: что покупалось и продавалось, что принесло выплаты и чем
/// закончился год по каждой бумаге.
class AnnualReportService {
  AnnualReportService._();

  /// Годы, за которые вообще есть данные.
  static List<int> availableYears() {
    final years = <int>{};
    for (final p in StorageService.purchases) {
      years.add(p.date.year);
    }
    for (final i in StorageService.incomes) {
      years.add(i.date.year);
    }
    if (years.isEmpty) years.add(DateTime.now().year);
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  static AnnualReport build(int year) {
    final from = DateTime(year);
    final to = DateTime(year + 1);

    final purchases = StorageService.purchases.toList()..sort(AnalyticsService.compareTrades);
    final incomes = StorageService.incomes;
    final now = DateTime.now();
    final isCurrentYear = year == now.year;
    final periodEnd = isCurrentYear ? now : to;
    final valuationDate =
        isCurrentYear ? now : DateTime(year, 12, 31, 23, 59, 59, 999);
    // Для текущего года отчёт должен сходиться с главным экраном и потому
    // использует те же актуальные онлайн/ручные котировки. Исторические годы
    // по-прежнему оцениваются строго на 31 декабря.
    final holdings = isCurrentYear
        ? AnalyticsService.currentHoldings()
        : AnalyticsService.holdingsAt(date: valuationDate);
    final startHoldings = AnalyticsService.holdingsAt(
      date: from.subtract(const Duration(microseconds: 1)),
    );

    // Количество на начало года считаем, прокручивая все сделки до 1 января.
    final qtyStart = <String, double>{};
    for (final p in purchases) {
      if (!p.date.isBefore(from)) continue;
      final q = qtyStart[p.ticker] ?? 0;
      qtyStart[p.ticker] = p.isSell ? (q - p.quantity).clamp(0, double.infinity) : q + p.quantity;
    }

    // Количество на конец периода: для прошедшего года — на 31 декабря, для
    // текущего — сегодняшнее.
    final qtyEnd = <String, double>{};
    for (final p in purchases) {
      if (p.date.isAfter(periodEnd)) continue;
      final q = qtyEnd[p.ticker] ?? 0;
      qtyEnd[p.ticker] = p.isSell ? (q - p.quantity).clamp(0, double.infinity) : q + p.quantity;
    }

    final names = <String, String>{};
    final bought = <String, double>{};
    final boughtSum = <String, double>{};
    final sold = <String, double>{};
    final soldSum = <String, double>{};
    final boughtByMonth = <int, double>{};

    for (final p in purchases) {
      names[p.ticker] = p.name.isNotEmpty ? p.name : p.ticker;
      if (p.date.isBefore(from) || p.date.isAfter(periodEnd)) continue;

      final sumRub = CurrencyService.toRub(
        p.quantity * p.pricePerUnit + (p.isSell ? -p.fee : p.fee),
        p.currency,
        date: p.date,
      );
      if (p.isSell) {
        sold[p.ticker] = (sold[p.ticker] ?? 0) + p.quantity;
        soldSum[p.ticker] = (soldSum[p.ticker] ?? 0) + sumRub;
      } else {
        bought[p.ticker] = (bought[p.ticker] ?? 0) + p.quantity;
        boughtSum[p.ticker] = (boughtSum[p.ticker] ?? 0) + sumRub;
        boughtByMonth[p.date.month] = (boughtByMonth[p.date.month] ?? 0) + sumRub;
      }
    }

    final payouts = <String, double>{};
    final payoutsByMonth = <int, double>{};
    double taxPaid = 0;
    for (final i in incomes) {
      if (i.date.isBefore(from) || i.date.isAfter(periodEnd)) continue;
      final rub = CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
      payouts[i.ticker] = (payouts[i.ticker] ?? 0) + rub;
      payoutsByMonth[i.date.month] = (payoutsByMonth[i.date.month] ?? 0) + rub;
      taxPaid += CurrencyService.toRub(i.taxPaid, i.currency, date: i.date);
      names[i.ticker] ??= i.name.isNotEmpty ? i.name : i.ticker;
    }

    // Реализованная прибыль по продажам этого года — методом ФИФО, тем же,
    // что и в остальном приложении.
    final realized = _realizedByTicker(purchases, from, periodEnd);

    final tickers = <String>{
      ...bought.keys,
      ...sold.keys,
      ...payouts.keys,
      ...qtyEnd.keys.where((t) => (qtyEnd[t] ?? 0) > 1e-9),
    };

    final rows = <ReportRow>[];
    for (final t in tickers) {
      final holding = holdings[t];
      final endQty = qtyEnd[t] ?? 0;
      rows.add(ReportRow(
        ticker: t,
        name: names[t] ?? t,
        sector: SectorService.sectorFor(t),
        qtyStart: qtyStart[t] ?? 0,
        qtyEnd: endQty,
        boughtQty: bought[t] ?? 0,
        boughtSumRub: boughtSum[t] ?? 0,
        soldQty: sold[t] ?? 0,
        soldSumRub: soldSum[t] ?? 0,
        realizedRub: realized[t] ?? 0,
        payoutsRub: payouts[t] ?? 0,
        valueRub: holding?.valueRub ?? 0,
        unrealizedRub: holding?.pnlRub ?? 0,
      ));
    }
    rows.sort((a, b) => b.valueRub.compareTo(a.valueRub));

    final bySector = <String, double>{};
    for (final r in rows) {
      if (r.valueRub <= 0) continue;
      bySector[r.sector] = (bySector[r.sector] ?? 0) + r.valueRub;
    }

    // Сколько своих денег добавлено за год — по тем же правилам, что и на
    // главной: пополнения, которые приложение определило по сделкам.
    final cash = CashService.summary();
    final investedThisYear = cash.moves
        .where((m) =>
            (m.kind == CashMoveKind.autoDeposit || m.kind == CashMoveKind.deposit) &&
            !m.date.isBefore(from) &&
            !m.date.isAfter(periodEnd))
        .fold(0.0, (sum, m) => sum + m.amountRub);

    return AnnualReport(
      year: year,
      rows: rows,
      boughtRub: boughtSum.values.fold(0.0, (a, b) => a + b),
      soldRub: soldSum.values.fold(0.0, (a, b) => a + b),
      payoutsRub: payouts.values.fold(0.0, (a, b) => a + b),
      realizedRub: realized.values.fold(0.0, (a, b) => a + b),
      taxPaidRub: taxPaid,
      investedRub: investedThisYear,
      valueStartRub:
          startHoldings.values.fold(0.0, (sum, holding) => sum + holding.valueRub),
      valueEndRub: rows.fold(0.0, (sum, r) => sum + r.valueRub),
      payoutsByMonth: payoutsByMonth,
      boughtByMonth: boughtByMonth,
      bySector: bySector,
    );
  }

  /// Прибыль от продаж внутри периода. Себестоимость списывается по средней —
  /// так же, как считается средняя цена позиции в остальном приложении.
  static Map<String, double> _realizedByTicker(List<dynamic> purchases, DateTime from, DateTime to) {
    final qty = <String, double>{};
    final costRub = <String, double>{};
    final realized = <String, double>{};

    for (final p in purchases) {
      final t = p.ticker as String;
      qty.putIfAbsent(t, () => 0);
      costRub.putIfAbsent(t, () => 0);

      if (p.isSell as bool) {
        final have = qty[t]!;
        if (have <= 1e-9) continue;
        final sellQty = (p.quantity as double) > have ? have : p.quantity as double;
        final avgCost = costRub[t]! / have;
        final proceeds = CurrencyService.toRub(
          sellQty * (p.pricePerUnit as double) - (p.fee as double),
          p.currency as String,
          date: p.date as DateTime,
        );
        final cost = sellQty * avgCost;
        if (!(p.date as DateTime).isBefore(from) && (p.date as DateTime).isBefore(to)) {
          realized[t] = (realized[t] ?? 0) + proceeds - cost;
        }
        qty[t] = have - sellQty;
        costRub[t] = costRub[t]! - cost;
      } else {
        qty[t] = qty[t]! + (p.quantity as double);
        costRub[t] = costRub[t]! +
            CurrencyService.toRub(
              (p.quantity as double) * (p.pricePerUnit as double) + (p.fee as double),
              p.currency as String,
              date: p.date as DateTime,
            );
      }
    }
    return realized;
  }
}
