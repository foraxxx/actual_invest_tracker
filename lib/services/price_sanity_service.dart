import 'analytics_service.dart';
import 'manual_price_service.dart';
import 'moex_sync_service.dart';

/// Проверка правдоподобности цены, введённой в сделке.
///
/// Зачем это нужно. Цена сделки не остаётся внутри самой сделки: при записи
/// она попадает в [ManualPriceService] как наблюдение рыночной цены на эту
/// дату, и дальше по ней оценивается ВСЯ позиция в истории портфеля. Одна
/// опечатка в цене поэтому обваливает график на величину, кратную размеру
/// позиции, а не на размер сделки: продажа 17 облигаций по ошибочной цене
/// 193 ₽ вместо 548 ₽ переоценила все 2096 штук и нарисовала на графике
/// провал в три четверти миллиона рублей.
///
/// Заметить такое постфактум почти невозможно: сделка выглядит обычной,
/// а ломается график за прошлые даты. Поэтому цена проверяется в момент
/// ввода, пока пользователь ещё помнит, что он вводил.
class PriceSanityService {
  /// Во сколько раз цена должна разойтись с рыночной, чтобы считаться
  /// подозрительной.
  ///
  /// Порог намеренно широкий. Задача — ловить опечатки в разряде (лишний
  /// ноль, потерянная цифра, сумма сделки вместо цены за штуку), а не спорить
  /// с пользователем о десятке процентов. Реальные сделки расходятся с
  /// текущей котировкой на проценты; ошибки ввода — в разы.
  static const double threshold = 2.0;

  /// Известная рыночная цена бумаги: сначала биржевая котировка, затем
  /// последняя сохранённая отметка. Возвращает null, если сравнивать не с чем —
  /// тогда проверять нечего и ввод принимается как есть.
  static double? knownPrice(String ticker) {
    final key = ticker.trim().toUpperCase();
    if (key.isEmpty) return null;
    final quote = MoexSyncService.marketSnapshot.value[key]?.price;
    if (quote != null && quote > 0) return quote;
    final online = AnalyticsService.priceFor(key);
    if (online != null && online > 0) return online;
    final manual = ManualPriceService.get(key);
    if (manual != null && manual > 0) return manual;
    return null;
  }

  /// Расходится ли цена с рыночной настолько, что это похоже на ошибку ввода.
  static bool isSuspicious(double price, double? market) {
    if (market == null || market <= 0 || price <= 0) return false;
    final ratio = price / market;
    return ratio >= threshold || ratio <= 1 / threshold;
  }

  /// Можно ли записать эту цену как наблюдение рыночной цены.
  ///
  /// Сама сделка сохраняется всегда — пользователь мог купить по любой цене,
  /// и спорить с фактом сделки приложение не вправе. Но подозрительная цена
  /// не становится оценкой позиции: сделка останется в списке как есть,
  /// а история портфеля не пострадает.
  static bool canRecordAsMarketPrice(String ticker, double price) =>
      !isSuspicious(price, knownPrice(ticker));

  /// Текст предупреждения для формы сделки.
  static String warning(double price, double market) {
    final times = price > market ? price / market : market / price;
    final direction = price > market ? 'выше' : 'ниже';
    return 'Цена ${direction} рыночной примерно в ${times.toStringAsFixed(times >= 10 ? 0 : 1)} раза '
        '(на бирже около ${market.toStringAsFixed(2)}). Проверьте, не введена ли сумма сделки '
        'вместо цены за одну бумагу.';
  }
}
