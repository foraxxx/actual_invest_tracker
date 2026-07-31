import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'moex_service.dart';

/// Котировка из сети, как она лежит в кэше.
class OnlinePrice {
  final double price;
  final DateTime fetchedAt;
  final String shortName;
  final String board;

  const OnlinePrice({
    required this.price,
    required this.fetchedAt,
    required this.shortName,
    required this.board,
  });

  Map<String, dynamic> toJson() => {
        'p': price,
        't': fetchedAt.toIso8601String(),
        'n': shortName,
        'b': board,
      };

  static OnlinePrice? fromJson(Map<String, dynamic> j) {
    final p = (j['p'] as num?)?.toDouble();
    final t = DateTime.tryParse('${j['t']}');
    if (p == null || t == null) return null;
    return OnlinePrice(
      price: p,
      fetchedAt: t,
      shortName: '${j['n'] ?? ''}',
      board: '${j['b'] ?? ''}',
    );
  }
}

/// Кэш котировок, полученных с биржи. Держится ОТДЕЛЬНО от ручных цен
/// (`ManualPriceService`): ручные отметки — это то, что ввёл пользователь, и
/// затирать их сетевыми данными нельзя. На графике цены обе линии рисуются
/// рядом.
class OnlinePriceService {
  static const boxName = 'online_prices';

  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static OnlinePrice? get(String ticker) {
    final raw = _box.get(ticker.toUpperCase());
    if (raw == null) return null;
    try {
      return OnlinePrice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Map<String, OnlinePrice> get all {
    final result = <String, OnlinePrice>{};
    for (final key in _box.keys) {
      final v = get('$key');
      if (v != null) result['$key'] = v;
    }
    return result;
  }

  /// Сколько прошло с момента загрузки котировки. Нужен, чтобы показывать
  /// «данные устарели», а не выдавать вчерашнюю цену за текущую.
  static Duration? ageOf(String ticker) {
    final p = get(ticker);
    return p == null ? null : DateTime.now().difference(p.fetchedAt);
  }

  /// Сохраняет пачку котировок одним заходом: при обновлении раз в 10 секунд
  /// поштучная запись в Hive заметно нагружала бы диск.
  static Future<void> saveAll(Map<String, MoexQuote> quotes) async {
    if (quotes.isEmpty) return;
    final entries = <String, String>{};
    quotes.forEach((ticker, q) {
      entries[ticker.toUpperCase()] = jsonEncode(OnlinePrice(
        price: q.price,
        fetchedAt: q.fetchedAt,
        shortName: q.shortName,
        board: q.board,
      ).toJson());
    });
    await _box.putAll(entries);
    version.value++;
  }

  static Future<void> clear() async {
    await _box.clear();
    version.value++;
  }
}
