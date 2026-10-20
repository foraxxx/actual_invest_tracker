import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'work_calendar.dart';

/// Как делить трату между выплатами.
///
/// [half] — поровну с обеих. [salary] и [advance] — целиком с первой или со
/// второй выплаты. [auto] — программа сама решает: целиком с той выплаты, где
/// свободнее, а делит, только если целиком не помещается.
enum BudgetSource { auto, half, salary, advance }

BudgetSource budgetSourceFrom(Object? name) => switch (name) {
      'half' => BudgetSource.half,
      'salary' => BudgetSource.salary,
      'advance' => BudgetSource.advance,
      _ => BudgetSource.auto,
    };

/// День выплаты: число месяца или последний день.
class PayDay {
  final bool last;
  final int day;

  const PayDay.day(this.day) : last = false;
  const PayDay.lastDay()
      : last = true,
        day = 31;

  int inMonth(int year, int month) => last ? daysInMonth(year, month) : math.min(day, daysInMonth(year, month));

  /// День выплаты с учётом выходных и праздников: если он нерабочий, деньги
  /// приходят в ближайший рабочий день раньше (можно выключить в настройках).
  int scheduled(int year, int month) {
    final d = inMonth(year, month);
    if (!BudgetService.shiftToWorkday) return d;
    return WorkCalendar.payDay(DateTime(year, month, d)).day;
  }

  Map<String, dynamic> toJson() => {'l': last, 'd': day};

  static PayDay fromJson(Object? raw, PayDay fallback) {
    if (raw is! Map) return fallback;
    if (raw['l'] == true) return const PayDay.lastDay();
    final d = (raw['d'] as num?)?.toInt();
    if (d == null || d < 1 || d > 31) return fallback;
    return PayDay.day(d);
  }
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Общие настройки бюджета: названия и дни двух выплат.
class BudgetConfig {
  final List<String> names;
  final List<PayDay> days;

  const BudgetConfig({required this.names, required this.days});

  static const initial = BudgetConfig(
    names: ['Зарплата', 'Аванс'],
    days: [PayDay.day(15), PayDay.lastDay()],
  );

  Map<String, dynamic> toJson() => {
        'n': names,
        'd': [for (final d in days) d.toJson()],
      };

  static BudgetConfig fromJson(Object? raw) {
    if (raw is! Map) return initial;
    final n = raw['n'];
    final d = raw['d'];
    final names = <String>[
      for (int i = 0; i < 2; i++)
        n is List && n.length > i && '${n[i]}'.trim().isNotEmpty ? '${n[i]}' : initial.names[i],
    ];
    final days = <PayDay>[
      for (int i = 0; i < 2; i++) PayDay.fromJson(d is List && d.length > i ? d[i] : null, initial.days[i]),
    ];
    return BudgetConfig(names: names, days: days);
  }
}

/// Категория: просто название и значок. Суммы задаются тратами месяца.
class BudgetCategory {
  final String id;
  final String name;
  final String emoji;

  /// Удалённая категория остаётся в прошлых месяцах, но в новые траты её
  /// выбрать нельзя.
  final bool deleted;

  const BudgetCategory({required this.id, required this.name, required this.emoji, this.deleted = false});

  BudgetCategory copyWith({String? name, String? emoji, bool? deleted}) => BudgetCategory(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'e': emoji,
        if (deleted) 'x': true,
      };

  static BudgetCategory? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return BudgetCategory(
      id: id,
      name: '${raw['n'] ?? ''}',
      emoji: '${raw['e'] ?? '•'}',
      deleted: raw['x'] == true,
    );
  }
}

/// Трата месяца: сколько отложить в категорию и как делить между выплатами.
class BudgetItem {
  final double amount;
  final BudgetSource source;

  const BudgetItem({required this.amount, this.source = BudgetSource.auto});

  Map<String, dynamic> toJson() => {'a': amount, 's': source.name};

  static BudgetItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final a = (raw['a'] as num?)?.toDouble();
    if (a == null) return null;
    return BudgetItem(amount: a, source: budgetSourceFrom(raw['s']));
  }
}

/// Разовое поступление в месяце: премия, возврат и т.п.
class BudgetExtra {
  final String id;
  final String name;
  final int day;
  final double amount;

  /// К какой выплате относится: 0 — первая, 1 — вторая.
  final int payout;

  const BudgetExtra({required this.id, required this.name, required this.day, required this.amount, required this.payout});

  Map<String, dynamic> toJson() => {'id': id, 'n': name, 'd': day, 'a': amount, 'p': payout};

  static BudgetExtra? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final a = (raw['a'] as num?)?.toDouble();
    if (a == null) return null;
    return BudgetExtra(
      id: '${raw['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      name: '${raw['n'] ?? ''}',
      day: ((raw['d'] as num?)?.toInt() ?? 1).clamp(1, 31).toInt(),
      amount: a,
      payout: (raw['p'] as num?)?.toInt() == 1 ? 1 : 0,
    );
  }
}

/// Отметка «отложил»: сколько, в какую категорию, с какой выплаты, когда.
class BudgetEntry {
  final String id;
  final String category;
  final int payout;
  final double amount;
  final DateTime date;

