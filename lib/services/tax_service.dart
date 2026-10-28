import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/purchase.dart';
import 'storage_service.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'iis_service.dart';
import 'portfolio_service.dart';
import '../design/format.dart';
import '../models/income.dart';

/// Как облагается портфель: обычный брокерский счёт или ИИС одного из типов.
enum TaxRegime { regular, iisA, iisB, iis3 }

/// Налоги за календарный год по портфелю.
class YearTaxes {
  /// Удержано с дивидендов — по факту из записей выплат, а где налог не
  /// указан — по ставке.
  final double dividends;

  /// Налог с полученных купонов: на обычном счёте брокер спишет его в конце
  /// года; на ИИС — только при закрытии.
  final double coupons;

  /// Налог с прибыли от продаж за год.
  final double sales;

  /// На ИИС-3 и ИИС типа Б: сколько налога с купонов и продаж не придётся
  /// платить при соблюдении срока.
  final double saved;

  /// Налог с купонов и продаж на ИИС не удерживается сейчас.
  final bool deferred;

  const YearTaxes({
    required this.dividends,
    required this.coupons,
    required this.sales,
    required this.saved,
    required this.deferred,
  });

  /// Сколько реально придётся заплатить за год.
  double get total => dividends + (deferred ? 0 : coupons + sales);
}

/// Налог с продажи одной сделки (может покрывать несколько лотов покупки —
/// частично попадающих под льготу ЛДВ, частично нет)
class SaleTaxResult {
  final double realizedGainRub; // итоговый финрезультат сделки, в рублях
  final double exemptGainRub; // прибыль, освобождённая по ЛДВ (владение 3+ года)
  final double taxableGainRub; // прибыль, облагаемая налогом
  final double taxRub; // сам налог к уплате
  final bool hasLdvPortion; // хотя бы часть сделки попала под льготу

  /// ИИС: налог сейчас не удерживается, [taxRub] — сколько он составит при
  /// досрочном закрытии (для ИИС-3 и типа Б) или при закрытии (тип А).
  final bool deferred;

  /// ИИС-3 и тип Б: при соблюдении срока налога не будет вовсе.
  final bool exemptAtTerm;

  SaleTaxResult({
    required this.realizedGainRub,
    required this.exemptGainRub,
    required this.taxableGainRub,
    required this.taxRub,
    required this.hasLdvPortion,
    this.deferred = false,
    this.exemptAtTerm = false,
  });

  /// Налог, который придётся заплатить, если всё идёт по плану.
  double get dueRub => exemptAtTerm ? 0 : taxRub;
}

/// Открытый (ещё не проданный) лот покупки — для подсказки "сколько ждать до ЛДВ"
class OpenLotInfo {
  final DateTime date;
  final double qty;
  final int daysUntilLdv; // 0 или отрицательное — уже действует льгота

  OpenLotInfo({required this.date, required this.qty, required this.daysUntilLdv});

  bool get ldvActive => daysUntilLdv <= 0;
}

class _MutableLot {
  DateTime date;
  double qty;
  double price;
  _MutableLot({required this.date, required this.qty, required this.price});
}

/// Расчёт налога на прибыль от продажи ценных бумаг (НДФЛ) и льготы на
/// долгосрочное владение (ЛДВ — от 3 лет владения прибыль не облагается налогом).
///
/// Упрощения (важно понимать, что это не полноценная замена налоговой консультации):
/// - Порог ЛДВ считается как 3×365 дней от даты покупки лота, без точного
///   календарного правила "3 года владения" и без лимита освобождаемой суммы
///   (в реальности есть предел ~3 млн ₽ в год за каждый год владения).
/// - Комиссия не распределяется пропорционально между лотами при частичной продаже.
/// - Ставка НДФЛ (13% или 15%) не учитывает прогрессивную шкалу по совокупному
///   годовому доходу — задаётся пользователем вручную как одна ставка.
class TaxService {
  static const boxName = 'tax_settings';
  static const enabledBoxName = 'tax_enabled';
  static late Box<double> _box;
  static late Box<bool> _enabledBox;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static const int ldvDays = 365 * 3;

  static Future<void> init() async {
    _box = await Hive.openBox<double>(boxName);
    _enabledBox = await Hive.openBox<bool>(enabledBoxName);
  }

  /// Ставка НДФЛ — одна на всё приложение: дивиденды, купоны, продажи и
  /// вычет по ИИС.
  static double get rate {
    try {
      return _box.get('rate', defaultValue: 0.13) ?? 0.13;
    } catch (_) {
      return 0.13;
    }
  }

  /// Порог, после которого доход облагается по ставке 15%.
  static const progressiveThreshold = 2400000.0;

