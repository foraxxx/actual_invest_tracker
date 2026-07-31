import '../models/purchase.dart';
import '../models/income.dart';
import 'storage_service.dart';
import 'currency_service.dart';
import 'manual_price_service.dart';
import 'online_price_service.dart';
import 'online_settings_service.dart';
import 'sector_service.dart';
import 'cash_service.dart';
import 'financial_math.dart';

/// Фильтр периода для статистики
enum PeriodFilter { month1, month3, month6, year1, all }

/// Текущая позиция по бумаге: количество, средняя цена входа, последняя цена сделки,
/// стоимость сейчас и прибыль/убыток (в рублях — базовой валюте статистики)
class HoldingInfo {
  final double qty;
  final double avgCost;
  final double lastPrice; // цена последней сделки (покупки/продажи)
  final double displayPrice; // цена, используемая для оценки стоимости — ручная, если задана, иначе lastPrice
  final bool hasManualPrice;
  final String currency;
  final double costBasisRub;
  final double valueRub;

  HoldingInfo({
    required this.qty,
    required this.avgCost,
    required this.lastPrice,
    required this.displayPrice,
    required this.hasManualPrice,
    required this.currency,
    required this.costBasisRub,
    required this.valueRub,
  });

  double get pnlRub => valueRub - costBasisRub;
  double get pnlPct => costBasisRub == 0 ? 0 : (pnlRub / costBasisRub) * 100;
}

/// Изменение стоимости "замороженного" на начало периода состава портфеля:
/// берём тикеры и количество, которые были на начало периода, и сравниваем
/// их оценку по ценам на тот момент и по сегодняшним ценам. Покупки/продажи,
/// сделанные ВНУТРИ периода, на это число не влияют — это чистая переоценка.
class PeriodChange {
  final double valueStart;
  final double valueEnd;
  final double changeAbs;
  final double changePct;

  const PeriodChange({
    required this.valueStart,
    required this.valueEnd,
    required this.changeAbs,
    required this.changePct,
  });
}

/// Проекция дохода по бумаге на ближайшие 12 мес — по факту фактических
/// выплат за прошлые 365 дней, приведённая к сегодняшнему количеству. Не
/// гарантия: реальные будущие выплаты могут быть как выше, так и ниже.
class DividendForecast {
  final String ticker;
  final double last12mRub; // прогноз в рублях на след. 12 мес
  final double yieldPct; // = last12mRub / текущая стоимость позиции * 100
  final bool hasHistory; // были ли вообще выплаты за последние 365 дней

  const DividendForecast({
    required this.ticker,
    required this.last12mRub,
    required this.yieldPct,
    required this.hasHistory,
  });
}

class AnalyticsService {
  /// Порядок сделок для всех расчётов.
  ///
  /// Сортировки только по дате мало: сортировка в Dart неустойчива, и сделки
  /// одного дня могли перемешаться. Если продажа оказывалась раньше покупки,
  /// продавать было нечего — количество обрезалось, и в портфеле навсегда
  /// оставались «призраки» уже проданных бумаг. Поэтому при равном времени
  /// покупка всегда идёт первой.
  static int compareTrades(Purchase a, Purchase b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    if (a.isSell == b.isSell) return a.id.compareTo(b.id);
    return a.isSell ? 1 : -1;
  }

  /// Актуальная цена бумаги из сети — если загрузка с биржи включена и
  /// котировка по этой бумаге есть. Когда онлайн выключен, метод всегда
  /// возвращает null, и оценка портфеля считается ровно как раньше.
  ///
  /// Приоритет: биржа → ручная цена → цена последней сделки. Ручная цена
  /// остаётся запасным вариантом для того, что на бирже не торгуется.
  static double? priceFor(String ticker) {
    if (!OnlineSettingsService.enabled) return null;
    return OnlinePriceService.get(ticker)?.price;
  }

