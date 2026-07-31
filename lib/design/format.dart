import '../models/purchase.dart';

/// Форматирование чисел и дат в одном месте — чтобы «1 234 567 ₽» выглядело
/// одинаково на каждом экране, а не по-своему в каждом виджете.
class Fmt {
  Fmt._();

  static const _months = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  static const _monthsFull = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  /// Разделяет разряды неразрывным пробелом: большие суммы читаются с
  /// одного взгляда, и строка не рвётся посреди числа при переносе.
  static String group(double v, {int decimals = 0}) {
    final negative = v < 0;
    final abs = v.abs();
    final fixed = abs.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('\u00A0');
      buf.write(intPart[i]);
    }
    final result = parts.length > 1 ? '${buf.toString()},${parts[1]}' : buf.toString();
    return negative ? '-$result' : result;
  }

  static String money(double v, {int decimals = 0, String currency = '₽'}) =>
      '${group(v, decimals: decimals)}\u00A0$currency';

  static String signedMoney(double v, {int decimals = 0, String currency = '₽'}) =>
      '${v >= 0 ? '+' : ''}${group(v, decimals: decimals)}\u00A0$currency';


  /// Цена или выплата «как есть»: число знаков подбирается под величину, а
  /// хвостовые нули убираются.
  ///
  /// У копеечных бумаг вроде дивиденда 0,0212 ₽ фиксированные два знака
  /// превращали значение в 0,02 — то есть в ноль по смыслу. Здесь мелкие
  /// суммы показываются целиком, а крупные не засоряются лишними знаками.
  static String price(double v, {String? currency}) {
    final a = v.abs();
    final int decimals;
    if (a >= 1000) {
      decimals = 2;
    } else if (a >= 100) {
      decimals = 2;
    } else if (a >= 10) {
      decimals = 3;
    } else if (a >= 1) {
      decimals = 4;
    } else if (a >= 0.01) {
      decimals = 5;
    } else {
      decimals = 8;
    }

    var text = v.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    }

    // Разряды отделяем только у целой части.
    final parts = text.split('.');
    final sign = parts[0].startsWith('-') ? '-' : '';
    final whole = parts[0].replaceFirst('-', '');
    final grouped = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]} ',
    );
    final result = parts.length > 1 ? '$sign$grouped,${parts[1]}' : '$sign$grouped';
    return currency == null ? result : '$result $currency';
  }

  static String pct(double v, {int decimals = 1}) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(decimals)}%';

  /// Компактная запись для тесных мест: 1,2 млн вместо 1 200 000.
  static String compact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(abs >= 10000000 ? 0 : 1)} млн';
    if (abs >= 10000) return '${(v / 1000).toStringAsFixed(0)} тыс';
    return group(v);
  }

  /// Количество бумаг: целое — без хвоста, дробное — с двумя знаками.
  static String qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Дата и время для подсказок на графиках. Внутри дня время обязательно:
  /// по свечам в десять минут иначе не понять, к какому моменту относится
  /// значение. На дневных свечах время всегда 00:00, поэтому его прячем.
  static String dateTime(DateTime d, {bool withTime = true}) {
    if (!withTime) return date(d);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${date(d)} $hh:$mm';
  }

  static String dateLong(DateTime d) => '${d.day} ${_monthsFull[d.month - 1]} ${d.year}';

  static String monthShort(int month) => _months[month - 1];

  /// Ключ вида 2026-07 -> «июл 26»
  static String monthKeyLabel(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return key;
    final month = int.tryParse(parts[1]) ?? 1;
    final year = parts[0].length >= 2 ? parts[0].substring(parts[0].length - 2) : parts[0];
    return '${_months[(month - 1).clamp(0, 11)]} $year';
  }

  static String monthTitle(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return key;
    final month = int.tryParse(parts[1]) ?? 1;
    return '${_monthsFull[(month - 1).clamp(0, 11)]} ${parts[0]}';
  }

  /// Русские окончания: 1 бумага, 2 бумаги, 5 бумаг.
  static String plural(int n, String one, String few, String many) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 == 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
  }

  static String papers(int n) => plural(n, 'бумага', 'бумаги', 'бумаг');
  static String deals(int n) => plural(n, 'сделка', 'сделки', 'сделок');
  static String purchases(int n) => plural(n, 'покупка', 'покупки', 'покупок');
  static String payouts(int n) => plural(n, 'выплата', 'выплаты', 'выплат');

  static String assetType(AssetType t) {
    switch (t) {
      case AssetType.stock:
        return 'Акция';
      case AssetType.bond:
        return 'Облигация';
      case AssetType.etf:
        return 'Фонд';
      case AssetType.currency:
        return 'Валюта';
      case AssetType.other:
        return 'Другое';
    }
  }

  static String assetTypeShort(AssetType t) {
    switch (t) {
      case AssetType.stock:
        return 'Акции';
      case AssetType.bond:
        return 'Облигации';
      case AssetType.etf:
        return 'Фонды';
      case AssetType.currency:
        return 'Валюта';
      case AssetType.other:
        return 'Другое';
    }
  }
}
