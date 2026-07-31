import '../models/purchase.dart';
import 'security_info.dart';
import 'securities_generated.dart';

/// Встроенный справочник популярных бумаг Мосбиржи.
/// Используется для автокомплита при вводе покупок и планов.
/// Реальных логотипов нет (это чужие товарные знаки) — вместо них
/// генерируются цветные аватарки с инициалами тикера, см. TickerAvatar.
class SecuritiesDatabase {
  static const List<SecurityInfo> _curated = [
    // --- Акции: нефть и газ ---
    SecurityInfo(ticker: 'GAZP', name: 'Газпром', type: AssetType.stock, sector: 'Нефть и газ'),
    SecurityInfo(ticker: 'LKOH', name: 'Лукойл', type: AssetType.stock, sector: 'Нефть и газ'),
    SecurityInfo(ticker: 'ROSN', name: 'Роснефть', type: AssetType.stock, sector: 'Нефть и газ'),
    SecurityInfo(ticker: 'NVTK', name: 'Новатэк', type: AssetType.stock, sector: 'Нефть и газ'),
    SecurityInfo(ticker: 'TATN', name: 'Татнефть', type: AssetType.stock, sector: 'Нефть и газ'),
    SecurityInfo(ticker: 'SNGS', name: 'Сургутнефтегаз', type: AssetType.stock, sector: 'Нефть и газ'),
    SecurityInfo(ticker: 'TRNFP', name: 'Транснефть', type: AssetType.stock, sector: 'Нефть и газ'),

    // --- Финансы ---
    SecurityInfo(ticker: 'SBER', name: 'Сбербанк', type: AssetType.stock, sector: 'Финансы'),
    SecurityInfo(ticker: 'SBERP', name: 'Сбербанк (прив.)', type: AssetType.stock, sector: 'Финансы'),
    SecurityInfo(ticker: 'VTBR', name: 'ВТБ', type: AssetType.stock, sector: 'Финансы'),
    SecurityInfo(ticker: 'T', name: 'Т-Технологии', type: AssetType.stock, sector: 'Финансы'),
    SecurityInfo(ticker: 'CBOM', name: 'МКБ', type: AssetType.stock, sector: 'Финансы'),
    SecurityInfo(ticker: 'SVCB', name: 'Совкомбанк', type: AssetType.stock, sector: 'Финансы'),
    SecurityInfo(ticker: 'BSPB', name: 'Банк Санкт-Петербург', type: AssetType.stock, sector: 'Финансы'),

    // --- Металлургия и добыча ---
    SecurityInfo(ticker: 'GMKN', name: 'Норникель', type: AssetType.stock, sector: 'Металлургия'),
    SecurityInfo(ticker: 'NLMK', name: 'НЛМК', type: AssetType.stock, sector: 'Металлургия'),
    SecurityInfo(ticker: 'MAGN', name: 'ММК', type: AssetType.stock, sector: 'Металлургия'),
    SecurityInfo(ticker: 'CHMF', name: 'Северсталь', type: AssetType.stock, sector: 'Металлургия'),
    SecurityInfo(ticker: 'ALRS', name: 'Алроса', type: AssetType.stock, sector: 'Металлургия'),
    SecurityInfo(ticker: 'PLZL', name: 'Полюс', type: AssetType.stock, sector: 'Металлургия'),
    SecurityInfo(ticker: 'RUAL', name: 'Русал', type: AssetType.stock, sector: 'Металлургия'),

    // --- Телеком и IT ---
    SecurityInfo(ticker: 'MTSS', name: 'МТС', type: AssetType.stock, sector: 'Телеком'),
    SecurityInfo(ticker: 'RTKM', name: 'Ростелеком', type: AssetType.stock, sector: 'Телеком'),
    SecurityInfo(ticker: 'YDEX', name: 'Яндекс', type: AssetType.stock, sector: 'IT'),
    SecurityInfo(ticker: 'VKCO', name: 'VK', type: AssetType.stock, sector: 'IT'),
    SecurityInfo(ticker: 'POSI', name: 'Positive Technologies', type: AssetType.stock, sector: 'IT'),
    SecurityInfo(ticker: 'ASTR', name: 'Астра', type: AssetType.stock, sector: 'IT'),

    // --- Ритейл и потребительский сектор ---
    SecurityInfo(ticker: 'MGNT', name: 'Магнит', type: AssetType.stock, sector: 'Ритейл'),
    SecurityInfo(ticker: 'FIVE', name: 'X5 Group', type: AssetType.stock, sector: 'Ритейл'),
    SecurityInfo(ticker: 'OZON', name: 'Ozon', type: AssetType.stock, sector: 'Ритейл'),
    SecurityInfo(ticker: 'LENT', name: 'Лента', type: AssetType.stock, sector: 'Ритейл'),

    // --- Энергетика ---
    SecurityInfo(ticker: 'IRAO', name: 'Интер РАО', type: AssetType.stock, sector: 'Энергетика'),
    SecurityInfo(ticker: 'HYDR', name: 'РусГидро', type: AssetType.stock, sector: 'Энергетика'),
    SecurityInfo(ticker: 'FEES', name: 'Россети', type: AssetType.stock, sector: 'Энергетика'),

    // --- Транспорт ---
    SecurityInfo(ticker: 'AFLT', name: 'Аэрофлот', type: AssetType.stock, sector: 'Транспорт'),
    SecurityInfo(ticker: 'FLOT', name: 'Совкомфлот', type: AssetType.stock, sector: 'Транспорт'),
    SecurityInfo(ticker: 'NMTP', name: 'НМТП', type: AssetType.stock, sector: 'Транспорт'),

    // --- ОФЗ (гособлигации) ---
    SecurityInfo(ticker: 'SU26238RMFS4', name: 'ОФЗ 26238', type: AssetType.bond, sector: 'Гособлигации'),
    SecurityInfo(ticker: 'SU26243RMFS4', name: 'ОФЗ 26243', type: AssetType.bond, sector: 'Гособлигации'),
    SecurityInfo(ticker: 'SU26240RMFS9', name: 'ОФЗ 26240', type: AssetType.bond, sector: 'Гособлигации'),
    SecurityInfo(ticker: 'SU26230RMFS0', name: 'ОФЗ 26230', type: AssetType.bond, sector: 'Гособлигации'),
    SecurityInfo(ticker: 'SU26234RMFS9', name: 'ОФЗ 26234', type: AssetType.bond, sector: 'Гособлигации'),

    // --- Корпоративные облигации ---
    SecurityInfo(ticker: 'RU000A1023T8', name: 'Роснефть облигации', type: AssetType.bond, sector: 'Корп. облигации'),
    SecurityInfo(ticker: 'RU000A105EX7', name: 'Сбербанк облигации', type: AssetType.bond, sector: 'Корп. облигации'),
    SecurityInfo(ticker: 'RU000A106R95', name: 'Газпром капитал', type: AssetType.bond, sector: 'Корп. облигации'),

    // --- Фонды (ETF/БПИФ) ---
    SecurityInfo(ticker: 'SBMX', name: 'Sber — Индекс МосБиржи', type: AssetType.etf, sector: 'Фонды акций'),
    SecurityInfo(ticker: 'TMOS', name: 'Т-Капитал — Индекс МосБиржи', type: AssetType.etf, sector: 'Фонды акций'),
    SecurityInfo(ticker: 'SBGB', name: 'Sber — Гособлигации', type: AssetType.etf, sector: 'Фонды облигаций'),
    SecurityInfo(ticker: 'SBMM', name: 'Sber — Денежный рынок', type: AssetType.etf, sector: 'Денежный рынок'),
    SecurityInfo(ticker: 'LQDT', name: 'ВИМ — Ликвидность', type: AssetType.etf, sector: 'Денежный рынок'),
    SecurityInfo(ticker: 'AKMM', name: 'Альфа — Денежный рынок', type: AssetType.etf, sector: 'Денежный рынок'),

    // --- Валюта ---
    SecurityInfo(ticker: 'USDRUB', name: 'Доллар США', type: AssetType.currency, sector: 'Валюта'),
    SecurityInfo(ticker: 'EURRUB', name: 'Евро', type: AssetType.currency, sector: 'Валюта'),
    SecurityInfo(ticker: 'CNYRUB', name: 'Юань', type: AssetType.currency, sector: 'Валюта'),
  ];

