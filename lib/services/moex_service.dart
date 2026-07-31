import 'dart:convert';

import 'package:http/http.dart' as http;

import 'currency_service.dart';
import 'moex_sync_service.dart';

/// Котировка одной бумаги, приведённая к рублям за штуку.
class MoexQuote {
  final String ticker;
  final String shortName;

  /// Цена в рублях за одну бумагу. Для облигаций уже пересчитана из процентов
  /// от номинала.
  final double price;

  /// Из какого поля ответа взята цена — нужно, чтобы в диагностике было видно,
  /// почему приехало именно это число.
  final String sourceField;

  final String board;
  final String market;
  final int lotSize;

  /// Международный код бумаги. Мосбиржа картинок не отдаёт, но по ISIN
  /// логотип можно найти в других источниках.
  final String isin;

  /// Номинал облигации. Для акций и фондов — null.
  final double? faceValue;

  /// Валюта номинала облигации: у части выпусков он в долларах или юанях,
  /// хотя торгуется бумага в рублях.
  final String faceUnit;

  /// Дата погашения облигации.
  final DateTime? matDate;

  /// Оборот за день в рублях — по нему удобно сортировать: сверху окажется то,
  /// что реально торгуется.
  final double turnover;

  /// Доходность к погашению, % — только у облигаций.
  final double? yieldPct;

  /// Ставка купона, % годовых. У флоатеров биржа её не знает заранее.
  final double? couponPercent;

  /// Период между купонами в днях.
  final int? couponPeriodDays;

  final DateTime fetchedAt;

  const MoexQuote({
    required this.ticker,
    required this.shortName,
    required this.price,
    required this.sourceField,
    required this.board,
    required this.market,
    required this.fetchedAt,
    this.lotSize = 1,
    this.isin = '',
    this.faceValue,
    this.faceUnit = 'SUR',
    this.matDate,
    this.turnover = 0,
    this.yieldPct,
    this.couponPercent,
    this.couponPeriodDays,
  });

  /// Выпуск в валюте: номинал не в рублях.
  bool get isForeignCurrency {
    final unit = faceUnit.toUpperCase();
    return unit.isNotEmpty && unit != 'SUR' && unit != 'RUB';
  }

  /// Флоатер — купон привязан к ставке и заранее неизвестен.
  bool get isFloater => isBond && (couponPercent == null || couponPercent == 0);

  /// Сколько купонов в году по данным биржи.
  int? get couponsPerYear {
    final period = couponPeriodDays;
    if (period == null || period <= 0) return null;
    return (365 / period).round().clamp(1, 12);
  }

  bool get isBond => faceValue != null;
}

/// Выплата по бумаге с биржи: дивиденд, купон или погашение номинала.
class MoexPayout {
  /// У дивидендов это дата закрытия реестра, у купонов — дата выплаты.
  final DateTime date;
  final double amount;
  final String currency;
  final String kind;
  final String? extra;

  const MoexPayout({
    required this.date,
    required this.amount,
    required this.currency,
    required this.kind,
    this.extra,
  });

  bool get isFuture => date.isAfter(DateTime.now());
}

/// Понятная человеку ошибка загрузки: показывается в настройках как есть.
class MoexException implements Exception {
  final String message;
  const MoexException(this.message);

  @override
  String toString() => message;
}

/// Клиент ISS API Московской биржи (https://iss.moex.com) — публичного и
/// бесплатного, без ключа и регистрации.
///
/// Важное про данные: бесплатный доступ отдаёт котировки с задержкой (обычно
/// 15 минут), а вне торговой сессии — цену последнего торгового дня. Поэтому
/// время котировки нужно показывать пользователю, а не выдавать её за текущую.
class MoexService {
  MoexService._();

  static const _host = 'iss.moex.com';
  static const _timeout = Duration(seconds: 15);

  /// Режимы торгов, которые покрывают всё, что бывает в портфеле частного
  /// инвестора. Порядок важен: первое совпадение по тикеру выигрывает.
  static const List<({String market, String board})> boards = [
    (market: 'shares', board: 'TQBR'), // акции
    (market: 'shares', board: 'TQTF'), // биржевые фонды
    (market: 'bonds', board: 'TQCB'), // корпоративные облигации
    (market: 'bonds', board: 'TQOB'), // ОФЗ
  ];

