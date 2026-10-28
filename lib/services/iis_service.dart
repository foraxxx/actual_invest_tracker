import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'cash_service.dart';
import 'portfolio_service.dart';
import 'tax_service.dart';

/// Тип ИИС.
enum IisType { newType, oldA, oldB }

extension IisTypeX on IisType {
  String get title => switch (this) {
        IisType.newType => 'Новый (с 2024)',
        IisType.oldA => 'Старый А',
        IisType.oldB => 'Старый Б',
      };

  String get short => switch (this) {
        IisType.newType => 'новый тип',
        IisType.oldA => 'старый, тип А',
        IisType.oldB => 'старый, тип Б',
      };

  /// Есть ли вычет на взносы.
  bool get hasContributionDeduction => this != IisType.oldB;
}

/// Отметка «вычет за год получен»: сколько пришло и когда.
class IisReceived {
  final double amount;
  final DateTime? date;

  const IisReceived({required this.amount, this.date});

  Map<String, dynamic> toJson() => {
        'a': amount,
        if (date != null) 'd': date!.toIso8601String(),
      };

  static IisReceived? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final a = (raw['a'] as num?)?.toDouble();
    if (a == null || a < 0) return null;
    return IisReceived(amount: a, date: DateTime.tryParse('${raw['d'] ?? ''}'));
  }
}

/// Настройки ИИС для портфеля.
class IisSettings {
  final IisType type;
  final DateTime openedAt;

  /// Ставка НДФЛ, по которой возвращается вычет: 13 или 15.
  final int ratePct;

  /// Полученные вычеты: год взносов -> отметка.
  final Map<int, IisReceived> received;

  const IisSettings({
    required this.type,
    required this.openedAt,
    this.ratePct = 13,
    this.received = const {},
  });

  IisSettings copyWith({IisType? type, DateTime? openedAt, int? ratePct, Map<int, IisReceived>? received}) =>
      IisSettings(
        type: type ?? this.type,
        openedAt: openedAt ?? this.openedAt,
        ratePct: ratePct ?? this.ratePct,
        received: received ?? this.received,
      );

  Map<String, dynamic> toJson() => {
        't': type.name,
        'o': openedAt.toIso8601String(),
        'r': ratePct,
        if (received.isNotEmpty) 'g': {for (final e in received.entries) '${e.key}': e.value.toJson()},
      };

  static IisSettings? fromJson(Map<String, dynamic> j) {
    final opened = DateTime.tryParse('${j['o']}');
    if (opened == null) return null;
    final received = <int, IisReceived>{};
    final rawReceived = j['g'];
    if (rawReceived is Map) {
      for (final e in rawReceived.entries) {
        final year = int.tryParse('${e.key}');
        final value = IisReceived.fromJson(e.value);
        if (year != null && value != null) received[year] = value;
      }
    }
    return IisSettings(
      type: IisType.values.firstWhere((t) => t.name == j['t'], orElse: () => IisType.newType),
      openedAt: opened,
      ratePct: (j['r'] as num?)?.toInt() == 15 ? 15 : 13,
      received: received,
    );
  }
}

/// Сводка по ИИС за текущий год.
class IisYear {
  final int year;
  final double contributed;

  /// База для вычета (400 000 ₽ в год) или лимит взносов старого ИИС.
  final double limit;

  /// Вычет за год: ставка × взносы в пределах 400 000 ₽. 0 у типа Б.
  final double deduction;
  final double maxDeduction;

  const IisYear({
    required this.year,
    required this.contributed,
    required this.limit,
    required this.deduction,
    required this.maxDeduction,
  });

  double get progress => limit <= 0 ? 0 : (contributed / limit).clamp(0.0, 1.0).toDouble();
  double get leftToLimit => math.max(0, limit - contributed);
  bool get limitReached => contributed >= limit - 0.5;
}

/// ИИС: отметка портфеля и расчёты взносов, вычета и срока.
///
/// Правила — по данным на 2026 год: вычет 13% (15% при доходе выше 2,4 млн ₽)
/// со взносов до 400 000 ₽ в год; у старого ИИС лимит взносов 1 млн ₽ в год,
/// минимальный срок 3 года; у нового ИИС минимальный срок зависит от года
/// открытия — 5 лет для 2024–2026 и на год больше за каждый следующий год, до
/// 10 лет. Вычет не может быть больше НДФЛ, уплаченного за год, — этого
/// приложение не знает, поэтому сумма показывается как ориентир.
class IisService {
  IisService._();

