import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Как сортировать список бумаг на бирже.
enum MarketSort { turnoverDesc, yieldDesc, name, priceDesc, priceAsc }

extension MarketSortX on MarketSort {
  String get title => switch (this) {
        MarketSort.turnoverDesc => 'По обороту',
        MarketSort.yieldDesc => 'По доходности',
        MarketSort.name => 'По тикеру',
        MarketSort.priceDesc => 'Цена по убыванию',
        MarketSort.priceAsc => 'Цена по возрастанию',
      };
}

/// Валюта выпуска.
enum CurrencyMode { any, rubles, foreign }

extension CurrencyModeX on CurrencyMode {
  String get title => switch (this) {
        CurrencyMode.any => 'Любая валюта',
        CurrencyMode.rubles => 'Рублёвые',
        CurrencyMode.foreign => 'Валютные',
      };
}

/// Тип купона у облигаций.
enum CouponMode { any, fixed, floating }

extension CouponModeX on CouponMode {
  String get title => switch (this) {
        CouponMode.any => 'Любой купон',
        CouponMode.fixed => 'Постоянный',
        CouponMode.floating => 'Переменный',
      };
}

/// Тип бумаги в терминах режимов торгов Мосбиржи.
enum MarketKind { shares, funds, corpBonds, ofz }

extension MarketKindX on MarketKind {
  String get title => switch (this) {
        MarketKind.shares => 'Акции',
        MarketKind.funds => 'Фонды',
        MarketKind.corpBonds => 'Облигации',
        MarketKind.ofz => 'ОФЗ',
      };

  String get board => switch (this) {
        MarketKind.shares => 'TQBR',
        MarketKind.funds => 'TQTF',
        MarketKind.corpBonds => 'TQCB',
        MarketKind.ofz => 'TQOB',
      };

  static MarketKind? fromBoard(String board) {
    for (final k in MarketKind.values) {
      if (k.board == board) return k;
    }
    return null;
  }
}

/// Набор условий отбора бумаг. Пустой набор значит «показывать всё».
class MarketFilter {
  final Set<MarketKind> kinds;
  final bool ownedOnly;
  final bool favoritesOnly;
  final CurrencyMode currency;
  final CouponMode coupon;

  /// Сколько купонов в году: 12, 4, 2, 1. Пустое множество — не важно.
  final Set<int> couponsPerYear;

  /// Минимальная доходность к погашению, %.
  final double? minYield;

  /// Минимальный оборот за день, ₽ — отсекает бумаги, которыми почти не торгуют.
  final double? minTurnover;

  final MarketSort sort;

  const MarketFilter({
    this.kinds = const {},
    this.ownedOnly = false,
    this.favoritesOnly = false,
    this.currency = CurrencyMode.any,
    this.coupon = CouponMode.any,
    this.couponsPerYear = const {},
    this.minYield,
    this.minTurnover,
    // По умолчанию сверху то, что реально торгуется.
    this.sort = MarketSort.turnoverDesc,
  });

  MarketFilter copyWith({
    Set<MarketKind>? kinds,
    bool? ownedOnly,
    bool? favoritesOnly,
    CurrencyMode? currency,
    CouponMode? coupon,
    Set<int>? couponsPerYear,
    double? minYield,
    double? minTurnover,
    bool clearYield = false,
    bool clearTurnover = false,
    MarketSort? sort,
  }) {
    return MarketFilter(
      kinds: kinds ?? this.kinds,
      ownedOnly: ownedOnly ?? this.ownedOnly,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      currency: currency ?? this.currency,
      coupon: coupon ?? this.coupon,
      couponsPerYear: couponsPerYear ?? this.couponsPerYear,
      minYield: clearYield ? null : (minYield ?? this.minYield),
      minTurnover: clearTurnover ? null : (minTurnover ?? this.minTurnover),
      sort: sort ?? this.sort,
    );
  }

  /// Сколько условий включено — это число показывается на кнопке фильтра.
  /// Сортировка условием не считается: она есть всегда.
  int get activeCount =>
      kinds.length +
      (ownedOnly ? 1 : 0) +
      (favoritesOnly ? 1 : 0) +
      (currency != CurrencyMode.any ? 1 : 0) +
      (coupon != CouponMode.any ? 1 : 0) +
      couponsPerYear.length +
      (minYield != null ? 1 : 0) +
      (minTurnover != null ? 1 : 0);

  bool get isEmpty => activeCount == 0 && sort == MarketSort.turnoverDesc;

  Map<String, dynamic> toJson() => {
        'kinds': kinds.map((k) => k.name).toList(),
        'owned': ownedOnly,
        'favorites': favoritesOnly,
        'currency': currency.name,
        'coupon': coupon.name,
        'couponsPerYear': couponsPerYear.toList(),
        'minYield': minYield,
        'minTurnover': minTurnover,
        'sort': sort.name,
      };

  static MarketFilter fromJson(Map<String, dynamic> json) {
    final kinds = <MarketKind>{};
    for (final raw in (json['kinds'] as List? ?? const [])) {
      for (final k in MarketKind.values) {
        if (k.name == '$raw') kinds.add(k);
      }
    }
    return MarketFilter(
      kinds: kinds,
      ownedOnly: json['owned'] == true,
      favoritesOnly: json['favorites'] == true,
      currency: CurrencyMode.values.firstWhere(
        (c) => c.name == '${json['currency']}',
        orElse: () => CurrencyMode.any,
      ),
      coupon: CouponMode.values.firstWhere(
        (c) => c.name == '${json['coupon']}',
        orElse: () => CouponMode.any,
      ),
      couponsPerYear: {
        for (final raw in (json['couponsPerYear'] as List? ?? const []))
          if (int.tryParse('$raw') != null) int.parse('$raw'),
      },
      minYield: (json['minYield'] as num?)?.toDouble(),
      minTurnover: (json['minTurnover'] as num?)?.toDouble(),
      sort: MarketSort.values.firstWhere(
        (s) => s.name == '${json['sort']}',
        orElse: () => MarketSort.turnoverDesc,
      ),
    );
  }
}

/// Сохранённые наборы фильтров с названиями — чтобы не собирать заново
/// «мои облигации» или «избранные акции» каждый раз.
class MarketFilterService {
  static const boxName = 'market_filters';

  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static Map<String, MarketFilter> get presets {
    final result = <String, MarketFilter>{};
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        result['$key'] = MarketFilter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Битую запись просто пропускаем — фильтр не те данные, чтобы из-за
        // него что-то ломать.
      }
    }
    return result;
  }

  static Future<void> save(String name, MarketFilter filter) async {
    final key = name.trim();
    if (key.isEmpty) return;
    await _box.put(key, jsonEncode(filter.toJson()));
    version.value++;
  }

  static Future<void> remove(String name) async {
    await _box.delete(name);
    version.value++;
  }
}
