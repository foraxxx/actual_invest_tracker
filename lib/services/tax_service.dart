import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/purchase.dart';
import 'storage_service.dart';
import 'analytics_service.dart';
import 'currency_service.dart';

/// Налог с продажи одной сделки (может покрывать несколько лотов покупки —
/// частично попадающих под льготу ЛДВ, частично нет)
class SaleTaxResult {
  final double realizedGainRub; // итоговый финрезультат сделки, в рублях
  final double exemptGainRub; // прибыль, освобождённая по ЛДВ (владение 3+ года)
  final double taxableGainRub; // прибыль, облагаемая налогом
  final double taxRub; // сам налог к уплате
  final bool hasLdvPortion; // хотя бы часть сделки попала под льготу

  SaleTaxResult({
    required this.realizedGainRub,
    required this.exemptGainRub,
    required this.taxableGainRub,
    required this.taxRub,
    required this.hasLdvPortion,
  });
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

  static double get rate => _box.get('rate', defaultValue: 0.13) ?? 0.13;

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
      List<Purchase> tickerPurchases) {
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
        final isLongTerm = holdingDays >= ldvDays;

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
      );
    }

    return (sales: sales, openLots: lots);
  }

  /// Налоговая разбивка по всем продажам во всех бумагах, ключ — id сделки-продажи
  static Map<String, SaleTaxResult> saleTaxBreakdown() {
    final byTicker = <String, List<Purchase>>{};
    for (final p in StorageService.purchases) {
      byTicker.putIfAbsent(p.ticker, () => []).add(p);
    }
    final result = <String, SaleTaxResult>{};
    byTicker.forEach((ticker, list) {
      result.addAll(_processTicker(list).sales);
    });
    return result;
  }

  /// Суммарный налог к уплате по всем продажам
  static double totalTaxDue() {
    return saleTaxBreakdown().values.fold(0.0, (s, r) => s + r.taxRub);
  }

  /// Открытые лоты покупки конкретной бумаги — для подсказки "до ЛДВ осталось N дней"
  static List<OpenLotInfo> openLotsForTicker(String ticker) {
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
