import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/deposit.dart';
import '../models/purchase.dart';
import '../models/income.dart';
import '../models/plan.dart';
import 'storage_service.dart';
import 'sector_service.dart';
import 'manual_price_service.dart';
import 'backup_crypto_service.dart';
import 'currency_service.dart';
import 'package:flutter/material.dart';
import 'tour_service.dart';
import 'online_settings_service.dart';
import 'tax_service.dart';
import 'theme_service.dart';
import 'logo_service.dart';
import 'favorites_service.dart';

/// Результат импорта бэкапа: сколько записей добавлено и какие логотипы не
/// нашлись рядом с файлом (тикер -> ожидаемый относительный путь) — раньше
/// такие иконки просто молча пропускались без следа.
class ImportResult {
  final int count;
  final Map<String, String> missingLogos;

  const ImportResult({required this.count, required this.missingLogos});
}

/// Экспорт/импорт всех данных в один JSON-файл.
/// Так как БД нет, это единственный способ сделать бэкап
/// или перенести данные на новый телефон.
class BackupService {
  static Future<Map<String, dynamic>> _buildData() async {
    final data = <String, dynamic>{
      'version': 4,
      'exportedAt': DateTime.now().toIso8601String(),
      // Настройки приложения: тема, налог, онлайн-загрузка, отметка об
      // обучении. Раньше в бэкап попадали только данные, и после переустановки
      // всё это приходилось выставлять заново.
      'settings': {
        'accentColor': ThemeService.accentColor.value.value,
        'themeMode': ThemeService.themeMode.value.index,
        'taxEnabled': TaxService.enabled,
        'taxRate': TaxService.rate,
        'onlineEnabled': OnlineSettingsService.enabled,
        'onlineIntervalSeconds': OnlineSettingsService.intervalSeconds,
        'tourDonePages': TourService.donePages,
      },
      'deposits': StorageService.deposits
          .map((d) => {
                'id': d.id,
                'date': d.date.toIso8601String(),
                'amount': d.amount,
                'currency': d.currency,
                'note': d.note,
                'broker': d.broker,
              })
          .toList(),
      'purchases': StorageService.purchases
          .map((p) => {
                'id': p.id,
                'date': p.date.toIso8601String(),
                'ticker': p.ticker,
                'name': p.name,
                'type': p.type.index,
                'quantity': p.quantity,
                'pricePerUnit': p.pricePerUnit,
                'fee': p.fee,
                'currency': p.currency,
                'note': p.note,
                'sector': p.sector,
                'isSell': p.isSell,
                'planId': p.planId,
              })
          .toList(),
      'incomes': StorageService.incomes
          .map((i) => {
                'id': i.id,
                'date': i.date.toIso8601String(),
                'ticker': i.ticker,
                'name': i.name,
                'type': i.type.index,
                'amountGross': i.amountGross,
                'taxPaid': i.taxPaid,
                'currency': i.currency,
                'note': i.note,
              })
          .toList(),
      'plans': StorageService.plans
          .map((p) => {
                'id': p.id,
                'ticker': p.ticker,
                'name': p.name,
                'type': p.type.index,
                'targetQuantity': p.targetQuantity,
                'targetPrice': p.targetPrice,
                'targetDate': p.targetDate?.toIso8601String(),
                'status': p.status.index,
                'note': p.note,
                'createdAt': p.createdAt.toIso8601String(),
                'purchasedQuantity': p.purchasedQuantity,
                'purchasedAvgPrice': p.purchasedAvgPrice,
              })
          .toList(),
      'customSectors': SectorService.customSectors,
      'sectorAssignments': SectorService.allAssignments,
    };

    // Дополнительные данные — каждая обёрнута в свой try/catch: сбой в одной
    // из них (например, при обращении к файлам логотипов на диске) не должен
    // ронять весь бэкап целиком и лишать пользователя даже основных данных
    // портфеля.
    try {
      data['manualPrices'] = ManualPriceService.all;
    } catch (_) {}
    try {
      data['manualPriceHistory'] = {
        for (final entry in ManualPriceService.allHistory.entries)
          entry.key: entry.value.map((p) => p.toJson()).toList(),
      };
    } catch (_) {}
    try {
      data['currencyRateHistory'] = {
        for (final c in CurrencyService.trackedCurrencies)
          c: CurrencyService.historyFor(c).map((p) => p.toJson()).toList(),
      };
    } catch (_) {}
    try {
      // Логотипы бумаг — встраиваем прямо в JSON как base64, без отдельной
      // папки рядом с бэкапом. Чуть увеличивает размер файла, зато бэкап —
      // один самодостаточный файл: ничего не потеряется, если картинки
      // отделятся от JSON при пересылке/переносе.
      final logosB64 = <String, Map<String, String>>{};
      for (final entry in LogoService.allPaths.entries) {
        final file = File(entry.value);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        logosB64[entry.key] = {
          'ext': _extOf(entry.value),
          'data': base64Encode(bytes),
        };
      }
      data['logosBase64'] = logosB64;
    } catch (_) {}
    try {
      data['favorites'] = FavoritesService.all;
    } catch (_) {}

    return data;
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot);
  }

  static Future<String> exportToJson() async {
    final jsonStr = await _serialize();

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'invest_tracker_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonStr);

    // Иконки бумаг встроены прямо в JSON (base64) — файл самодостаточный,
    // отдельно пересылать/сохранять картинки не нужно.
    await Share.shareXFiles([XFile(file.path)], text: 'Бэкап Invest Tracker');

    return file.path;
  }

  /// Тихо (без диалогов и шеринга) сохраняет бэкап текущего портфеля в файл
  /// с фиксированным именем внутри указанной папки — перезаписывает один и
  /// тот же файл, а не копит новый на каждое изменение. Используется
  /// автосохранением (см. AutoBackupService). Возвращает null при успехе,
  /// иначе текст ошибки — например, если папка оказалась недоступна для
  /// записи (ограничения файловой системы Android на некоторых
  /// устройствах/версиях). Раньше сбой здесь проглатывался молча.
  static Future<String?> saveToFolder(String folderPath) async {
    try {
      final jsonStr = await _serialize();
      final file = File('$folderPath/invest_tracker_autobackup.json');
      await file.writeAsString(jsonStr);
    } catch (e) {
      return e.toString();
    }
    return null;
  }

  /// Готовит содержимое файла: если включено шифрование, JSON заворачивается
  /// в конверт с шифротекстом.
  static Future<String> _serialize() async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(await _buildData());
    final password = BackupCryptoService.enabled ? BackupCryptoService.password : null;
    if (password == null) return jsonStr;
    return BackupCryptoService.encrypt(jsonStr, password);
  }

  /// [askPassword] вызывается, если файл зашифрован, а сохранённый пароль не
  /// подошёл — например, копия сделана на другом устройстве.
  static Future<ImportResult> importFromFilePath(
    String path, {
    Future<String?> Function()? askPassword,
  }) async {
    var content = await File(path).readAsString();
    final logosBaseDir = File(path).parent.path;

    if (BackupCryptoService.looksEncrypted(content)) {
      content = await _decryptContent(content, askPassword);
    }

    return importFromJson(content, logosBaseDir: logosBaseDir);
  }

  static Future<String> _decryptContent(
    String content,
    Future<String?> Function()? askPassword,
  ) async {
    // Сначала пробуем пароль, который уже задан в приложении: чаще всего
    // копия сделана этим же телефоном.
    final saved = BackupCryptoService.password;
    if (saved != null) {
      try {
        return BackupCryptoService.decrypt(content, saved);
      } catch (_) {
        // Пароль не подошёл — спросим у пользователя.
      }
    }

    if (askPassword == null) {
      throw const FormatException('Бэкап зашифрован, нужен пароль');
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      final entered = await askPassword();
      if (entered == null || entered.trim().isEmpty) {
        throw const FormatException('Импорт отменён: файл зашифрован');
      }
      try {
        return BackupCryptoService.decrypt(content, entered.trim());
      } catch (_) {
        // Пробуем ещё раз — до трёх попыток.
      }
    }
    throw const FormatException('Неверный пароль');
  }

  /// Иконки бумаг теперь встроены прямо в бэкап (base64, поле
  /// 'logosBase64') — отдельная папка не нужна, [logosBaseDir] для них
  /// больше не требуется.
  ///
  /// [logosBaseDir] используется только как ОБРАТНАЯ СОВМЕСТИМОСТЬ со
  /// старыми бэкапами (до встраивания), где иконки лежали отдельными
  /// файлами в подпапке 'logos' рядом с JSON. ВАЖНО для этого старого
  /// случая: на Android системный выбор файла иногда возвращает путь к
  /// ВРЕМЕННОЙ КОПИИ выбранного файла, а не к его настоящему расположению —
  /// тогда папка 'logos' рядом с этой копией не находится, даже если она
  /// реально лежит рядом с оригиналом. См. ImportResult.missingLogos и
  /// retryMissingLogos ниже для ручного восстановления в этом случае.
  static Future<ImportResult> importFromJson(String jsonStr, {String? logosBaseDir}) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version < 1 || version > 4) {
      throw FormatException('Неподдерживаемая версия бэкапа: $version');
    }

    // Сначала полностью разбираем и проверяем основные данные, не меняя
    // рабочее хранилище. Только валидный файл допускается к применению.
    final importedDeposits = <Deposit>[];
    for (final raw in (data['deposits'] as List? ?? [])) {
      final d = raw as Map;
      importedDeposits.add(Deposit(
        id: d['id'],
        date: DateTime.parse(d['date']),
        amount: (d['amount'] as num).toDouble(),
        currency: d['currency'] ?? 'RUB',
        note: d['note'],
        broker: d['broker'],
      ));
    }

    final importedPurchases = <Purchase>[];
    for (final raw in (data['purchases'] as List? ?? [])) {
      final p = raw as Map;
      final quantity = (p['quantity'] as num).toDouble();
      final price = (p['pricePerUnit'] as num).toDouble();
      final fee = (p['fee'] as num?)?.toDouble() ?? 0;
      // Комиссия здесь — не только расход, а поправка к сумме сделки: при
      // покупке облигации в неё добавляется уплаченный НКД, при продаже —
      // ВЫЧИТАЕТСЯ полученный (см. broker_import_service: `commissions - nkd`).
      // Дальше по коду сделка считается как `qty * price - fee` для продажи и
      // `qty * price + fee` для покупки, поэтому отрицательное значение здесь
      // законно и означает, что НКД превысил комиссии.
      //
      // Раньше проверка требовала `fee >= 0` и роняла импорт собственного
      // бэкапа приложения на первой же продаже ОФЗ: экспорт такие сделки
      // сохранял, а импорт объявлял файл некорректным.
      if (quantity <= 0 || price < 0 || !quantity.isFinite || !price.isFinite || !fee.isFinite) {
        throw FormatException('Некорректная сделка ${p['ticker'] ?? ''}');
      }
      importedPurchases.add(Purchase(
        id: p['id'],
        date: DateTime.parse(p['date']),
        ticker: p['ticker'],
        name: p['name'],
        type: AssetType.values[p['type']],
        quantity: quantity,
        pricePerUnit: price,
        fee: fee,
        currency: p['currency'] ?? 'RUB',
        note: p['note'],
        sector: p['sector'],
        isSell: p['isSell'] ?? false,
        planId: p['planId'],
      ));
    }

    final importedIncomes = <Income>[];
    for (final raw in (data['incomes'] as List? ?? [])) {
      final i = raw as Map;
      final gross = (i['amountGross'] as num).toDouble();
      final tax = (i['taxPaid'] as num?)?.toDouble() ?? 0;
      if (gross < 0 || tax < 0 || tax > gross) {
        throw FormatException('Некорректная выплата ${i['ticker'] ?? ''}');
      }
      importedIncomes.add(Income(
        id: i['id'],
        date: DateTime.parse(i['date']),
        ticker: i['ticker'],
        name: i['name'],
        type: IncomeType.values[i['type']],
        amountGross: gross,
        taxPaid: tax,
        currency: i['currency'] ?? 'RUB',
        note: i['note'],
      ));
    }

    final importedPlans = <Plan>[];
    for (final raw in (data['plans'] as List? ?? [])) {
      final p = raw as Map;
      importedPlans.add(Plan(
        id: p['id'],
        ticker: p['ticker'],
        name: p['name'],
        type: AssetType.values[p['type']],
        targetQuantity: (p['targetQuantity'] as num).toDouble(),
        targetPrice: (p['targetPrice'] as num?)?.toDouble(),
        targetDate:
            p['targetDate'] != null ? DateTime.parse(p['targetDate']) : null,
        status: PlanStatus.values[p['status']],
        note: p['note'],
        createdAt: DateTime.parse(p['createdAt']),
        purchasedQuantity:
            (p['purchasedQuantity'] as num?)?.toDouble() ?? 0,
        purchasedAvgPrice:
            (p['purchasedAvgPrice'] as num?)?.toDouble() ?? 0,
      ));
    }

    final depositsById = {for (final d in StorageService.deposits) d.id: d}
      ..addEntries(importedDeposits.map((d) => MapEntry(d.id, d)));
    final purchasesById = {for (final p in StorageService.purchases) p.id: p}
      ..addEntries(importedPurchases.map((p) => MapEntry(p.id, p)));
    final incomesById = {for (final i in StorageService.incomes) i.id: i}
      ..addEntries(importedIncomes.map((i) => MapEntry(i.id, i)));
    final plansById = {for (final p in StorageService.plans) p.id: p}
      ..addEntries(importedPlans.map((p) => MapEntry(p.id, p)));

    await StorageService.replaceFinancialData(
      deposits: depositsById.values,
      purchases: purchasesById.values,
      incomes: incomesById.values,
      plans: plansById.values,
    );
    final count = importedDeposits.length +
        importedPurchases.length +
        importedIncomes.length +
        importedPlans.length;

    for (final sector in (data['customSectors'] as List? ?? [])) {
      await SectorService.addSector(sector as String);
    }
    final sectorAssignments = (data['sectorAssignments'] as Map?) ?? {};
    for (final entry in sectorAssignments.entries) {
      await SectorService.assignSector(entry.key as String, entry.value as String);
    }

    final priceHistory = (data['manualPriceHistory'] as Map?) ?? {};
    if (priceHistory.isNotEmpty) {
      for (final entry in priceHistory.entries) {
        final ticker = entry.key as String;
        for (final point in (entry.value as List)) {
          final map = point as Map<String, dynamic>;
          await ManualPriceService.setAt(
            ticker,
            DateTime.parse(map['date']),
            (map['price'] as num).toDouble(),
          );
        }
      }
    } else {
      // Старый бэкап без истории — заводим единственную точку на дату экспорта.
      final manualPrices = (data['manualPrices'] as Map?) ?? {};
      final fallbackDate = data['exportedAt'] != null ? DateTime.parse(data['exportedAt']) : DateTime.now();
      for (final entry in manualPrices.entries) {
        await ManualPriceService.setAt(entry.key as String, fallbackDate, (entry.value as num).toDouble());
      }
    }

    final rateHistory = (data['currencyRateHistory'] as Map?) ?? {};
    for (final entry in rateHistory.entries) {
      final currency = entry.key as String;
      for (final point in (entry.value as List)) {
        final map = point as Map<String, dynamic>;
        await CurrencyService.setRateAt(
          currency,
          DateTime.parse(map['date']),
          (map['rate'] as num).toDouble(),
        );
      }
    }

    final settings = (data['settings'] as Map?) ?? {};
    if (settings.isNotEmpty) {
      final accent = settings['accentColor'];
      if (accent is int) await ThemeService.setAccentColor(Color(accent));
      final mode = settings['themeMode'];
      if (mode is int && mode >= 0 && mode < ThemeMode.values.length) {
        await ThemeService.setThemeMode(ThemeMode.values[mode]);
      }
      final taxEnabled = settings['taxEnabled'];
      if (taxEnabled is bool) await TaxService.setEnabled(taxEnabled);
      final taxRate = settings['taxRate'];
      if (taxRate is num) await TaxService.setRate(taxRate.toDouble());
      final onlineEnabled = settings['onlineEnabled'];
      if (onlineEnabled is bool) await OnlineSettingsService.setEnabled(onlineEnabled);
      final interval = settings['onlineIntervalSeconds'];
      if (interval is int) await OnlineSettingsService.setIntervalSeconds(interval);
      final tourPages = settings['tourDonePages'];
      if (tourPages is List) {
        await TourService.restoreDonePages(tourPages.map((e) => '$e').toList());
      }
    }

    final missingLogos = <String, String>{};
    final logosB64 = (data['logosBase64'] as Map?) ?? {};
    if (logosB64.isNotEmpty) {
      // Новый формат — иконки встроены прямо в бэкап (base64), отдельная
      // папка не нужна.
      for (final entry in logosB64.entries) {
        final ticker = entry.key as String;
        try {
          final info = entry.value as Map;
          final bytes = base64Decode(info['data'] as String);
          final ext = (info['ext'] as String?) ?? '.png';
          await LogoService.setLogoBytes(ticker, bytes, ext);
        } catch (_) {
          missingLogos[ticker] = 'встроенная иконка повреждена';
        }
      }
    } else {
      // Старый формат бэкапа (до встраивания base64) — иконки как отдельные
      // файлы в папке 'logos' рядом с JSON.
      final logos = (data['logos'] as Map?) ?? {};
      for (final entry in logos.entries) {
        final ticker = entry.key as String;
        final relativePath = entry.value as String;
        final source = logosBaseDir != null ? File('$logosBaseDir/$relativePath') : null;
        if (source != null && await source.exists()) {
          await LogoService.setLogo(ticker, source);
        } else {
          // либо папка бэкапа не передана, либо файла рядом реально нет —
          // либо (частый случай на Android) выбор файла вернул путь к
          // временной копии, а не к настоящему расположению файла.
          missingLogos[ticker] = relativePath;
        }
      }
    }

    for (final ticker in (data['favorites'] as List? ?? [])) {
      if (!FavoritesService.isFavorite(ticker as String)) {
        await FavoritesService.toggle(ticker);
      }
    }

    return ImportResult(count: count, missingLogos: missingLogos);
  }

  /// Повторная попытка подтянуть логотипы из ВРУЧНУЮ выбранной папки — для
  /// случая, когда автоматический поиск рядом с файлом бэкапа не нашёл папку
  /// 'logos' (см. комментарий у importFromJson про временные копии файлов
  /// на Android). Пробует найти файл и по относительному пути из бэкапа
  /// ('logos/TICKER.png'), и просто по имени файла в выбранной папке — на
  /// случай, если пользователь указал сразу папку 'logos', а не её родителя.
  static Future<int> retryMissingLogos(Map<String, String> missingLogos, String folderPath) async {
    int fixed = 0;
    for (final entry in missingLogos.entries) {
      final ticker = entry.key;
      final relativePath = entry.value;
      final candidates = [
        File('$folderPath/$relativePath'),
        File('$folderPath/${relativePath.split('/').last}'),
      ];
      for (final c in candidates) {
        if (await c.exists()) {
          await LogoService.setLogo(ticker, c);
          fixed++;
          break;
        }
      }
    }
    return fixed;
  }
}