  /// Режим открытого портфеля.
  static TaxRegime get regime {
    try {
      return regimeFor(PortfolioService.activeId);
    } catch (_) {
      return TaxRegime.regular;
    }
  }

  static TaxRegime regimeFor(String portfolioId) {
    try {
      final s = IisService.settingsFor(portfolioId);
      if (s == null) return TaxRegime.regular;
      return switch (s.type) {
        IisType.newType => TaxRegime.iis3,
        IisType.oldA => TaxRegime.iisA,
        IisType.oldB => TaxRegime.iisB,
      };
    } catch (_) {
      return TaxRegime.regular;
    }
  }

  /// Льгота за 3 года владения действует только на обычном счёте.
  static bool ldvAppliesFor(TaxRegime r) => r == TaxRegime.regular;

  /// Налог с купонов и продаж удерживается не сразу, а при закрытии ИИС.
  static bool deferredFor(TaxRegime r) => r != TaxRegime.regular;

  /// При соблюдении срока ИИС налога с купонов и продаж не будет.
  static bool exemptAtTermFor(TaxRegime r) => r == TaxRegime.iisB || r == TaxRegime.iis3;

  static Future<void> setRate(double r) async {
    await _box.put('rate', r);
    version.value++;
  }

  static bool get enabled => _enabledBox.get('enabled', defaultValue: true) ?? true;

  static Future<void> setEnabled(bool v) async {
    await _enabledBox.put('enabled', v);
    version.value++;
  }

  /// FIFO-разбор всех сделок по одному тикеру: возвращает и налоговую разбивку
  /// по продажам (ключ — id продажи), и оставшиеся открытые лоты.
  static ({Map<String, SaleTaxResult> sales, List<_MutableLot> openLots}) _processTicker(
      List<Purchase> tickerPurchases, {TaxRegime? regimeOverride}) {
    final reg = regimeOverride ?? regime;
    final ldv = ldvAppliesFor(reg);
    final sorted = [...tickerPurchases]..sort(AnalyticsService.compareTrades);
    final lots = <_MutableLot>[];
    final sales = <String, SaleTaxResult>{};

    for (final p in sorted) {
      if (!p.isSell) {
        lots.add(_MutableLot(date: p.date, qty: p.quantity, price: p.pricePerUnit));
        continue;
      }

      double remaining = p.quantity;
      double realizedGain = 0;
      double exemptGain = 0;
      double taxableGain = 0;
      bool hasLdvPortion = false;

      while (remaining > 1e-9 && lots.isNotEmpty) {
        final lot = lots.first;
        final take = lot.qty < remaining ? lot.qty : remaining;

        final costBasis = take * lot.price;
        final proceeds = take * p.pricePerUnit;
        final gain = proceeds - costBasis;
        final gainRub = CurrencyService.toRub(gain, p.currency, date: p.date);

        final holdingDays = p.date.difference(lot.date).inDays;
        final isLongTerm = ldv && holdingDays >= ldvDays;

        realizedGain += gainRub;
        if (gain > 0) {
          if (isLongTerm) {
            exemptGain += gainRub;
            hasLdvPortion = true;
          } else {
            taxableGain += gainRub;
          }
        }

        lot.qty -= take;
        remaining -= take;
        if (lot.qty <= 1e-9) lots.removeAt(0);
      }

      final tax = taxableGain > 0 ? taxableGain * rate : 0.0;
      sales[p.id] = SaleTaxResult(
        realizedGainRub: realizedGain,
        exemptGainRub: exemptGain,
        taxableGainRub: taxableGain,
        taxRub: tax,
        hasLdvPortion: hasLdvPortion,
        deferred: deferredFor(reg),
        exemptAtTerm: exemptAtTermFor(reg),
      );
    }

    return (sales: sales, openLots: lots);
  }

  /// Налоговая разбивка по всем продажам во всех бумагах, ключ — id сделки-продажи
  static Map<String, SaleTaxResult> saleTaxBreakdown({List<Purchase>? purchases, TaxRegime? regimeOverride}) {
    final byTicker = <String, List<Purchase>>{};
    for (final p in purchases ?? StorageService.purchases) {
      byTicker.putIfAbsent(p.ticker, () => []).add(p);
    }
    final result = <String, SaleTaxResult>{};
    byTicker.forEach((ticker, list) {
      result.addAll(_processTicker(list, regimeOverride: regimeOverride).sales);
    });
    return result;
  }

  /// Суммарный налог к уплате по всем продажам (на обычном счёте и ИИС
  /// типа А; на ИИС-3 и типе Б при соблюдении срока — 0).
  static double totalTaxDue() {
    return saleTaxBreakdown().values.fold(0.0, (s, r) => s + r.dueRub);
  }

