import 'dart:math' as math;

import '../models/income.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'moex_service.dart';
import 'storage_service.dart';

/// Облигация с купоном в нужном месяце.
class BondPick {
  final String secid;
  final String name;

  /// TQOB — ОФЗ, TQCB — корпоративные.
  final String board;

  /// Купон на одну облигацию, ₽, до налога.
  final double coupon;
  final DateTime couponDate;
  final int periodDays;
  final DateTime? maturity;

  /// Доходность к погашению, % годовых.
  final double? yieldPct;

  /// Цена одной облигации с НКД, ₽.
  final double price;
  final int? listLevel;

  /// Доходность заметно выше ОФЗ или третий уровень листинга.
  final bool risky;

  const BondPick({
    required this.secid,
    required this.name,
    required this.board,
    required this.coupon,
    required this.couponDate,
    required this.periodDays,
    required this.maturity,
    required this.yieldPct,
    required this.price,
    required this.listLevel,
    required this.risky,
  });

  bool get ofz => board == 'TQOB';
  bool get monthly => periodDays >= 28 && periodDays <= 31;
}

/// Акция, по которой вы уже получали дивиденды в этом месяце.
class StockPick {
  final String ticker;
  final String name;
  final DateTime lastDate;

  /// Сколько пришло на одну акцию в прошлый раз, после налога.
  final double perShare;

  /// Сколько акций у вас сейчас (0 — продана).
  final double qtyNow;

  /// Текущая цена, если известна.
  final double? price;

  const StockPick({
    required this.ticker,
    required this.name,
    required this.lastDate,
    required this.perShare,
    required this.qtyNow,
    required this.price,
  });

  /// Разовая доходность выплаты к нынешней цене, %.
  double? get payoutPct => price == null || price! <= 0 ? null : perShare / price! * 100;
}

/// Подбор бумаг, которые платят в нужном месяце.
class PayoutPickerService {
  PayoutPickerService._();

  static List<Map<String, dynamic>>? _rows;
  static DateTime? _loadedAt;

  /// Строки облигаций с биржи. Держим в памяти полчаса: список большой, а
  /// человек может переключать месяцы.
  static Future<List<Map<String, dynamic>>> _loadRows() async {
    final fresh = _loadedAt != null && DateTime.now().difference(_loadedAt!) < const Duration(minutes: 30);
    if (_rows != null && fresh) return _rows!;
    final ofz = await MoexService.bondBoardRows('TQOB');
    List<Map<String, dynamic>> corp = const [];
    try {
      corp = await MoexService.bondBoardRows('TQCB');
    } catch (_) {
      // Без корпоративных — хотя бы ОФЗ.
    }
    _rows = [...ofz, ...corp];
    _loadedAt = DateTime.now();
    return _rows!;
  }

  static Future<List<BondPick>> bondsFor(DateTime month) async => bondsFromRows(await _loadRows(), month);

  /// Облигации, у которых купон приходится на [month]: дата купона считается
  /// от ближайшего купона шагом периода. Бумаги с погашением или офертой
  /// раньше этого купона не берём.
  static List<BondPick> bondsFromRows(List<Map<String, dynamic>> rows, DateTime month) {
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month + 1);
    final ofzYields = <double>[];
    final candidates = <BondPick>[];

    for (final r in rows) {
      final unit = '${r['FACEUNIT'] ?? ''}'.toUpperCase();
      if (unit != 'SUR' && unit != 'RUB') continue;
      final yieldPct = _num(r['YIELD']);
      if (r['BOARD'] == 'TQOB' && yieldPct != null && yieldPct > 0) ofzYields.add(yieldPct);

      final coupon = _num(r['COUPONVALUE']);
      final period = _num(r['COUPONPERIOD'])?.round();
      final next = _date(r['NEXTCOUPON']);
      final face = _num(r['FACEVALUE']);
      final pricePct = _num(r['LAST']) ?? _num(r['PREVPRICE']);
      if (coupon == null || coupon <= 0 || period == null || period <= 0 || next == null) continue;
      if (face == null || face <= 0 || pricePct == null || pricePct <= 0) continue;
      final maturity = _date(r['MATDATE']);
      final offer = _date(r['OFFERDATE']);

      DateTime? inMonth;
      var d = next;
      for (int i = 0; i < 400 && d.isBefore(monthEnd); i++) {
        if (!d.isBefore(monthStart)) {
          inMonth = d;
          break;
        }
        d = d.add(Duration(days: period));
      }
      if (inMonth == null) continue;
      if (maturity != null && maturity.isBefore(inMonth)) continue;
      if (offer != null && offer.isBefore(inMonth)) continue;

      final price = pricePct * face / 100 + (_num(r['ACCRUEDINT']) ?? 0);
      final listLevel = _num(r['LISTLEVEL'])?.round();
      candidates.add(BondPick(
        secid: '${r['SECID']}',
        name: '${r['SHORTNAME'] ?? r['SECID']}',
        board: '${r['BOARD']}',
        coupon: coupon,
        couponDate: inMonth,
        periodDays: period,
        maturity: maturity,
        yieldPct: yieldPct,
        price: price,
        listLevel: listLevel,
        risky: false,
      ));
    }

