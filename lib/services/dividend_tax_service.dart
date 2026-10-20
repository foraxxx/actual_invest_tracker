import 'dart:async';

import '../models/income.dart';
import 'analytics_service.dart';
import 'dividend_history_service.dart';
import 'storage_service.dart';

/// Дивиденд в выплате: сколько было на акцию, сколько акций было на дату
/// отсечки и сколько это до налога.
class DividendPayoutInfo {
  final DividendRecord record;
  final double shares;

  const DividendPayoutInfo(this.record, this.shares);

  double get gross => record.amount * shares;
}

/// Сверяет записанные дивиденды с историей выплат.
///
/// Брокер часто присылает в отчёте только сумму, которая пришла на счёт, —
/// уже после налога. Такая выплата записывалась без налога, и «до налога»
/// совпадало с «после налога». Если известен дивиденд на акцию и число
/// акций на дату отсечки, сумму до налога можно посчитать точно: тогда налог
/// восстанавливается. Запись меняется, только если пришедшая сумма — это
/// ровно сумма до налога минус 13 % или 15 %; во всех остальных случаях она
/// остаётся как есть.
class DividendTaxService {
  DividendTaxService._();

  static Timer? _debounce;
  static bool _running = false;

  /// Число акций на конец дня перед отсечкой: при расчётах «на следующий
  /// день» в реестр попадают те, кто купил до этого дня включительно.
  static double sharesAtCutoff(String ticker, DateTime cutoff) {
    final day = DateTime(cutoff.year, cutoff.month, cutoff.day - 1, 23, 59, 59);
    return AnalyticsService.holdingsAt(date: day)[ticker]?.qty ??
        AnalyticsService.holdingsAt(date: day)[ticker.toUpperCase()]?.qty ??
        0;
  }

  /// Дивиденд, за который пришла выплата, если он есть в истории.
  static DividendPayoutInfo? infoFor(Income i) {
    if (i.type != IncomeType.dividend) return null;
    final record = DividendHistoryService.of(i.ticker)?.paidBy(i.date);
    if (record == null) return null;
    final shares = sharesAtCutoff(i.ticker, record.date);
    if (shares <= 0) return null;
    return DividendPayoutInfo(record, shares);
  }

  /// Следить за новыми выплатами и обновлениями истории.
  static void attach() {
    StorageService.dataVersion.addListener(_schedule);
    DividendHistoryService.changed.addListener(_schedule);
    _schedule();
  }

  static void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(repair()));
  }

  /// Восстанавливает налог у дивидендов, записанных без него.
  static Future<int> repair() async {
    if (_running) return 0;
    _running = true;
    var fixed = 0;
    try {
      for (final i in StorageService.incomes) {
        if (i.type != IncomeType.dividend || i.taxPaid > 0 || i.currency != 'RUB') continue;
        final info = infoFor(i);
        if (info == null || info.gross <= 0) continue;
        final ratio = i.amountGross / info.gross;
        // 13 % — обычная ставка, 15 % — с суммы свыше 2,4 млн в год.
        // Запас — на округление у брокера.
        if (ratio < 0.845 || ratio > 0.875) continue;
        final gross = (info.gross * 100).round() / 100;
        final net = i.amountGross;
        await StorageService.addIncome(Income(
          id: i.id,
          date: i.date,
          ticker: i.ticker,
          name: i.name,
          type: i.type,
          amountGross: gross,
          taxPaid: ((gross - net) * 100).round() / 100,
          currency: i.currency,
          note: i.note,
        ));
        fixed++;
      }
    } catch (_) {
      // Сверка — дополнительная; ошибка не должна мешать работе.
    } finally {
      _running = false;
    }
    return fixed;
  }
}
