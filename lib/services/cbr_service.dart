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

  /// Есть ли хоть что-то для расчётов: таблица по месяцам, ставка по дням
  /// или инфляция, указанная вручную.
  static bool get hasData => _months.isNotEmpty || _daily.isNotEmpty || manualInflation != null;

  /// Есть ли инфляция — с сайта или указанная вручную.
  static bool get hasInflation => _infl.values.isNotEmpty || manualInflation != null;

  /// Инфляция, указанная вручную, % за год. Используется, только если с
  /// сайта Банка России её получить не удалось.
  static double? get manualInflation => double.tryParse(_box.get('manualInflation') ?? '');

  static Future<void> setManualInflation(double? value) async {
    if (value == null) {
      await _box.delete('manualInflation');
    } else {
      await _box.put('manualInflation', '$value');
    }
    _inflSeries = null;
    version.value++;
  }

  // --- Ключевая ставка по дням (веб-сервис Банка России) ---

  static List<(DateTime, double)>? _dailyCache;

  /// Даты изменения ключевой ставки и её новые значения, по возрастанию.
  static List<(DateTime, double)> get _daily => _dailyCache ??= () {
        final raw = _box.get('keyDaily');
        if (raw == null) return <(DateTime, double)>[];
        try {
          return [
            for (final p in jsonDecode(raw) as List)
              (_dayFromInt((p as List)[0] as int), (p[1] as num).toDouble()),
          ];
        } catch (_) {
          return <(DateTime, double)>[];
        }
      }();

  static int _dayToInt(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime _dayFromInt(int v) => DateTime(v ~/ 10000, v ~/ 100 % 100, v % 100);

  static Future<void> saveDailyKeyRates(List<(DateTime, double)> changes) async {
    await _box.put('keyDaily', jsonEncode([
      for (final c in changes) [_dayToInt(c.$1), c.$2],
    ]));
    _dailyCache = null;
    version.value++;
  }

  /// Разбирает ответ веб-сервиса Банка России «KeyRateXML»: записи вида
  /// `<DT>2024-12-20T00:00:00+03:00</DT><Rate>21.00</Rate>`. Возвращает
  /// только дни, когда ставка менялась.
  static List<(DateTime, double)> parseKeyRateXml(String xml) {
    final pattern = RegExp(r'<DT>\s*(\d{4})-(\d{2})-(\d{2})[^<]*</DT>\s*<Rate>\s*([\d.,]+)\s*</Rate>');
    final points = <(DateTime, double)>[];
    for (final m in pattern.allMatches(xml)) {
      final rate = double.tryParse(m.group(4)!.replaceAll(',', '.'));
      if (rate == null) continue;
      points.add((DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)), rate));
    }
    points.sort((a, b) => a.$1.compareTo(b.$1));
    final changes = <(DateTime, double)>[];
    for (final p in points) {
      if (changes.isEmpty || changes.last.$2 != p.$2) changes.add(p);
    }
    return changes;
  }

  static Future<List<(DateTime, double)>> _fetchDailyKeyRates(DateTime to) async {
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';
    final body = '<?xml version="1.0" encoding="utf-8"?>'
        '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
        'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
        '<soap:Body><KeyRateXML xmlns="http://web.cbr.ru/">'
        '<fromDate>2013-09-13T00:00:00</fromDate><ToDate>${iso(to)}</ToDate>'
        '</KeyRateXML></soap:Body></soap:Envelope>';
    final response = await http
        .post(
          Uri.parse('https://www.cbr.ru/DailyInfoWebServ/DailyInfo.asmx'),
          headers: {
            'Content-Type': 'text/xml; charset=utf-8',
            'SOAPAction': '"http://web.cbr.ru/KeyRateXML"',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return parseKeyRateXml(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

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
    final now = DateTime.now();
    // Ключевая ставка по дням — из официального веб-сервиса. Он не зависит
    // от вёрстки сайта, поэтому работает, даже если страница поменяется.
    var dailyOk = false;
    try {
      final changes = await _fetchDailyKeyRates(now);
      if (changes.isNotEmpty) {
        await saveDailyKeyRates(changes);
        dailyOk = true;
      }
    } catch (_) {}
    try {
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
      if (dailyOk) await _box.put('at', DateTime.now().toIso8601String());
      error.value = _months.isNotEmpty
          ? 'Не удалось обновить инфляцию с сайта Банка России — считаем по сохранённой'
          : (manualInflation != null
              ? null
              : 'Не удалось загрузить инфляцию с сайта Банка России. Её можно указать вручную');
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
  static double? _valueAt(int ord, bool inflation) =>
      (inflation ? _infl : _key).at(ord) ?? (inflation ? manualInflation : null);

  /// Ключевая ставка в месяце даты [d]. После последнего известного месяца
  /// действует последняя ставка — она не меняется, пока её не пересмотрят.
  static double? keyRateAt(DateTime d) {
    final daily = _daily;
    if (daily.isNotEmpty) {
      var lo = 0;
      var hi = daily.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (daily[mid].$1.isAfter(d)) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      return lo == 0 ? daily.first.$2 : daily[lo - 1].$2;
    }
    return _valueAt(_ord(d), false);
  }

  /// Ближайшая дата после [cursor], когда ставка могла поменяться: день
  /// решения Банка России, а без дневных данных — начало следующего месяца.
  static DateTime _nextKeyChange(DateTime cursor) {
    final nextMonth = DateTime(cursor.year, cursor.month + 1);
    final daily = _daily;
    if (daily.isEmpty) return nextMonth;
    for (final c in daily) {
      if (c.$1.isAfter(cursor)) return c.$1;
    }
    return DateTime(9999);
  }

  /// Инфляция за 12 месяцев по данным за месяц даты [d] — только если Банк
  /// России её уже опубликовал. Будущее не дорисовываем.
  static double? inflationIn(DateTime d) =>
      _months[_ord(d)]?.inflation ?? (_infl.values.isEmpty ? manualInflation : null);

  /// Средняя ключевая ставка за период, по дням.
  static double? averageKeyRate(DateTime from, DateTime to) {
    if (!hasData || !to.isAfter(from)) return keyRateAt(to);
    double sum = 0;
    double days = 0;
    var cursor = from;
    while (cursor.isBefore(to)) {
      final next = _nextKeyChange(cursor);
      final end = next.isBefore(to) ? next : to;
      final rate = keyRateAt(cursor);
      if (rate == null) return null;
      final d = end.difference(cursor).inMilliseconds / Duration.millisecondsPerDay;
      sum += rate * d;
      days += d;
      cursor = end;
    }
    return days <= 0 ? null : sum / days;
  }

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
      final next = _nextKeyChange(cursor);
      final end = next.isBefore(to) ? next : to;
      final rate = keyRateAt(cursor);
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
