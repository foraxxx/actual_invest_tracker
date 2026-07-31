import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Одна точка истории курса: дата и значение курса к рублю
class RatePoint {
  final DateTime date;
  final double rate;
  const RatePoint({required this.date, required this.rate});

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'rate': rate};
  factory RatePoint.fromJson(Map<String, dynamic> j) =>
      RatePoint(date: DateTime.parse(j['date']), rate: (j['rate'] as num).toDouble());
}

/// Курсы валют к рублю (базовая валюта статистики — RUB), с историей по датам.
/// Приложение офлайн и не тянет котировки из интернета — курсы вводятся
/// пользователем вручную. Каждая сделка конвертируется по курсу, действовавшему
/// на её дату (ближайший известный курс на эту дату или раньше), а не по
/// сегодняшнему курсу — так изменение курса в настройках не искажает
/// задним числом уже случившиеся сделки.
class CurrencyService {
  static const boxName = 'currency_rate_history';
  static late Box<String> _box; // key: currency, value: JSON-массив точек истории

  static final ValueNotifier<int> version = ValueNotifier(0);

  static const Map<String, double> _defaults = {
    'USD': 90.0,
    'EUR': 100.0,
    'CNY': 12.5,
  };

  static const List<String> trackedCurrencies = ['USD', 'EUR', 'CNY'];

  /// Ниже этого значения курс к рублю быть не может ни у одной из
  /// отслеживаемых валют. Служит защитой от мусора из сети: один неверно
  /// определённый инструмент на бирже — и вся история сделок пересчитается
  /// по курсу 0,08 ₽.
  static const double minPlausibleRate = 0.5;

  /// Разовая уборка: выкидывает из истории точки с невозможным курсом.
  /// Нужна тем, кому такие значения успели записаться до появления проверки.
  static Future<int> dropImplausiblePoints() async {
    int removed = 0;
    for (final currency in trackedCurrencies) {
      final points = _history(currency);
      final clean = points.where((p) => p.rate >= minPlausibleRate).toList();
      if (clean.length != points.length) {
        removed += points.length - clean.length;
        await _saveHistory(currency, clean);
      }
    }
    if (removed > 0) version.value++;
    return removed;
  }

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
    for (final currency in trackedCurrencies) {
      if (_history(currency).isEmpty) {
        await _saveHistory(currency, [RatePoint(date: DateTime.now(), rate: _defaults[currency]!)]);
      }
    }
  }

  static List<RatePoint> _history(String currency) {
    final raw = _box.get(currency);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(RatePoint.fromJson).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  static Future<void> _saveHistory(String currency, List<RatePoint> points) async {
    points.sort((a, b) => a.date.compareTo(b.date));
    await _box.put(currency, jsonEncode(points.map((p) => p.toJson()).toList()));
  }

  /// История курса валюты, отсортированная по дате (старые сверху)
  static List<RatePoint> historyFor(String currency) => _history(currency);

  /// Добавляет/обновляет точку курса на конкретную дату (день). Если точка
  /// на эту же дату уже есть — перезаписывает её.
  static Future<void> setRateAt(String currency, DateTime date, double rate) async {
    final day = DateTime(date.year, date.month, date.day);
    final points = _history(currency);
    points.removeWhere((p) => p.date.year == day.year && p.date.month == day.month && p.date.day == day.day);
    points.add(RatePoint(date: day, rate: rate));
    await _saveHistory(currency, points);
    version.value++;
  }

  static Future<void> deleteRateAt(String currency, DateTime date) async {
    final points = _history(currency);
    points.removeWhere((p) => p.date.year == date.year && p.date.month == date.month && p.date.day == date.day);
    await _saveHistory(currency, points);
    version.value++;
  }

  /// Курс валюты на конкретную дату: ближайшая известная точка на эту дату
  /// или раньше; если такой нет — самая ранняя известная точка.
  static double rateFor(String currency, {DateTime? date}) {
    if (currency == 'RUB') return 1.0;
    final points = _history(currency);
    if (points.isEmpty) return _defaults[currency] ?? 1.0;
    final target = date ?? DateTime.now();

    RatePoint? best;
    for (final p in points) {
      if (!p.date.isAfter(target)) {
        best = p;
      } else {
        break;
      }
    }
    return (best ?? points.first).rate;
  }

  /// Текущий (последний известный) курс — для отображения в настройках
  static double currentRate(String currency) => rateFor(currency);

  /// Переводит сумму в валюте currency в рубли по курсу на указанную дату
  /// (по умолчанию — по сегодняшнему курсу, если дата не указана)
  static double toRub(double amount, String currency, {DateTime? date}) =>
      amount * rateFor(currency, date: date);
}