  const BudgetEntry({required this.id, required this.category, required this.payout, required this.amount, required this.date});

  Map<String, dynamic> toJson() => {'id': id, 'c': category, 'p': payout, 'a': amount, 'd': date.toIso8601String()};

  static BudgetEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['c'];
    final a = (raw['a'] as num?)?.toDouble();
    final d = DateTime.tryParse('${raw['d'] ?? ''}');
    if (c is! String || a == null || d == null) return null;
    return BudgetEntry(
      id: '${raw['id'] ?? d.microsecondsSinceEpoch}',
      category: c,
      payout: (raw['p'] as num?)?.toInt() == 1 ? 1 : 0,
      amount: a,
      date: d,
    );
  }
}

/// Пара сумм: с первой и со второй выплаты.
typedef Pair = List<double>;

Map<String, dynamic> _pairsToJson(Map<String, Pair> m) => {
      for (final e in m.entries)
        if (e.value[0].abs() > 0.004 || e.value[1].abs() > 0.004) e.key: [e.value[0], e.value[1]],
    };

Map<String, Pair> _pairsFromJson(Object? raw) {
  final result = <String, Pair>{};
  if (raw is! Map) return result;
  for (final e in raw.entries) {
    final v = e.value;
    if (v is List && v.length >= 2) {
      result['${e.key}'] = [(v[0] as num?)?.toDouble() ?? 0, (v[1] as num?)?.toDouble() ?? 0];
    }
  }
  return result;
}

/// Хранимые данные месяца.
class BudgetMonthData {
  final int year;
  final int month;

  /// Месяц заполнен: заданы доходы и траты. Незаполненная запись бывает,
  /// только если сюда что-то перенесли из прошлого месяца.
  final bool filled;

  /// Суммы двух выплат (на руки).
  final List<double> income;

  /// День выплаты в этом месяце, если его сдвинули вручную.
  final List<int?> dayOverride;

  /// Сколько оставлять на жизнь с каждой выплаты.
  final double living;

  final List<BudgetExtra> extras;

  /// Траты месяца: категория → сумма и способ деления.
  final Map<String, BudgetItem> items;

  /// Перенесено из прошлого месяца.
  final Map<String, Pair> carryIn;

  /// Перенесено отсюда на следующий месяц.
  final Map<String, Pair> moved;

  final List<BudgetEntry> entries;

  /// Раскладка траты по выплатам, зафиксированная при первой отметке: дальше
  /// авто-распределение её не двигает.
  final Map<String, Pair> locked;

  const BudgetMonthData({
    required this.year,
    required this.month,
    this.filled = true,
    this.income = const [0, 0],
    this.dayOverride = const [null, null],
    this.living = 0,
    this.extras = const [],
    this.items = const {},
    this.carryIn = const {},
    this.moved = const {},
    this.entries = const [],
    this.locked = const {},
  });

  String get key => BudgetService.monthKey(year, month);

  BudgetMonthData copyWith({
    bool? filled,
    List<double>? income,
    List<int?>? dayOverride,
    double? living,
    List<BudgetExtra>? extras,
    Map<String, BudgetItem>? items,
    Map<String, Pair>? carryIn,
    Map<String, Pair>? moved,
    List<BudgetEntry>? entries,
    Map<String, Pair>? locked,
  }) =>
      BudgetMonthData(
        year: year,
        month: month,
        filled: filled ?? this.filled,
        income: income ?? this.income,
        dayOverride: dayOverride ?? this.dayOverride,
        living: living ?? this.living,
        extras: extras ?? this.extras,
        items: items ?? this.items,
        carryIn: carryIn ?? this.carryIn,
        moved: moved ?? this.moved,
        entries: entries ?? this.entries,
        locked: locked ?? this.locked,
      );

  Map<String, dynamic> toJson() => {
        'v': 2,
        'y': year,
        'm': month,
        'fl': filled,
        'i': income,
        'o': dayOverride,
        'l': living,
        'x': [for (final e in extras) e.toJson()],
        'it': {for (final e in items.entries) e.key: e.value.toJson()},
        'c': _pairsToJson(carryIn),
        'mv': _pairsToJson(moved),
        'e': [for (final e in entries) e.toJson()],
        if (locked.isNotEmpty) 'k': _pairsToJson(locked),
      };

  static BudgetMonthData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final y = (raw['y'] as num?)?.toInt();
    final m = (raw['m'] as num?)?.toInt();
    if (y == null || m == null || m < 1 || m > 12) return null;
    final i = raw['i'];
    final o = raw['o'];
    final items = <String, BudgetItem>{};
    final rawItems = raw['it'];
    if (rawItems is Map) {
      for (final e in rawItems.entries) {
        final item = BudgetItem.fromJson(e.value);
        if (item != null) items['${e.key}'] = item;
      }
    }
    return BudgetMonthData(
      year: y,
      month: m,
      filled: raw['fl'] != false,
      income: [
        for (int k = 0; k < 2; k++) i is List && i.length > k ? ((i[k] as num?)?.toDouble() ?? 0) : 0.0,
      ],
      dayOverride: [
        for (int k = 0; k < 2; k++) o is List && o.length > k ? (o[k] as num?)?.toInt() : null,
      ],
      living: (raw['l'] as num?)?.toDouble() ?? 0,
      extras: (raw['x'] as List? ?? const []).map(BudgetExtra.fromJson).whereType<BudgetExtra>().toList(),
      items: items,
      carryIn: _pairsFromJson(raw['c']),
      moved: _pairsFromJson(raw['mv']),
      entries: (raw['e'] as List? ?? const []).map(BudgetEntry.fromJson).whereType<BudgetEntry>().toList(),
      locked: _pairsFromJson(raw['k']),
    );
  }
}

