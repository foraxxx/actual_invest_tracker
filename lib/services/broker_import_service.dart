import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../data/securities.dart';
import '../models/deposit.dart';
import '../models/income.dart';
import '../models/purchase.dart';
import 'analytics_service.dart';
import 'moex_service.dart';
import 'moex_sync_service.dart';
import 'xlsx_reader.dart';
import 'storage_service.dart';

/// Поддерживаемые брокеры. У каждого свой формат выгрузки, поэтому файл
/// разбирается своим парсером — общий «универсальный» разбор тут невозможен.
enum Broker { vtb }

extension BrokerX on Broker {
  String get title => switch (this) {
        Broker.vtb => 'ВТБ Инвестиции',
      };

  String get hint => switch (this) {
        Broker.vtb => 'Отчёт брокера в XLSX: в приложении ВТБ Мои Инвестиции — '
            'Профиль → Отчёты → Брокерский отчёт за период.',
      };

  List<String> get extensions => switch (this) {
        Broker.vtb => ['xlsx'],
      };
}

/// Одна разобранная сделка. Тикер может не определиться — тогда строка ждёт
/// ручного сопоставления.
class ImportedTrade {
  final DateTime date;
  final String rawName;
  final String isin;
  final double quantity;
  final double pricePerUnit;
  final double fee;
  final String currency;
  final bool isSell;

  /// Определённый тикер. null — не удалось сопоставить.
  String? ticker;

  ImportedTrade({
    required this.date,
    required this.rawName,
    required this.isin,
    required this.quantity,
    required this.pricePerUnit,
    required this.fee,
    required this.currency,
    required this.isSell,
    this.ticker,
  });
}

/// Полученная выплата.
class ImportedPayout {
  final DateTime date;
  final String rawName;
  final String isin;
  final double amount;
  final String currency;
  final bool isCoupon;
  String? ticker;

  ImportedPayout({
    required this.date,
    required this.rawName,
    required this.isin,
    required this.amount,
    required this.currency,
    required this.isCoupon,
    this.ticker,
  });
}

/// Пополнение или вывод денег со счёта.
class ImportedCashMove {
  final DateTime date;
  final double amount; // + пополнение, − вывод
  final String currency;
  final String note;

  const ImportedCashMove({
    required this.date,
    required this.amount,
    required this.currency,
    required this.note,
  });
}

/// Фактический остаток бумаги по отчёту — по нему сверяется портфель.
class ImportedHolding {
  final String rawName;
  final String isin;
  final double quantity;
  String? ticker;

  ImportedHolding({
    required this.rawName,
    required this.isin,
    required this.quantity,
    this.ticker,
  });
}

class BrokerImportResult {
  final List<ImportedTrade> trades;
  final List<ImportedPayout> payouts;
  final List<ImportedCashMove> cashMoves;

  /// Остатки на конец периода — «правда» брокера, с которой сверяется портфель.
  final List<ImportedHolding> holdings;

  final String? period;

  const BrokerImportResult({
    required this.trades,
    required this.payouts,
    required this.cashMoves,
    required this.holdings,
    this.period,
  });

  bool get isEmpty => trades.isEmpty && payouts.isEmpty && cashMoves.isEmpty;

  List<ImportedTrade> get unresolvedTrades => trades.where((t) => t.ticker == null).toList();

  /// Названия бумаг, которые не удалось опознать — по одному на бумагу.
  List<String> get unresolvedNames =>
      unresolvedTrades.map((t) => t.rawName.split(',').first.trim()).toSet().toList();
}

/// Разбор брокерских отчётов.
class BrokerImportService {
  BrokerImportService._();

  static BrokerImportResult parse(Broker broker, Uint8List bytes) {
    return switch (broker) {
      Broker.vtb => _parseVtb(bytes),
    };
  }

  // ---------------------------------------------------------------------------
  // ВТБ
  // ---------------------------------------------------------------------------

