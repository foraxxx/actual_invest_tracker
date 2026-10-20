import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'html_table_reader.dart';
import 'moex_service.dart';
import 'online_settings_service.dart';

/// Одна выплата дивиденда на акцию.
class DividendRecord {
  /// Дата закрытия реестра (отсечка).
  final DateTime date;

  /// Сумма на одну акцию в рублях, до налога.
  final double amount;

  /// Когда компания объявила выплату. null — дата объявления неизвестна.
  final DateTime? announced;

  /// Оценка аналитиков, а не решение компании.
  final bool forecast;

  const DividendRecord({required this.date, required this.amount, this.announced, this.forecast = false});

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get isFuture => date.isAfter(_today) || date.isAtSameMomentAs(_today);

  /// Объявлена компанией и ещё не выплачена.
  bool get isAnnounced => !forecast && isFuture;

  int get dayKey => date.year * 10000 + date.month * 100 + date.day;

  List<Object?> toJson() => [
        dayKey,
        amount,
        announced == null ? 0 : announced!.year * 10000 + announced!.month * 100 + announced!.day,
        forecast ? 1 : 0,
      ];

  static DateTime _fromKey(int k) => DateTime(k ~/ 10000, k ~/ 100 % 100, k % 100);

  static DividendRecord? fromJson(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final d = (raw[0] as num?)?.toInt();
    final a = (raw[1] as num?)?.toDouble();
    if (d == null || a == null) return null;
    final ann = raw.length > 2 ? (raw[2] as num?)?.toInt() ?? 0 : 0;
    return DividendRecord(
      date: _fromKey(d),
      amount: a,
      announced: ann > 0 ? _fromKey(ann) : null,
      forecast: raw.length > 3 && raw[3] == 1,
    );
  }
}

/// История дивидендов одной акции, сохранённая на телефоне.
class DividendHistory {
  final List<DividendRecord> records;
  final DateTime? updatedAt;

  /// Откуда последний раз удалось получить данные.
  final String source;

  /// Ошибка последней попытки, если она была неудачной.
  final String? error;

  const DividendHistory({required this.records, this.updatedAt, this.source = '', this.error});

  bool get isEmpty => records.isEmpty;

  /// Сумма на акцию по годам отсечки: выплачено, объявлено и прогноз
  /// отдельно.
  Map<int, ({double paid, double announced, double forecast})> byYear() {
    final map = <int, ({double paid, double announced, double forecast})>{};
    for (final r in records) {
      final cur = map[r.date.year] ?? (paid: 0.0, announced: 0.0, forecast: 0.0);
      map[r.date.year] = r.forecast
          ? (paid: cur.paid, announced: cur.announced, forecast: cur.forecast + r.amount)
          : r.isFuture
              ? (paid: cur.paid, announced: cur.announced + r.amount, forecast: cur.forecast)
              : (paid: cur.paid + r.amount, announced: cur.announced, forecast: cur.forecast);
    }
    return map;
  }

  /// Дивиденды на акцию с отсечкой за последние 12 месяцев.
  double get last12m {
    final now = DateTime.now();
    final from = DateTime(now.year - 1, now.month, now.day);
    return records
        .where((r) => !r.forecast && !r.isFuture && r.date.isAfter(from))
        .fold(0.0, (s, r) => s + r.amount);
  }

  /// Ближайшая объявленная компанией выплата.
  DividendRecord? get nextAnnounced {
    final list = records.where((r) => r.isAnnounced).toList()..sort((a, b) => a.date.compareTo(b.date));
    return list.isEmpty ? null : list.first;
  }
}

/// История дивидендов акций.
///
/// Мосбиржа перестала бесплатно отдавать дивиденды, поэтому основной
/// источник — страницы Доход.ру, запасной — smart-lab. Всё, что однажды
/// загрузилось, хранится на телефоне и попадает в бэкап: если сайт
/// поменяется или пропадёт, история не потеряется. Новые загрузки только
/// добавляют и уточняют выплаты; удаляются лишь устаревшие прогнозы.
class DividendHistoryService {
  DividendHistoryService._();

  static const boxName = 'dividend_history';
  static Box<String>? _box;
  static final ValueNotifier<int> version = ValueNotifier(0);
  static final Map<String, Future<DividendHistory?>> _inFlight = {};
  static final Map<String, DividendHistory?> _cache = {};

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static String _key(String ticker) => ticker.toUpperCase();

