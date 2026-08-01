import 'dart:convert';
import 'dart:typed_data';

/// Минимальный читатель табличных HTML-отчётов брокеров.
///
/// Нам не нужен DOM и оформление документа: только строки таблиц. Поэтому
/// разбираем `table/tr/td` напрямую и нормализуем пробелы и HTML-сущности.
class HtmlTableReader {
  HtmlTableReader._();

  static String text(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  static List<List<List<String>>> tables(Uint8List bytes) {
    final source = text(bytes);
    final tablePattern = RegExp(r'<table\b[^>]*>(.*?)</table\s*>', caseSensitive: false, dotAll: true);
    final rowPattern = RegExp(r'<tr\b[^>]*>(.*?)</tr\s*>', caseSensitive: false, dotAll: true);
    final cellPattern = RegExp(r'<t[dh]\b[^>]*>(.*?)</t[dh]\s*>', caseSensitive: false, dotAll: true);

    return [
      for (final table in tablePattern.allMatches(source))
        [
          for (final row in rowPattern.allMatches(table.group(1)!))
            [
              for (final cell in cellPattern.allMatches(row.group(1)!))
                _plainText(cell.group(1)!),
            ],
        ],
    ];
  }

  static String _plainText(String html) {
    var value = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    value = value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    value = value.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|\d+);'), (match) {
      final raw = match.group(1)!;
      final code = raw.startsWith('x')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    });
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