  static BrokerImportResult _parseVtb(Uint8List bytes) {
    final rows = XlsxReader.firstSheet(bytes);

    final trades = <ImportedTrade>[];
    final payouts = <ImportedPayout>[];
    final cash = <ImportedCashMove>[];

    // --- Сделки ---
    // Ниже в отчёте идут ещё разделы с такой же таблицей — завершённые и
    // незавершённые сделки. Без явной границы разбор заезжал в них и удваивал
    // каждую сделку.
    final tradesStart = _findRow(rows, 'Заключенные в отчетном периоде сделки');
    final tradesEnd = _findRow(rows, 'Завершенные в отчетном периоде сделки') ?? rows.length;
    if (tradesStart != null && tradesStart + 1 < rows.length) {
      final header = rows[tradesStart + 1];
      final cName = _col(header, ['Наименование ценной бумаги']);
      final cDate = _col(header, ['Дата и время заключения']);
      final cKind = _col(header, ['Вид сделки']);
      final cQty = _col(header, ['Количество']);
      final cCur = _col(header, ['Валюта расч']);
      final cSum = _col(header, ['Сумма сделки']); // включает НКД
      final cNkd = _col(header, ['НКД по сделке', 'НКД\n']);
      final cFee1 = _col(header, ['Комиссия Банка за расч']);
      final cFee2 = _col(header, ['Комиссия Банка за заключ']);

      for (int i = tradesStart + 2; i < tradesEnd && i < rows.length; i++) {
        final row = rows[i];
        final name = _at(row, cName);
        if (name.isEmpty) {
          // Пустая строка — конец раздела, но у ВТБ внутри бывают пропуски.
          if (_isBlank(row)) continue;
          break;
        }
        final kind = _at(row, cKind);
        if (!kind.contains('окупка') && !kind.contains('родажа')) continue;

        final date = _parseDate(_at(row, cDate));
        final qty = _parseNum(_at(row, cQty));
        final sum = _parseNum(_at(row, cSum));
        // НКД в отчёте есть не у всех строк — у акций колонка пустая.
        final nkd = _parseNum(_at(row, cNkd)) ?? 0;
        if (date == null || qty == null || qty <= 0 || sum == null) continue;

        final isSell = kind.contains('родажа');
        // Цену считаем из суммы: у облигаций в колонке цены проценты от
        // номинала, а сумма всегда в деньгах. НКД в цену не входит.
        final price = (sum - nkd) / qty;
        final fees = (_parseNum(_at(row, cFee1)) ?? 0) + (_parseNum(_at(row, cFee2)) ?? 0);

        trades.add(ImportedTrade(
          date: date,
          rawName: name,
          isin: _isinFrom(name),
          quantity: qty,
          pricePerUnit: price,
          // НКД при покупке — часть расхода, при продаже — часть прихода.
          fee: isSell ? fees - nkd : fees + nkd,
          currency: _currency(_at(row, cCur)),
          isSell: isSell,
        ));
      }
    }

    // --- Движение денежных средств: выплаты, пополнения, выводы ---
    final cashStart = _findRow(rows, 'Движение денежных средств');
    final cashEnd = _findRow(rows, 'Отчёт об остатках ценных бумаг') ?? rows.length;
    if (cashStart != null && cashStart + 1 < rows.length) {
      final header = rows[cashStart + 1];
      final cDate = _col(header, ['Дата']);
      final cSum = _col(header, ['Сумма']);
      final cCur = _col(header, ['Валюта']);
      final cType = _col(header, ['Тип операции']);
      final cNote = _col(header, ['Комментарий']);

      for (int i = cashStart + 2; i < cashEnd && i < rows.length; i++) {
        final row = rows[i];
        final type = _at(row, cType);
        final dateText = _at(row, cDate);
        if (type.isEmpty && dateText.isEmpty) {
          if (_isBlank(row)) continue;
          // Дошли до следующего раздела.
          if (_at(row, cSum).isEmpty) break;
          continue;
        }

        final date = _parseDate(dateText);
        final amount = _parseNum(_at(row, cSum));
        if (date == null || amount == null) continue;
        final currency = _currency(_at(row, cCur));
        final note = _at(row, cNote);

        if (type.contains('ивиденд') || type.contains('упон')) {
          payouts.add(ImportedPayout(
            date: date,
            rawName: note,
            isin: _isinFrom(note),
            amount: amount,
            currency: currency,
            isCoupon: type.contains('упон'),
          ));
        } else if (type.contains('ачисление денежных средств')) {
          cash.add(ImportedCashMove(date: date, amount: amount, currency: currency, note: note));
        } else if (type.contains('писание денежных средств') || type.contains('ывод')) {
          cash.add(ImportedCashMove(
            date: date,
            amount: -amount.abs(),
            currency: currency,
            note: note,
          ));
        }
      }
    }

    // --- Остатки бумаг на конец периода ---
    final holdings = <ImportedHolding>[];
    final holdStart = _findRow(rows, 'остатках ценных бумаг');
    // Следом идёт «Движение ценных бумаг» — таблица с теми же бумагами и
    // количествами в других колонках. Без границы разбор считал каждую бумагу
    // дважды.
    final holdEnd = _findRow(rows, 'Движение ценных бумаг') ?? rows.length;
    if (holdStart != null && holdStart + 1 < rows.length) {
      final header = rows[holdStart + 1];
      final cName = _col(header, ['Наименование ценной бумаги']);
      // Плановый остаток учитывает сделки, расчёты по которым ещё идут — именно
      // это количество показывает приложение брокера.
      final cPlanned = _col(header, ['Плановый исходящий остаток']);
      final cOut = _col(header, ['Исходящий остаток']);

      for (int i = holdStart + 2; i < holdEnd && i < rows.length; i++) {
        final row = rows[i];
        final name = _at(row, cName);
        if (name.isEmpty) {
          if (_isBlank(row)) continue;
          break;
        }
        if (name.startsWith('ИТОГО')) break;
        // Внутри раздела есть подзаголовки «АКЦИЯ», «ОБЛИГАЦИЯ».
        if (_at(row, cOut).isEmpty && _at(row, cPlanned).isEmpty) continue;

        final qty = _parseNum(_at(row, cPlanned)) ?? _parseNum(_at(row, cOut)) ?? 0;
        holdings.add(ImportedHolding(rawName: name, isin: _isinFrom(name), quantity: qty));
      }
    }

    _resolveTickers(trades, payouts, holdings);

    return BrokerImportResult(
      trades: trades,
      payouts: payouts,
      cashMoves: cash,
      holdings: holdings,
      period: _findText(rows, 'Отчет Банка ВТБ'),
    );
  }