  static const boxName = 'iis';
  static const deductionBase = 400000.0;
  static const oldContributionLimit = 1000000.0;

  static late Box<String> _box;
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static IisSettings? settingsFor(String portfolioId) {
    final raw = _box.get(portfolioId);
    if (raw == null) return null;
    try {
      return IisSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static IisSettings? get current => settingsFor(PortfolioService.activeId);

  static Future<void> save(String portfolioId, IisSettings? settings) async {
    if (settings == null) {
      await _box.delete(portfolioId);
    } else {
      await _box.put(portfolioId, jsonEncode(settings.toJson()));
    }
    version.value++;
  }

  /// Минимальный срок счёта в годах.
  @visibleForTesting
  static int minTermYears(IisSettings s) {
    if (s.type != IisType.newType) return 3;
    final y = s.openedAt.year;
    if (y <= 2026) return 5;
    return math.min(10, 5 + (y - 2026));
  }

  /// Дата, после которой счёт можно закрыть без потери льгот.
  static DateTime minTermEnd(IisSettings s) {
    final o = s.openedAt;
    return DateTime(o.year + minTermYears(s), o.month, o.day);
  }

  /// Взносы по месяцам: ключ — первое число месяца.
  static Map<DateTime, double> contributionsByMonth() {
    final result = <DateTime, double>{};
    for (final m in CashService.summary().moves) {
      if (m.kind != CashMoveKind.deposit && m.kind != CashMoveKind.autoDeposit) continue;
      if (m.amountRub <= 0) continue;
      final key = DateTime(m.date.year, m.date.month);
      result[key] = (result[key] ?? 0) + m.amountRub;
    }
    return result;
  }

  static IisYear yearSummary(IisSettings s, int year, {Map<DateTime, double>? byMonth}) {
    final months = byMonth ?? contributionsByMonth();
    final contributed = months.entries.where((e) => e.key.year == year).fold(0.0, (a, e) => a + e.value);
    // Ставка — общая, из настроек налога.
    final rate = TaxService.rate;
    final hasDeduction = s.type.hasContributionDeduction;
    final limit = hasDeduction ? deductionBase : oldContributionLimit;
    return IisYear(
      year: year,
      contributed: contributed,
      limit: limit,
      deduction: hasDeduction ? math.min(contributed, deductionBase) * rate : 0,
      maxDeduction: hasDeduction ? deductionBase * rate : 0,
    );
  }

  /// Отмечает вычет за [year] полученным (или снимает отметку, если
  /// [value] null) у текущего портфеля.
  static Future<void> setReceived(int year, IisReceived? value) async {
    final s = current;
    if (s == null) return;
    final map = Map<int, IisReceived>.from(s.received);
    if (value == null) {
      map.remove(year);
    } else {
      map[year] = value;
    }
    await save(PortfolioService.activeId, s.copyWith(received: map));
  }

  /// Прошедшие годы, за которые вычет положен, но не отмечен полученным.
  /// Сначала самые свежие.
  static List<IisYear> pendingYears(IisSettings s, {Map<DateTime, double>? byMonth, DateTime? now}) {
    if (!s.type.hasContributionDeduction) return const [];
    final months = byMonth ?? contributionsByMonth();
    final thisYear = (now ?? DateTime.now()).year;
    return [
      for (int y = thisYear - 1; y >= s.openedAt.year; y--)
        if (!s.received.containsKey(y)) yearSummary(s, y, byMonth: months),
    ].where((y) => y.deduction > 0.5).toList();
  }

  /// Сколько вычетов отмечено полученными за всё время.
  static double totalReceived(IisSettings s) => s.received.values.fold(0.0, (a, r) => a + r.amount);

  /// Годы с открытия счёта по текущий.
  static List<int> years(IisSettings s) {
    final now = DateTime.now().year;
    return [for (int y = s.openedAt.year; y <= now; y++) y];
  }
}
