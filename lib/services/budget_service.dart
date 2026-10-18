import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Как откладывать в категорию.
enum BudgetMode { monthly, toDate }

/// С какой выплаты брать деньги на категорию.
///
/// [balance] — программа сама делит сумму между выплатами так, чтобы после
/// всех категорий с обеих выплат оставалось одинаково.
enum BudgetSource { salary, advance, half, balance }

/// День выплаты: число месяца или последний день.
class PayDay {
  final bool last;
  final int day;

  const PayDay.day(this.day) : last = false;
  const PayDay.lastDay()
      : last = true,
        day = 31;

  int inMonth(int year, int month) => last ? daysInMonth(year, month) : math.min(day, daysInMonth(year, month));

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

/// Общие настройки бюджета: названия и даты двух выплат.
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

/// Категория, в которую откладываются деньги.
class BudgetCategory {
  final String id;
  final String name;
  final String emoji;
  final BudgetMode mode;

  /// Сколько в месяц (режим «каждый месяц»).
  final double amount;

  /// Цель: сколько накопить. В режиме «копить к дате» обязательна.
  final double? target;

  /// К какому месяцу накопить (режим «копить к дате»).
  final int? targetYear;
  final int? targetMonth;

  final BudgetSource source;

  /// Удалённая категория остаётся в прошлых месяцах, но в новых не
  /// планируется.
  final bool deleted;

  const BudgetCategory({
    required this.id,
    required this.name,
    required this.emoji,
    this.mode = BudgetMode.monthly,
    this.amount = 0,
    this.target,
    this.targetYear,
    this.targetMonth,
    this.source = BudgetSource.half,
    this.deleted = false,
  });

  bool get toDate => mode == BudgetMode.toDate && target != null && targetYear != null && targetMonth != null;

  BudgetCategory copyWith({bool? deleted}) => BudgetCategory(
        id: id,
        name: name,
        emoji: emoji,
        mode: mode,
        amount: amount,
        target: target,
        targetYear: targetYear,
        targetMonth: targetMonth,
        source: source,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'e': emoji,
        'm': mode.name,
        'a': amount,
        if (target != null) 't': target,
        if (targetYear != null) 'ty': targetYear,
        if (targetMonth != null) 'tm': targetMonth,
        's': source.name,
        if (deleted) 'x': true,
      };

  static BudgetCategory? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    T byName<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    return BudgetCategory(
      id: id,
      name: '${raw['n'] ?? ''}',
      emoji: '${raw['e'] ?? '•'}',
      mode: byName(BudgetMode.values, raw['m'], BudgetMode.monthly),
      amount: (raw['a'] as num?)?.toDouble() ?? 0,
      target: (raw['t'] as num?)?.toDouble(),
      targetYear: (raw['ty'] as num?)?.toInt(),
      targetMonth: (raw['tm'] as num?)?.toInt(),
      source: byName(BudgetSource.values, raw['s'], BudgetSource.half),
      deleted: raw['x'] == true,
    );
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

  /// Суммы двух выплат (на руки).
  final List<double> income;

  /// Дата выплаты в этом месяце, если её сдвинули вручную.
  final List<int?> dayOverride;

  /// Сколько оставлять на жизнь с каждой выплаты.
  final double living;

  final List<BudgetExtra> extras;

  /// План по категориям, зафиксированный, когда месяц прошёл. null — месяц
  /// текущий или будущий, план считается по категориям.
  final Map<String, Pair>? frozen;

  /// Перенесено из прошлого месяца.
  final Map<String, Pair> carryIn;

  /// Перенесено отсюда на следующий месяц.
  final Map<String, Pair> moved;

  /// Остаток, направленный в категории.
  final Map<String, Pair> directed;

  final List<BudgetEntry> entries;

  const BudgetMonthData({
    required this.year,
    required this.month,
    required this.income,
    this.dayOverride = const [null, null],
    required this.living,
    this.extras = const [],
    this.frozen,
    this.carryIn = const {},
    this.moved = const {},
    this.directed = const {},
    this.entries = const [],
  });

  String get key => BudgetService.monthKey(year, month);

