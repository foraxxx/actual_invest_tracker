import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'moex_service.dart';

/// Дневные цены бумаг с биржи, сохранённые на телефоне.
///
/// Раньше история всех бумаг скачивалась заново при каждом открытии главной.
/// Теперь полная история берётся один раз, а дальше докачиваются только
/// новые дни — несколько последних, на случай поправок биржи.
class PriceHistoryCache {
  PriceHistoryCache._();

  static const boxName = 'price_history';
  static Box<String>? _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static int _day(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime _date(int v) => DateTime(v ~/ 10000, v ~/ 100 % 100, v % 100);

  static ({DateTime from, DateTime at, List<MapEntry<DateTime, double>> points})? _read(String key) {
    final raw = _box?.get(key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final points = [
        for (final p in m['p'] as List) MapEntry(_date((p as List)[0] as int), (p[1] as num).toDouble()),
      ];
      return (
        from: _date(m['f'] as int),
        at: DateTime.parse(m['a'] as String),
        points: points,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, DateTime from, List<MapEntry<DateTime, double>> points) async {
    await _box?.put(
      key,
      jsonEncode({
        'f': _day(from),
        'a': DateTime.now().toIso8601String(),
        'p': [
          for (final p in points) [_day(p.key), p.value],
        ],
      }),
    );
  }

  /// Склеивает старые и новые точки по дням; новые важнее.
  static List<MapEntry<DateTime, double>> merge(
    List<MapEntry<DateTime, double>> old,
    List<MapEntry<DateTime, double>> fresh,
  ) {
    final byDay = <int, double>{for (final p in old) _day(p.key): p.value};
    for (final p in fresh) {
      byDay[_day(p.key)] = p.value;
    }
    final days = byDay.keys.toList()..sort();
    return [for (final d in days) MapEntry(_date(d), byDay[d]!)];
  }

  /// История закрытий бумаги с [from]: из сохранённого, с докачкой новых
  /// дней. Без сети возвращает то, что уже есть на телефоне.
  static Future<List<MapEntry<DateTime, double>>> history(
    String ticker, {
    required DateTime from,
    String? market,
    String? board,
  }) =>
      _cached(
        ticker.toUpperCase(),
        from,
        (since) => MoexService.fetchSecurityHistory(ticker, from: since, market: market, board: board),
      );

  /// История курса валюты к рублю с биржи — по тем же правилам.
  static Future<List<MapEntry<DateTime, double>>> currency(String code, {required DateTime from}) =>
      _cached('FX:$code', from, (since) => MoexService.fetchCurrencyHistory(code, from: since));

  /// Сохранённая история курса без обращения к бирже.
  static List<MapEntry<DateTime, double>> cachedCurrency(String code) => _read('FX:$code')?.points ?? const [];

  static Future<List<MapEntry<DateTime, double>>> _cached(
    String key,
    DateTime from,
    Future<List<MapEntry<DateTime, double>>> Function(DateTime since) fetch,
  ) async {
    final cached = _read(key);
    final now = DateTime.now();
    final covers = cached != null && cached.points.isNotEmpty && !cached.from.isAfter(from);
    if (covers) {
      final at = cached.at;
      if (at.year == now.year && at.month == now.month && at.day == now.day) return cached.points;
      try {
        final fresh = await fetch(cached.points.last.key.subtract(const Duration(days: 5)));
        final merged = merge(cached.points, fresh);
        await _write(key, cached.from, merged);
        return merged;
      } catch (_) {
        return cached.points;
      }
    }
    try {
      final points = await fetch(from);
      if (points.isNotEmpty) await _write(key, from, points);
      return points.isNotEmpty ? points : (cached?.points ?? const []);
    } catch (_) {
      return cached?.points ?? const [];
    }
  }
}
