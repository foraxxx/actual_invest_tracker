import 'dart:convert';

import 'package:http/http.dart' as http;

/// Finds verified organisation logos through Wikidata and Wikimedia Commons.
class WikiLogoService {
  WikiLogoService._();

  static const _timeout = Duration(seconds: 12);
  static final Map<String, String?> _cache = {};
  static final Map<String, Map?> _claimsCache = {};

  /// Searches by the official issuer name as well as its short and historical
  /// aliases. Only entities that look like organisations are accepted.
  static Future<String?> logoUrl(
    String companyName, {
    Iterable<String> aliases = const [],
    int width = 240,
  }) async {
    final queries = <String>{
      _clean(companyName),
      for (final alias in aliases) _clean(alias),
    }..removeWhere((value) => value.isEmpty);
    if (queries.isEmpty) return null;
    final cacheKey = queries.join('|');
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final seen = <String>{};
      for (final query in queries) {
        for (final id in await _searchEntities(query)) {
          if (!seen.add(id) || !await _isCompany(id)) continue;
          final file = await _logoFile(id);
          if (file == null) continue;
          final url = await _rasterUrl(file, width);
          if (url == null) continue;
          _cache[cacheKey] = url;
          return url;
        }
      }
      _cache[cacheKey] = null;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _searchEntities(String query) async {
    final ids = <String>[];
    for (final language in ['ru', 'en']) {
      final uri = Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbsearchentities',
        'search': query,
        'language': language,
        'uselang': language,
        'type': 'item',
        'limit': '7',
        'format': 'json',
      });
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) continue;
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      for (final item in json['search'] as List? ?? const []) {
        final id = '${(item as Map)['id']}';
        if (id.startsWith('Q') && !ids.contains(id)) ids.add(id);
      }
    }
    return ids;
  }

  /// Prevents a similarly named person, place or product from becoming a
  /// security logo. Wikidata uses many corporate subclasses, so a logo plus
  /// an official website or industry is accepted as a corporate marker too.
  static Future<bool> _isCompany(String entityId) async {
    final claims = await _claims(entityId);
    if (claims == null || (claims['P154'] as List? ?? const []).isEmpty) return false;
    const companyTypes = {
      'Q43229',
      'Q4830453',
      'Q6881511',
      'Q783794',
      'Q891723',
      'Q1807108',
      'Q4201895',
    };
    final types = <String>{};
    for (final claim in claims['P31'] as List? ?? const []) {
      final value = ((claim as Map)['mainsnak'] as Map?)?['datavalue'] as Map?;
      final id = (value?['value'] as Map?)?['id'];
      if (id is String) types.add(id);
    }
    return types.any(companyTypes.contains) ||
        (claims['P856'] as List? ?? const []).isNotEmpty ||
        (claims['P452'] as List? ?? const []).isNotEmpty;
  }

  static Future<Map?> _claims(String entityId) async {
    if (_claimsCache.containsKey(entityId)) return _claimsCache[entityId];
    final uri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbgetclaims',
      'entity': entityId,
      'format': 'json',
    });
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final claims = json['claims'] as Map?;
    _claimsCache[entityId] = claims;
    return claims;
  }

  static Future<String?> _logoFile(String entityId) async {
    final claims = await _claims(entityId);
    final logos = claims?['P154'] as List?;
    if (logos == null || logos.isEmpty) return null;
    final value = ((logos.first as Map)['mainsnak'] as Map?)?['datavalue'] as Map?;
    final file = value?['value'];
    return file is String && file.isNotEmpty ? file : null;
  }

  /// Commons returns a raster thumbnail even for an SVG original. This adds
  /// SVG-source support without an extra rendering dependency in the app.
  static Future<String?> _rasterUrl(String file, int width) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'titles': 'File:$file',
      'prop': 'imageinfo',
      'iiprop': 'url|mime',
      'iiurlwidth': '$width',
      'format': 'json',
      'origin': '*',
    });
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final pages = (json['query'] as Map?)?['pages'] as Map?;
    if (pages == null) return null;
    for (final page in pages.values) {
      final imageInfo = (page as Map)['imageinfo'] as List?;
      if (imageInfo == null || imageInfo.isEmpty) continue;
      final info = imageInfo.first as Map;
      final thumb = info['thumburl'];
      if (thumb is String && thumb.isNotEmpty) return thumb;
      final original = info['url'];
      if (!'${info['mime']}'.contains('svg') && original is String && original.isNotEmpty) {
        return original;
      }
    }
    return null;
  }

  static String _clean(String raw) {
    var text = raw
        .replaceAll(RegExp(r'["«»„“]'), ' ')
        .replaceAll(
          RegExp(r'\b(ПАО|ОАО|АО|ЗАО|ООО|PJSC|JSC|OJSC|LLC)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+(ао|ап|а\.п\.|п|преф)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'[-–]\s*п\b', caseSensitive: false), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