  /// Колонки запрашиваем явно — ответ по всему режиму иначе весит сотни
  /// килобайт, а на мобильном интернете это заметно.
  static const _securitiesColumns =
      'SECID,SHORTNAME,ISIN,PREVPRICE,PREVLEGALCLOSEPRICE,FACEVALUE,FACEUNIT,MATDATE,LOTSIZE,'
      'COUPONPERCENT,COUPONVALUE,COUPONPERIOD';
  static const _marketdataColumns =
      'SECID,LAST,LCURRENTPRICE,MARKETPRICE,UPDATETIME,VALTODAY,YIELD';

  /// Загружает котировки по всем режимам и возвращает их по тикерам.
  ///
  /// Если [tickers] задан, лишнее отбрасывается — но запрос всё равно идёт
  /// целиком по режиму: четыре запроса на любой размер портфеля дешевле, чем
  /// по запросу на бумагу.
  static Future<Map<String, MoexQuote>> fetchQuotes({Set<String>? tickers}) async {
    final result = <String, MoexQuote>{};
    final errors = <String>[];

    for (final b in boards) {
      try {
        final quotes = await fetchBoard(market: b.market, board: b.board);
        for (final q in quotes) {
          if (tickers != null && !tickers.contains(q.ticker)) continue;
          // Первый режим, где бумага нашлась, и остаётся источником.
          result.putIfAbsent(q.ticker, () => q);
        }
      } catch (e) {
        errors.add('${b.board}: $e');
      }
    }

    // Полный провал — это ошибка. Если хотя бы один режим ответил, работаем с
    // тем, что есть: у пользователя может не быть облигаций вовсе.
    if (result.isEmpty && errors.isNotEmpty) {
      throw MoexException(errors.join('\n'));
    }
    return result;
  }

  /// Загружает один режим торгов целиком.
  static Future<List<MoexQuote>> fetchBoard({required String market, required String board}) async {
    final uri = Uri.https(_host, '/iss/engines/stock/markets/$market/boards/$board/securities.json', {
      'iss.meta': 'off',
      'iss.only': 'securities,marketdata',
      'securities.columns': _securitiesColumns,
      'marketdata.columns': _marketdataColumns,
    });

    final http.Response response;
    try {
      response = await http.get(uri).timeout(_timeout);
    } catch (e) {
      throw MoexException('нет связи с биржей ($e)');
    }

    if (response.statusCode != 200) {
      throw MoexException('биржа ответила кодом ${response.statusCode}');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw MoexException('не удалось разобрать ответ биржи');
    }

    final securities = _table(json, 'securities');
    final marketdata = <String, Map<String, dynamic>>{
      for (final row in _table(json, 'marketdata'))
        if (row['SECID'] is String) row['SECID'] as String: row,
    };

    final now = DateTime.now();
    final isBondMarket = market == 'bonds';
    final quotes = <MoexQuote>[];

    for (final sec in securities) {
      final ticker = sec['SECID'];
      if (ticker is! String || ticker.isEmpty) continue;

      final md = marketdata[ticker] ?? const <String, dynamic>{};
      final faceValue = isBondMarket ? _toDouble(sec['FACEVALUE']) : null;

      // Приоритет: цена последней сделки, затем текущая расчётная, затем
      // рыночная, и лишь потом закрытие прошлого дня. Ночью и в выходные
      // живых сделок нет, поэтому запасные варианты обязательны.
      final candidates = <(String, double?)>[
        ('LAST', _toDouble(md['LAST'])),
        ('LCURRENTPRICE', _toDouble(md['LCURRENTPRICE'])),
        ('MARKETPRICE', _toDouble(md['MARKETPRICE'])),
        ('PREVPRICE', _toDouble(sec['PREVPRICE'])),
        ('PREVLEGALCLOSEPRICE', _toDouble(sec['PREVLEGALCLOSEPRICE'])),
      ];

      String? field;
      double? raw;
      for (final c in candidates) {
        if (c.$2 != null && c.$2! > 0) {
          field = c.$1;
          raw = c.$2;
          break;
        }
      }
      if (raw == null || field == null) continue;

      // Облигации на бирже котируются в процентах от номинала: 110,5 значит
      // 110,5% от 1000 ₽, то есть 1105 ₽. В приложении цены хранятся в рублях,
      // поэтому пересчитываем сразу здесь.
      final price = (isBondMarket && faceValue != null && faceValue > 0) ? raw * faceValue / 100 : raw;

      quotes.add(MoexQuote(
        ticker: ticker,
        shortName: (sec['SHORTNAME'] as String?) ?? ticker,
        price: price,
        sourceField: field,
        board: board,
        market: market,
        lotSize: (_toDouble(sec['LOTSIZE'])?.round().clamp(1, 1000000) ?? 1).toInt(),
        isin: (sec['ISIN'] as String?) ?? '',
        faceValue: faceValue,
        faceUnit: '${sec['FACEUNIT'] ?? 'SUR'}',
        matDate: DateTime.tryParse('${sec['MATDATE']}'),
        turnover: _toDouble(md['VALTODAY']) ?? 0,
        yieldPct: _toDouble(md['YIELD']),
        couponPercent: _toDouble(sec['COUPONPERCENT']),
        couponPeriodDays: _toDouble(sec['COUPONPERIOD'])?.round(),
        fetchedAt: now,
      ));
    }

    return quotes;
  }