    ofzYields.sort();
    final ofzMedian = ofzYields.isEmpty ? null : ofzYields[ofzYields.length ~/ 2];
    final result = [
      for (final b in candidates)
        // Без доходности или с явно сломанной — не показываем.
        if (b.yieldPct != null && b.yieldPct! > 0 && b.yieldPct! < 80)
          BondPick(
            secid: b.secid,
            name: b.name,
            board: b.board,
            coupon: b.coupon,
            couponDate: b.couponDate,
            periodDays: b.periodDays,
            maturity: b.maturity,
            yieldPct: b.yieldPct,
            price: b.price,
            listLevel: b.listLevel,
            risky: (b.listLevel ?? 3) >= 3 || (ofzMedian != null && b.yieldPct! > ofzMedian + 8),
          ),
    ];
    // Сначала надёжные, внутри — по доходности.
    result.sort((a, b) {
      if (a.risky != b.risky) return a.risky ? 1 : -1;
      return (b.yieldPct ?? 0).compareTo(a.yieldPct ?? 0);
    });
    return result;
  }

  /// Средняя купонная доходность облигаций на рынке: годовой купон к цене,
  /// % годовых. Именно купон, а не доходность к погашению: для пассивного
  /// дохода важны деньги, которые приходят выплатами.
  static Future<double?> marketCouponYield() async => marketCouponYieldFromRows(await _loadRows());

  static double? marketCouponYieldFromRows(List<Map<String, dynamic>> rows, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final values = <double>[];
    for (final r in rows) {
      final unit = '${r['FACEUNIT'] ?? ''}'.toUpperCase();
      if (unit != 'SUR' && unit != 'RUB') continue;
      // Только надёжные и не короткие: третий уровень и бумаги, которые
      // гасятся в ближайший год, сильно искажают среднее.
      if ((_num(r['LISTLEVEL'])?.round() ?? 3) >= 3) continue;
      final maturity = _date(r['MATDATE']);
      if (maturity != null && maturity.isBefore(today.add(const Duration(days: 365)))) continue;
      final coupon = _num(r['COUPONVALUE']);
      final period = _num(r['COUPONPERIOD']);
      final face = _num(r['FACEVALUE']);
      final pricePct = _num(r['LAST']) ?? _num(r['PREVPRICE']);
      if (coupon == null || coupon <= 0 || period == null || period <= 0) continue;
      if (face == null || face <= 0 || pricePct == null || pricePct <= 0) continue;
      final y = coupon * 365 / period / (pricePct * face / 100) * 100;
      if (y > 2 && y < 40) values.add(y);
    }
    if (values.length < 5) return null;
    values.sort();
    return values[values.length ~/ 2];
  }

  /// Акции, по которым вы получали дивиденды в месяце [month] (любого года).
  /// Сумма на акцию — из последней такой выплаты.
  static List<StockPick> stocksFor(DateTime month) {
    final last = <String, Income>{};
    for (final i in StorageService.incomes) {
      if (i.type != IncomeType.dividend || i.date.month != month.month) continue;
      if (i.amountNet <= 0) continue;
      final t = i.ticker.toUpperCase();
      final prev = last[t];
      if (prev == null || i.date.isAfter(prev.date)) last[t] = i;
    }
    final holdingsNow = AnalyticsService.currentHoldings();
    final result = <StockPick>[];
    for (final e in last.entries) {
      final income = e.value;
      // Сколько акций было в день выплаты — чтобы получить сумму на одну.
      final then = AnalyticsService.holdingsAt(date: income.date)[income.ticker] ??
          AnalyticsService.holdingsAt(date: income.date.subtract(const Duration(days: 40)))[income.ticker];
      final qtyThen = then?.qty ?? 0;
      if (qtyThen <= 0) continue;
      final perShare = CurrencyService.toRub(income.amountNet, income.currency, date: income.date) / qtyThen;
      final now = holdingsNow[income.ticker];
      result.add(StockPick(
        ticker: income.ticker,
        name: income.name.trim().isEmpty ? income.ticker : income.name.trim(),
        lastDate: income.date,
        perShare: perShare,
        qtyNow: now?.qty ?? 0,
        price: now?.displayPrice ?? AnalyticsService.priceFor(income.ticker),
      ));
    }
    result.sort((a, b) => (b.payoutPct ?? 0).compareTo(a.payoutPct ?? 0));
    return result;
  }

  /// Сколько штук взять для примера: на сумму около 100 000 ₽.
  static int sampleQty(double price) => price <= 0 ? 1 : math.max(1, (100000 / price).round());

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    final d = DateTime.tryParse(v);
    if (d == null || d.year < 1900) return null;
    return d;
  }
}
