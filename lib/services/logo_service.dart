import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'moex_service.dart';
import 'wiki_logo_service.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Логотипы ценных бумаг. Картинка лежит файлом в папке приложения, путь —
/// в Hive.
///
/// Приоритет источников: загруженный тобой вручную логотип → скачанный ранее
/// и лежащий в кэше → попытка скачать по ISIN → градиентная аватарка с
/// буквами. Скачивание происходит один раз на бумагу и только при включённой
/// загрузке с биржи; офлайн-режим работает ровно как раньше.
class LogoService {
  static const boxName = 'ticker_logos';
  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static String? getPath(String ticker) {
    final path = _box.get(ticker.toUpperCase());
    if (path == null) return null;
    if (!File(path).existsSync()) return null;
    return path;
  }

  static Future<void> setLogo(String ticker, File sourceFile) async {
    final ext = sourceFile.path.split('.').last;
    await setLogoBytes(ticker, await sourceFile.readAsBytes(), ext);
  }

  /// То же самое, но из уже готовых байтов — используется при импорте
  /// бэкапа, где иконка хранится встроенной в JSON (base64), без отдельного
  /// файла на диске.
  static Future<void> setLogoBytes(String ticker, List<int> bytes, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final logosDir = Directory('${dir.path}/logos');
    if (!await logosDir.exists()) {
      await logosDir.create(recursive: true);
    }
    final cleanExt = ext.startsWith('.') ? ext : '.$ext';
    final destPath = '${logosDir.path}/${ticker.toUpperCase()}$cleanExt';

    // удаляем старый логотип этой бумаги, если был другого расширения
    final old = _box.get(ticker.toUpperCase());
    if (old != null && old != destPath && File(old).existsSync()) {
      await FileImage(File(old)).evict();
      await File(old).delete();
    }

    await File(destPath).writeAsBytes(bytes);
    // Flutter кэширует декодированную картинку по пути файла — раз путь у нас
    // всегда один и тот же для этого тикера (перезаписываем), без явного
    // сброса кэша старая картинка так и оставалась бы видна до перезапуска
    // приложения. Сбрасываем кэш именно для этого файла, чтобы новая картинка
    // отрисовалась сразу же везде, где показывается TickerAvatar.
    await FileImage(File(destPath)).evict();
    await _box.put(ticker.toUpperCase(), destPath);
    version.value++;
  }

  static Future<void> removeLogo(String ticker) async {
    final path = _box.get(ticker.toUpperCase());
    if (path != null) {
      await FileImage(File(path)).evict();
      if (File(path).existsSync()) {
        await File(path).delete();
      }
    }
    await _box.delete(ticker.toUpperCase());
    version.value++;
  }


  /// Откуда пробуем взять логотип. Шаблоны перебираются по порядку,
  /// побеждает первый, который вернул картинку. Мосбиржа изображений не
  /// отдаёт, поэтому источники внешние — если какой-то перестанет работать,
  /// достаточно поправить этот список.
  static const List<String> urlTemplates = [
    'https://invest-brands.cdn-tinkoff.ru/{isin}x160.png',
    'https://invest-brands.cdn-tinkoff.ru/{isin}x320.png',
    'https://invest-brands.cdn-tinkoff.ru/{isin}x640.png',
    'https://invest-brands.cdn-tinkoff.ru/{ticker}x160.png',
    'https://invest-brands.cdn-tinkoff.ru/{ticker}x320.png',
    'https://static.tinkoff.ru/brands/traiding/{isin}x160.png',
    'https://static.tinkoff.ru/brands/traiding/{ticker}x160.png',
    // Некоторые CDN хранят имена в нижнем регистре.
    'https://invest-brands.cdn-tinkoff.ru/{isin_lower}x160.png',
    'https://invest-brands.cdn-tinkoff.ru/{ticker_lower}x160.png',
  ];

  /// Последние неудачи с адресами, которые пробовались, — показывается в
  /// настройках. По этому списку понятно, каких источников не хватает.
  static final Map<String, List<String>> lastFailures = {};

  static const _triedPrefix = '#tried:';
  static const _retryAfter = Duration(days: 7);

  /// Тикеры, по которым попытка уже идёт прямо сейчас — чтобы список из
  /// тысячи строк не запустил тысячу одинаковых загрузок.
  static final Set<String> _inFlight = {};

  static bool _recentlyTried(String ticker) {
    final raw = _box.get('$_triedPrefix${ticker.toUpperCase()}');
    if (raw == null) return false;
    final when = DateTime.tryParse(raw);
    if (when == null) return false;
    return DateTime.now().difference(when) < _retryAfter;
  }