  // ---------------------------------------------------------------------------
  // Сопоставление бумаг
  // ---------------------------------------------------------------------------

  /// Тикер ищем по ISIN среди загруженных с биржи бумаг, затем по первому
  /// слову названия (у фондов это сам тикер), затем по встроенному справочнику.
  static void _resolveTickers(
    List<ImportedTrade> trades,
    List<ImportedPayout> payouts,
    List<ImportedHolding> holdings,
  ) {
    final byIsin = <String, String>{};
    for (final q in MoexSyncService.marketSnapshot.value.values) {
      if (q.isin.isNotEmpty) byIsin[q.isin.toUpperCase()] = q.ticker;
    }

    final cache = <String, String?>{};

    String? resolve(String isin, String name) {
      final key = '$isin|$name';
      if (cache.containsKey(key)) return cache[key];

      String? result;

      // 1. ISIN — единственный надёжный ключ. Работает при включённой загрузке
      // с биржи: там у каждой бумаги есть свой ISIN.
      if (isin.isNotEmpty) {
        result = byIsin[isin.toUpperCase()];
      }

      // 2. Первое слово названия латиницей — у фондов это и есть тикер
      // («LQDT ETF», «LSNGP РСетиЛЭ-п»).
      if (result == null) {
        final first = name.trim().split(RegExp(r'[\s,]+')).first;
        if (RegExp(r'^[A-Z]{3,6}$').hasMatch(first) &&
            SecuritiesDatabase.byTicker(first) != null) {
          result = first;
        }
      }

      // 3. Поиск по названию — только если он даёт ОДИН вариант. Раньше здесь
      // брался первый из списка, и облигация «Сбер SbD9R» могла превратиться в
      // акции Сбербанка: покупки и продажи расходились по разным бумагам, а
      // проданные позиции навсегда оставались в портфеле.
      if (result == null) {
        final query = name.split(',').first.trim();
        final found = SecuritiesDatabase.search(query);
        if (found.length == 1) {
          result = found.first.ticker;
        }
      }

      cache[key] = result;
      return result;
    }

    for (final t in trades) {
      t.ticker = resolve(t.isin, t.rawName);
    }
    for (final p in payouts) {
      p.ticker = resolve(p.isin, p.rawName);
    }
    for (final h in holdings) {
      h.ticker = resolve(h.isin, h.rawName);
    }
  }

