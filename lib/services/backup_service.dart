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
import 'budget_service.dart';
import 'dividend_history_service.dart';
import 'currency_service.dart';
import 'package:flutter/material.dart';
import 'tour_service.dart';
import 'online_settings_service.dart';
import 'tax_service.dart';
import 'theme_service.dart';
import 'logo_service.dart';
import 'favorites_service.dart';
import 'goal_service.dart';
import 'iis_service.dart';
import 'portfolio_service.dart';
import 'appearance_service.dart';

/// Результат импорта бэкапа: сколько записей добавлено и какие логотипы не
/// нашлись рядом с файлом (тикер -> ожидаемый относительный путь) — раньше
/// такие иконки просто молча пропускались без следа.
class ImportResult {
  final int count;
  final Map<String, String> missingLogos;

  /// Сколько портфелей загружено из общего бэкапа. 0 — старый бэкап одного
  /// портфеля, загруженный в текущий.
  final int portfolios;

  const ImportResult({required this.count, required this.missingLogos, this.portfolios = 0});
}

/// Экспорт/импорт всех данных в один JSON-файл.
/// Так как БД нет, это единственный способ сделать бэкап
/// или перенести данные на новый телефон.
class BackupService {
  /// Версия формата. 5 — общий бэкап: все портфели в одном файле. 1–4 —
  /// бэкап одного портфеля, такие файлы по-прежнему загружаются в текущий.
  static const formatVersion = 5;