  /// Тикеры валютных пар на бирже: расчёты «завтра» (TOM) — это основной
  /// торгуемый инструмент, по нему и считают курс.
  /// Найденные идентификаторы валютных пар: обозначения на бирже менялись
  /// не раз, поэтому мы их не угадываем, а вычисляем из ответа биржи и
  /// запоминаем — тем же идентификатором потом грузится история.
  static final Map<String, String> resolvedCurrencySecIds = {};

  /// Валюты, которых на валютном рынке не нашлось: например, торги парой
  /// могли быть остановлены. Для них честнее показать курс из настроек и
  /// сказать об этом, чем молча подставить старое значение.
  static final Set<String> unavailableCurrencies = {};

  /// Текущие курсы валют с валютного рынка Мосбиржи.
  ///
  /// Инструмент для каждой валюты ищем прямо в ответе: подходит строка, где
  /// торгуемая валюта (FACEUNIT) совпадает с нужной, а расчёты идут в рублях.
  /// Из подходящих берём режим «завтра» (TOM) — основной торгуемый.
  static Future<Map<String, double>> fetchCurrencyRates() async {
    final uri = Uri.https(_host, '/iss/engines/currency/markets/selt/boards/CETS/securities.json', {
      'iss.meta': 'off',
      'iss.only': 'securities,marketdata',
      'securities.columns': 'SECID,SHORTNAME,FACEUNIT,CURRENCYID,PREVPRICE',
      'marketdata.columns': 'SECID,LAST,MARKETPRICE',
    });

    final json = await _getJson(uri);
    final marketdata = <String, Map<String, dynamic>>{
      for (final row in _table(json, 'marketdata'))
        if (row['SECID'] is String) row['SECID'] as String: row,
    };

    final result = <String, double>{};
    for (final currency in CurrencyService.trackedCurrencies) {
      String? bestId;
      double? bestRate;
      bool bestIsTom = false;

      for (final sec in _table(json, 'securities')) {
        final secId = sec['SECID'];
        if (secId is! String) continue;
        final upper = secId.toUpperCase();

        // Своп-инструменты (TODTOM, TOMSPT) котируют не курс, а разницу между
        // расчётами в разные дни — это копейки. Отсекаем сразу: именно на них
        // отбор ловился и подставлял курс вида 0,08 ₽.
        if (upper.contains('TODTOM') || upper.contains('TOMSPT') || upper.contains('SPT')) continue;

        final faceUnit = '${sec['FACEUNIT'] ?? ''}'.toUpperCase();
        final quoted = '${sec['CURRENCYID'] ?? ''}'.toUpperCase();
        final matchesByFields = faceUnit == currency && (quoted == 'SUR' || quoted == 'RUB' || quoted.isEmpty);
        final matchesById = !matchesByFields &&
            upper.startsWith(currency) &&
            !upper.substring(currency.length).contains(RegExp(r'USD|EUR|CNY'));
        if (!matchesByFields && !matchesById) continue;

        final md = marketdata[secId] ?? const <String, dynamic>{};
        final rate = _toDouble(md['LAST']) ?? _toDouble(md['MARKETPRICE']) ?? _toDouble(sec['PREVPRICE']);
        // Курс любой из этих валют к рублю заведомо больше рубля. Всё, что
        // меньше, — точно не курс, каким бы правдоподобным ни выглядел
        // идентификатор.
        if (rate == null || rate < CurrencyService.minPlausibleRate) continue;

        final isTom = upper.endsWith('TOM') || upper.endsWith('_TOM');
        if (bestRate == null || (isTom && !bestIsTom)) {
          bestId = secId;
          bestRate = rate;
          bestIsTom = isTom;
        }
      }

      if (bestId != null && bestRate != null) {
        resolvedCurrencySecIds[currency] = bestId;
        unavailableCurrencies.remove(currency);
        result[currency] = bestRate;
      } else {
        unavailableCurrencies.add(currency);
      }
    }
    return result;
  }