  /// Пробует скачать логотип, если его ещё нет. Возвращает true, если
  /// картинка появилась.
  ///
  /// Неудачная попытка запоминается, и следующая будет не раньше чем через
  /// неделю: у части бумаг логотипа нет нигде, и долбить сеть при каждой
  /// перерисовке списка не нужно.
  static Future<bool> fetchIfMissing(
    String ticker, {
    String? isin,
    /// Бумага эмитента, чей логотип подойдёт: у облигаций своих картинок нет.
    String? issuerTicker,
    String? issuerIsin,
    /// Название бумаги и её эмитента — по ним ищем логотип в Викиданных.
    String? companyName,
    String? issuerName,
  }) async {
    final key = ticker.toUpperCase();
    if (getPath(key) != null) return false;
    if (_inFlight.contains(key) || _recentlyTried(key)) return false;
    _inFlight.add(key);

    final tried = <String>[];

    try {
      // Пробуем сначала свои идентификаторы, потом эмитента.
      final variants = <({String? isin, String ticker})>[
        (isin: isin, ticker: key),
        if (issuerTicker != null && issuerTicker.toUpperCase() != key)
          (isin: issuerIsin, ticker: issuerTicker.toUpperCase()),
      ];

      for (final variant in variants) {
      for (final template in urlTemplates) {
        final url = template
            .replaceAll('{isin}', variant.isin ?? '')
            .replaceAll('{isin_lower}', (variant.isin ?? '').toLowerCase())
            .replaceAll('{ticker}', variant.ticker)
            .replaceAll('{ticker_lower}', variant.ticker.toLowerCase());
        if (url.contains('{') ||
            (template.contains('isin') && (variant.isin == null || variant.isin!.isEmpty))) {
          continue;
        }
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          final type = response.headers['content-type'] ?? '';
          tried.add('${response.statusCode} ${type.split(';').first} · $url');
          // Часть CDN на «нет такой картинки» отвечает не 404, а заглушкой
          // или html — поэтому проверяем и тип, и размер.
          if (response.statusCode == 200 && type.startsWith('image/') && response.bodyBytes.length > 200) {
            final ext = type.contains('png') ? 'png' : (type.contains('svg') ? 'svg' : 'jpg');
            if (ext == 'svg') continue; // SVG Image.file не покажет
            await setLogoBytes(key, response.bodyBytes, ext);
            await _box.delete('$_triedPrefix$key');
            lastFailures.remove(key);
            return true;
          }
        } catch (e) {
          tried.add('ошибка сети · $url');
        }
      }
      }
      // CDN брокеров нас не знают — пробуем Викиданные по названию компании.
      for (final name in {if (companyName != null) companyName, if (issuerName != null) issuerName}) {
        final url = await WikiLogoService.logoUrl(name);
        if (url == null) {
          tried.add('в Викиданных нет логотипа · $name');
          continue;
        }
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
          final type = response.headers['content-type'] ?? '';
          tried.add('${response.statusCode} ${type.split(';').first} · $url');
          if (response.statusCode == 200 &&
              type.startsWith('image/') &&
              !type.contains('svg') &&
              response.bodyBytes.length > 200) {
            await setLogoBytes(key, response.bodyBytes, type.contains('png') ? 'png' : 'jpg');
            await _box.delete('$_triedPrefix$key');
            lastFailures.remove(key);
            return true;
          }
        } catch (e) {
          tried.add('ошибка сети · $url');
        }
      }

      await _box.put('$_triedPrefix$key', DateTime.now().toIso8601String());
      lastFailures[key] = tried;
      return false;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Разовый проход по списку бумаг — для кнопки в настройках.
  /// Возвращает, сколько логотипов удалось подтянуть.
  static Future<({int loaded, List<String> failed})> fetchForAll(
    Map<String, String> tickerToIsin, {
    /// Названия бумаг: по ним ищется логотип в Викиданных, когда CDN молчат.
    Map<String, String> names = const {},
  }) async {
    int loaded = 0;
    final failed = <String>[];
    for (final e in tickerToIsin.entries) {
      if (getPath(e.key) != null) continue;

      // Своего логотипа у выпуска может не быть, поэтому сразу узнаём бумагу
      // эмитента: для облигаций это основной путь.
      final issuer = await MoexService.issuerShareFor(e.key);
      final issuerIsin = issuer == null ? null : await MoexService.isinOf(issuer);
      final issuerName = issuer == null ? null : await MoexService.nameOf(issuer);

      if (await fetchIfMissing(
        e.key,
        isin: e.value,
        issuerTicker: issuer,
        issuerIsin: issuerIsin,
        companyName: names[e.key],
        issuerName: issuerName,
      )) {
        loaded++;
        continue;
      }
      failed.add(e.key);
    }
    return (loaded: loaded, failed: failed);
  }

  /// Забыть неудачу по одной бумаге — чтобы сразу попробовать другой источник.
  static Future<void> forgetFailedAttempt(String ticker) async {
    await _box.delete('$_triedPrefix${ticker.toUpperCase()}');
  }

  /// Сбрасывает отметки о неудачных попытках, чтобы попробовать заново.
  static Future<void> forgetFailedAttempts() async {
    final keys = _box.keys.where((k) => '$k'.startsWith(_triedPrefix)).toList();
    await _box.deleteAll(keys);
  }

  /// Все текущие логотипы — тикер -> абсолютный путь к файлу на диске
  /// (только существующие файлы). Используется для бэкапа.
  static Map<String, String> get allPaths {
    final map = <String, String>{};
    for (final key in _box.keys) {
      final ticker = key as String;
      if (ticker.startsWith(_triedPrefix)) continue;
      final path = getPath(ticker);
      if (path != null) map[ticker] = path;
    }
    return map;
  }
}