  static Future<Map<String, dynamic>> _buildData() async {
    final portfolios = <Map<String, dynamic>>[];
    for (final meta in PortfolioService.list) {
      final records = await StorageService.readAllFor(meta.id);
      final sectors = await SectorService.readFor(meta.id);
      final entry = <String, dynamic>{
        'name': meta.name,
        'status': meta.status.name,
        'isActive': meta.id == PortfolioService.activeId,
        'createdAt': meta.createdAt.toIso8601String(),
        'deposits': records.deposits.map(_depositJson).toList(),
        'purchases': records.purchases.map(_purchaseJson).toList(),
        'incomes': records.incomes.map(_incomeJson).toList(),
        'plans': records.plans.map(_planJson).toList(),
        'customSectors': sectors.custom,
        'sectorAssignments': sectors.assignments,
      };
      // Финансовая цель и отметка ИИС этого портфеля.
      try {
        final goal = GoalService.goalFor(meta.id);
        if (goal != null) entry['goal'] = goal.toJson();
        final passive = GoalService.passiveFor(meta.id);
        if (passive != null) entry['passiveGoal'] = passive.toJson();
        final iis = IisService.settingsFor(meta.id);
        if (iis != null) entry['iis'] = iis.toJson();
      } catch (_) {}
      portfolios.add(entry);
    }

    final data = <String, dynamic>{
      'version': formatVersion,
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
        // Оформление: скрытие сумм, состав портфеля, значения на графике,
        // свёрнутые разделы, календарь выплат.
        'hideAmounts': AppearanceService.hideAmounts,
        'holdingsGrouping': AppearanceService.holdingsGrouping.name,
        'chartHints': AppearanceService.chartHints.name,
        'sectionPreview': AppearanceService.sectionPreview.name,
        'payoutCalendar': AppearanceService.payoutCalendar.name,
        'metricsLayout': AppearanceService.metricsLayout.name,
        // Всё оформление целиком, включая свёрнутые разделы, выбранные
        // вкладки и переключатели на экранах.
        'appearanceBox': AppearanceService.exportAll(),
      },
      'portfolios': portfolios,
      // Бюджет общий для всех портфелей — хранится как есть.
      'budget': BudgetService.exportAll(),
      // История дивидендов, однажды загруженная с сайтов: если сайт
      // поменяется, она останется в бэкапе.
      'dividendHistory': DividendHistoryService.exportAll(),
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
      // Только свои картинки: встроенные логотипы в бэкап не входят.
      data['logosCustom'] = true;
    } catch (_) {}
    try {
      data['favorites'] = FavoritesService.all;
    } catch (_) {}
    return data;
  }

  static Map<String, dynamic> _depositJson(Deposit d) => {
        'id': d.id,
        'date': d.date.toIso8601String(),
        'amount': d.amount,
        'currency': d.currency,
        'note': d.note,
        'broker': d.broker,
      };

  static Map<String, dynamic> _purchaseJson(Purchase p) => {
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
        // Пишется только когда в план засчитана часть сделки: у
        // остальных ключа нет, и файл читается и старыми версиями.
        if (p.planQuantity != null) 'planQuantity': p.planQuantity,
      };

  static Map<String, dynamic> _incomeJson(Income i) => {
        'id': i.id,
        'date': i.date.toIso8601String(),
        'ticker': i.ticker,
        'name': i.name,
        'type': i.type.index,
        'amountGross': i.amountGross,
        'taxPaid': i.taxPaid,
        'currency': i.currency,
        'note': i.note,
      };

  static Map<String, dynamic> _planJson(Plan p) => {
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
      };

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

  /// Тихо (без диалогов и шеринга) сохраняет общий бэкап всех портфелей в файл
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
  /// [confirmBudget] спрашивает, заменять ли бюджет, если в бэкапе он
  /// старее текущего: (когда сохранён бюджет в бэкапе, когда менялся текущий).
  static Future<ImportResult> importFromFilePath(
    String path, {
    Future<String?> Function()? askPassword,
    Future<bool> Function(DateTime? backupAt, DateTime? currentAt)? confirmBudget,
  }) async {
    var content = await File(path).readAsString();
    final logosBaseDir = File(path).parent.path;

    if (BackupCryptoService.looksEncrypted(content)) {
      content = await _decryptContent(content, askPassword);
    }

    return importFromJson(content, logosBaseDir: logosBaseDir, confirmBudget: confirmBudget);
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
  static Future<ImportResult> importFromJson(
    String jsonStr, {
    String? logosBaseDir,
    Future<bool> Function(DateTime? backupAt, DateTime? currentAt)? confirmBudget,
  }) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version < 1 || version > formatVersion) {
      throw FormatException('Неподдерживаемая версия бэкапа: $version');
    }

    // Сначала полностью разбираем и проверяем основные данные, не меняя
    // рабочее хранилище. Только валидный файл допускается к применению.
    int count = 0;
    int portfolioCount = 0;
    if (version >= 5) {
      // Общий бэкап: портфели с тем же названием заменяются целиком,
      // недостающие создаются. Активный портфель не переключается.
      final parsed = <(Map, _Records)>[];
      for (final raw in (data['portfolios'] as List? ?? [])) {
        final src = raw as Map;
        final name = '${src['name'] ?? ''}'.trim();
        if (name.isEmpty) throw const FormatException('Портфель без названия');
        parsed.add((src, _parseRecords(src)));
      }
      for (final (src, records) in parsed) {
        final name = '${src['name']}'.trim();
        PortfolioMeta? found;
        for (final p in PortfolioService.list) {
          if (p.name.trim().toLowerCase() == name.toLowerCase()) found = p;
        }
        final meta = found ?? await PortfolioService.create(name);
        final status = src['status'] == PortfolioStatus.closed.name ? PortfolioStatus.closed : PortfolioStatus.active;
        if (meta.status != status) await PortfolioService.setStatus(meta.id, status);

        await StorageService.replaceFinancialDataFor(
          meta.id,
          deposits: records.deposits,
          purchases: records.purchases,
          incomes: records.incomes,
          plans: records.plans,
        );
        await SectorService.replaceFor(
          meta.id,
          [for (final s in (src['customSectors'] as List? ?? [])) '$s'],
          {
            for (final e in ((src['sectorAssignments'] as Map?) ?? {}).entries) '${e.key}': '${e.value}',
          },
        );
        final goalRaw = src['goal'];
        await GoalService.saveFor(
          meta.id,
          goalRaw is Map ? FinancialGoal.fromJson(Map<String, dynamic>.from(goalRaw)) : null,
        );
        final passiveRaw = src['passiveGoal'];
        await GoalService.savePassiveFor(
          meta.id,
          passiveRaw is Map ? PassiveGoal.fromJson(Map<String, dynamic>.from(passiveRaw)) : null,
        );
        final iisRaw = src['iis'];
        await IisService.save(
          meta.id,
          iisRaw is Map ? IisSettings.fromJson(Map<String, dynamic>.from(iisRaw)) : null,
        );
        count += records.count;
        portfolioCount++;
      }
    } else {
      // Старый бэкап одного портфеля — в текущий портфель, с объединением
      // по id, как и раньше.
      final records = _parseRecords(data);
      final depositsById = {for (final d in StorageService.deposits) d.id: d}
        ..addEntries(records.deposits.map((d) => MapEntry(d.id, d)));
      final purchasesById = {for (final p in StorageService.purchases) p.id: p}
        ..addEntries(records.purchases.map((p) => MapEntry(p.id, p)));
      final incomesById = {for (final i in StorageService.incomes) i.id: i}
        ..addEntries(records.incomes.map((i) => MapEntry(i.id, i)));
      final plansById = {for (final p in StorageService.plans) p.id: p}
        ..addEntries(records.plans.map((p) => MapEntry(p.id, p)));

      await StorageService.replaceFinancialData(
        deposits: depositsById.values,
        purchases: purchasesById.values,
        incomes: incomesById.values,
        plans: plansById.values,
      );
      count = records.count;

      for (final sector in (data['customSectors'] as List? ?? [])) {
        await SectorService.addSector(sector as String);
      }
      final sectorAssignments = (data['sectorAssignments'] as Map?) ?? {};
      for (final entry in sectorAssignments.entries) {
        await SectorService.assignSector(entry.key as String, entry.value as String);
      }

      // Цель и ИИС — в портфель, куда загружается бэкап. В старых бэкапах
      // этих полей нет: тогда текущие настройки не трогаем.
      final goalRaw = data['goal'];
      if (goalRaw is Map) {
        final goal = FinancialGoal.fromJson(Map<String, dynamic>.from(goalRaw));
        if (goal != null) await GoalService.save(goal);
      }
      final iisRaw = data['iis'];
      if (iisRaw is Map) {
        final iis = IisSettings.fromJson(Map<String, dynamic>.from(iisRaw));
        if (iis != null) await IisService.save(PortfolioService.activeId, iis);
      }
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
      // В старых бэкапах этих полей нет — тогда оформление не трогаем.
      final hide = settings['hideAmounts'];
      if (hide is bool) await AppearanceService.setHideAmounts(hide);
      T? byName<T extends Enum>(List<T> values, Object? name) {
        for (final v in values) {
          if (v.name == name) return v;
        }
        return null;
      }

      final grouping = byName(HoldingsGrouping.values, settings['holdingsGrouping']);
      if (grouping != null) await AppearanceService.setHoldingsGrouping(grouping);
      final hints = byName(ChartHints.values, settings['chartHints']);
      if (hints != null) await AppearanceService.setChartHints(hints);
      final preview = byName(SectionPreview.values, settings['sectionPreview']);
      if (preview != null) await AppearanceService.setSectionPreview(preview);
      final calendar = byName(PayoutCalendarStyle.values, settings['payoutCalendar']);
      if (calendar != null) await AppearanceService.setPayoutCalendar(calendar);
      final metrics = byName(MetricsLayout.values, settings['metricsLayout']);
      if (metrics != null) await AppearanceService.setMetricsLayout(metrics);
      final box = settings['appearanceBox'];
      if (box is Map) {
        await AppearanceService.importAll({
          for (final e in box.entries)
            if (e.value is String) '${e.key}': e.value as String,
        });
      }
    }

    final missingLogos = <String, String>{};
    // В старых бэкапах лежат и скачанные приложением логотипы. Там, где есть
    // встроенный, он лучше — скачанный пропускаем.
    final onlyCustom = data['logosCustom'] == true;
    bool skipLogo(String ticker) => !onlyCustom && LogoService.hasBundled(ticker);
    final logosB64 = (data['logosBase64'] as Map?) ?? {};
    if (logosB64.isNotEmpty) {
      // Новый формат — иконки встроены прямо в бэкап (base64), отдельная
      // папка не нужна.
      for (final entry in logosB64.entries) {
        final ticker = entry.key as String;
        if (skipLogo(ticker)) continue;
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
        if (skipLogo(ticker)) continue;
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

    final dividends = data['dividendHistory'];
    if (dividends is Map) {
      await DividendHistoryService.importAll({
        for (final e in dividends.entries)
          if (e.value is String) '${e.key}': e.value as String,
      });
    }

    // Бюджет: в старых бэкапах его нет — тогда не трогаем.
    final budget = data['budget'];
    if (budget is Map && budget.isNotEmpty) {
      // Бюджет заменяется целиком. Если в бэкапе он старее того, что сейчас в
      // приложении, — сначала спрашиваем, чтобы не потерять свежие отметки.
      final backupAt = BudgetService.updatedIn(budget);
      final currentAt = BudgetService.started ? BudgetService.updatedAt : null;
      var replace = true;
      if (confirmBudget != null && currentAt != null && (backupAt == null || backupAt.isBefore(currentAt))) {
        replace = await confirmBudget(backupAt, currentAt);
      }
      if (replace) await BudgetService.replaceAll(budget);
    }

    for (final ticker in (data['favorites'] as List? ?? [])) {
      if (!FavoritesService.isFavorite(ticker as String)) {
        await FavoritesService.toggle(ticker);
      }
    }


    return ImportResult(count: count, missingLogos: missingLogos, portfolios: portfolioCount);
  }

  /// Разбирает и проверяет сделки, выплаты, пополнения и планы одного
  /// портфеля. Ошибка в любой записи — FormatException, ничего не меняется.
  static _Records _parseRecords(Map src) {
    final importedDeposits = <Deposit>[];
    for (final raw in (src['deposits'] as List? ?? [])) {
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
    for (final raw in (src['purchases'] as List? ?? [])) {
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
        // Бэкапы до появления поля его не содержат — это «вся сделка».
        planQuantity: (p['planQuantity'] as num?)?.toDouble(),
      ));
    }

    final importedIncomes = <Income>[];
    for (final raw in (src['incomes'] as List? ?? [])) {
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
    for (final raw in (src['plans'] as List? ?? [])) {
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


    return _Records(
      deposits: importedDeposits,
      purchases: importedPurchases,
      incomes: importedIncomes,
      plans: importedPlans,
    );
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

/// Записи одного портфеля из бэкапа.
class _Records {
  final List<Deposit> deposits;
  final List<Purchase> purchases;
  final List<Income> incomes;
  final List<Plan> plans;

  const _Records({required this.deposits, required this.purchases, required this.incomes, required this.plans});

  int get count => deposits.length + purchases.length + incomes.length + plans.length;
}