  /// История закрытий: используется для графиков на вкладке «Биржа».
  /// [path] — раздел ISS, [secId] — инструмент.
  static Future<List<MapEntry<DateTime, double>>> _fetchHistory({
    required String path,
    required DateTime from,
  }) async {
    final points = <MapEntry<DateTime, double>>[];
    // ISS отдаёт историю страницами по 100 строк.
    for (int start = 0; start < 1000; start += 100) {
      final uri = Uri.https(_host, path, {
        'iss.meta': 'off',
        'iss.only': 'history',
        'history.columns': 'TRADEDATE,CLOSE',
        'from': '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        'start': '$start',
      });
      final rows = _table(await _getJson(uri), 'history');
      if (rows.isEmpty) break;
      for (final r in rows) {
        final date = DateTime.tryParse('${r['TRADEDATE']}');
        final close = _toDouble(r['CLOSE']);
        if (date != null && close != null && close > 0) {
          points.add(MapEntry(date, close));
        }
      }
      if (rows.length < 100) break;
    }
    points.sort((a, b) => a.key.compareTo(b.key));
    return points;
  }





  /// Кэш «ISIN → тикер на бирже». Один и тот же ISIN встречается в отчёте
  /// десятки раз, а спрашивать биржу нужно один раз.
  static final Map<String, String?> _tickerByIsin = {};

  /// Ищет бумагу на бирже по ISIN. Нужен для импорта брокерских отчётов: там
  /// тикеров нет, только название и ISIN. В отличие от списка котировок,
  /// поиск находит и то, что уже не торгуется, — а именно такие бумаги и
  /// оставались неопознанными.
  static Future<String?> tickerByIsin(String isin) async {
    final key = isin.trim().toUpperCase();
    if (key.isEmpty) return null;
    if (_tickerByIsin.containsKey(key)) return _tickerByIsin[key];

    try {
      final uri = Uri.https(_host, '/iss/securities.json', {
        'q': key,
        'iss.meta': 'off',
        'iss.only': 'securities',
        'securities.columns': 'secid,isin,primary_boardid,is_traded',
        'limit': '20',
      });
      final rows = _table(await _getJson(uri), 'securities');

      String? exact;
      for (final r in rows) {
        if ('${r['isin']}'.trim().toUpperCase() != key) continue;
        final secid = '${r['secid']}'.trim();
        if (secid.isEmpty) continue;
        // Торгуемая бумага предпочтительнее: у одного эмитента бывают старые
        // выпуски с тем же ISIN в архиве.
        if ('${r['is_traded']}' == '1') {
          exact = secid;
          break;
        }
        exact ??= secid;
      }

      _tickerByIsin[key] = exact;
      return exact;
    } catch (_) {
      // Нет сети — просто не смогли опознать, импорт продолжится без этой бумаги.
      return null;
    }
  }


  /// ISIN бумаги по её тикеру — нужен для поиска логотипа по эмитенту.
  /// Полное название бумаги — им ищется логотип эмитента в Викиданных.
  static Future<String?> nameOf(String secid) async {
    final key = secid.trim().toUpperCase();
    if (key.isEmpty) return null;
    if (_nameCache.containsKey(key)) return _nameCache[key];
    try {
      final uri = Uri.https(_host, '/iss/securities/$key.json', {
        'iss.meta': 'off',
        'iss.only': 'description',
        'description.columns': 'name,value',
      });
      String? name;
      for (final r in _table(await _getJson(uri), 'description')) {
        final field = '${r['name']}'.toUpperCase();
        if (field == 'NAME' || field == 'SHORTNAME') {
          name ??= '${r['value']}'.trim();
        }
      }
      _nameCache[key] = name;
      return name;
    } catch (_) {
      return null;
    }
  }

  static final Map<String, String?> _nameCache = {};

