import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Точка истории ручной цены: конкретная дата + цена, которую ввёл пользователь.
class PricePoint {
  final DateTime date;
  final double price;
  const PricePoint({required this.date, required this.price});

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'price': price};

  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
        date: DateTime.parse(j['date'] as String),
        price: (j['price'] as num).toDouble(),
      );
}

/// Вручную указанная "текущая цена" бумаги, с историей по датам ввода.
/// Приложение офлайн и не тянет котировки из интернета, поэтому по умолчанию
/// используется цена последней сделки — но если пользователь укажет
/// актуальную цену вручную, она приоритетнее и используется для оценки
/// стоимости позиции, графиков и расчёта изменения портфеля за период.
///
/// Каждый раз, когда цена вводится/меняется, фиксируется дата ввода — это
/// даёт настоящую (пусть и заполняемую вручную) историю цены бумаги во
/// времени, а не только "последнее известное значение".
class ManualPriceService {
  static const boxName = 'manual_price_history';
  static const _legacyBoxName = 'manual_prices'; // старый формат: тикер -> одна цена (до истории)
  static late Box<String> _box; // key: тикер, value: JSON-массив точек PricePoint

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
    await _migrateLegacyIfNeeded();
  }

  /// Переносит старые одиночные цены (без истории) в новый формат один раз.
  static Future<void> _migrateLegacyIfNeeded() async {
    if (!await Hive.boxExists(_legacyBoxName)) return;
    final legacy = await Hive.openBox<double>(_legacyBoxName);
    for (final key in legacy.keys) {
      final ticker = (key as String).toUpperCase();
      if (_history(ticker).isNotEmpty) continue; // уже мигрировано ранее
      final price = legacy.get(key);
      if (price != null && price > 0) {
        await _saveHistory(ticker, [PricePoint(date: _dayOnly(DateTime.now()), price: price)]);
      }
    }
    await legacy.deleteFromDisk();
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<PricePoint> _history(String ticker) {
    final raw = _box.get(ticker.toUpperCase());
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final points = list.map(PricePoint.fromJson).toList();
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  static Future<void> _saveHistory(String ticker, List<PricePoint> points) async {
    points.sort((a, b) => a.date.compareTo(b.date));
    await _box.put(ticker.toUpperCase(), jsonEncode(points.map((p) => p.toJson()).toList()));
  }

  /// Текущая (последняя по дате) ручная цена, или null, если ещё не задавалась.
  static double? get(String ticker) {
    final h = _history(ticker);
    return h.isEmpty ? null : h.last.price;
  }

  /// Вся история цен по тикеру, отсортированная по дате (от старых к новым).
  static List<PricePoint> historyFor(String ticker) => _history(ticker);

  /// Последняя известная ручная цена на дату [date] или раньше.
  /// Возвращает null, если на эту дату (и раньше) ручных цен ещё не было.
  static double? priceAt(String ticker, DateTime date) {
    final points = _history(ticker);
    PricePoint? best;
    for (final p in points) {
      if (!p.date.isAfter(date)) {
        best = p;
      } else {
        break;
      }
    }
    return best?.price;
  }

  /// Добавляет/обновляет точку цены на сегодняшнюю дату. Если сегодня цена
  /// уже вводилась — перезаписывает её, а не плодит дубли за один день.
  static Future<void> set(String ticker, double price) => setAt(ticker, DateTime.now(), price);

  /// Добавляет/обновляет точку цены на произвольную дату (используется, в
  /// частности, при импорте бэкапа). Точка на ту же календарную дату
  /// перезаписывается.
  static Future<void> setAt(String ticker, DateTime date, double price) async {
    final t = ticker.toUpperCase();
    final day = _dayOnly(date);
    final points = _history(t);
    points.removeWhere((p) => _dayOnly(p.date) == day);
    points.add(PricePoint(date: day, price: price));
    await _saveHistory(t, points);
    version.value++;
  }

  /// Удаляет всю историю ручных цен по тикеру (полный сброс на цену сделки).
  static Future<void> clear(String ticker) async {
    await _box.delete(ticker.toUpperCase());
    version.value++;
  }

  /// Удаляет одну точку истории на конкретную дату.
  static Future<void> deletePoint(String ticker, DateTime date) async {
    final t = ticker.toUpperCase();
    final day = _dayOnly(date);
    final points = _history(t)..removeWhere((p) => _dayOnly(p.date) == day);
    await _saveHistory(t, points);
    version.value++;
  }

  /// Все текущие (последние) ручные цены — используется там, где нужна
  /// только "сейчас" цена, без истории.
  static Map<String, double> get all {
    final map = <String, double>{};
    for (final key in _box.keys) {
      final t = key as String;
      final p = get(t);
      if (p != null) map[t] = p;
    }
    return map;
  }

  /// Полная история по всем тикерам (для бэкапа).
  static Map<String, List<PricePoint>> get allHistory {
    final map = <String, List<PricePoint>>{};
    for (final key in _box.keys) {
      final t = key as String;
      map[t] = _history(t);
    }
    return map;
  }
}
