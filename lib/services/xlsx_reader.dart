import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Чтение XLSX без сторонних «умных» библиотек.
///
/// Готовые пакеты разбирают ещё и оформление, и на отчёте ВТБ падали на
/// нестандартных форматах чисел («custom numFmtId starts at 164 but found a
/// value of 0»). Нам оформление не нужно — нужны значения ячеек, а XLSX это
/// обычный ZIP с XML внутри.
class XlsxReader {
  XlsxReader._();

  /// Возвращает первый лист книги как таблицу строк. Пустые ячейки — пустые
  /// строки, ряды дополняются до одинаковой длины.
  static List<List<String>> firstSheet(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    String? sharedXml;
    final sheets = <String, String>{};

    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == 'xl/sharedStrings.xml') {
        sharedXml = _text(file.content);
      } else if (file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml')) {
        sheets[file.name] = _text(file.content);
      }
    }

    if (sheets.isEmpty) return const [];

    // Листы могут лежать не по порядку — берём с наименьшим номером.
    final names = sheets.keys.toList()..sort();
    final shared = sharedXml == null ? const <String>[] : _sharedStrings(sharedXml);

    return _parseSheet(sheets[names.first]!, shared);
  }

  static String _text(List<int> content) => utf8.decode(content, allowMalformed: true);

  /// Общая таблица строк: в XLSX текст ячеек хранится отдельно, а в самой
  /// ячейке лежит только номер записи.
  static List<String> _sharedStrings(String xml) {
    final doc = XmlDocument.parse(xml);
    return doc
        .findAllElements('si')
        .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  }

  static List<List<String>> _parseSheet(String xml, List<String> shared) {
    final doc = XmlDocument.parse(xml);
    final rows = <List<String>>[];
    int maxColumns = 0;

    for (final row in doc.findAllElements('row')) {
      final cells = <int, String>{};

      for (final cell in row.findAllElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final column = _columnIndex(ref);
        if (column < 0) continue;

        final type = cell.getAttribute('t');
        String value;

        if (type == 'inlineStr') {
          value = cell.findAllElements('t').map((t) => t.innerText).join();
        } else {
          final raw = cell.findElements('v').isEmpty ? '' : cell.findElements('v').first.innerText;
          if (type == 's') {
            final index = int.tryParse(raw);
            value = (index != null && index >= 0 && index < shared.length) ? shared[index] : '';
          } else {
            value = raw;
          }
        }

        if (value.trim().isNotEmpty) cells[column] = value.trim();
        if (column + 1 > maxColumns) maxColumns = column + 1;
      }

      final list = List<String>.filled(maxColumns, '');
      cells.forEach((index, value) {
        if (index < list.length) list[index] = value;
      });
      rows.add(list);
    }

    // Выравниваем длину рядов: дальше к ячейкам обращаются по номеру колонки.
    for (final row in rows) {
      if (row.length < maxColumns) {
        row.addAll(List<String>.filled(maxColumns - row.length, ''));
      }
    }
    return rows;
  }

  /// «B12» → 1. Буквенная часть — это число в 26-ричной системе.
  static int _columnIndex(String ref) {
    int result = 0;
    for (int i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        result = result * 26 + (code - 64);
      } else if (code >= 97 && code <= 122) {
        result = result * 26 + (code - 96);
      } else {
        break;
      }
    }
    return result - 1;
  }
}