  /// Сохранённая история. null — по бумаге ещё ничего не загружалось.
  static DividendHistory? of(String ticker) {
    final key = _key(ticker);
    if (_cache.containsKey(key)) return _cache[key];
    final raw = _box?.get(key);
    DividendHistory? h;
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        h = DividendHistory(
          records: _records(m['r'])..sort((a, b) => a.date.compareTo(b.date)),
          updatedAt: DateTime.tryParse('${m['u'] ?? ''}'),
          source: '${m['s'] ?? ''}',
          error: m['e'] as String?,
        );
      } catch (_) {
        h = null;
      }
    }
    _cache[key] = h;
    return h;
  }

  static List<DividendRecord> _records(Object? raw) => [
        for (final r in (raw is List ? raw : const [])) DividendRecord.fromJson(r),
      ].whereType<DividendRecord>().toList();

  static Future<void> _save(String ticker, DividendHistory h) async {
    final key = _key(ticker);
    _cache[key] = h;
    await _box?.put(
      key,
      jsonEncode({
        'r': [for (final r in h.records) r.toJson()],
        if (h.updatedAt != null) 'u': h.updatedAt!.toIso8601String(),
        's': h.source,
        if (h.error != null) 'e': h.error,
      }),
    );
    version.value++;
  }

  static bool _freshToday(DividendHistory? h) {
    final u = h?.updatedAt;
    if (u == null) return false;
    final n = DateTime.now();
    return u.year == n.year && u.month == n.month && u.day == n.day;
  }

  /// Обновляет историю бумаги — не чаще раза в день. [moex] — дивиденды с
  /// биржи, если она их отдала: подмешиваются к остальному.
  static Future<DividendHistory?> update(String ticker, {List<MoexPayout> moex = const [], bool force = false}) {
    final key = _key(ticker);
    final running = _inFlight[key];
    if (running != null) return running;
    final f = _update(key, moex, force).whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = f;
    return f;
  }

  static Future<DividendHistory?> _update(String ticker, List<MoexPayout> moex, bool force) async {
    final old = of(ticker);
    final fromMoex = [
      for (final p in moex)
        if (p.kind == 'Дивиденд' && p.dateKnown && p.amount > 0) DividendRecord(date: p.date, amount: p.amount),
    ];
    if (!OnlineSettingsService.enabled || (!force && _freshToday(old) && old?.error == null)) {
      if (fromMoex.isEmpty) return old;
      final merged = merge(old?.records ?? const [], fromMoex, replaceForecasts: false);
      final h = DividendHistory(records: merged, updatedAt: old?.updatedAt, source: old?.source ?? 'Мосбиржа');
      await _save(ticker, h);
      return h;
    }

    List<DividendRecord>? fresh;
    var source = '';
    String? error;
    try {
      fresh = parseDohod(await _get('https://www.dohod.ru/ik/analytics/dividend/${ticker.toLowerCase()}'));
      source = 'Доход.ру';
      if (fresh.isEmpty) fresh = null;
    } catch (_) {
      fresh = null;
    }
    if (fresh == null) {
      try {
        fresh = parseSmartLab(await _get('https://smart-lab.ru/q/${ticker.toUpperCase()}/dividend/'));
        source = 'smart-lab';
        if (fresh.isEmpty) fresh = null;
      } catch (_) {
        fresh = null;
      }
    }
    if (fresh == null) {
      error = 'не удалось загрузить';
      source = old?.source ?? '';
    }
    final merged = merge(
      old?.records ?? const [],
      [...?fresh, ...fromMoex],
      replaceForecasts: fresh != null,
    );
    if (fresh == null && fromMoex.isNotEmpty && source.isEmpty) source = 'Мосбиржа';
    final h = DividendHistory(
      records: merged,
      // Время обновления — только когда данные действительно пришли: иначе
      // подпись «обновлено сегодня» обманывала бы.
      updatedAt: fresh != null ? DateTime.now() : old?.updatedAt,
      source: source,
      error: error,
    );
    await _save(ticker, h);
    return h;
  }

  static Future<String> _get(String url) async {
    final r = await http.get(Uri.parse(url), headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) InvestTracker',
      'Accept': 'text/html',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('код ${r.statusCode}');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Обновляет историю по всем акциям из списка — по очереди, с паузой,
  /// чтобы не нагружать ни телефон, ни сайт.
  static Future<void> refreshAll(Iterable<String> tickers) async {
    if (!OnlineSettingsService.enabled) return;
    for (final t in tickers) {
      final h = of(t);
      if (_freshToday(h) && h?.error == null) continue;
      await update(t);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  /// Пометка прогноза аналитиков в выплатах для прогноза.
  static const forecastMark = 'прогноз';

  /// Выплаты в виде, привычном прогнозу. Прогнозы аналитиков тоже идут —
  /// с пометкой [forecastMark] и без точной даты (dateKnown: false): в
  /// календарь объявленных выплат и годовую статистику они не попадают, а в
  /// прогноз на 12 месяцев — попадают, как и на графике в карточке.
  static List<MoexPayout> asPayouts(String ticker) => [
        for (final r in of(ticker)?.records ?? const <DividendRecord>[])
          MoexPayout(
            date: r.date,
            amount: r.amount,
            currency: 'RUB',
            kind: 'Дивиденд',
            dateKnown: !r.forecast,
            extra: r.forecast ? forecastMark : null,
          ),
      ];

  // --- Склейка ---

  /// Склеивает сохранённые и новые записи. Выплаты не удаляются никогда;
  /// одинаковая дата отсечки — уточняется сумма. Прогнозы заменяются
  /// свежими ([replaceForecasts]), прошедшие и уже объявленные — убираются.
  static List<DividendRecord> merge(
    List<DividendRecord> old,
    List<DividendRecord> fresh, {
    required bool replaceForecasts,
  }) {
    final actual = <int, DividendRecord>{
      for (final r in old)
        if (!r.forecast) r.dayKey: r,
    };
    for (final r in fresh) {
      if (r.forecast) continue;
      final prev = actual[r.dayKey];
      actual[r.dayKey] = DividendRecord(
        date: r.date,
        amount: r.amount,
        announced: r.announced ?? prev?.announced,
      );
    }
    final forecasts = [
      for (final r in (replaceForecasts ? fresh : old))
        if (r.forecast) r,
    ];
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final keptForecasts = forecasts.where((f) {
      if (f.date.isBefore(start)) return false;
      // Компания объявила выплату — оценка рядом с ней больше не нужна.
      return !actual.values.any((a) => (a.date.difference(f.date).inDays).abs() < 75);
    });
    return [...actual.values, ...keptForecasts]..sort((a, b) => a.date.compareTo(b.date));
  }

  // --- Разбор страниц ---

  static final _date = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})');

  static DateTime? _parseDate(String s) {
    final m = _date.firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  static double? _parseAmount(String s) {
    final clean = s.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.');
    final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(clean);
    return m == null ? null : double.tryParse(m.group(0)!);
  }

  static List<List<List<String>>> _tables(String html) =>
      HtmlTableReader.tables(Uint8List.fromList(utf8.encode(html)));

  static int _col(List<String> header, bool Function(String) test) {
    for (int i = 0; i < header.length; i++) {
      if (test(header[i].toLowerCase())) return i;
    }
    return -1;
  }

  /// Страница Доход.ру: таблица «Все выплаты» — дата объявления, дата
  /// закрытия реестра (у прогноза с пометкой «прогноз»), год, дивиденд.
  static List<DividendRecord> parseDohod(String html) {
    for (final table in _tables(html)) {
      if (table.isEmpty) continue;
      final header = table.first;
      final dateCol = _col(header, (h) => h.contains('реестр'));
      final amountCol = _col(header, (h) => h.contains('дивиденд') && !h.contains('дата') && !h.contains('год'));
      if (dateCol < 0 || amountCol < 0) continue;
      final annCol = _col(header, (h) => h.contains('объявлен'));
      final result = <DividendRecord>[];
      for (final row in table.skip(1)) {
        if (row.length <= dateCol || row.length <= amountCol) continue;
        final date = _parseDate(row[dateCol]);
        final amount = _parseAmount(row[amountCol]);
        if (date == null || amount == null || amount <= 0) continue;
        final forecast = row[dateCol].toLowerCase().contains('прогноз');
        result.add(DividendRecord(
          date: date,
          amount: amount,
          announced: annCol >= 0 && row.length > annCol ? _parseDate(row[annCol]) : null,
          forecast: forecast,
        ));
      }
      if (result.isNotEmpty) return result;
    }
    return const [];
  }

  /// Страница smart-lab: дата отсечки и дивиденд в рублях. Объявлена ли
  /// будущая выплата, по странице понять нельзя — поэтому будущие строки
  /// считаются прогнозом.
  static List<DividendRecord> parseSmartLab(String html) {
    final result = <DividendRecord>[];
    for (final table in _tables(html)) {
      if (table.isEmpty) continue;
      final header = table.first;
      final dateCol = _col(header, (h) => h.contains('отсечк'));
      final amountCol = _col(header, (h) => h.contains('дивиденд') && !h.contains('доходн'));
      if (dateCol < 0 || amountCol < 0) continue;
      for (final row in table.skip(1)) {
        if (row.length <= dateCol || row.length <= amountCol) continue;
        final date = _parseDate(row[dateCol]);
        final amount = _parseAmount(row[amountCol]);
        if (date == null || amount == null || amount <= 0) continue;
        final r = DividendRecord(date: date, amount: amount);
        result.add(DividendRecord(date: date, amount: amount, forecast: r.isFuture));
      }
    }
    return result;
  }

  // --- Бэкап ---

  static Map<String, String> exportAll() => {
        for (final k in _box?.keys ?? const [])
          if (_box!.get(k) != null) '$k': _box!.get(k)!,
      };

  /// Восстановление из бэкапа: сохранённые записи склеиваются с теми, что
  /// уже есть, — ничего не теряется ни с той, ни с другой стороны.
  static Future<void> importAll(Map<String, String> data) async {
    for (final e in data.entries) {
      DividendHistory? incoming;
      try {
        final m = jsonDecode(e.value) as Map;
        incoming = DividendHistory(
          records: _records(m['r']),
          updatedAt: DateTime.tryParse('${m['u'] ?? ''}'),
          source: '${m['s'] ?? ''}',
        );
      } catch (_) {
        continue;
      }
      final current = of(e.key);
      final merged = merge(current?.records ?? const [], incoming.records, replaceForecasts: current == null);
      await _save(
        e.key,
        DividendHistory(
          records: merged,
          updatedAt: current?.updatedAt ?? incoming.updatedAt,
          source: current?.source ?? incoming.source,
        ),
      );
    }
  }
}