  BudgetMonthData copyWith({
    List<double>? income,
    List<int?>? dayOverride,
    double? living,
    List<BudgetExtra>? extras,
    Map<String, Pair>? frozen,
    bool clearFrozen = false,
    Map<String, Pair>? carryIn,
    Map<String, Pair>? moved,
    Map<String, Pair>? directed,
    List<BudgetEntry>? entries,
  }) =>
      BudgetMonthData(
        year: year,
        month: month,
        income: income ?? this.income,
        dayOverride: dayOverride ?? this.dayOverride,
        living: living ?? this.living,
        extras: extras ?? this.extras,
        frozen: clearFrozen ? null : (frozen ?? this.frozen),
        carryIn: carryIn ?? this.carryIn,
        moved: moved ?? this.moved,
        directed: directed ?? this.directed,
        entries: entries ?? this.entries,
      );

  Map<String, dynamic> toJson() => {
        'y': year,
        'm': month,
        'i': income,
        'o': dayOverride,
        'l': living,
        'x': [for (final e in extras) e.toJson()],
        if (frozen != null) 'f': _pairsToJson(frozen!),
        'c': _pairsToJson(carryIn),
        'v': _pairsToJson(moved),
        'r': _pairsToJson(directed),
        'e': [for (final e in entries) e.toJson()],
      };

  static BudgetMonthData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final y = (raw['y'] as num?)?.toInt();
    final m = (raw['m'] as num?)?.toInt();
    if (y == null || m == null || m < 1 || m > 12) return null;
    final i = raw['i'];
    final o = raw['o'];
    return BudgetMonthData(
      year: y,
      month: m,
      income: [
        for (int k = 0; k < 2; k++) i is List && i.length > k ? ((i[k] as num?)?.toDouble() ?? 0) : 0.0,
      ],
      dayOverride: [
        for (int k = 0; k < 2; k++) o is List && o.length > k ? (o[k] as num?)?.toInt() : null,
      ],
      living: (raw['l'] as num?)?.toDouble() ?? 0,
      extras: (raw['x'] as List? ?? const []).map(BudgetExtra.fromJson).whereType<BudgetExtra>().toList(),
      frozen: raw['f'] == null ? null : _pairsFromJson(raw['f']),
      carryIn: _pairsFromJson(raw['c']),
      moved: _pairsFromJson(raw['v']),
      directed: _pairsFromJson(raw['r']),
      entries: (raw['e'] as List? ?? const []).map(BudgetEntry.fromJson).whereType<BudgetEntry>().toList(),
    );
  }
}

/// Строка категории в расчёте месяца.
class BudgetLine {
  final BudgetCategory category;

  /// Сколько отложить с каждой выплаты (с переносами и направленным
  /// остатком, за вычетом перенесённого дальше).
  final Pair plan;

  /// Сколько уже отложено с каждой выплаты.
  final Pair done;

  final Pair carryIn;
  final Pair moved;
  final Pair directed;

  const BudgetLine({
    required this.category,
    required this.plan,
    required this.done,
    required this.carryIn,
    required this.moved,
    required this.directed,
  });

  double get planTotal => plan[0] + plan[1];
  double get doneTotal => done[0] + done[1];
  double left(int i) => math.max(0.0, plan[i] - done[i]);
  double get leftTotal => left(0) + left(1);
  double get carryTotal => carryIn[0] + carryIn[1];
  double get movedTotal => moved[0] + moved[1];
  bool cellDone(int i) => plan[i] > 0.5 && done[i] >= plan[i] - 0.5;
}

/// Полный расчёт месяца.
class BudgetMonthView {
  final BudgetMonthData data;
  final BudgetConfig config;
  final List<BudgetLine> lines;

  /// Есть ли у месяца сохранённые данные. Нет — месяц до начала бюджета или
  /// будущий, который ещё не трогали.
  final bool stored;

  const BudgetMonthView({required this.data, required this.config, required this.lines, required this.stored});

  int get year => data.year;
  int get month => data.month;

  int payDay(int i) {
    final o = data.dayOverride[i];
    if (o != null) return math.min(o, daysInMonth(year, month));
    return config.days[i].inMonth(year, month);
  }

  DateTime payDate(int i) => DateTime(year, month, payDay(i));
  bool dayMoved(int i) => data.dayOverride[i] != null && data.dayOverride[i] != config.days[i].inMonth(year, month);

  double extrasFor(int i) => data.extras.where((e) => e.payout == i).fold(0.0, (a, e) => a + e.amount);

  /// Всё, что приходит с выплатой: она сама и разовые поступления к ней.
  double income(int i) => data.income[i] + extrasFor(i);
  double get incomeTotal => income(0) + income(1);