  static DateTime? _periodStart(PeriodFilter f, {DateTime? now}) {
    final current = now ?? DateTime.now();
    switch (f) {
      case PeriodFilter.month1:
        return DateTime(current.year, current.month - 1, current.day);
      case PeriodFilter.month3:
        return DateTime(current.year, current.month - 3, current.day);
      case PeriodFilter.month6:
        return DateTime(current.year, current.month - 6, current.day);
      case PeriodFilter.year1:
        return DateTime(current.year - 1, current.month, current.day);
      case PeriodFilter.all:
        return null;
    }
  }

  static List<Purchase> filterPurchases(PeriodFilter f, {AssetType? type, String? sector}) {
    final start = _periodStart(f);
    return StorageService.purchases.where((p) {
      final okDate = start == null || p.date.isAfter(start);
      final okType = type == null || p.type == type;
      final okSector = sector == null || p.sector == sector;
      return okDate && okType && okSector;
    }).toList()
      ..sort(compareTrades);
  }

  static List<Income> filterIncomes(PeriodFilter f, {IncomeType? type}) {
    final start = _periodStart(f);
    return StorageService.incomes.where((i) {
      final okDate = start == null || i.date.isAfter(start);
      final okType = type == null || i.type == type;
      return okDate && okType;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  static double totalInvested({PeriodFilter f = PeriodFilter.all}) {
    double sum = 0;
    for (final p in filterPurchases(f)) {
      final amountRub =
          CurrencyService.toRub(p.settlementAmount, p.currency, date: p.date);
      sum += p.isSell ? -amountRub : amountRub;
    }
    return sum;
  }

  static double totalIncome({PeriodFilter f = PeriodFilter.all}) {
    double sum = 0;
    for (final i in filterIncomes(f)) {
      sum += CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
    }
    return sum;
  }

  /// Полный финансовый результат за период: переоценка бумаг, результат
  /// продаж, комиссии и фактически полученные выплаты. Покупки и продажи
  /// учитываются как денежные потоки, поэтому новые вложения не становятся
  /// прибылью сами по себе.
  static double profitForPeriod(PeriodFilter f, {DateTime? now}) {
    final end = now ?? DateTime.now();
    final start = _periodStart(f, now: end);
    final startValue = start == null
        ? 0.0
        : holdingsAt(date: start).values.fold(0.0, (sum, holding) => sum + holding.valueRub);
    final endValue = now == null
        ? currentPortfolioValueRub()
        : holdingsAt(date: end).values.fold(0.0, (sum, holding) => sum + holding.valueRub);

    double tradeFlows = 0;
    for (final trade in StorageService.purchases) {
      if (start != null && !trade.date.isAfter(start)) continue;
      if (trade.date.isAfter(end)) continue;
      final amount = CurrencyService.toRub(
        trade.settlementAmount,
        trade.currency,
        date: trade.date,
      );
      tradeFlows += trade.isSell ? amount : -amount;
    }

    double payouts = 0;
    for (final income in StorageService.incomes) {
      if (start != null && !income.date.isAfter(start)) continue;
      if (income.date.isAfter(end)) continue;
      payouts += CurrencyService.toRub(income.amountNet, income.currency, date: income.date);
    }
    return endValue - startValue + tradeFlows + payouts;
  }

  static Map<AssetType, double> investedByType({PeriodFilter f = PeriodFilter.all}) {
    final map = <AssetType, double>{};
    for (final p in filterPurchases(f)) {
      final amount =
          CurrencyService.toRub(p.settlementAmount, p.currency, date: p.date);
      map[p.type] = (map[p.type] ?? 0) + (p.isSell ? -amount : amount);
    }
    map.removeWhere((_, v) => v <= 0);
    return map;
  }

  static Map<String, double> investedBySector({PeriodFilter f = PeriodFilter.all}) {
    final map = <String, double>{};
    for (final p in filterPurchases(f)) {
      final key = p.sector?.isNotEmpty == true ? p.sector! : 'Без сектора';
      final amount =
          CurrencyService.toRub(p.settlementAmount, p.currency, date: p.date);
      map[key] = (map[key] ?? 0) + (p.isSell ? -amount : amount);
    }
    map.removeWhere((_, v) => v <= 0);
    return map;
  }

  static Map<String, double> incomeByMonth({PeriodFilter f = PeriodFilter.year1, IncomeType? type}) {
    final map = <String, double>{};
    for (final i in filterIncomes(f, type: type)) {
      final key = '${i.date.year}-${i.date.month.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
    }
    return map;
  }

  static Map<String, HoldingInfo> currentHoldings() {
    return holdingsAt();
  }

  /// Состояние позиций на конец [date]. Если дата не передана, используется
  /// текущая оценка, включая онлайн-котировку. Для исторического среза цена и
  /// валютный курс берутся не позднее указанной даты.
  static Map<String, HoldingInfo> holdingsAt({DateTime? date}) {
    final purchases = [...StorageService.purchases]..sort(compareTrades);

    final qty = <String, double>{};
    final costBasis = <String, double>{}; // в валюте бумаги — для отображения средней цены
    final costBasisRub = <String, double>{}; // в рублях, по курсу на дату каждой сделки — для честного P&L
    final lastPrice = <String, double>{};
    final currencyOf = <String, String>{};

    for (final p in purchases) {
      if (date != null && p.date.isAfter(date)) continue;
      final t = p.ticker;
      qty.putIfAbsent(t, () => 0);
      costBasis.putIfAbsent(t, () => 0);
      costBasisRub.putIfAbsent(t, () => 0);
      currencyOf[t] = p.currency;
      lastPrice[t] = p.pricePerUnit;

      if (p.isSell) {
        final curQty = qty[t]!;
        final sellQty = p.quantity > curQty ? curQty : p.quantity;
        if (curQty > 0) {
          final avgCostPerUnit = costBasis[t]! / curQty;
          final avgCostRubPerUnit = costBasisRub[t]! / curQty;
          costBasis[t] = costBasis[t]! - sellQty * avgCostPerUnit;
          costBasisRub[t] = costBasisRub[t]! - sellQty * avgCostRubPerUnit;
        }
        final newQty = curQty - sellQty;
        qty[t] = newQty < 0 ? 0 : newQty;
      } else {
        costBasis[t] = costBasis[t]! + p.quantity * p.pricePerUnit + p.fee;
        costBasisRub[t] = costBasisRub[t]! +
            CurrencyService.toRub(p.quantity * p.pricePerUnit + p.fee, p.currency, date: p.date);
        qty[t] = qty[t]! + p.quantity;
      }
    }

    final result = <String, HoldingInfo>{};
    qty.forEach((ticker, q) {
      if (q <= 1e-9) return;
      final cur = currencyOf[ticker] ?? 'RUB';
      final avgCost = costBasis[ticker]! / q;
      final lastPx = lastPrice[ticker] ?? avgCost;
      final manualPx = date == null
          ? ManualPriceService.get(ticker)
          : ManualPriceService.priceAt(ticker, date);
      final displayPx =
          date == null ? (priceFor(ticker) ?? manualPx ?? lastPx) : (manualPx ?? lastPx);
      result[ticker] = HoldingInfo(
        qty: q,
        avgCost: avgCost,
        lastPrice: lastPx,
        displayPrice: displayPx,
        hasManualPrice: manualPx != null,
        currency: cur,
        costBasisRub: costBasisRub[ticker]!,
        valueRub: CurrencyService.toRub(q * displayPx, cur, date: date),
      );
    });
    return result;
  }

  /// Реализованная прибыль/убыток по всем продажам за всё время — то, что
  /// НЕ входит в totalUnrealizedPnlRub (он считается только по открытым
  /// сейчас позициям). Метод учёта — средняя цена входа на момент продажи,
  /// тот же, что и в currentHoldings(), чтобы реализованная и нереализованная
  /// прибыль честно складывались в одну "Общую прибыль".
  ///
  /// Отдельно от TaxService: там для расчёта налога/ЛДВ используется FIFO по
  /// лотам (это важно для корректного налогового учёта), поэтому число здесь
  /// может немного отличаться от "реализованного результата" в налоговом
  /// разделе — оба варианта корректны, это просто два разных метода учёта.
  static double totalRealizedPnlRub() {
    final purchases = [...StorageService.purchases]..sort(compareTrades);

    final qty = <String, double>{};
    final costBasisRub = <String, double>{};
    double realizedRub = 0;

    for (final p in purchases) {
      final t = p.ticker;
      qty.putIfAbsent(t, () => 0);
      costBasisRub.putIfAbsent(t, () => 0);

      if (p.isSell) {
        final curQty = qty[t]!;
        final sellQty = p.quantity > curQty ? curQty : p.quantity;
        if (curQty > 0) {
          final avgCostRubPerUnit = costBasisRub[t]! / curQty;
          final proceedsRub =
              CurrencyService.toRub(sellQty * p.pricePerUnit - p.fee, p.currency, date: p.date);
          final costOfSoldRub = sellQty * avgCostRubPerUnit;
          realizedRub += proceedsRub - costOfSoldRub;
          costBasisRub[t] = costBasisRub[t]! - costOfSoldRub;
        }
        final newQty = curQty - sellQty;
        qty[t] = newQty < 0 ? 0 : newQty;
      } else {
        costBasisRub[t] = costBasisRub[t]! +
            CurrencyService.toRub(p.quantity * p.pricePerUnit + p.fee, p.currency, date: p.date);
        qty[t] = qty[t]! + p.quantity;
      }
    }

    return realizedRub;
  }

  /// Стоимость текущих (не проданных полностью) позиций по секторам, в рублях.
  /// Секторы берутся из SectorService (ручная привязка > справочник > "Без сектора").
  static Map<String, double> currentValueBySector() {
    final holdings = currentHoldings();
    final map = <String, double>{};
    holdings.forEach((ticker, h) {
      final sector = SectorService.sectorFor(ticker);
      map[sector] = (map[sector] ?? 0) + h.valueRub;
    });
    return map;
  }

  /// Стоимость текущих позиций по каждой отдельной бумаге, в рублях
  static Map<String, double> currentValueByTicker() {
    final holdings = currentHoldings();
    final map = <String, double>{};
    holdings.forEach((ticker, h) => map[ticker] = h.valueRub);
    return map;
  }

  static double currentPortfolioValueRub() =>
      currentHoldings().values.fold(0.0, (s, h) => s + h.valueRub);

  static double totalUnrealizedPnlRub() =>
      currentHoldings().values.fold(0.0, (s, h) => s + h.pnlRub);

  static double topHoldingConcentrationPct() {
    final holdings = currentHoldings();
    if (holdings.isEmpty) return 0;
    final total = holdings.values.fold(0.0, (s, h) => s + h.valueRub);
    if (total <= 0) return 0;
    final maxValue = holdings.values.map((h) => h.valueRub).reduce((a, b) => a > b ? a : b);
    return (maxValue / total) * 100;
  }

  static String? topHoldingTicker() {
    final holdings = currentHoldings();
    if (holdings.isEmpty) return null;
    String? best;
    double bestValue = -1;
    holdings.forEach((ticker, h) {
      if (h.valueRub > bestValue) {
        bestValue = h.valueRub;
        best = ticker;
      }
    });
    return best;
  }

  /// Чистое изменение стоимости портфеля за период, БЕЗ учёта новых покупок
  /// и продаж, сделанных внутри периода: состав (тикер → количество) на
  /// начало периода фиксируется, и этот же набор оценивается по ценам на
  /// начало периода и по сегодняшним. Для PeriodFilter.all возвращает null —
  /// там нет "состава на начало", с которым можно сравнивать (для всего
  /// времени такую роль уже играет "Общая прибыль").
  static PeriodChange? portfolioChangeForPeriod(PeriodFilter f) {
    final start = _periodStart(f);
    if (start == null) return null;

    final purchasesSorted = [...StorageService.purchases]..sort(compareTrades);

    // Состав портфеля на начало периода: количество и последняя известная
    // на тот момент цена/валюта каждого тикера.
    final qtyAtStart = <String, double>{};
    final priceAtStart = <String, double>{};
    final currencyOf = <String, String>{};
    for (final p in purchasesSorted) {
      if (p.date.isAfter(start)) break;
      final newQty = (qtyAtStart[p.ticker] ?? 0) + p.signedQuantity;
      qtyAtStart[p.ticker] = newQty < 0 ? 0 : newQty;
      priceAtStart[p.ticker] = p.pricePerUnit;
      currencyOf[p.ticker] = p.currency;
    }

    // Последняя цена сделки ПОСЛЕ начала периода на тикер — пригодится для
    // бумаг, которые к сегодняшнему дню уже полностью проданы: их сегодняшней
    // "рыночной" оценки в currentHoldings() уже нет, но известна цена продажи.
    final lastPriceAfterStart = <String, double>{};
    for (final p in purchasesSorted) {
      if (p.date.isAfter(start)) {
        lastPriceAfterStart[p.ticker] = p.pricePerUnit;
      }
    }

    final holdingsToday = currentHoldings();

    double valueStart = 0;
    double valueEnd = 0;
    qtyAtStart.forEach((ticker, q) {
      if (q <= 1e-9) return;
      final cur = currencyOf[ticker] ?? 'RUB';
      // Приоритет — реально сохранённая ручная цена на начало периода (или
      // ближайшую дату до него); если пользователь её не вводил, откатываемся
      // к цене последней сделки на тот момент (старое приближение).
      final priceStart = ManualPriceService.priceAt(ticker, start) ?? priceAtStart[ticker] ?? 0;
      valueStart += CurrencyService.toRub(q * priceStart, cur, date: start);

      final holdingNow = holdingsToday[ticker];
      final priceEnd = holdingNow?.displayPrice ?? lastPriceAfterStart[ticker] ?? priceStart;
      valueEnd += CurrencyService.toRub(q * priceEnd, cur);
    });

    if (valueStart <= 0) return null;
    final changeAbs = valueEnd - valueStart;
    final changePct = (changeAbs / valueStart) * 100;
    return PeriodChange(valueStart: valueStart, valueEnd: valueEnd, changeAbs: changeAbs, changePct: changePct);
  }

  static List<MapEntry<DateTime, double>> portfolioValueTimeline() {
    if (StorageService.purchases.isEmpty) return [];
    final dates = <DateTime>{};
    for (final p in StorageService.purchases) {
      dates.add(DateTime(p.date.year, p.date.month, p.date.day, 23, 59, 59));
    }
    for (final history in ManualPriceService.allHistory.values) {
      for (final point in history) {
        dates.add(DateTime(
          point.date.year,
          point.date.month,
          point.date.day,
          23,
          59,
          59,
        ));
      }
    }
    dates.add(DateTime.now());
    final sorted = dates.toList()..sort();
    return [
      for (final date in sorted)
        MapEntry(
          date,
          holdingsAt(date: date).values.fold(0.0, (sum, h) => sum + h.valueRub),
        ),
    ];
  }

  static List<({DateTime date, double price, bool isSell})> priceHistoryForTicker(String ticker) {
    final list = StorageService.purchases
        .where((p) => p.ticker == ticker)
        .map((p) => (date: p.date, price: p.pricePerUnit, isSell: p.isSell))
        .toList()
      // Здесь список не сделок, а точек цены — хватает сортировки по времени.
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  static List<String> allOwnedTickers() {
    final set = <String>{};
    for (final p in StorageService.purchases) {
      set.add(p.ticker);
    }
    final list = set.toList()..sort();
    return list;
  }

  static double? xirrPercent() {
    final flows = <DatedCashFlow>[];

    for (final p in StorageService.purchases) {
      final amountRub =
          CurrencyService.toRub(p.settlementAmount, p.currency, date: p.date);
      flows.add(DatedCashFlow(p.date, p.isSell ? amountRub : -amountRub));
    }
    for (final i in StorageService.incomes) {
      flows.add(DatedCashFlow(
        i.date,
        CurrencyService.toRub(i.amountNet, i.currency, date: i.date),
      ));
    }

    final currentValue = currentPortfolioValueRub();
    if (currentValue > 0) {
      flows.add(DatedCashFlow(DateTime.now(), currentValue));
    }
    return FinancialMath.xirrPercent(flows);
  }

  /// Time-weighted return: доходность самого портфеля без влияния размера и
  /// времени внешних пополнений/выводов. Денежный остаток входит в стоимость
  /// счёта; сделки и выплаты считаются внутренними движениями.
  static double? twrPercent() {
    final cash = CashService.summary();
    final dates = <DateTime>{
      ...StorageService.purchases.map((p) => p.date),
      ...StorageService.incomes.map((i) => i.date),
      ...StorageService.deposits.map((d) => d.date),
      for (final h in ManualPriceService.allHistory.values) ...h.map((p) => p.date),
      DateTime.now(),
    }.toList()
      ..sort();
    if (dates.length < 2) return null;

    double cashAt(DateTime date) => cash.moves
        .where((m) => !m.date.isAfter(date))
        .fold(0.0, (sum, m) => sum + m.amountRub);
    double accountAt(DateTime date) =>
        holdingsAt(date: date).values.fold(0.0, (sum, h) => sum + h.valueRub) +
        cashAt(date);

    final periods = <TwrPeriod>[];
    var previousDate = dates.first;
    var previousValue = accountAt(previousDate);
    for (final date in dates.skip(1)) {
      final endValue = accountAt(date);
      final externalFlow = cash.moves
          .where((m) =>
              m.date.isAfter(previousDate) &&
              !m.date.isAfter(date) &&
              (m.kind == CashMoveKind.deposit ||
                  m.kind == CashMoveKind.withdrawal ||
                  m.kind == CashMoveKind.autoDeposit))
          .fold(0.0, (sum, m) => sum + m.amountRub);
      if (previousValue > 1e-9) {
        periods.add(TwrPeriod(
          startValue: previousValue,
          endValue: endValue,
          externalFlow: externalFlow,
        ));
      }
      previousDate = date;
      previousValue = endValue;
    }
    return FinancialMath.twrPercent(periods);
  }

  /// Прогноз дохода на бумагу за 12 мес — НЕ гарантия, а честная проекция
  /// по факту фактических выплат за последние 365 дней, приведённая к
  /// сегодняшнему количеству бумаг в портфеле (а не к сумме, которая была
  /// выплачена тогда — количество бумаг могло меняться). Работает полностью
  /// офлайн: использует только уже введённые вручную дивиденды/купоны.
  static Map<String, DividendForecast> dividendForecastByTicker() {
    final holdings = currentHoldings();
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final purchasesSorted = [...StorageService.purchases]..sort(compareTrades);
    final incomesSorted = [...StorageService.incomes]..sort((a, b) => a.date.compareTo(b.date));

    // Сколько бумаг данного тикера было в портфеле на конкретную дату —
    // нужно, чтобы вычислить выплату "на одну бумагу" в момент каждой
    // исторической выплаты (общая сумма сама по себе не годится для
    // проекции на сегодняшнее, другое, количество).
    double qtyAt(String ticker, DateTime date) {
      double q = 0;
      for (final p in purchasesSorted) {
        if (p.ticker != ticker) continue;
        if (p.date.isAfter(date)) break;
        q += p.signedQuantity;
      }
      return q < 0 ? 0 : q;
    }

    final result = <String, DividendForecast>{};
    holdings.forEach((ticker, holding) {
      final relevant = incomesSorted.where((i) => i.ticker == ticker && i.date.isAfter(cutoff));
      double projectedRub = 0;
      bool hasHistory = false;
      for (final inc in relevant) {
        final qAtIncome = qtyAt(ticker, inc.date);
        if (qAtIncome <= 1e-9) continue; // выплата была до того, как бумага появилась в портфеле — пропускаем
        final perShare = inc.amountNet / qAtIncome;
        projectedRub += CurrencyService.toRub(perShare * holding.qty, inc.currency);
        hasHistory = true;
      }
      final yieldPct = holding.valueRub > 0 ? (projectedRub / holding.valueRub) * 100 : 0.0;
      result[ticker] = DividendForecast(
        ticker: ticker,
        last12mRub: projectedRub,
        yieldPct: yieldPct,
        hasHistory: hasHistory,
      );
    });
    return result;
  }

  /// Суммарный прогноз дохода по всему портфелю за 12 мес (по факту прошлых выплат).
  static double totalDividendForecastRub() =>
      dividendForecastByTicker().values.fold(0.0, (s, f) => s + f.last12mRub);

  /// Текущая стоимость и суммарная прибыль (нереализованная + реализованная +
  /// доход) для явно переданных списков сделок/доходов — в отличие от
  /// большинства методов выше, не привязан к текущему активному портфелю.
  /// Используется на странице со списком портфелей, чтобы посчитать
  /// статистику для КАЖДОГО портфеля, включая неактивные сейчас, не трогая
  /// состояние StorageService.
  static ({double valueRub, double profitRub}) summaryFor({
    required List<Purchase> purchases,
    required List<Income> incomes,
  }) {
    final sorted = [...purchases]..sort(compareTrades);

    final qty = <String, double>{};
    final costBasisRub = <String, double>{};
    final lastPrice = <String, double>{};
    final currencyOf = <String, String>{};
    double realizedRub = 0;

    for (final p in sorted) {
      final t = p.ticker;
      qty.putIfAbsent(t, () => 0);
      costBasisRub.putIfAbsent(t, () => 0);
      currencyOf[t] = p.currency;
      lastPrice[t] = p.pricePerUnit;

      if (p.isSell) {
        final curQty = qty[t]!;
        if (curQty > 0) {
          final avgCostRubPerUnit = costBasisRub[t]! / curQty;
          final sellQty = p.quantity > curQty ? curQty : p.quantity;
          final proceedsRub =
              CurrencyService.toRub(sellQty * p.pricePerUnit - p.fee, p.currency, date: p.date);
          final costOfSoldRub = sellQty * avgCostRubPerUnit;
          realizedRub += proceedsRub - costOfSoldRub;
          costBasisRub[t] = costBasisRub[t]! - costOfSoldRub;
        }
        final newQty = curQty - p.quantity;
        qty[t] = newQty < 0 ? 0 : newQty;
      } else {
        costBasisRub[t] = costBasisRub[t]! +
            CurrencyService.toRub(p.quantity * p.pricePerUnit + p.fee, p.currency, date: p.date);
        qty[t] = qty[t]! + p.quantity;
      }
    }

    double valueRub = 0;
    double unrealizedRub = 0;
    qty.forEach((ticker, q) {
      if (q <= 1e-9) return;
      final cur = currencyOf[ticker] ?? 'RUB';
      final lastPx = lastPrice[ticker] ?? 0;
      final manualPx = ManualPriceService.get(ticker);
      final displayPx = priceFor(ticker) ?? manualPx ?? lastPx;
      final v = CurrencyService.toRub(q * displayPx, cur);
      valueRub += v;
      unrealizedRub += v - costBasisRub[ticker]!;
    });

    double incomeRub = 0;
    for (final i in incomes) {
      incomeRub += CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
    }

    return (valueRub: valueRub, profitRub: unrealizedRub + realizedRub + incomeRub);
  }
}