/// Строка траты в расчёте месяца.
class BudgetLine {
  final BudgetCategory category;

  /// Сама трата месяца; null — строка есть только из-за переноса или
  /// отметок.
  final BudgetItem? item;

  /// Сколько отложить с каждой выплаты (с переносом из прошлого месяца, за
  /// вычетом перенесённого дальше).
  final Pair plan;
  final Pair done;
  final Pair carryIn;
  final Pair moved;

  const BudgetLine({
    required this.category,
    required this.item,
    required this.plan,
    required this.done,
    required this.carryIn,
    required this.moved,
  });

  /// Как делится трата в этом месяце.
  BudgetSource get source => item?.source ?? BudgetSource.auto;

  double get planTotal => plan[0] + plan[1];
  double get doneTotal => done[0] + done[1];
  double left(int i) => math.max(0.0, plan[i] - done[i]);
  double get leftTotal => left(0) + left(1);
  double get carryTotal => carryIn[0] + carryIn[1];
  double get movedTotal => moved[0] + moved[1];
  bool cellDone(int i) => plan[i] > 0.5 && done[i] >= plan[i] - 0.5;
  bool get complete => planTotal > 0.5 && doneTotal >= planTotal - 0.5;
}

/// Полный расчёт месяца.
class BudgetMonthView {
  final BudgetMonthData data;
  final BudgetConfig config;
  final List<BudgetLine> lines;

  /// Есть ли у месяца запись (заполненная или с переносом).
  final bool stored;

  const BudgetMonthView({required this.data, required this.config, required this.lines, required this.stored});

  int get year => data.year;
  int get month => data.month;
  bool get filled => stored && data.filled;

  int payDay(int i) {
    final o = data.dayOverride[i];
    if (o != null) return math.min(o, daysInMonth(year, month));
    return config.days[i].scheduled(year, month);
  }

  DateTime payDate(int i) => DateTime(year, month, payDay(i));
  bool dayMoved(int i) => data.dayOverride[i] != null && data.dayOverride[i] != config.days[i].scheduled(year, month);

  double extrasFor(int i) => data.extras.where((e) => e.payout == i).fold(0.0, (a, e) => a + e.amount);

  /// Всё, что приходит с выплатой: она сама и разовые поступления к ней.
  double income(int i) => data.income[i] + extrasFor(i);

  double planned(int i) => lines.fold(0.0, (a, l) => a + l.plan[i]);
  double get plannedTotal => planned(0) + planned(1);
  double doneFor(int i) => lines.fold(0.0, (a, l) => a + l.done[i]);
  double get doneTotal => doneFor(0) + doneFor(1);
  double leftFor(int i) => lines.fold(0.0, (a, l) => a + l.left(i));

  /// Что остаётся с выплаты после «на жизнь» и трат. Меньше нуля — не
  /// хватает.
  double rest(int i) => income(i) - data.living - planned(i);
  double get freeTotal => math.max(0.0, rest(0)) + math.max(0.0, rest(1));

  double get progress => plannedTotal <= 0 ? 0 : (doneTotal / plannedTotal).clamp(0.0, 1.0).toDouble();
  bool get complete => plannedTotal > 0.5 && doneTotal >= plannedTotal - 0.5;

  BudgetLine? lineFor(String id) {
    for (final l in lines) {
      if (l.category.id == id) return l;
    }
    return null;
  }
}

/// Состояние месяца для выбора месяца.
enum BudgetMonthState { empty, future, current, complete, partial }

class BudgetMonthStatus {
  final BudgetMonthState state;
  final double progress;
  const BudgetMonthStatus(this.state, [this.progress = 0]);
}

/// Бюджет: сколько отложить с зарплаты и аванса. Общий для всех портфелей,
/// хранится отдельно от них.
class BudgetService {
  BudgetService._();