  /// Досопоставление через биржу: спрашиваем тикер по ISIN у тех бумаг, что не
  /// нашлись локально. Так опознаются и те выпуски, которые уже не торгуются и
  /// поэтому отсутствуют в списке котировок.
  static Future<int> resolveOnline(BrokerImportResult result) async {
    final isins = <String>{
      for (final t in result.trades)
        if (t.ticker == null && t.isin.isNotEmpty) t.isin,
      for (final p in result.payouts)
        if (p.ticker == null && p.isin.isNotEmpty) p.isin,
      for (final h in result.holdings)
        if (h.ticker == null && h.isin.isNotEmpty) h.isin,
    };
    if (isins.isEmpty) return 0;

    final found = <String, String>{};
    for (final isin in isins) {
      final ticker = await MoexService.tickerByIsin(isin);
      if (ticker != null) found[isin.toUpperCase()] = ticker;
    }

    for (final t in result.trades) {
      t.ticker ??= found[t.isin.toUpperCase()];
    }
    for (final p in result.payouts) {
      p.ticker ??= found[p.isin.toUpperCase()];
    }
    for (final h in result.holdings) {
      h.ticker ??= found[h.isin.toUpperCase()];
    }
    return found.length;
  }

  /// Полная очистка портфеля перед импортом. Нужна, когда отчёт брокера должен
  /// стать единственным источником правды: ручные записи и следы прошлых
  /// импортов иначе складываются с новыми.
  static Future<void> clearPortfolio({bool keepPlans = true}) async {
    for (final p in StorageService.purchases.toList()) {
      await StorageService.deletePurchase(p.id);
    }
    for (final i in StorageService.incomes.toList()) {
      await StorageService.deleteIncome(i.id);
    }
    for (final d in StorageService.deposits.toList()) {
      await StorageService.deleteDeposit(d.id);
    }
    if (!keepPlans) {
      for (final plan in StorageService.plans.toList()) {
        await StorageService.deletePlan(plan.id);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Запись в приложение
  // ---------------------------------------------------------------------------

  /// Переносит разобранное в портфель. Повторный импорт того же файла ничего
  /// не задваивает: одинаковые записи узнаются по дате, бумаге, количеству и
  /// цене.
  static Future<({int trades, int payouts, int deposits, int duplicates, int unresolved})> apply(
    BrokerImportResult result, {
    bool importTrades = true,
    bool importPayouts = true,
    bool importCash = true,
  }) async {
    int addedTrades = 0;
    int addedPayouts = 0;
    int addedDeposits = 0;
    // Пропуски разделяем: «уже было» — это норма при повторном импорте, а
    // «не опознана бумага» — то, что требует внимания.
    int duplicates = 0;
    int unresolved = 0;

    // Считаем, сколько ОДИНАКОВЫХ записей уже есть. У брокера обычная история —
    // одна заявка исполняется несколькими сделками с равной ценой в один день;
    // прежняя проверка «такая запись уже есть» съедала все повторы, кроме
    // первого, и в портфеле недоставало бумаг.
    final seenTrades = <String, int>{};
    for (final p in StorageService.purchases) {
      seenTrades.update(_tradeKey(p.ticker, p.date, p.quantity, p.pricePerUnit, p.isSell),
          (v) => v + 1, ifAbsent: () => 1);
    }
    final seenIncomes = <String, int>{};
    for (final i in StorageService.incomes) {
      seenIncomes.update(_payoutKey(i.ticker, i.date, i.amountGross), (v) => v + 1, ifAbsent: () => 1);
    }
    final seenDeposits = <String, int>{};
    for (final d in StorageService.deposits) {
      seenDeposits.update(_cashKey(d.date, d.amount), (v) => v + 1, ifAbsent: () => 1);
    }

    if (importTrades) {
      for (final t in result.trades) {
        final ticker = t.ticker;
        if (ticker == null) {
          unresolved++;
          continue;
        }
        final key = _tradeKey(ticker, t.date, t.quantity, t.pricePerUnit, t.isSell);
        final already = seenTrades[key] ?? 0;
        if (already > 0) {
          seenTrades[key] = already - 1;
          duplicates++;
          continue;
        }
        final info = SecuritiesDatabase.byTicker(ticker);
        await StorageService.addPurchase(Purchase(
          id: const Uuid().v4(),
          date: t.date,
          ticker: ticker.toUpperCase(),
          name: info?.name ?? t.rawName.split(',').first.trim(),
          type: info?.type ?? (t.rawName.contains('обл') ? AssetType.bond : AssetType.stock),
          quantity: t.quantity,
          pricePerUnit: t.pricePerUnit,
          fee: t.fee,
          currency: t.currency,
          sector: info?.sector ?? '',
          isSell: t.isSell,
          note: 'Импорт из отчёта брокера',
        ));
        addedTrades++;
      }
    }

    if (importPayouts) {
      for (final p in result.payouts) {
        final ticker = p.ticker;
        if (ticker == null) {
          unresolved++;
          continue;
        }
        final key = _payoutKey(ticker, p.date, p.amount);
        final already = seenIncomes[key] ?? 0;
        if (already > 0) {
          seenIncomes[key] = already - 1;
          duplicates++;
          continue;
        }
        final info = SecuritiesDatabase.byTicker(ticker);
        await StorageService.addIncome(Income(
          id: const Uuid().v4(),
          date: p.date,
          ticker: ticker.toUpperCase(),
          name: info?.name ?? ticker,
          type: p.isCoupon ? IncomeType.coupon : IncomeType.dividend,
          // В отчёте сумма уже за вычетом налога, если он удерживался.
          amountGross: p.amount,
          taxPaid: 0,
          currency: p.currency,
          note: 'Импорт из отчёта брокера',
        ));
        addedPayouts++;
      }
    }

    if (importCash) {
      for (final m in result.cashMoves) {
        final key = _cashKey(m.date, m.amount);
        final already = seenDeposits[key] ?? 0;
        if (already > 0) {
          seenDeposits[key] = already - 1;
          duplicates++;
          continue;
        }
        await StorageService.addDeposit(Deposit(
          id: const Uuid().v4(),
          date: m.date,
          amount: m.amount,
          currency: m.currency,
          note: m.amount >= 0 ? 'Пополнение (импорт)' : 'Вывод (импорт)',
        ));
        addedDeposits++;
      }
    }

    return (
      trades: addedTrades,
      payouts: addedPayouts,
      deposits: addedDeposits,
      duplicates: duplicates,
      unresolved: unresolved,
    );
  }

  /// Сколько бумаг реально добавится при импорте — с учётом того, что часть
  /// сделок уже есть в портфеле.
  static Map<String, double> _plannedDelta(BrokerImportResult result) {
    final seen = <String, int>{};
    for (final p in StorageService.purchases) {
      seen.update(_tradeKey(p.ticker, p.date, p.quantity, p.pricePerUnit, p.isSell),
          (v) => v + 1, ifAbsent: () => 1);
    }

    final delta = <String, double>{};
    for (final t in result.trades) {
      final ticker = t.ticker?.toUpperCase();
      if (ticker == null) continue;
      final key = _tradeKey(ticker, t.date, t.quantity, t.pricePerUnit, t.isSell);
      final already = seen[key] ?? 0;
      if (already > 0) {
        seen[key] = already - 1;
        continue;
      }
      delta[ticker] = (delta[ticker] ?? 0) + (t.isSell ? -t.quantity : t.quantity);
    }
    return delta;
  }

  /// Количества бумаг в портфеле прямо сейчас.
  static Map<String, double> currentQuantities() {
    final result = <String, double>{};
    AnalyticsService.currentHoldings()
        .forEach((ticker, h) => result[ticker.toUpperCase()] = h.qty);
    return result;
  }

  /// Каким портфель станет после импорта.
  ///
  /// При замене содержимого это остатки из отчёта. При обычном импорте — то,
  /// что есть, плюс сделки, которых ещё нет.
  static Map<String, double> expectedAfter(
    BrokerImportResult result, {
    required bool replaceAll,
  }) {
    if (replaceAll) {
      final after = <String, double>{};
      for (final h in result.holdings) {
        final ticker = h.ticker?.toUpperCase();
        if (ticker == null) continue;
        after[ticker] = (after[ticker] ?? 0) + h.quantity;
      }
      return after;
    }

    final after = Map<String, double>.from(currentQuantities());
    _plannedDelta(result).forEach((ticker, delta) {
      after[ticker] = (after[ticker] ?? 0) + delta;
    });
    return after;
  }

  /// Сравнение двух состояний портфеля для показа на экране.
  static List<({String ticker, double now, double after})> diff(
    Map<String, double> now,
    Map<String, double> after,
  ) {
    final rows = <({String ticker, double now, double after})>[];
    for (final ticker in {...now.keys, ...after.keys}) {
      final a = after[ticker] ?? 0;
      final n = now[ticker] ?? 0;
      if (a <= 1e-9 && n <= 1e-9) continue;
      rows.add((ticker: ticker, now: n, after: a));
    }
    rows.sort((x, y) {
      final changed = ((y.after - y.now).abs()).compareTo((x.after - x.now).abs());
      return changed != 0 ? changed : y.after.compareTo(x.after);
    });
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Мелочи разбора
  // ---------------------------------------------------------------------------

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Ключ одинаковости записи. Цену округляем до копеек: в отчёте она с
  /// точностью до четвёртого знака, а при повторном импорте должна совпасть.
  static String _tradeKey(String ticker, DateTime date, double qty, double price, bool isSell) =>
      '${ticker.toUpperCase()}|${_day(date)}|${qty.toStringAsFixed(4)}|'
      '${price.toStringAsFixed(2)}|$isSell';

  static String _payoutKey(String ticker, DateTime date, double amount) =>
      '${ticker.toUpperCase()}|${_day(date)}|${amount.toStringAsFixed(2)}';

  static String _cashKey(DateTime date, double amount) =>
      '${_day(date)}|${amount.toStringAsFixed(2)}';

  static String _at(List<String> row, int? index) =>
      (index == null || index < 0 || index >= row.length) ? '' : row[index];

  static bool _isBlank(List<String> row) => row.every((c) => c.trim().isEmpty);

  /// Номер колонки по фрагменту заголовка. Заголовки у ВТБ многострочные, так
  /// что сравниваем по вхождению, а не по равенству.
  ///
  /// Ключевые слова перебираются по очереди целиком по всем колонкам: сначала
  /// самое точное, потом запасные. Иначе «НКД» находился в заголовке «Сумма
  /// сделки … (включая НКД)» — и суммой сделки становился накопленный доход.
  static int? _col(List<String> header, List<String> keywords) {
    for (final k in keywords) {
      for (int i = 0; i < header.length; i++) {
        if (header[i].replaceAll('\n', ' ').contains(k)) return i;
      }
    }
    return null;
  }

  static int? _findRow(List<List<String>> rows, String text) {
    for (int i = 0; i < rows.length; i++) {
      for (final cell in rows[i]) {
        if (cell.contains(text)) return i;
      }
    }
    return null;
  }

  static String? _findText(List<List<String>> rows, String startsWith) {
    for (final row in rows) {
      for (final cell in row) {
        if (cell.contains(startsWith)) return cell.replaceAll('\n', ' ').trim();
      }
    }
    return null;
  }

  static String _isinFrom(String text) {
    final match = RegExp(r'\b([A-Z]{2}[A-Z0-9]{9}\d)\b').firstMatch(text.toUpperCase());
    return match?.group(1) ?? '';
  }

  static String _currency(String raw) {
    final v = raw.trim().toUpperCase();
    if (v.isEmpty || v == 'RUR' || v == 'РУБ' || v == 'RUB') return 'RUB';
    return v;
  }

  static double? _parseNum(String raw) {
    if (raw.trim().isEmpty) return null;
    final cleaned = raw
        .replaceAll('\u00A0', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.')
        // В отчётах встречается разделитель разрядов запятой: «2,003.0».
        .replaceAll(RegExp(r'\.(?=\d{3}\b)'), '');
    return double.tryParse(cleaned);
  }

  /// Дата приходит либо как «2026-01-11 17:49:45», либо как «11.01.2026».
  static DateTime? _parseDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // Время сохраняем: внутри одного дня порядок сделок важен, иначе продажа
    // может встать раньше покупки и «съесть» её.
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    // В XLSX дата — это число дней от 30.12.1899. Отличаем её от обычных чисел
    // по диапазону: 20000 — это 1954 год, 80000 — 2119-й, между ними даты
    // реальных отчётов, а цены и количества туда не попадают.
    final serial = double.tryParse(text.replaceAll(',', '.'));
    if (serial != null && serial > 20000 && serial < 80000) {
      // Дробная часть — время суток.
      final millis = ((serial - serial.floor()) * 86400000).round();
      return DateTime(1899, 12, 30)
          .add(Duration(days: serial.floor(), milliseconds: millis));
    }

    final dotted = RegExp(r'(\d{1,2})[.](\d{1,2})[.](\d{4})').firstMatch(text);
    if (dotted != null) {
      return DateTime(
        int.parse(dotted.group(3)!),
        int.parse(dotted.group(2)!),
        int.parse(dotted.group(1)!),
      );
    }
    return null;
  }
}