  double planned(int i) => lines.fold(0.0, (a, l) => a + l.plan[i]);
  double get plannedTotal => planned(0) + planned(1);
  double doneFor(int i) => lines.fold(0.0, (a, l) => a + l.done[i]);
  double get doneTotal => doneFor(0) + doneFor(1);

  /// Что остаётся с выплаты после «на жизнь» и категорий. Меньше нуля —
  /// не хватает.
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

/// Состояние месяца для сетки года.
enum BudgetMonthState { none, future, current, complete, partial }

class BudgetMonthStatus {
  final BudgetMonthState state;
  final double progress;
  const BudgetMonthStatus(this.state, [this.progress = 0]);
}

/// Бюджет: распределение зарплаты и аванса по категориям. Общий для всех
/// портфелей, хранится отдельно от них.
class BudgetService {
  BudgetService._();

  static const boxName = 'budget';
  static late Box<String> _box;
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
    await _freezePast();
  }

  static String monthKey(int y, int m) => '$y-${m.toString().padLeft(2, '0')}';
  static int _ord(int y, int m) => y * 12 + (m - 1);

  static DateTime get _now => DateTime.now();
  static int get _currentOrd => _ord(_now.year, _now.month);

  /// Начат ли бюджет: пользователь хоть раз его открывал.
  static bool get started => _box.containsKey('cats');

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

  /// Сохраняет даты и названия выплат. Прошедшие месяцы сохраняют прежние
  /// даты — они фиксируются как ручные.
  static Future<void> saveConfig(BudgetConfig c) async {
    final old = config;
    final now = _currentOrd;
    for (final d in _months()) {
      if (_ord(d.year, d.month) >= now) continue;
      final o = [
        for (int i = 0; i < 2; i++) d.dayOverride[i] ?? old.days[i].inMonth(d.year, d.month),
      ];
      await _box.put('m:${d.key}', jsonEncode(d.copyWith(dayOverride: o).toJson()));
    }
    _monthsCache = null;
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

  static Future<void> _saveCategories(List<BudgetCategory> list) async {
    await _box.put('cats', jsonEncode([for (final c in list) c.toJson()]));
    version.value++;
  }

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(1000)}';

