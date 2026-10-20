import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Логотипы ценных бумаг.
///
/// Что показывается: картинка, которую вы поставили бумаге сами → логотип,
/// встроенный в приложение → заглушка с буквами тикера. Из интернета
/// логотипы больше не загружаются.
///
/// Встроенные логотипы упакованы в один файл assets/logos/logos.bin: одна
/// картинка WebP на эмитента (у десятков облигаций одной компании она общая)
/// и оглавление «тикер или ISIN → картинка». Картинки заранее обрезаны так,
/// чтобы знак занимал круг одинаково у всех бумаг.
///
/// Формат файла: «LOGO», длина оглавления (4 байта), оглавление в JSON
/// {"f": [[смещение, длина], …], "m": {тикер: номер картинки}}, картинки.
class LogoService {
  static const boxName = 'ticker_logos';
  static const _packAsset = 'assets/logos/logos.bin';
  static const _migrationKey = '#bundled_logos';
  static late Box<String> _box;

  /// Тикер или ISIN → номер картинки.
  static Map<String, int> _bundled = const {};
  static ByteData? _pack;
  static int _dataStart = 0;
  static List<List<int>> _files = const [];

  /// Готовые картинки по номеру: один и тот же объект для всех бумаг
  /// эмитента, поэтому Flutter декодирует картинку один раз.
  static final Map<int, MemoryImage> _images = {};

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
    try {
      final pack = await rootBundle.load(_packAsset);
      final headLen = pack.getUint32(4, Endian.little);
      final head = jsonDecode(utf8.decode(pack.buffer.asUint8List(pack.offsetInBytes + 8, headLen))) as Map;
      _files = [for (final f in head['f'] as List) [(f as List)[0] as int, f[1] as int]];
      _bundled = {for (final e in (head['m'] as Map).entries) '${e.key}': e.value as int};
      _dataStart = 8 + headLen;
      _pack = pack;
    } catch (_) {
      _bundled = const {};
    }
    if (_box.get(_migrationKey) != '1') await _dropDownloaded();
  }

  /// Один раз после перехода на встроенные логотипы: убираем то, что
  /// приложение раньше скачивало само, — у этих бумаг теперь есть картинка
  /// получше. Логотипы бумаг, которых нет среди встроенных, остаются.
  static Future<void> _dropDownloaded() async {
    final keys = _box.keys.map((k) => '$k').toList();
    final remove = <String>{
      for (final k in keys)
        if (k.toLowerCase().startsWith('#tried:') || k == '#retry_schema') k,
    };
    for (final k in keys) {
      if (k.startsWith('#') || k.startsWith('@')) continue;
      if (_bundled.containsKey(k)) remove.add(k);
    }
    // Картинки эмитентов, на которые больше никто не ссылается.
    final used = <String>{
      for (final k in keys)
        if (!remove.contains(k)) ...[
          if (_box.get(k)?.startsWith('@issuer:') == true)
            '#issuer_${_box.get(k)!.substring('@issuer:'.length)}'.toUpperCase(),
        ],
    };
    for (final k in keys) {
      if (k.toUpperCase().startsWith('#ISSUER_') && !used.contains(k.toUpperCase())) remove.add(k);
    }
    for (final k in remove) {
      final path = _box.get(k);
      if (path != null && !path.startsWith('@')) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
    await _box.deleteAll(remove);
    await _box.put(_migrationKey, '1');
  }

  /// Есть ли у бумаги встроенный логотип.
  static bool hasBundled(String ticker) => _bundled.containsKey(ticker.toUpperCase());

  /// Встроенный логотип: сначала по тикеру, потом по ISIN.
  static ImageProvider? bundled(String ticker, {String? isin}) {
    final pack = _pack;
    if (pack == null) return null;
    final i = _bundled[ticker.toUpperCase()] ??
        (isin == null || isin.isEmpty ? null : _bundled[isin.toUpperCase()]);
    if (i == null || i >= _files.length) return null;
    return _images.putIfAbsent(i, () {
      final f = _files[i];
      return MemoryImage(pack.buffer.asUint8List(pack.offsetInBytes + _dataStart + f[0], f[1]));
    });
  }

  /// Своя картинка бумаги (поставленная вручную), если есть.
  static String? getPath(String ticker) {
    var path = _box.get(ticker.toUpperCase());
    if (path == null) return null;
    if (path.startsWith('@issuer:')) {
      path = _box.get('#issuer_${path.substring('@issuer:'.length)}'.toUpperCase());
      if (path == null) return null;
    }
    if (!File(path).existsSync()) return null;
    return path;
  }

  static Future<void> setLogo(String ticker, File sourceFile) async {
    final ext = sourceFile.path.split('.').last;
    await setLogoBytes(ticker, await sourceFile.readAsBytes(), ext);
  }

  /// То же самое, но из готовых байтов — для восстановления из бэкапа.
  static Future<void> setLogoBytes(String ticker, List<int> bytes, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final logosDir = Directory('${dir.path}/logos');
    if (!await logosDir.exists()) {
      await logosDir.create(recursive: true);
    }
    final cleanExt = ext.startsWith('.') ? ext : '.$ext';
    final destPath = '${logosDir.path}/${ticker.toUpperCase()}$cleanExt';

    final old = _box.get(ticker.toUpperCase());
    if (old != null && old != destPath && !old.startsWith('@') && File(old).existsSync()) {
      await FileImage(File(old)).evict();
      await File(old).delete();
    }

    await File(destPath).writeAsBytes(bytes);
    // Путь у тикера всегда один и тот же, поэтому сбрасываем кэш картинки —
    // иначе до перезапуска была бы видна старая.
    await FileImage(File(destPath)).evict();
    await _box.put(ticker.toUpperCase(), destPath);
    version.value++;
  }

  static Future<void> removeLogo(String ticker) async {
    final key = ticker.toUpperCase();
    final raw = _box.get(key);
    if (raw != null && !raw.startsWith('@')) {
      await FileImage(File(raw)).evict();
      if (File(raw).existsSync()) await File(raw).delete();
    }
    await _box.delete(key);
    version.value++;
  }

  /// Свои картинки — тикер → путь к файлу. Для бэкапа: встроенные
  /// логотипы в него не попадают, они есть в любой копии приложения.
  static Map<String, String> get allPaths {
    final map = <String, String>{};
    for (final key in _box.keys) {
      final ticker = '$key';
      if (ticker.startsWith('#')) continue;
      final path = getPath(ticker);
      if (path != null) map[ticker] = path;
    }
    return map;
  }
}
