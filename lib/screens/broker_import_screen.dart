import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/broker_import_service.dart';
import '../services/moex_sync_service.dart';
import '../services/storage_service.dart';

/// Импорт сделок и выплат из отчёта брокера. Сначала выбирается брокер:
/// формат выгрузки у каждого свой, и разбирать их одинаково нельзя.
class BrokerImportScreen extends StatefulWidget {
  const BrokerImportScreen({super.key});

  @override
  State<BrokerImportScreen> createState() => _BrokerImportScreenState();
}

class _BrokerImportScreenState extends State<BrokerImportScreen> {
  Broker? _broker;
  BrokerImportResult? _result;
  String? _error;
  bool _busy = false;

  bool _importTrades = true;
  bool _importPayouts = true;
  bool _importCash = true;
  bool _replaceAll = false;
  bool _keepPlans = true;
  int _resolvedOnline = 0;

  /// Состояние портфеля на момент разбора файла. Замораживаем его, чтобы
  /// сверка не пересчитывалась по данным, которые меняются прямо во время
  /// импорта: сделки добавляются по одной, и в середине процесса портфель
  /// выглядит странно — например, бумага уже куплена, но ещё не продана.
  Map<String, double> _before = const {};
  bool _imported = false;

  Future<void> _pickFile() async {
    final broker = _broker;
    if (broker == null) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: broker.extensions,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final bytes = await File(path).readAsBytes();
      final parsed = BrokerImportService.parse(broker, bytes);
      // Что не опозналось локально — спрашиваем у биржи по ISIN. Это главный
      // способ поймать бумаги, которых уже нет в списке торгуемых.
      final resolved = await BrokerImportService.resolveOnline(parsed);
      if (!mounted) return;
      setState(() {
        _result = parsed;
        _resolvedOnline = resolved;
        _before = BrokerImportService.currentQuantities();
        _imported = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _apply() async {
    final result = _result;
    if (result == null) return;
    setState(() => _busy = true);
    try {
      if (_replaceAll) await BrokerImportService.clearPortfolio(keepPlans: _keepPlans);
      final added = await BrokerImportService.apply(
        result,
        importTrades: _importTrades,
        importPayouts: _importPayouts,
        importCash: _importCash,
      );
      // Импорт — явное действие пользователя. Сразу подтягиваем последние
      // доступные цены импортированных позиций, даже если торговая сессия
      // закрыта; иначе до ручного обновления портфель оценивался по ценам
      // сделок и показывал заниженную стоимость.
      await MoexSyncService.instance.refreshNow(force: true);
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Импорт завершён'),
          content: Text([
            'Добавлено сделок: ${added.trades}',
            'Выплат: ${added.payouts}',
            'Движений по счёту: ${added.deposits}',
            if (added.duplicates > 0) '\nУже были в портфеле: ${added.duplicates}',
            if (added.unresolved > 0)
              'Не опознаны бумаги: ${added.unresolved} — такие сделки пропущены',
          ].join('\n')),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
          ],
        ),
      );
      // Остаёмся на экране: ниже показывается сверка, и это главное, на что
      // стоит посмотреть после импорта.
      if (mounted) setState(() => _imported = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Импорт от брокера')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          Text(
            'Отчёты у брокеров устроены по-разному, поэтому сначала выбери своего — '
            'файл будет разобран по его формату.',
            style: TextStyle(fontSize: 12, height: 1.45, color: context.dim),
          ),
          const SizedBox(height: 16),

          for (final broker in Broker.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                border: Border.all(
                  color: _broker == broker ? context.accent.withOpacity(0.5) : context.hairline,
                  width: _broker == broker ? 1.4 : 1,
                ),
                onTap: () => setState(() {
                  _broker = broker;
                  _result = null;
                  _error = null;
                }),
                child: Row(
                  children: [
                    Icon(
                      _broker == broker ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 20,
                      color: _broker == broker ? context.accent : context.dim,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(broker.title,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(broker.hint,
                              style: TextStyle(fontSize: 11.5, height: 1.35, color: context.dim)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 6),
          GradientButton(
            label: _busy ? 'Читаю файл…' : 'Выбрать файл отчёта',
            icon: Icons.upload_file_rounded,
            onPressed: (_broker == null || _busy) ? null : _pickFile,
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            InfoBanner(
              icon: Icons.error_outline_rounded,
              color: AppColors.negative,
              text: 'Не удалось разобрать файл: $_error',
            ),
          ],

          if (result != null) ...[
            const SizedBox(height: 20),
            if (result.period != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  result.period!,
                  style: TextStyle(fontSize: 11, height: 1.35, color: context.dim),
                ),
              ),

            if (result.isEmpty)
              const InfoBanner(
                icon: Icons.help_outline_rounded,
                color: AppColors.warning,
                text: 'В файле не нашлось ни сделок, ни выплат. Похоже, это отчёт другого '
                    'формата — пришли его мне, добавлю разбор.',
              )
            else ...[
              FadeSlideIn(child: _summary(result)),
              const SizedBox(height: 14),
              AppCheckRow(
                value: _importTrades,
                title: 'Сделки',
                subtitle: '${result.trades.length} покупок и продаж',
                onChanged: (v) => setState(() => _importTrades = v),
              ),
              AppCheckRow(
                value: _importPayouts,
                title: 'Дивиденды и купоны',
                subtitle: '${result.payouts.length} выплат',
                onChanged: (v) => setState(() => _importPayouts = v),
              ),
              AppCheckRow(
                value: _replaceAll,
                title: 'Заменить содержимое портфеля',
                subtitle: 'Удалить все сделки, выплаты и движения денег перед импортом — '
                    'тогда портфель станет точной копией отчёта',
                onChanged: (v) => setState(() => _replaceAll = v),
              ),
              if (_replaceAll && StorageService.plans.isNotEmpty)
                AppCheckRow(
                  value: _keepPlans,
                  title: 'Сохранить мои планы',
                  subtitle: '${StorageService.plans.length} ${Fmt.plural(StorageService.plans.length, "план", "плана", "планов")} '
                      'останутся в приложении после замены портфеля',
                  onChanged: (v) => setState(() => _keepPlans = v),
                ),
              AppCheckRow(
                value: _importCash,
                title: 'Пополнения и выводы',
                subtitle: '${result.cashMoves.length} движений по счёту — '
                    'с ними «Вложено своих» станет точным',
                onChanged: (v) => setState(() => _importCash = v),
              ),

              if (_resolvedOnline > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Опознано через биржу по ISIN: $_resolvedOnline '
                '${Fmt.papers(_resolvedOnline)}.',
                style: TextStyle(fontSize: 11, color: context.dim),
              ),
            ],

            if (result.unresolvedTrades.isNotEmpty) ...[
                const SizedBox(height: 14),
                InfoBanner(
                  icon: Icons.help_outline_rounded,
                  color: AppColors.warning,
                  text: 'Не удалось определить тикер у ${result.unresolvedTrades.length} '
                      '${Fmt.plural(result.unresolvedTrades.length, "сделки", "сделок", "сделок")}. '
                      'Впиши тикеры ниже или оставь пустыми — такие строки будут пропущены. '
                      'Включённая загрузка с биржи распознаёт бумаги по ISIN.',
                ),
                const SizedBox(height: 10),
                ..._unresolvedList(result),
              ],

              if (result.holdings.isNotEmpty) ...[
                const SizedBox(height: 18),
                _reconcileBlock(result),
              ],

              const SizedBox(height: 20),
              GradientButton(
                label: _busy
                    ? 'Импортирую…'
                    : _replaceAll
                        ? 'Заменить портфель данными отчёта'
                        : 'Импортировать в портфель',
                icon: Icons.check_rounded,
                onPressed: _busy ? null : _apply,
              ),
              const SizedBox(height: 10),
              Text(
                'Повторный импорт того же файла ничего не задвоит: одинаковые записи '
                'узнаются по дате, бумаге, количеству и цене.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, height: 1.4, color: context.dim),
              ),
            ],
          ],
        ],
      ),
    );
  }


  /// Сверка: что в портфеле сейчас и что станет после импорта. Это самая
  /// полезная часть экрана — видно результат до того, как нажал кнопку.
  Widget _reconcileBlock(BrokerImportResult result) {
    // До импорта справа — расчёт, после импорта — то, что реально получилось.
    final after = _imported
        ? BrokerImportService.currentQuantities()
        : BrokerImportService.expectedAfter(result, replaceAll: _replaceAll);
    final rows = BrokerImportService.diff(_before, after);
    final changed = rows.where((r) => (r.after - r.now).abs() > 1e-9).toList();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                changed.isEmpty ? Icons.verified_rounded : Icons.rule_rounded,
                size: 18,
                color: changed.isEmpty ? AppColors.positive : context.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_imported ? 'Что получилось' : 'Что станет после импорта',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            changed.isEmpty
                ? (_imported
                    ? 'Портфель совпадает с отчётом.'
                    : 'Портфель уже совпадает с отчётом — импорт ничего не изменит.')
                : _imported
                    ? 'Слева — как было до импорта, справа — как стало. '
                        'Изменилось ${changed.length} ${Fmt.papers(changed.length)}.'
                    : 'Слева — сколько бумаг в портфеле сейчас, справа — сколько станет. '
                        'Изменится ${changed.length} ${Fmt.papers(changed.length)}.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final row in rows.take(25))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.ticker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      Fmt.qty(row.now),
                      style: TextStyle(fontSize: 12.5, color: context.dim),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded, size: 13, color: context.dim),
                    ),
                    Text(
                      Fmt.qty(row.after),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        // Позиция исчезнет — это самое заметное изменение.
                        color: row.after <= 1e-9
                            ? AppColors.negative
                            : (row.after - row.now).abs() > 1e-9
                                ? AppColors.positive
                                : null,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _replaceAll
                  ? 'С заменой содержимого портфель станет точной копией отчёта: справа '
                      'то, что показывает приложение брокера на конец периода.'
                  : 'Без замены содержимого к текущим количествам добавится только то, чего '
                      'ещё нет в портфеле. Если справа выходит не то, что показывает брокер, '
                      'включи «Заменить содержимое портфеля».',
              style: TextStyle(fontSize: 11, height: 1.4, color: context.dim),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BrokerImportResult result) {
    final buys = result.trades.where((t) => !t.isSell).length;
    final sells = result.trades.length - buys;
    final tickers = result.trades.map((t) => t.ticker).whereType<String>().toSet();
    final deposits = result.cashMoves.where((m) => m.amount > 0).fold(0.0, (s, m) => s + m.amount);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Что нашлось в файле',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _line('Покупок', '$buys'),
          _line('Продаж', '$sells'),
          _line('Бумаг распознано', '${tickers.length}'),
          _line('Выплат', '${result.payouts.length}'),
          _line('Пополнений на', Fmt.money(deposits)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: context.dim))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  /// Нераспознанные бумаги: показываем по одной строке на бумагу, а не на
  /// сделку — иначе один и тот же тикер пришлось бы вписывать десятки раз.
  List<Widget> _unresolvedList(BrokerImportResult result) {
    final byName = <String, List<ImportedTrade>>{};
    for (final t in result.unresolvedTrades) {
      byName.putIfAbsent(t.rawName, () => []).add(t);
    }

    return byName.entries.map((entry) {
      final trades = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key.split(',').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${trades.length} ${Fmt.deals(trades.length)}'
                    '${trades.first.isin.isNotEmpty ? " · ${trades.first.isin}" : ""}',
                    style: TextStyle(fontSize: 10.5, color: context.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 118,
              child: AppTextField(
                controller: TextEditingController(text: trades.first.ticker ?? ''),
                label: 'Тикер',
                onChanged: (v) {
                  final ticker = v.trim().toUpperCase();
                  for (final t in trades) {
                    t.ticker = ticker.isEmpty ? null : ticker;
                  }
                },
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