  /// Полный список = отобранные вручную бумаги (с секторами) + полный список
  /// Мосбиржи (акции, БПИФ и облигации) из выгрузки пользователя.
  /// При совпадении тикера приоритет у вручную отобранной записи (у неё есть сектор).
  static late final List<SecurityInfo> all = _mergeAll();

  static List<SecurityInfo> _mergeAll() {
    final result = <SecurityInfo>[..._curated];
    final knownTickers = result.map((s) => s.ticker.toUpperCase()).toSet();
    for (final s in generatedSecurities) {
      if (knownTickers.contains(s.ticker.toUpperCase())) continue;
      knownTickers.add(s.ticker.toUpperCase());
      result.add(s);
    }
    return result;
  }

  static List<SecurityInfo> search(String query) {
    if (query.isEmpty) return all.take(30).toList();
    final q = query.toLowerCase();
    final matches = all
        .where((s) => s.ticker.toLowerCase().contains(q) || s.name.toLowerCase().contains(q))
        .toList();
    // сначала точные/близкие совпадения по тикеру, потом остальные
    matches.sort((a, b) {
      final aExact = a.ticker.toLowerCase().startsWith(q) ? 0 : 1;
      final bExact = b.ticker.toLowerCase().startsWith(q) ? 0 : 1;
      return aExact.compareTo(bExact);
    });
    return matches.take(50).toList();
  }

  static SecurityInfo? byTicker(String ticker) {
    try {
      return all.firstWhere((s) => s.ticker.toUpperCase() == ticker.toUpperCase());
    } catch (_) {
      return null;
    }
  }
}