  static Future<String?> isinOf(String secid) async {
    final key = secid.trim().toUpperCase();
    if (key.isEmpty) return null;

    // Сначала смотрим то, что уже загружено с котировками.
    for (final q in MoexSyncService.marketSnapshot.value.values) {
      if (q.ticker.toUpperCase() == key && q.isin.isNotEmpty) return q.isin;
    }

    try {
      final uri = Uri.https(_host, '/iss/securities.json', {
        'q': key,
        'iss.meta': 'off',
        'iss.only': 'securities',
        'securities.columns': 'secid,isin',
        'limit': '10',
      });
      for (final r in _table(await _getJson(uri), 'securities')) {
        if ('${r['secid']}'.trim().toUpperCase() == key) {
          final isin = '${r['isin']}'.trim();
          if (isin.isNotEmpty) return isin;
        }
      }
    } catch (_) {
      // Без ISIN просто попробуем логотип по тикеру.
    }
    return null;
  }

  /// Кэш «бумага → бумага эмитента, у которой стоит искать логотип».
  static final Map<String, String?> _issuerProxy = {};

  /// Находит у того же эмитента акцию — её логотип и берём для облигации.
  ///
  /// У облигаций собственных логотипов почти нигде нет, а у эмитента есть.
  /// Поэтому для «Сбербанк оббП775» логотип ищется по SBER: картинка та же,
  /// что показывает и приложение брокера.
  static Future<String?> issuerShareFor(String secid) async {
    final key = secid.trim().toUpperCase();
    if (key.isEmpty) return null;
    if (_issuerProxy.containsKey(key)) return _issuerProxy[key];

    try {
      // Описание бумаги: оттуда берём идентификатор и название эмитента.
      final descUri = Uri.https(_host, '/iss/securities/$key.json', {
        'iss.meta': 'off',
        'iss.only': 'description',
        'description.columns': 'name,value',
      });
      final rows = _table(await _getJson(descUri), 'description');

      String? emitentId;
      String? emitentTitle;
      for (final r in rows) {
        final name = '${r['name']}'.toUpperCase();
        final value = '${r['value']}';
        if (name == 'EMITENT_ID') emitentId = value;
        if (name == 'EMITENT_TITLE') emitentTitle = value;
      }
      if (emitentTitle == null || emitentTitle.isEmpty) {
        _issuerProxy[key] = null;
        return null;
      }

      // Ищем бумаги того же эмитента и берём акцию.
      final searchUri = Uri.https(_host, '/iss/securities.json', {
        'q': emitentTitle,
        'iss.meta': 'off',
        'iss.only': 'securities',
        'securities.columns': 'secid,isin,type,emitent_id,is_traded',
        'limit': '50',
      });
      final found = _table(await _getJson(searchUri), 'securities');

      String? best;
      for (final r in found) {
        final type = '${r['type']}';
        if (!type.contains('share')) continue;
        if (emitentId != null && '${r['emitent_id']}' != emitentId) continue;
        final candidate = '${r['secid']}'.trim();
        if (candidate.isEmpty) continue;
        // Обыкновенная акция предпочтительнее привилегированной: логотип у них
        // один, но обыкновенная чаще есть в справочниках.
        if (type == 'common_share') {
          best = candidate;
          break;
        }
        best ??= candidate;
      }

      _issuerProxy[key] = best;
      return best;
    } catch (_) {
      return null;
    }
  }