  /// Первый вход: стандартные категории и текущий месяц.
  static Future<void> ensureStarted() async {
    if (!started) {
      final now = DateTime.now().microsecondsSinceEpoch;
      await _saveCategories([
        for (int i = 0; i < defaultCategories.length; i++)
          BudgetCategory(id: '${now}_$i', emoji: defaultCategories[i].$1, name: defaultCategories[i].$2),
      ]);
    }
    final n = _now;
    if (_load(n.year, n.month) == null) {
      await _save(_blank(n.year, n.month));
    }
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

  static Future<void> deleteCategory(String id) async {
    final list = allCategories;
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) return;
    // Если по категории ничего не было — удаляем совсем, иначе прячем: в
    // прошлых месяцах она должна остаться.
    final used = _months().any((m) =>
        m.entries.any((e) => e.category == id) || (m.frozen?.containsKey(id) ?? false));
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

  /// Новый месяц: суммы — как в ближайшем сохранённом месяце.
  static BudgetMonthData _blank(int y, int m) {
    final target = _ord(y, m);
    BudgetMonthData? nearest;
    var best = 1 << 30;
    for (final d in _months()) {
      final o = _ord(d.year, d.month);
      // Прошлые месяцы предпочтительнее будущих.
      final dist = o <= target ? target - o : (o - target) + 1000;
      if (dist < best) {
        best = dist;
        nearest = d;
      }
    }
    return BudgetMonthData(
      year: y,
      month: m,
      income: nearest == null ? [0, 0] : [nearest.income[0], nearest.income[1]],
      living: nearest?.living ?? 0,
    );
  }

  static bool hasMonth(int y, int m) => _load(y, m) != null;

  static int? get firstMonthOrd {
    final list = _months();
    return list.isEmpty ? null : _ord(list.first.year, list.first.month);
  }

  /// Прошедшие месяцы получают зафиксированный план — правка категорий их
  /// больше не меняет.
  static Future<void> _freezePast() async {
    final now = _currentOrd;
    for (final d in _months()) {
      if (d.frozen == null && _ord(d.year, d.month) < now) {
        final plan = _livePlan(d);
        await _box.put('m:${d.key}', jsonEncode(d.copyWith(frozen: plan).toJson()));
      }
    }
    _monthsCache = null;
  }

  /// Всего отложено в категорию до начала месяца [y]-[m].
  static double savedBefore(String id, int y, int m) {
    final limit = _ord(y, m);
    double sum = 0;
    for (final d in _months()) {
      if (_ord(d.year, d.month) >= limit) continue;
      for (final e in d.entries) {
        if (e.category == id) sum += e.amount;
      }
    }
    return sum;
  }

  /// Всего отложено в категорию за всё время.
  static double savedTotal(String id) {
    double sum = 0;
    for (final d in _months()) {
      for (final e in d.entries) {
        if (e.category == id) sum += e.amount;
      }
    }
    return sum;
  }

  /// Сколько откладывать в месяц по категории «копить к дате»: остаток цели
  /// поровну на оставшиеся месяцы, с округлением вверх до сотни. Для будущих
  /// месяцев — как в текущем.
  static double monthlyFor(BudgetCategory c, int y, int m) {
    if (!c.toDate) return c.amount;
    final cur = _now;
    // Прошлый месяц считается от себя, будущие — от текущего.
    final base = math.min(_ord(y, m), _currentOrd);
    final by = base ~/ 12;
    final bm = base % 12 + 1;
    final targetOrd = _ord(c.targetYear!, c.targetMonth!);
    if (_ord(y, m) > targetOrd) return 0;
    final left = c.target! - savedBefore(c.id, by, bm);
    if (left <= 0.5) return 0;
    final months = math.max(1, targetOrd - base + 1);
    final raw = left / months;
    final rounded = raw >= 100 ? (raw / 100).ceil() * 100.0 : raw.ceilToDouble();
    // В будущих месяцах план не больше, чем осталось копить.
    if (cur.year != y || cur.month != m) return math.min(rounded, left);
    return rounded;
  }

  static double _roundPart(double v, double whole) {
    if (whole >= 200) return ((v / 100).round() * 100.0).clamp(0.0, whole).toDouble();
    return v.roundToDouble().clamp(0.0, whole).toDouble();
  }

  /// План по категориям, посчитанный по их нынешним настройкам.
  static Map<String, Pair> _livePlan(BudgetMonthData d) {
    final plan = <String, Pair>{};
    final balance = <BudgetCategory, double>{};
    final fixed = [0.0, 0.0];
    for (final c in categories) {
      final amt = monthlyFor(c, d.year, d.month);
      if (amt <= 0.004) continue;
      switch (c.source) {
        case BudgetSource.salary:
          plan[c.id] = [amt, 0];
        case BudgetSource.advance:
          plan[c.id] = [0, amt];
        case BudgetSource.half:
          final a = amt >= 200 ? (amt / 2 / 100).ceil() * 100.0 : (amt / 2).ceilToDouble();
          plan[c.id] = [math.min(a, amt), amt - math.min(a, amt)];
        case BudgetSource.balance:
          balance[c] = amt;
          continue;
      }
      fixed[0] += plan[c.id]![0];
      fixed[1] += plan[c.id]![1];
    }
    if (balance.isNotEmpty) {
      double extra(int i) => d.extras.where((e) => e.payout == i).fold(0.0, (a, e) => a + e.amount);
      double add(Map<String, Pair> m, int i) => m.values.fold(0.0, (a, p) => a + p[i]);
      final free = [
        for (int i = 0; i < 2; i++)
          d.income[i] + extra(i) - d.living - fixed[i] - add(d.carryIn, i) - add(d.directed, i) + add(d.moved, i),
      ];
      final total = balance.values.fold(0.0, (a, v) => a + v);
      final x0 = ((free[0] - free[1] + total) / 2).clamp(0.0, total).toDouble();
      for (final e in balance.entries) {
        final a = _roundPart(e.value * x0 / total, e.value);
        plan[e.key.id] = [a, e.value - a];
      }
    }
    return plan;
  }

  /// Расчёт месяца. Если данных нет — месяц по умолчанию (не сохраняется).
  static BudgetMonthView view(int y, int m) {
    final stored = _load(y, m);
    final d = stored ?? _blank(y, m);
    final past = _ord(y, m) < _currentOrd;
    final base = stored?.frozen ?? (past && stored == null ? <String, Pair>{} : _livePlan(d));
    final ids = <String>{
      ...base.keys,
      ...d.carryIn.keys,
      ...d.directed.keys,
      ...d.entries.map((e) => e.category),
      // В текущем и будущих месяцах видны все категории, даже без суммы.
      if (!past) ...categories.map((c) => c.id),
    };
    final order = <String, int>{};
    final all = allCategories;
    for (int i = 0; i < all.length; i++) {
      order[all[i].id] = i;
    }
    final lines = <BudgetLine>[];
    Pair get(Map<String, Pair> m, String id) => m[id] ?? [0.0, 0.0];
    for (final id in ids) {
      final c = category(id) ?? BudgetCategory(id: id, name: 'Удалённая категория', emoji: '•', deleted: true);
      final b = get(base, id);
      final ci = get(d.carryIn, id);
      final mv = get(d.moved, id);
      final dr = get(d.directed, id);
      final done = [0.0, 0.0];
      for (final e in d.entries) {
        if (e.category == id) done[e.payout] += e.amount;
      }
      lines.add(BudgetLine(
        category: c,
        plan: [for (int i = 0; i < 2; i++) math.max(0.0, b[i] + ci[i] + dr[i] - mv[i])],
        done: done,
        carryIn: ci,
        moved: mv,
        directed: dr,
      ));
    }
    lines.sort((a, b) => (order[a.category.id] ?? 1 << 20).compareTo(order[b.category.id] ?? 1 << 20));
    return BudgetMonthView(data: d, config: config, lines: lines, stored: stored != null);
  }

  static Future<BudgetMonthData> _ensure(int y, int m) async {
    final d = _load(y, m);
    if (d != null) return d;
    final blank = _blank(y, m);
    // Прошлый месяц без данных получает план на момент создания.
    final created = _ord(y, m) < _currentOrd ? blank.copyWith(frozen: _livePlan(blank)) : blank;
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
    await _save(d.copyWith(income: income, dayOverride: dayOverride, living: living, extras: extras));
  }

  // --- Отметки ---

  /// Начать месяц без данных (например, прошлый — чтобы заполнить задним
  /// числом).
  static Future<void> startMonth(int y, int m) async {
    await _ensure(y, m);
  }

  /// Добавляет отметку и возвращает её id.
  static Future<String?> addEntry(int y, int m, String category, int payout, double amount, {DateTime? date}) async {
    if (amount.abs() < 0.5) return null;
    final d = await _ensure(y, m);
    final now = DateTime.now();
    // Отметка в чужом месяце датируется днём выплаты, а не сегодняшним днём.
    final inMonth = now.year == y && now.month == m;
    final when = date ?? (inMonth ? now : DateTime(y, m, view(y, m).payDay(payout)));
    final id = newId();
    await _save(d.copyWith(entries: [
      ...d.entries,
      BudgetEntry(id: id, category: category, payout: payout, amount: amount, date: when),
    ]));
    return id;
  }

  /// Отметить всё, что осталось по ячейке (или по всей категории).
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

  static Future<void> deleteEntries(List<String> ids) async {
    for (final id in ids) {
      await deleteEntry(id);
    }
  }

  /// Вернуть удалённую отметку.
  static Future<void> restoreEntry(BudgetEntry e) async {
    final d = await _ensure(e.date.year, e.date.month);
    await _save(d.copyWith(entries: [...d.entries, e]));
  }

  /// Снять отметки ячейки в этом месяце.
  static Future<void> clearCell(int y, int m, String category, int payout) async {
    final d = _load(y, m);
    if (d == null) return;
    await _save(d.copyWith(
      entries: d.entries.where((e) => !(e.category == category && e.payout == payout)).toList(),
    ));
  }

  static Future<void> deleteEntry(String id) async {
    for (final d in _months()) {
      if (d.entries.any((e) => e.id == id)) {
        await _save(d.copyWith(entries: d.entries.where((e) => e.id != id).toList()));
        return;
      }
    }
  }

  /// Все отметки категории, новые сверху: (месяц, отметка).
  static List<BudgetEntry> history(String category) {
    final result = <BudgetEntry>[];
    for (final d in _months()) {
      result.addAll(d.entries.where((e) => e.category == category));
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  // --- Перенос и остаток ---

  static Map<String, Pair> _addPair(Map<String, Pair> m, String id, Pair v) {
    final result = {for (final e in m.entries) e.key: [e.value[0], e.value[1]]};
    final cur = result[id] ?? [0.0, 0.0];
    result[id] = [cur[0] + v[0], cur[1] + v[1]];
    if (result[id]![0].abs() < 0.004 && result[id]![1].abs() < 0.004) result.remove(id);
    return result;
  }

  /// Перенести неотложенное по категории на следующий месяц.
  static Future<void> moveToNext(int y, int m, String category) async {
    final line = view(y, m).lineFor(category);
    if (line == null || line.leftTotal < 0.5) return;
    final amount = [line.left(0), line.left(1)];
    final d = await _ensure(y, m);
    await _save(d.copyWith(moved: _addPair(d.moved, category, amount)));
    final ny = m == 12 ? y + 1 : y;
    final nm = m == 12 ? 1 : m + 1;
    final next = await _ensure(ny, nm);
    await _save(next.copyWith(carryIn: _addPair(next.carryIn, category, amount)));
  }

  /// Отменить перенос на следующий месяц.
  static Future<void> undoMove(int y, int m, String category) async {
    final d = _load(y, m);
    final amount = d?.moved[category];
    if (d == null || amount == null) return;
    await _save(d.copyWith(moved: _addPair(d.moved, category, [-amount[0], -amount[1]])));
    final ny = m == 12 ? y + 1 : y;
    final nm = m == 12 ? 1 : m + 1;
    final next = _load(ny, nm);
    if (next != null) {
      await _save(next.copyWith(carryIn: _addPair(next.carryIn, category, [-amount[0], -amount[1]])));
    }
  }

  /// Направить свободный остаток месяца в категорию: сначала с той выплаты,
  /// где свободно больше.
  static Future<void> direct(int y, int m, String category, double amount) async {
    if (amount < 0.5) return;
    final v = view(y, m);
    final free = [math.max(0.0, v.rest(0)), math.max(0.0, v.rest(1))];
    final first = free[0] >= free[1] ? 0 : 1;
    final part = [0.0, 0.0];
    var left = amount;
    for (final i in [first, 1 - first]) {
      final take = math.min(left, free[i]);
      part[i] += take;
      left -= take;
    }
    // Если направили больше, чем свободно, — лишнее с той же выплаты.
    part[first] += left;
    final d = await _ensure(y, m);
    await _save(d.copyWith(directed: _addPair(d.directed, category, part)));
  }

  /// Убрать направленный остаток из категории.
  static Future<void> undoDirect(int y, int m, String category) async {
    final d = _load(y, m);
    final amount = d?.directed[category];
    if (d == null || amount == null) return;
    await _save(d.copyWith(directed: _addPair(d.directed, category, [-amount[0], -amount[1]])));
  }

  // --- Год ---

  static BudgetMonthStatus status(int y, int m) {
    final o = _ord(y, m);
    if (!hasMonth(y, m)) {
      return BudgetMonthStatus(o > _currentOrd ? BudgetMonthState.future : BudgetMonthState.none);
    }
    final v = view(y, m);
    if (o > _currentOrd) return BudgetMonthStatus(BudgetMonthState.future, v.progress);
    if (o == _currentOrd) return BudgetMonthStatus(BudgetMonthState.current, v.progress);
    if (v.plannedTotal <= 0.5) return const BudgetMonthStatus(BudgetMonthState.none);
    return BudgetMonthStatus(v.complete ? BudgetMonthState.complete : BudgetMonthState.partial, v.progress);
  }

  /// Итоги года по категориям: (категория, отложено, план). План — по
  /// прошедшим и текущему месяцу.
  static List<(BudgetCategory, double, double)> yearTotals(int year) {
    final saved = <String, double>{};
    final plan = <String, double>{};
    final limit = _currentOrd;
    for (int m = 1; m <= 12; m++) {
      if (!hasMonth(year, m)) continue;
      final v = view(year, m);
      for (final l in v.lines) {
        saved[l.category.id] = (saved[l.category.id] ?? 0) + l.doneTotal;
        if (_ord(year, m) <= limit) {
          plan[l.category.id] = (plan[l.category.id] ?? 0) + l.planTotal;
        }
      }
    }
    final result = <(BudgetCategory, double, double)>[];
    for (final c in allCategories) {
      final s = saved[c.id] ?? 0;
      final p = plan[c.id] ?? 0;
      if (s < 0.5 && p < 0.5) continue;
      result.add((c, s, p));
    }
    result.sort((a, b) => b.$2.compareTo(a.$2));
    return result;
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
    await _freezePast();
    version.value++;
  }
}
