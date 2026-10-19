import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'html_table_reader.dart';
import 'online_settings_service.dart';

/// Данные Банка России за месяц: ключевая ставка и годовая инфляция.
class CbrMonth {
  final int year;
  final int month;

  /// Ключевая ставка, % годовых.
  final double? keyRate;

  /// Инфляция к тому же месяцу прошлого года, %.
  final double? inflation;

  const CbrMonth({required this.year, required this.month, this.keyRate, this.inflation});

  int get ord => year * 12 + month - 1;
}

/// Инфляция и ключевая ставка с сайта Банка России («Инфляция и ключевая
/// ставка Банка России»). Загружаются раз в неделю, если включена загрузка
/// данных из интернета, и хранятся на телефоне — без сети считается по
/// сохранённому.
class CbrService {
  CbrService._();

  static const boxName = 'cbr';
  static late Box<String> _box;
  static final ValueNotifier<int> version = ValueNotifier(0);
  static final ValueNotifier<String?> error = ValueNotifier(null);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static Map<int, CbrMonth>? _cache;

  static Map<int, CbrMonth> get _months {
    final cached = _cache;
    if (cached != null) return cached;
    final result = <int, CbrMonth>{};
    final raw = _box.get('months');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        for (final e in m.entries) {
          final parts = '${e.key}'.split('-');
          final v = e.value as List;
          final y = int.parse(parts[0]);
          final mo = int.parse(parts[1]);
          final month = CbrMonth(
            year: y,
            month: mo,
            keyRate: (v[0] as num?)?.toDouble(),
            inflation: (v[1] as num?)?.toDouble(),
          );
          result[month.ord] = month;
        }
      } catch (_) {}
    }
    return _cache = result;
  }

  static bool get hasData => _months.isNotEmpty;

  static DateTime? get fetchedAt => DateTime.tryParse(_box.get('at') ?? '');

  /// Последний месяц, за который известна инфляция.
  static CbrMonth? get lastInflation {
    CbrMonth? last;
    for (final m in _months.values) {
      if (m.inflation != null && (last == null || m.ord > last.ord)) last = m;
    }
    return last;
  }

  static Future<void> saveMonths(List<CbrMonth> months) async {
    final map = <String, List<double?>>{
      for (final m in months) '${m.year}-${m.month.toString().padLeft(2, '0')}': [m.keyRate, m.inflation],
    };
    await _box.put('months', jsonEncode(map));
    await _box.put('at', DateTime.now().toIso8601String());
    _cache = null;
    _keySeries = null;
    _inflSeries = null;
    version.value++;
  }

  static bool _loading = false;

  /// Обновляет данные, если они старше недели. Без разрешения на загрузку из
  /// интернета ничего не делает.
  static Future<void> refreshIfStale({bool force = false}) async {
    if (_loading || !OnlineSettingsService.enabled) return;
    final at = fetchedAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(days: 7)) return;
    _loading = true;
    try {
      final now = DateTime.now();
      String d(DateTime x) =>
          '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
      final uri = Uri.parse('https://www.cbr.ru/hd_base/infl/').replace(queryParameters: {
        'UniDbQuery.Posted': 'True',
        'UniDbQuery.From': '01.01.2013',
        'UniDbQuery.To': d(now),
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final months = parse(response.bodyBytes);
      if (months.isEmpty) throw const FormatException('нет таблицы');
      await saveMonths(months);
      error.value = null;
    } catch (_) {
      error.value = hasData
          ? 'Не удалось обновить данные Банка России — считаем по сохранённым'
          : 'Не удалось загрузить данные Банка России';
    } finally {
      _loading = false;
    }
  }

  static void refreshInBackground() => unawaited(refreshIfStale());

  static double? _num(String raw) {
    final t = raw.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.').replaceAll('%', '').trim();
    return double.tryParse(t);
  }

  /// Разбирает страницу «Инфляция и ключевая ставка Банка России»: месяц в
  /// виде «09.2026», ключевая ставка и инфляция в % г/г.
  static List<CbrMonth> parse(Uint8List bytes) {
    final datePattern = RegExp(r'^(\d{1,2})\.(\d{4})$');
    for (final table in HtmlTableReader.tables(bytes)) {
      int? keyCol;
      int? inflCol;
      final result = <CbrMonth>[];
      for (final row in table) {
        if (keyCol == null || inflCol == null) {
          for (int i = 0; i < row.length; i++) {
            final h = row[i].toLowerCase();
            if (h.contains('ключев')) keyCol = i;
            if (h.contains('инфляц') && !h.contains('цел')) inflCol = i;
          }
          continue;
        }
        if (row.isEmpty) continue;
        final m = datePattern.firstMatch(row[0].trim());
        if (m == null) continue;
        result.add(CbrMonth(
          year: int.parse(m.group(2)!),
          month: int.parse(m.group(1)!),
          keyRate: keyCol < row.length ? _num(row[keyCol]) : null,
          inflation: inflCol < row.length ? _num(row[inflCol]) : null,
        ));
      }
      if (result.isNotEmpty) return result;
    }
    return const [];
  }

  // --- Расчёты ---

  static int _ord(DateTime d) => d.year * 12 + d.month - 1;

  static _Series? _keySeries;
  static _Series? _inflSeries;

  static _Series get _key => _keySeries ??= _Series.of(_months.values, (m) => m.keyRate);
  static _Series get _infl => _inflSeries ??= _Series.of(_months.values, (m) => m.inflation);

  /// Значение за месяц или ближайший известный до него (а если раньше ничего
  /// нет — первый известный после).
  static double? _valueAt(int ord, bool inflation) => (inflation ? _infl : _key).at(ord);

  /// Во сколько раз выросли цены с [from] по [to].
  ///
  /// У Банка России инфляция годовая (месяц к тому же месяцу прошлого года),
  /// поэтому период режется на годы с конца: целые годы считаются точно, а
  /// остаток — долей годовой инфляции.
  static double? inflationFactor(DateTime from, DateTime to) {
    if (!hasData || !to.isAfter(from)) return hasData ? 1 : null;
    var months = to.difference(from).inDays / 30.4375;
    var ord = _ord(to);
    var factor = 1.0;
    while (months > 0) {
      final infl = _valueAt(ord, true);
      if (infl == null) return null;
      final part = math.min(12.0, months);
      factor *= math.pow(1 + infl / 100, part / 12).toDouble();
      months -= part;
      ord -= 12;
    }
    return factor;
  }

  /// Во сколько раз выросли бы деньги под ключевую ставку с [from] по [to]:
  /// каждый месяц — по ставке этого месяца.
  static double? keyRateFactor(DateTime from, DateTime to) {
    if (!hasData || !to.isAfter(from)) return hasData ? 1 : null;
    var factor = 1.0;
    var cursor = from;
    while (cursor.isBefore(to)) {
      final nextMonth = DateTime(cursor.year, cursor.month + 1);
      final end = nextMonth.isBefore(to) ? nextMonth : to;
      final rate = _valueAt(_ord(cursor), false);
      if (rate == null) return null;
      final days = end.difference(cursor).inMilliseconds / Duration.millisecondsPerDay;
      factor *= math.pow(1 + rate / 100, days / 365).toDouble();
      cursor = end;
    }
    return factor;
  }

  // --- Бэкап ---

  static Map<String, String> exportAll() => {
        for (final k in _box.keys)
          if (_box.get(k) != null) '$k': _box.get(k)!,
      };
}

/// Помесячный ряд с заполненными пропусками: месяц без значения берёт
/// предыдущее известное.
class _Series {
  final int first;
  final List<double> values;

  const _Series(this.first, this.values);

  factory _Series.of(Iterable<CbrMonth> months, double? Function(CbrMonth) pick) {
    final known = <int, double>{
      for (final m in months)
        if (pick(m) != null) m.ord: pick(m)!,
    };
    if (known.isEmpty) return const _Series(0, []);
    final ords = known.keys.toList()..sort();
    final values = <double>[];
    var last = known[ords.first]!;
    for (int o = ords.first; o <= ords.last; o++) {
      last = known[o] ?? last;
      values.add(last);
    }
    return _Series(ords.first, values);
  }

  double? at(int ord) {
    if (values.isEmpty) return null;
    final i = ord - first;
    if (i < 0) return values.first;
    if (i >= values.length) return values.last;
    return values[i];
  }
}