  static const boxName = 'budget';
  static late Box<String> _box;
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
    await _migrate();
    await checkMonthChange();
  }

  static String monthKey(int y, int m) => '$y-${m.toString().padLeft(2, '0')}';
  static int _ord(int y, int m) => y * 12 + (m - 1);
  static (int, int) _fromOrd(int o) => (o ~/ 12, o % 12 + 1);

  static DateTime get _now => DateTime.now();
  static int get _currentOrd => _ord(_now.year, _now.month);

  /// Начат ли бюджет: пользователь хоть раз его открывал.
  static bool get started => _box.containsKey('cats');

  /// Переносить выплату с выходного или праздника на рабочий день раньше.
  static bool get shiftToWorkday {
    try {
      return _box.get('shift') != '0';
    } catch (_) {
      return true;
    }
  }

  static Future<void> setShiftToWorkday(bool value) async {
    await _touch();
    await _box.put('shift', value ? '1' : '0');
    version.value++;
  }

  // --- Настройки ---

  static BudgetConfig get config {
    final raw = _box.get('config');
    if (raw == null) return BudgetConfig.initial;
    try {
      return BudgetConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      return BudgetConfig.initial;
    }
  }

  /// Сохраняет дни и названия выплат. Прошедшие месяцы сохраняют прежние
  /// дни — они фиксируются как ручные.
  static Future<void> saveConfig(BudgetConfig c) async {
    final old = config;
    final now = _currentOrd;
    for (final d in _months()) {
      if (_ord(d.year, d.month) >= now) continue;
      final o = [
        for (int i = 0; i < 2; i++) d.dayOverride[i] ?? old.days[i].scheduled(d.year, d.month),
      ];
      await _box.put('m:${d.key}', jsonEncode(d.copyWith(dayOverride: o).toJson()));
    }
    _monthsCache = null;
    await _touch();
    await _box.put('config', jsonEncode(c.toJson()));
    version.value++;
  }

  // --- Категории ---

  static const defaultCategories = [
    ('📈', 'Инвестиции'),
    ('🏠', 'Квартира'),
    ('🚗', 'Машина'),
    ('🏖', 'Отпуск'),
    ('💻', 'Электроника'),
    ('🛋', 'Для дома'),
    ('🏋', 'Зал'),
    ('👕', 'Одежда'),
    ('💊', 'Здоровье'),
    ('🎁', 'Подарки'),
    ('📺', 'Подписки'),
    ('🌐', 'Интернет'),
  ];

  static List<BudgetCategory> get allCategories {
    final raw = _box.get('cats');
    if (raw == null) return <BudgetCategory>[];
    try {
      return (jsonDecode(raw) as List).map(BudgetCategory.fromJson).whereType<BudgetCategory>().toList();
    } catch (_) {
      return <BudgetCategory>[];
    }
  }

  static List<BudgetCategory> get categories => allCategories.where((c) => !c.deleted).toList();

  static BudgetCategory? category(String id) {
    for (final c in allCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Когда бюджет последний раз менялся — для сравнения с бэкапом.
  static DateTime? get updatedAt => DateTime.tryParse(_box.get('meta:updated') ?? '');

  static DateTime? updatedIn(Map raw) => DateTime.tryParse('${raw['meta:updated'] ?? ''}');

  static Future<void> _touch() => _box.put('meta:updated', DateTime.now().toIso8601String());

  static Future<void> _saveCategories(List<BudgetCategory> list) async {
    await _touch();
    await _box.put('cats', jsonEncode([for (final c in list) c.toJson()]));
    version.value++;
  }

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(1000)}';

  /// Первый вход: стандартные категории.
  static Future<void> ensureStarted() async {
    if (started) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    await _saveCategories([
      for (int i = 0; i < defaultCategories.length; i++)
        BudgetCategory(id: '${now}_$i', emoji: defaultCategories[i].$1, name: defaultCategories[i].$2),
    ]);
  }

  static Future<void> saveCategory(BudgetCategory c) async {
    final list = allCategories;
    final i = list.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      list[i] = c;
    } else {
      list.add(c);
    }
    await _saveCategories(list);
  }

  /// Удаляет категорию. Если она есть в каком-нибудь месяце — прячет: в тех
  /// месяцах она должна остаться.
  static Future<void> deleteCategory(String id) async {
    final list = allCategories;
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final used = _months().any((m) =>
        m.items.containsKey(id) || m.entries.any((e) => e.category == id) || m.carryIn.containsKey(id));
    if (used) {
      list[i] = list[i].copyWith(deleted: true);
    } else {
      list.removeAt(i);
    }
    await _saveCategories(list);
  }

  // --- Месяцы ---

  static BudgetMonthData? _load(int y, int m) {
    final raw = _box.get('m:${monthKey(y, m)}');
    if (raw == null) return null;
    try {
      return BudgetMonthData.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(BudgetMonthData d) async {
    _monthsCache = null;
    await _touch();
    await _box.put('m:${d.key}', jsonEncode(d.toJson()));
    _monthsCache = null;
    version.value++;
  }

  static List<BudgetMonthData>? _monthsCache;

  static List<BudgetMonthData> _months() => _monthsCache ??= _readMonths();

  static List<BudgetMonthData> _readMonths() {
    final result = <BudgetMonthData>[];
    for (final k in _box.keys) {
      if ('$k'.startsWith('m:')) {
        final raw = _box.get(k);
        if (raw == null) continue;
        try {
          final d = BudgetMonthData.fromJson(jsonDecode(raw));
          if (d != null) result.add(d);
        } catch (_) {}
      }
    }
    result.sort((a, b) => _ord(a.year, a.month).compareTo(_ord(b.year, b.month)));
    return result;
  }

  static bool isFilled(int y, int m) => _load(y, m)?.filled ?? false;

  /// Ближайший заполненный месяц до [y]-[m].
  static (int, int)? previousFilled(int y, int m) {
    final limit = _ord(y, m);
    (int, int)? best;
    for (final d in _months()) {
      if (d.filled && _ord(d.year, d.month) < limit) best = (d.year, d.month);
    }
    return best;
  }

  /// Скопировать месяц [from] в [to]: доходы, «на жизнь» и все траты, без
  /// отметок и премий. Перенесённое в [to] остаётся.
  static Future<void> copyMonth((int, int) from, (int, int) to) async {
    final src = _load(from.$1, from.$2);
    if (src == null) return;
    final existing = _load(to.$1, to.$2);
    final base = existing ?? BudgetMonthData(year: to.$1, month: to.$2);
    await _save(base.copyWith(
      filled: true,
      income: [src.income[0], src.income[1]],
      living: src.living,
      items: Map<String, BudgetItem>.from(src.items),
    ));
  }

  /// Скопировать только траты из [from] в уже заполненный месяц.
  static Future<void> copyItems((int, int) from, (int, int) to) async {
    final src = _load(from.$1, from.$2);
    final dst = _load(to.$1, to.$2);
    if (src == null || dst == null) return;
    await _save(dst.copyWith(items: Map<String, BudgetItem>.from(src.items)));
  }

  /// Начать месяц с нуля.
  static Future<void> startEmpty(int y, int m) async {
    final existing = _load(y, m);
    await _save((existing ?? BudgetMonthData(year: y, month: m)).copyWith(filled: true));
  }

  /// При смене месяца: если новый месяц ещё не заполнен, он копируется из
  /// прошлого. Срабатывает один раз на месяц — после сброса месяц остаётся
  /// пустым.
  static Future<void> checkMonthChange() async {
    final now = _currentOrd;
    final seen = int.tryParse(_box.get('meta:seen') ?? '');
    if (seen == now) return;
    await _box.put('meta:seen', '$now');
    if (seen == null) return;
    final (y, m) = _fromOrd(now);
    if (!isFilled(y, m)) {
      final prev = previousFilled(y, m);
      if (prev != null) await copyMonth(prev, (y, m));
    }
    version.value++;
  }

  static Future<BudgetMonthData> _ensure(int y, int m) async {
    final d = _load(y, m);
    if (d != null) return d;
    final created = BudgetMonthData(year: y, month: m);
    await _save(created);
    return created;
  }

  static Future<void> saveMonth({
    required int year,
    required int month,
    required List<double> income,
    required List<int?> dayOverride,
    required double living,
    required List<BudgetExtra> extras,
  }) async {
    final d = await _ensure(year, month);
    await _save(d.copyWith(
      filled: true,
      income: income,
      dayOverride: dayOverride,
      living: living,
      extras: extras,
    ));
  }

  /// Сбросить месяц целиком: доходы, траты, отметки, переносы. Перенесённое
  /// сюда возвращается в прошлый месяц, перенесённое отсюда убирается из
  /// следующего. Месяц становится пустым.
  static Future<void> resetMonth(int y, int m) async {
    final d = _load(y, m);
    if (d == null) return;
    if (d.carryIn.isNotEmpty) {
      final (py, pm) = _fromOrd(_ord(y, m) - 1);
      final prev = _load(py, pm);
      if (prev != null) {
        var moved = prev.moved;
        for (final e in d.carryIn.entries) {
          moved = _addPair(moved, e.key, [-e.value[0], -e.value[1]]);
        }
        await _save(prev.copyWith(moved: moved));
      }
    }
    if (d.moved.isNotEmpty) {
      final (ny, nm) = _fromOrd(_ord(y, m) + 1);
      final next = _load(ny, nm);
      if (next != null) {
        var carry = next.carryIn;
        for (final e in d.moved.entries) {
          carry = _addPair(carry, e.key, [-e.value[0], -e.value[1]]);
        }
        final updated = next.copyWith(carryIn: carry);
        // Пустая запись, где был только перенос, больше не нужна.
        if (!updated.filled && updated.carryIn.isEmpty && updated.entries.isEmpty) {
          _monthsCache = null;
          await _box.delete('m:${updated.key}');
        } else {
          await _save(updated);
        }
      }
    }
    _monthsCache = null;
    await _touch();
    await _box.delete('m:${d.key}');
    _monthsCache = null;
    version.value++;
  }

  /// Вернуть месяц как был (для «Отменить»).
  static Future<void> restoreMonth(BudgetMonthData d) => _save(d);

  static BudgetMonthData? monthData(int y, int m) => _load(y, m);

  // --- Траты ---

  /// Добавить или заменить трату месяца.
  static Future<void> setItem(int y, int m, String category, BudgetItem item) async {
    final d = await _ensure(y, m);
    final items = Map<String, BudgetItem>.from(d.items)..[category] = item;
    // Сменили способ деления — раскладка считается заново.
    final locked = Map<String, Pair>.from(d.locked);
    if (d.items[category]?.source != item.source) locked.remove(category);
    await _save(d.copyWith(filled: true, items: items, locked: locked));
  }

  /// Убрать трату из месяца вместе с её отметками.
  static Future<void> removeItem(int y, int m, String category) async {
    final d = _load(y, m);
    if (d == null) return;
    await _save(d.copyWith(
      items: Map<String, BudgetItem>.from(d.items)..remove(category),
      entries: d.entries.where((e) => e.category != category).toList(),
      locked: Map<String, Pair>.from(d.locked)..remove(category),
    ));
  }

  // --- Расчёт ---

  /// Часть суммы [whole], округлённая до сотни (у маленьких сумм — до рубля).
  static double round100(double v, double whole) {
    if (whole >= 200) return ((v / 100).round() * 100.0).clamp(0.0, whole).toDouble();
    return v.roundToDouble().clamp(0.0, whole).toDouble();
  }

  static double _floorPart(double v, double whole) {
    if (whole >= 200) return ((v / 100).floor() * 100.0).clamp(0.0, whole).toDouble();
    return v.floorToDouble().clamp(0.0, whole).toDouble();
  }

  static Pair _half(double amt) {
    final a = amt >= 200 ? (amt / 2 / 100).ceil() * 100.0 : (amt / 2).ceilToDouble();
    final first = math.min(a, amt);
    return [first, amt - first];
  }

  /// Раскладка трат месяца по выплатам.
  ///
  /// Сначала «пополам» и закреплённые за выплатой. Потом «авто» по одной, от
  /// больших сумм к меньшим: каждая целиком на ту выплату, где сейчас
  /// свободнее. Если целиком не помещается никуда — берётся сколько свободно,
  /// остальное со второй выплаты. Трату, которую уже отмечали, не двигаем.
  static Map<String, Pair> _plan(BudgetMonthData d) {
    final plan = <String, Pair>{};
    final autos = <(String, double)>[];
    final fixed = [0.0, 0.0];
    for (final e in d.items.entries) {
      final amt = e.value.amount;
      if (amt <= 0.004) continue;
      final lock = d.locked[e.key];
      Pair? cell;
      if (lock != null && lock[0] + lock[1] > 0.004) {
        final total = lock[0] + lock[1];
        final first = (amt - total).abs() < 0.5 ? lock[0] : round100(amt * lock[0] / total, amt);
        cell = [first, amt - first];
      } else {
        switch (e.value.source) {
          case BudgetSource.half:
            cell = _half(amt);
          case BudgetSource.salary:
            cell = [amt, 0.0];
          case BudgetSource.advance:
            cell = [0.0, amt];
          case BudgetSource.auto:
            autos.add((e.key, amt));
        }
      }
      if (cell != null) {
        plan[e.key] = cell;
        fixed[0] += cell[0];
        fixed[1] += cell[1];
      }
    }
    if (autos.isEmpty) return plan;
    double extra(int i) => d.extras.where((e) => e.payout == i).fold(0.0, (a, e) => a + e.amount);
    double carry(int i) => d.carryIn.values.fold(0.0, (a, p) => a + p[i]);
    final free = [
      for (int i = 0; i < 2; i++) d.income[i] + extra(i) - d.living - fixed[i] - carry(i),
    ];
    autos.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (id, amt) in autos) {
      final best = free[0] >= free[1] ? 0 : 1;
      final other = 1 - best;
      final cell = [0.0, 0.0];
      if (amt <= free[best] + 0.5 || free[best] <= 0) {
        cell[best] = amt;
      } else {
        final part = _floorPart(free[best], amt);
        cell[best] = part;
        cell[other] = amt - part;
      }
      plan[id] = cell;
      free[0] -= cell[0];
      free[1] -= cell[1];
    }
    return plan;
  }

  /// Расчёт месяца. Если записи нет — пустой месяц (не сохраняется).
  static BudgetMonthView view(int y, int m) {
    final stored = _load(y, m);
    final d = stored ?? BudgetMonthData(year: y, month: m, filled: false);
    final base = _plan(d);
    final ids = <String>{
      ...d.items.keys,
      ...d.carryIn.keys,
      ...d.entries.map((e) => e.category),
    };
    final lines = <BudgetLine>[];
    Pair get(Map<String, Pair> m, String id) => m[id] ?? [0.0, 0.0];
    for (final id in ids) {
      final c = category(id) ?? BudgetCategory(id: id, name: 'Удалённая категория', emoji: '•', deleted: true);
      final b = get(base, id);
      final ci = get(d.carryIn, id);
      final mv = get(d.moved, id);
      final done = [0.0, 0.0];
      for (final e in d.entries) {
        if (e.category == id) done[e.payout] += e.amount;
      }
      lines.add(BudgetLine(
        category: c,
        item: d.items[id],
        plan: [for (int i = 0; i < 2; i++) math.max(0.0, b[i] + ci[i] - mv[i])],
        done: done,
        carryIn: ci,
        moved: mv,
      ));
    }
    // Сначала самые большие траты.
    lines.sort((a, b) {
      final byPlan = b.planTotal.compareTo(a.planTotal);
      return byPlan != 0 ? byPlan : a.category.name.compareTo(b.category.name);
    });
    return BudgetMonthView(data: d, config: config, lines: lines, stored: stored != null);
  }

  // --- Отметки ---

  /// Добавляет отметку и возвращает её id.
  static Future<String?> addEntry(int y, int m, String category, int payout, double amount, {DateTime? date}) async {
    if (amount.abs() < 0.5) return null;
    final d = await _ensure(y, m);
    final now = DateTime.now();
    // Отметка в чужом месяце датируется днём выплаты.
    final inMonth = now.year == y && now.month == m;
    final when = date ?? (inMonth ? now : DateTime(y, m, view(y, m).payDay(payout)));
    final id = newId();
    var locked = d.locked;
    if (!locked.containsKey(category)) {
      final base = _plan(d)[category];
      if (base != null) locked = {...locked, category: [base[0], base[1]]};
    }
    await _save(d.copyWith(
      entries: [
        ...d.entries,
        BudgetEntry(id: id, category: category, payout: payout, amount: amount, date: when),
      ],
      locked: locked,
    ));
    return id;
  }

  /// Отметить всё, что осталось по ячейке (или по всей трате).
  static Future<List<String>> markLeft(int y, int m, String category, {int? payout}) async {
    final ids = <String>[];
    final line = view(y, m).lineFor(category);
    if (line == null) return ids;
    for (int i = 0; i < 2; i++) {
      if (payout != null && payout != i) continue;
      final left = line.left(i);
      if (left > 0.5) {
        final id = await addEntry(y, m, category, i, left);
        if (id != null) ids.add(id);
      }
    }
    return ids;
  }

  /// Отметить всё, что осталось по выплате, во всех тратах.
  static Future<List<String>> markAllPayout(int y, int m, int payout) async {
    final ids = <String>[];
    final cats = view(y, m).lines.where((l) => l.left(payout) > 0.5).map((l) => l.category.id).toList();
    for (final id in cats) {
      ids.addAll(await markLeft(y, m, id, payout: payout));
    }
    return ids;
  }

  /// Новые отметки месяца. Трата без отметок снова раскладывается сама.
  static BudgetMonthData _withEntries(BudgetMonthData d, List<BudgetEntry> entries) {
    final used = entries.map((e) => e.category).toSet();
    return d.copyWith(
      entries: entries,
      locked: {
        for (final e in d.locked.entries)
          if (used.contains(e.key)) e.key: e.value,
      },
    );
  }

  /// Снять отметки ячейки в этом месяце.
  static Future<void> clearCell(int y, int m, String category, int payout) async {
    final d = _load(y, m);
    if (d == null) return;
    await _save(_withEntries(
      d,
      d.entries.where((e) => !(e.category == category && e.payout == payout)).toList(),
    ));
  }

  static Future<void> deleteEntry(String id) async {
    for (final d in _months()) {
      if (d.entries.any((e) => e.id == id)) {
        await _save(_withEntries(d, d.entries.where((e) => e.id != id).toList()));
        return;
      }
    }
  }

  static Future<void> deleteEntries(List<String> ids) async {
    for (final id in ids) {
      await deleteEntry(id);
    }
  }

  // --- Перенос и остаток ---

  static Map<String, Pair> _addPair(Map<String, Pair> m, String id, Pair v) {
    final result = {for (final e in m.entries) e.key: [e.value[0], e.value[1]]};
    final cur = result[id] ?? [0.0, 0.0];
    result[id] = [cur[0] + v[0], cur[1] + v[1]];
    if (result[id]![0].abs() < 0.004 && result[id]![1].abs() < 0.004) result.remove(id);
    return result;
  }

  /// Перенести неотложенное по трате на следующий месяц.
  static Future<void> moveToNext(int y, int m, String category) async {
    final line = view(y, m).lineFor(category);
    if (line == null || line.leftTotal < 0.5) return;
    final amount = [line.left(0), line.left(1)];
    final d = await _ensure(y, m);
    await _save(d.copyWith(moved: _addPair(d.moved, category, amount)));
    final (ny, nm) = _fromOrd(_ord(y, m) + 1);
    // Следующий месяц может быть ещё не заполнен — тогда запись только с
    // переносом, месяц остаётся пустым.
    final next = _load(ny, nm) ?? BudgetMonthData(year: ny, month: nm, filled: false);
    await _save(next.copyWith(carryIn: _addPair(next.carryIn, category, amount)));
  }

  /// Отменить перенос на следующий месяц.
  static Future<void> undoMove(int y, int m, String category) async {
    final d = _load(y, m);
    final amount = d?.moved[category];
    if (d == null || amount == null) return;
    await _save(d.copyWith(moved: _addPair(d.moved, category, [-amount[0], -amount[1]])));
    final (ny, nm) = _fromOrd(_ord(y, m) + 1);
    final next = _load(ny, nm);
    if (next != null) {
      final updated = next.copyWith(carryIn: _addPair(next.carryIn, category, [-amount[0], -amount[1]]));
      if (!updated.filled && updated.carryIn.isEmpty && updated.entries.isEmpty) {
        _monthsCache = null;
        await _box.delete('m:${updated.key}');
        _monthsCache = null;
        version.value++;
      } else {
        await _save(updated);
      }
    }
  }

  /// Добавить нераспределённый остаток к трате категории.
  static Future<void> addToItem(int y, int m, String category, double amount) async {
    if (amount < 0.5) return;
    final d = await _ensure(y, m);
    final cur = d.items[category];
    final items = Map<String, BudgetItem>.from(d.items)
      ..[category] = BudgetItem(amount: (cur?.amount ?? 0) + amount, source: cur?.source ?? BudgetSource.auto);
    await _save(d.copyWith(items: items));
  }

  // --- Выбор месяца ---

  static BudgetMonthStatus status(int y, int m) {
    final o = _ord(y, m);
    final v = view(y, m);
    if (!v.filled) return const BudgetMonthStatus(BudgetMonthState.empty);
    if (o > _currentOrd) return BudgetMonthStatus(BudgetMonthState.future, v.progress);
    if (o == _currentOrd) return BudgetMonthStatus(BudgetMonthState.current, v.progress);
    return BudgetMonthStatus(v.complete ? BudgetMonthState.complete : BudgetMonthState.partial, v.progress);
  }

  // --- Бэкап ---

  static Map<String, String> exportAll() => {
        for (final k in _box.keys)
          if (_box.get(k) != null) '$k': _box.get(k)!,
      };

  static Future<void> replaceAll(Map raw) async {
    await _box.clear();
    _monthsCache = null;
    for (final e in raw.entries) {
      if (e.value is String) await _box.put('${e.key}', e.value as String);
    }
    _monthsCache = null;
    await _migrate();
    version.value++;
  }

  // --- Переход со старого формата ---

  /// Раньше суммы хранились в категориях, а у прошлых месяцев был
  /// зафиксированный план. Теперь у каждого месяца свои траты.
  static Future<void> _migrate() async {
    final rawCats = _box.get('cats');
    List oldCats = const [];
    try {
      if (rawCats != null) oldCats = jsonDecode(rawCats) as List;
    } catch (_) {}
    var changed = false;
    for (final k in _box.keys.toList()) {
      if (!'$k'.startsWith('m:')) continue;
      final raw = _box.get(k);
      if (raw == null) continue;
      Map j;
      try {
        j = jsonDecode(raw) as Map;
      } catch (_) {
        continue;
      }
      if (j['v'] == 2) continue;
      final items = <String, Map<String, dynamic>>{};
      final locked = <String, List<double>>{};
      final frozen = j['f'];
      if (frozen is Map) {
        // Прошлый месяц: план как был, раскладка — зафиксированная.
        for (final e in frozen.entries) {
          final v = e.value;
          if (v is! List || v.length < 2) continue;
          final a = (v[0] as num?)?.toDouble() ?? 0;
          final b = (v[1] as num?)?.toDouble() ?? 0;
          if (a + b <= 0.004) continue;
          items['${e.key}'] = {'a': a + b, 's': 'auto'};
          locked['${e.key}'] = [a, b];
        }
      } else {
        // Текущий или будущий месяц: суммы из старых категорий.
        final amounts = (j['a'] as Map?) ?? const {};
        final sources = (j['p'] as Map?) ?? const {};
        for (final c in oldCats) {
          if (c is! Map || c['x'] == true) continue;
          final id = '${c['id']}';
          final override = amounts[id];
          final amount = override is num ? override.toDouble() : ((c['a'] as num?)?.toDouble() ?? 0);
          if (amount <= 0.004) continue;
          items[id] = {'a': amount, 's': '${sources[id] ?? c['s'] ?? 'auto'}'};
        }
      }
      // Направленный остаток становится частью траты.
      final directed = j['r'];
      if (directed is Map) {
        for (final e in directed.entries) {
          final v = e.value;
          if (v is! List || v.length < 2) continue;
          final add = ((v[0] as num?)?.toDouble() ?? 0) + ((v[1] as num?)?.toDouble() ?? 0);
          final cur = items['${e.key}'];
          items['${e.key}'] = {'a': ((cur?['a'] as num?)?.toDouble() ?? 0) + add, 's': cur?['s'] ?? 'auto'};
        }
      }
      final oldLocked = j['k'];
      if (oldLocked is Map) {
        for (final e in oldLocked.entries) {
          final v = e.value;
          if (v is List && v.length >= 2) {
            locked['${e.key}'] = [(v[0] as num?)?.toDouble() ?? 0, (v[1] as num?)?.toDouble() ?? 0];
          }
        }
      }
      final migrated = {
        'v': 2,
        'y': j['y'],
        'm': j['m'],
        'fl': true,
        'i': j['i'],
        'o': j['o'],
        'l': j['l'],
        'x': j['x'] ?? const [],
        'it': items,
        'c': j['c'] ?? const {},
        'mv': j['v'] is Map ? j['v'] : const {},
        'e': j['e'] ?? const [],
        if (locked.isNotEmpty) 'k': locked,
      };
      await _box.put(k, jsonEncode(migrated));
      changed = true;
    }
    // Категории — только название и значок.
    if (oldCats.isNotEmpty && oldCats.any((c) => c is Map && (c.containsKey('a') || c.containsKey('m')))) {
      final cleaned = oldCats.map(BudgetCategory.fromJson).whereType<BudgetCategory>().map((c) => c.toJson()).toList();
      await _box.put('cats', jsonEncode(cleaned));
      changed = true;
    }
    if (changed) {
      _monthsCache = null;
      // Уже начатый бюджет не должен копировать месяц при первом запуске
      // новой версии.
      if (!_box.containsKey('meta:seen')) await _box.put('meta:seen', '$_currentOrd');
    }
  }
}