  /// Выплата по бумаге: дивиденд у акции или купон у облигации.
  static Future<List<MoexPayout>> fetchPayouts(String ticker, {bool isBond = false}) async {
    final upper = ticker.toUpperCase();
    if (isBond) {
      // График купонов отдаётся страницами по 20 строк, а у длинных выпусков
      // их несколько десятков — забираем всё, иначе история обрывается.
      final result = <MoexPayout>[];
      for (int start = 0; start < 400; start += 20) {
        final uri = Uri.https(_host, '/iss/securities/$upper/bondization.json', {
          'iss.meta': 'off',
          'iss.only': 'coupons,amortizations',
          'coupons.columns': 'coupondate,value,valueprc,faceunit',
          'amortizations.columns': 'amortdate,value,faceunit',
          'start': '$start',
        });
        final json = await _getJson(uri);
        final coupons = _table(json, 'coupons');
        final amortizations = _table(json, 'amortizations');
        if (coupons.isEmpty && amortizations.isEmpty) break;

        for (final r in coupons) {
          final date = DateTime.tryParse('${r['coupondate']}');
          if (date == null) continue;
          final prc = _toDouble(r['valueprc']);
          result.add(MoexPayout(
            date: date,
            amount: _toDouble(r['value']) ?? 0,
            currency: '${r['faceunit'] ?? 'RUB'}',
            kind: 'Купон',
            extra: prc != null ? '${prc.toStringAsFixed(2)}% годовых' : null,
          ));
        }
        for (final r in amortizations) {
          final date = DateTime.tryParse('${r['amortdate']}');
          if (date == null) continue;
          result.add(MoexPayout(
            date: date,
            amount: _toDouble(r['value']) ?? 0,
            currency: '${r['faceunit'] ?? 'RUB'}',
            kind: 'Погашение номинала',
          ));
        }
        if (coupons.length < 20 && amortizations.length < 20) break;
      }
      result.sort((a, b) => b.date.compareTo(a.date));
      return result;
    }

    final uri = Uri.https(_host, '/iss/securities/$upper/dividends.json', {
      'iss.meta': 'off',
      'iss.only': 'dividends',
      'dividends.columns': 'registryclosedate,value,currencyid',
    });
    final result = <MoexPayout>[
      for (final r in _table(await _getJson(uri), 'dividends'))
        if (DateTime.tryParse('${r['registryclosedate']}') != null)
          MoexPayout(
            date: DateTime.parse('${r['registryclosedate']}'),
            amount: _toDouble(r['value']) ?? 0,
            currency: '${r['currencyid'] ?? 'RUB'}',
            kind: 'Дивиденд',
          ),
    ];
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Отраслевые индексы Мосбиржи: состав каждого — это готовый список бумаг
  /// сектора. Другого источника отраслей у ISS нет, зато этот официальный.
  static const Map<String, String> sectorIndices = {
    'MOEXOG': 'Нефть и газ',
    'MOEXEU': 'Электроэнергетика',
    'MOEXTL': 'Телекоммуникации',
    'MOEXMM': 'Металлы и добыча',
    'MOEXFN': 'Финансы',
    'MOEXCN': 'Потребительский сектор',
    'MOEXTN': 'Транспорт',
    'MOEXIT': 'Информационные технологии',
    'MOEXRE': 'Строительство',
    'MOEXCH': 'Химия и нефтехимия',
  };

  /// Тикер -> отрасль, собранное по составам отраслевых индексов.
  static Future<Map<String, String>> fetchSectorMap() async {
    final result = <String, String>{};
    for (final entry in sectorIndices.entries) {
      try {
        final uri = Uri.https(_host, '/iss/statistics/engines/stock/markets/index/analytics/${entry.key}.json', {
          'iss.meta': 'off',
          'iss.only': 'analytics',
          'analytics.columns': 'ticker,secids,SECID',
          'limit': '100',
        });
        for (final row in _table(await _getJson(uri), 'analytics')) {
          final ticker = row['ticker'] ?? row['secids'] ?? row['SECID'];
          if (ticker is String && ticker.isNotEmpty) {
            result.putIfAbsent(ticker.toUpperCase(), () => entry.value);
          }
        }
      } catch (_) {
        // Один недоступный индекс не должен ломать остальные.
      }
    }
    return result;
  }

  /// Свечи — универсальный источник для всех графиков: и по бумагам, и по
  /// валютам, и по индексу. В отличие от истории торгов, тут можно взять
  /// внутридневные интервалы и не нужно знать режим торгов.
  ///
  /// [interval]: 1 — минута, 10 — десять минут, 60 — час, 24 — день,
  /// 7 — неделя, 31 — месяц.
  static Future<List<MapEntry<DateTime, double>>> fetchCandles({
    required String engine,
    required String market,
    required String secId,
    required DateTime from,
    required int interval,
    /// Правая граница окна — нужна для листания графика в прошлое.
    DateTime? till,
    int maxRows = 2000,
  }) async {
    final points = <MapEntry<DateTime, double>>[];
    for (int start = 0; start < maxRows; start += 500) {
      final uri = Uri.https(_host, '/iss/engines/$engine/markets/$market/securities/$secId/candles.json', {
        'iss.meta': 'off',
        'iss.only': 'candles',
        'candles.columns': 'begin,close',
        'from': _isoDate(from),
        if (till != null) 'till': _isoDate(till),
        'interval': '$interval',
        'start': '$start',
      });
      final rows = _table(await _getJson(uri), 'candles');
      if (rows.isEmpty) break;
      for (final r in rows) {
        final date = DateTime.tryParse('${r['begin']}');
        final close = _toDouble(r['close']);
        if (date != null && close != null && close > 0) points.add(MapEntry(date, close));
      }
      if (rows.length < 500) break;
    }
    points.sort((a, b) => a.key.compareTo(b.key));
    return points;
  }

  /// Свечи по бумаге: режим торгов не нужен, но рынок (акции или облигации)
  /// приходится подобрать — пробуем оба.
  static Future<List<MapEntry<DateTime, double>>> fetchSecurityCandles(
    String ticker, {
    required DateTime from,
    required int interval,
    DateTime? till,
    String? market,
    int maxRows = 2000,
  }) async {
    final markets = <String>[if (market != null) market, 'shares', 'bonds'];
    for (final m in markets.toSet()) {
      try {
        final points = await fetchCandles(
          engine: 'stock',
          market: m,
          secId: ticker.toUpperCase(),
          from: from,
          till: till,
          interval: interval,
          maxRows: maxRows,
        );
        if (points.isNotEmpty) return points;
      } catch (_) {
        // Пробуем следующий рынок.
      }
    }
    return const [];
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// История цен бумаги с биржи. Режим торгов берём из последнего снимка
  /// рынка, а если бумаги там нет — перебираем основные.
  static Future<List<MapEntry<DateTime, double>>> fetchSecurityHistory(
    String ticker, {
    required DateTime from,
    String? market,
    String? board,
  }) async {
    final variants = <({String market, String board})>[
      if (market != null && board != null) (market: market, board: board),
      ...boards.where((b) => b.market != market || b.board != board),
    ];

    for (final v in variants) {
      try {
        final points = await _fetchHistory(
          path: '/iss/history/engines/stock/markets/${v.market}/boards/${v.board}'
              '/securities/${ticker.toUpperCase()}.json',
          from: from,
        );
        if (points.isNotEmpty) return points;
      } catch (_) {
        // Пробуем следующий режим торгов.
      }
    }
    return const [];
  }

  /// История индекса МосБиржи (IMOEX).
  static Future<List<MapEntry<DateTime, double>>> fetchIndexHistory({required DateTime from}) =>
      _fetchHistory(
        path: '/iss/history/engines/stock/markets/index/boards/SNDX/securities/IMOEX.json',
        from: from,
      );

  /// История курса валюты.
  static Future<List<MapEntry<DateTime, double>>> fetchCurrencyHistory(
    String currency, {
    required DateTime from,
  }) async {
    // Идентификатор берём тот же, что дал текущий курс. Если его ещё нет —
    // сперва спрашиваем курсы, заодно определится и инструмент.
    if (!resolvedCurrencySecIds.containsKey(currency)) {
      try {
        await fetchCurrencyRates();
      } catch (_) {
        // Ниже вернём пустую историю — экран покажет это сам.
      }
    }
    final secId = resolvedCurrencySecIds[currency];
    if (secId == null) return const [];

    return _fetchHistory(
      path: '/iss/history/engines/currency/markets/selt/boards/CETS/securities/$secId.json',
      from: from,
    );
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await http.get(uri).timeout(_timeout);
    } catch (e) {
      throw MoexException('нет связи с биржей ($e)');
    }
    if (response.statusCode != 200) {
      throw MoexException('биржа ответила кодом ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw MoexException('не удалось разобрать ответ биржи');
    }
  }

  /// Разбирает блок ISS вида {"columns": [...], "data": [[...], ...]} в список
  /// словарей. Колонки читаем по именам, а не по позициям: биржа может
  /// добавить поле, и жёсткие индексы тогда разъедутся.
  static List<Map<String, dynamic>> _table(Map<String, dynamic> json, String key) {
    final block = json[key];
    if (block is! Map) return const [];
    final columns = block['columns'];
    final data = block['data'];
    if (columns is! List || data is! List) return const [];

    final names = columns.map((c) => '$c').toList();
    final rows = <Map<String, dynamic>>[];
    for (final row in data) {
      if (row is! List) continue;
      final map = <String, dynamic>{};
      for (int i = 0; i < names.length && i < row.length; i++) {
        map[names[i]] = row[i];
      }
      rows.add(map);
    }
    return rows;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }
}
