import 'dart:convert';

import 'package:http/http.dart' as http;

/// Логотипы из Викиданных и Викисклада.
///
/// CDN брокеров хранят картинки под своими внутренними идентификаторами, и
/// подобрать их снаружи нельзя — проверка показала ноль попаданий из двадцати
/// двух. Викиданные же публичны, отдают логотипы по названию компании и
/// разрешают повторное использование.
class WikiLogoService {
  WikiLogoService._();

  static const _timeout = Duration(seconds: 12);

  /// Название компании -> адрес картинки. Один и тот же эмитент встречается
  /// много раз, а запрос не бесплатный.
  static final Map<String, String?> _cache = {};

  /// Ищет логотип по названию эмитента. Возвращает адрес PNG нужного размера.
  static Future<String?> logoUrl(String companyName, {int width = 240}) async {
    final query = _clean(companyName);
    if (query.isEmpty) return null;
    if (_cache.containsKey(query)) return _cache[query];

    try {
      final entities = await _searchEntities(query);
      for (final id in entities) {
        final file = await _logoFile(id);
        if (file == null) continue;
        // Special:FilePath отдаёт файл по имени, а с параметром width ещё и
        // превращает SVG в PNG — растр нам и нужен.
        final url = Uri.https(
          'commons.wikimedia.org',
          '/wiki/Special:FilePath/${Uri.encodeComponent(file)}',
          {'width': '$width'},
        ).toString();
        _cache[query] = url;
        return url;
      }
      _cache[query] = null;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Первые несколько подходящих сущностей: ищем сначала по-русски, потом
  /// по-английски — часть эмитентов описана только в английском разделе.
  static Future<List<String>> _searchEntities(String query) async {
    final ids = <String>[];
    for (final language in ['ru', 'en']) {
      final uri = Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbsearchentities',
        'search': query,
        'language': language,
        'uselang': language,
        'type': 'item',
        'limit': '5',
        'format': 'json',
      });
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) continue;
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      for (final item in (json['search'] as List? ?? const [])) {
        final id = '${(item as Map)['id']}';
        if (id.startsWith('Q') && !ids.contains(id)) ids.add(id);
      }
      if (ids.isNotEmpty) break;
    }
    return ids;
  }

  /// Свойство P154 — «логотип». Если его нет, сущность нам не подходит.
  static Future<String?> _logoFile(String entityId) async {
    final uri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbgetclaims',
      'entity': entityId,
      'property': 'P154',
      'format': 'json',
    });
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final claims = (json['claims'] as Map?)?['P154'] as List?;
    if (claims == null || claims.isEmpty) return null;

    final value = ((claims.first as Map)['mainsnak'] as Map?)?['datavalue'] as Map?;
    final file = value?['value'];
    return file is String && file.isNotEmpty ? file : null;
  }

  /// Убираем из названия то, что мешает поиску: организационные формы,
  /// кавычки и хвосты вроде «ао», «ап», «-п».
  static String _clean(String raw) {
    var text = raw
        .replaceAll(RegExp(r'["«»„“]'), ' ')
        .replaceAll(RegExp(r'\b(ПАО|ОАО|АО|ЗАО|ООО|ПJSC|PJSC|JSC|OJSC|LLC)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+(ао|ап|а\.п\.|п|преф)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[-–]\s*п\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }
}