  /// Налог с продаж и купонов, если закрыть ИИС прямо сейчас (на ИИС-3 и
  /// типе Б — при досрочном закрытии). Купоны — за всё время счёта.
  static double taxIfClosedNow() {
    final reg = regime;
    if (!deferredFor(reg)) return 0;
    final sales = saleTaxBreakdown().values.fold(0.0, (s, r) => s + r.taxRub);
    final coupons = StorageService.incomes
        .where((i) => i.type == IncomeType.coupon)
        .fold(0.0, (s, i) => s + CurrencyService.toRub(i.amountGross - i.taxPaid, i.currency, date: i.date));
    return sales + coupons * rate;
  }

  /// Налоги портфеля за [year]. [purchases] и [incomes] — данные портфеля
  /// (по умолчанию открытого), [regimeOverride] — его режим.
  static YearTaxes yearTaxes(
    int year, {
    List<Purchase>? purchases,
    List<Income>? incomes,
    TaxRegime? regimeOverride,
  }) {
    final reg = regimeOverride ?? regime;
    final r = rate;
    double divTax = 0, couponIncome = 0;
    for (final i in incomes ?? StorageService.incomes) {
      if (i.date.year != year) continue;
      if (i.type == IncomeType.dividend) {
        // Фактически удержанный налог, если он записан; иначе — по ставке.
        divTax += i.taxPaid > 0
            ? CurrencyService.toRub(i.taxPaid, i.currency, date: i.date)
            : CurrencyService.toRub(i.amountGross, i.currency, date: i.date) * r;
      } else {
        couponIncome += CurrencyService.toRub(i.amountGross - i.taxPaid, i.currency, date: i.date);
      }
    }
    final buys = purchases ?? StorageService.purchases;
    final breakdown = saleTaxBreakdown(purchases: buys, regimeOverride: reg);
    final ids = {for (final p in buys) if (p.isSell && p.date.year == year) p.id};
    final sales = breakdown.entries.where((e) => ids.contains(e.key)).fold(0.0, (s, e) => s + e.value.taxRub);
    final coupons = couponIncome * r;
    final exempt = exemptAtTermFor(reg);
    return YearTaxes(
      dividends: divTax,
      coupons: coupons,
      sales: sales,
      saved: exempt ? coupons + sales : 0,
      deferred: deferredFor(reg),
    );
  }

  /// Доход за год для порога 2,4 млн по всем портфелям: дивиденды и купоны
  /// до налога плюс облагаемая прибыль от продаж на обычных счетах.
  static Future<double> yearIncomeAllPortfolios(int year) async {
    double total = 0;
    for (final p in PortfolioService.list) {
      final data = await StorageService.readDataFor(p.id);
      final reg = regimeFor(p.id);
      for (final i in data.incomes) {
        if (i.date.year != year) continue;
        // Купоны и продажи на ИИС-3 и Б при соблюдении срока в доход не идут.
        if (i.type == IncomeType.coupon && exemptAtTermFor(reg)) continue;
        total += CurrencyService.toRub(i.amountGross, i.currency, date: i.date);
      }
      if (exemptAtTermFor(reg)) continue;
      final sells = {for (final s in data.purchases) if (s.isSell && s.date.year == year) s.id};
      final b = saleTaxBreakdown(purchases: data.purchases, regimeOverride: reg);
      for (final e in b.entries) {
        if (sells.contains(e.key)) total += e.value.taxableGainRub;
      }
    }
    return total;
  }

  /// Открытые лоты покупки конкретной бумаги — для подсказки "до ЛДВ осталось N дней"
  static List<OpenLotInfo> openLotsForTicker(String ticker) {
    // На ИИС льготы за 3 года нет — и подсказки «до льготы» тоже.
    if (!ldvAppliesFor(regime)) return const [];
    final list = StorageService.purchases.where((p) => p.ticker == ticker).toList();
    final lots = _processTicker(list).openLots;
    final now = DateTime.now();
    return lots.map((l) {
      final ldvDate = l.date.add(const Duration(days: ldvDays));
      final daysLeft = ldvDate.difference(now).inDays;
      return OpenLotInfo(date: l.date, qty: l.qty, daysUntilLdv: daysLeft);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }
}


/// Подпись налога у продажи в списке сделок.
String? saleTaxLabel(SaleTaxResult r) {
  String money(double v) => Fmt.money(v);
  if (r.realizedGainRub <= 0) return 'без налога (убыток)';
  if (r.taxableGainRub <= 0 && r.hasLdvPortion) return 'без налога (ЛДВ)';
  if (r.taxRub <= 0) return null;
  if (r.exemptAtTerm) return 'налог 0 ₽ · при досрочном закрытии ИИС ≈ ${money(r.taxRub)}';
  if (r.deferred) return 'налог ≈ ${money(r.taxRub)} — при закрытии ИИС';
  return 'налог ≈ ${money(r.taxRub)}';
}
