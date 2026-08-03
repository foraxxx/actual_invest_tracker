import 'dart:convert';

import 'package:http/http.dart' as http;

/// Finds verified organisation logos through Wikidata and Wikimedia Commons.
class WikiLogoService {
  WikiLogoService._();

  static const _timeout = Duration(seconds: 12);
  static final Map<String, String?> _cache = {};
  static final Map<String, Map?> _claimsCache = {};
  static const _headers = {
    'User-Agent': 'InvestTracker/1.0 (Android; issuer logo lookup)',
    'Accept': 'application/json',
  };

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
    queries.addAll({
      for (final query in queries.toList()) _latinSearchVariant(query),
    });
    queries.removeWhere((value) => value.isEmpty);
    if (queries.isEmpty) return null;
    final cacheKey = queries.join('|');
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final seen = <String>{};
      for (final query in queries) {
        for (final id in await _searchEntities(query)) {
          if (!seen.add(id) || !await _isCompany(id)) continue;
          final file = await _logoFile(id);
          if (file != null) {
            final url = await _rasterUrl(file, width);
            if (url != null) {
              _cache[cacheKey] = url;
              return url;
            }
          }

          // У части компаний (например, после ребрендинга) в Wikidata есть
          // официальный сайт, но ещё нет отдельного поля «логотип». В таком
          // случае берём иконку с сайта, а не привязываем тикеры вручную.
          final websiteUrl = await _officialWebsiteImage(id);
          if (websiteUrl != null) {
            _cache[cacheKey] = websiteUrl;
            return websiteUrl;
          }
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
      final response = await http.get(uri, headers: _headers).timeout(_timeout);
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
    if (claims == null) return false;
    final hasLogo = (claims['P154'] as List? ?? const []).isNotEmpty;
    final hasWebsite = (claims['P856'] as List? ?? const []).isNotEmpty;
    if (!hasLogo && !hasWebsite) return false;
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
        (claims['P452'] as List? ?? const []).isNotEmpty;
  }

  static Future<Map?> _claims(String entityId) async {
    if (_claimsCache.containsKey(entityId)) return _claimsCache[entityId];
    final uri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbgetclaims',
      'entity': entityId,
      'format': 'json',
    });
    final response = await http.get(uri, headers: _headers).timeout(_timeout);
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

  static Future<String?> _officialWebsiteImage(String entityId) async {
    final claims = await _claims(entityId);
    final websites = claims?['P856'] as List?;
    if (websites == null || websites.isEmpty) return null;

    for (final claim in websites) {
      final value = ((claim as Map)['mainsnak'] as Map?)?['datavalue'] as Map?;
      final raw = value?['value'];
      if (raw is! String || raw.isEmpty) continue;
      final website = Uri.tryParse(raw);
      if (website == null || !website.hasScheme) continue;
      try {
        final response = await http.get(
          website,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Android) InvestTracker/1.0',
            'Accept': 'text/html,application/xhtml+xml',
          },
        ).timeout(_timeout);
        if (response.statusCode < 200 || response.statusCode >= 400) continue;
        final html = utf8.decode(response.bodyBytes, allowMalformed: true);
        final candidates = <({int rank, String url})>[];
        for (final match in RegExp(
          r'<(?:link|meta)\b[^>]*>',
          caseSensitive: false,
        ).allMatches(html)) {
          final tag = match.group(0)!;
          final rel = _htmlAttribute(tag, 'rel')?.toLowerCase() ?? '';
          final property = _htmlAttribute(tag, 'property')?.toLowerCase() ?? '';
          final name = _htmlAttribute(tag, 'name')?.toLowerCase() ?? '';
          final source = _htmlAttribute(tag, 'href') ?? _htmlAttribute(tag, 'content');
          if (source == null || source.trim().isEmpty) continue;

          final rank = rel.contains('apple-touch-icon')
              ? 0
              : rel.split(RegExp(r'\s+')).contains('icon')
                  ? 1
                  : property == 'og:image' || name == 'og:image'
                      ? 2
                      : -1;
          if (rank < 0) continue;
          final resolved = website.resolve(source.trim());
          if (resolved.scheme == 'http' || resolved.scheme == 'https') {
            candidates.add((rank: rank, url: resolved.toString()));
          }
        }
        candidates.sort((a, b) => a.rank.compareTo(b.rank));
        if (candidates.isNotEmpty) return candidates.first.url;
      } catch (_) {
        // Один недоступный сайт не должен обрывать поиск по остальным именам.
      }
    }
    return null;
  }

  static String? _htmlAttribute(String tag, String name) {
    final match = RegExp(
      '${RegExp.escape(name)}\\s*=\\s*["\\x27]([^"\\x27]+)["\\x27]',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1)?.replaceAll('&amp;', '&');
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
    final response = await http.get(uri, headers: _headers).timeout(_timeout);
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
          RegExp(
            r'\b(МКПАО|ПАО|ОАО|АО|ЗАО|ООО|PJSC|JSC|OJSC|LLC)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(международная\s+компания|публичное\s+акционерное\s+общество)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+(ао|ап|а\.п\.|п|преф)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'[-–]\s*п\b', caseSensitive: false), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Wikidata often stores a recently renamed Russian company only under an
  /// English/Latin label. Transliteration is applied to every issuer name,
  /// so this is not a ticker-specific exception list.
  static String _latinSearchVariant(String raw) {
    const letters = <String, String>{
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
      'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
      'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
      'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
      'ы': 'y', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'ь': '', 'ъ': '',
    };
    final out = StringBuffer();
    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      final lower = char.toLowerCase();
      final latin = letters[lower];
      if (latin == null) {
        out.write(char);
      } else if (char == char.toUpperCase() && char != lower) {
        out.write(latin[0].toUpperCase());
        out.write(latin.substring(1));
      } else {
        out.write(latin);
      }
    }
    return out
        .toString()
        .replaceAll(RegExp(r'\bTekhnologii\b', caseSensitive: false), 'Technologies')
        .replaceAll(RegExp(r'\bGruppa\b', caseSensitive: false), 'Group')
        .trim();
  }
}
