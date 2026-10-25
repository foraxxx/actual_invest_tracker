import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/purchase.dart';
import '../screens/ticker_detail_screen.dart';
import '../services/manual_price_service.dart';
import '../services/price_sanity_service.dart';
import '../services/storage_service.dart';

/// Правка уже сохранённой сделки — открывается и со страницы «Сделки», и из
/// карточки бумаги.
///
/// Бумагу поменять нельзя: сделка с другой бумагой — это другая сделка, её
/// проще удалить и внести заново. Всё остальное правится: покупка или
/// продажа, дата, количество, сумма, комиссия, валюта, заметка.
///
/// После сохранения пересчитывается всё, что зависит от сделки: позиции,
/// график, налоги и прогресс плана, если сделка в него засчитана.
///
/// [withTickerLink] — показать в шапке кнопку перехода в карточку бумаги:
/// нужна на странице «Сделки», где нажатие на сделку теперь открывает правку.
Future<void> showEditTradeSheet(BuildContext context, Purchase trade, {bool withTickerLink = false}) {
  final qtyCtrl = TextEditingController(text: _num(trade.quantity));
  final sumCtrl = TextEditingController(text: (trade.quantity * trade.pricePerUnit).toStringAsFixed(2));
  final feeCtrl = TextEditingController(text: _num(trade.fee));
  final noteCtrl = TextEditingController(text: trade.note ?? '');
  bool isSell = trade.isSell;
  DateTime date = trade.date;
  String currency = trade.currency;
  String? error;

  double? parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.'));

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        final qty = parse(qtyCtrl) ?? 0;
        final sum = parse(sumCtrl) ?? 0;
        final perUnit = qty > 0 ? sum / qty : 0.0;

        Future<void> save() async {
          final fee = parse(feeCtrl) ?? 0;
          if (qty <= 0 || sum <= 0) {
            setSheetState(() => error = 'Укажите количество и сумму сделки');
            return;
          }
          final problem = _sellProblem(trade, isSell: isSell, quantity: qty, date: date);
          if (problem != null) {
            final proceed = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Продаж больше, чем покупок'),
                content: Text('$problem\n\nЛишнее количество будет проигнорировано при расчётах. '
                    'Всё равно сохранить?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Отмена')),
                  FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Сохранить')),
                ],
              ),
            );
            if (proceed != true) return;
          }

          final oldDate = trade.date;
          final oldPrice = trade.pricePerUnit;
          final previousPlanId = trade.planId;

          trade
            ..isSell = isSell
            ..date = date
            ..quantity = qty
            ..pricePerUnit = perUnit
            ..fee = fee
            ..currency = currency
            ..note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();
          // Продажа в план не засчитывается: план — это покупки.
          if (isSell) {
            trade
              ..planId = null
              ..planQuantity = null;
          }
          await StorageService.updatePurchase(trade, previousPlanId: previousPlanId);

          // Цена сделки была записана в историю цен как рыночная — переносим
          // её на новую дату и цену. Старую точку убираем, только если она
          // от этой сделки и других сделок с бумагой в тот день нет.
          await _movePricePoint(trade, oldDate: oldDate, oldPrice: oldPrice);

          if (ctx.mounted) Navigator.pop(ctx);
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Правка сделки',
                subtitle: trade.name.trim().isEmpty ? trade.ticker : '${trade.name} · ${trade.ticker}',
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              if (withTickerLink)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        AppPageRoute(builder: (_) => TickerDetailScreen(ticker: trade.ticker)),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Карточка бумаги'),
                  ),
                ),
              const SizedBox(height: 16),
              SegmentedToggle<bool>(
                values: const [false, true],
                selected: isSell,
                labelOf: (v) => v ? 'Продажа' : 'Покупка',
                iconOf: (v) => v ? Icons.sell_outlined : Icons.add_shopping_cart_rounded,
                onChanged: (v) => setSheetState(() => isSell = v),
              ),
              const SizedBox(height: 12),
              AppDateField(
                value: date,
                label: 'Дата сделки',
                lastDate: DateTime.now(),
                firstDate: DateTime(2000),
                // Время сделки сохраняем: от него зависит порядок сделок в
                // один день (сначала купили, потом продали).
                onPicked: (d) => setSheetState(
                  () => date = DateTime(d.year, d.month, d.day, date.hour, date.minute, date.second),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: qtyCtrl,
                      label: 'Количество, шт',
                      number: true,
                      onChanged: (_) => setSheetState(() => error = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      controller: sumCtrl,
                      label: 'Сумма всех бумаг',
                      number: true,
                      onChanged: (_) => setSheetState(() => error = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                qty > 0 && sum > 0
                    ? 'Цена одной бумаги: ${Fmt.price(perUnit, type: trade.type)}'
                    : 'Цена одной бумаги посчитается из суммы и количества',
                style: TextStyle(fontSize: 11.5, color: ctx.dim, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: AppTextField(controller: feeCtrl, label: 'Комиссия', number: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppDropdown<String>(
                      value: currency,
                      label: 'Валюта',
                      items: const ['RUB', 'USD', 'EUR', 'CNY']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setSheetState(() => currency = v ?? 'RUB'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(controller: noteCtrl, label: 'Заметка (необязательно)'),
              if (trade.planId != null && !isSell) ...[
                const SizedBox(height: 12),
                const InfoBanner(
                  icon: Icons.flag_outlined,
                  color: AppColors.info,
                  text: 'Сделка засчитана в план — его прогресс пересчитается после сохранения.',
                ),
              ],
              if (trade.planId != null && isSell) ...[
                const SizedBox(height: 12),
                const InfoBanner(
                  icon: Icons.flag_outlined,
                  color: AppColors.warning,
                  text: 'Продажа не засчитывается в план — сделка будет убрана из него.',
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 20),
              GradientButton(
                label: 'Сохранить',
                icon: Icons.check_rounded,
                onPressed: save,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Удалить сделку?'),
                      content: const Text('Позиции, график и налоги пересчитаются без неё.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Отмена')),
                        TextButton(style: TextButton.styleFrom(foregroundColor: AppColors.negative), onPressed: () => Navigator.pop(dctx, true), child: const Text('Удалить')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await StorageService.deletePurchase(trade.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.negative),
                label: const Text('Удалить сделку', style: TextStyle(color: AppColors.negative)),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Число без лишних нулей: 10 вместо 10.0, 0.5 как есть.
String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// Не окажется ли после правки продаж больше, чем было бумаг. Прокручиваем
/// все сделки с этой бумагой по порядку, подставив правленую.
String? _sellProblem(Purchase trade, {required bool isSell, required double quantity, required DateTime date}) {
  final ticker = trade.ticker.toUpperCase();
  final list = StorageService.purchases
      .where((p) => p.ticker.toUpperCase() == ticker)
      .map((p) => p.id == trade.id ? (date: date, sell: isSell, qty: quantity) : (date: p.date, sell: p.isSell, qty: p.quantity))
      .toList()
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      // В один день сначала покупки, потом продажи.
      return (a.sell ? 1 : 0) - (b.sell ? 1 : 0);
    });
  double held = 0;
  for (final t in list) {
    held += t.sell ? -t.qty : t.qty;
    if (held < -1e-9) {
      return 'На ${Fmt.date(t.date)} продано на ${Fmt.qty(-held)} шт больше, чем было куплено.';
    }
  }
  return null;
}

Future<void> _movePricePoint(Purchase trade, {required DateTime oldDate, required double oldPrice}) async {
  final ticker = trade.ticker.toUpperCase();
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  final oldPoint = ManualPriceService.historyFor(ticker).where((p) => sameDay(p.date, oldDate));
  final pointFromThisTrade = oldPoint.any((p) => (p.price - oldPrice).abs() < 1e-6);
  final otherTradesThatDay = StorageService.purchases
      .any((p) => p.id != trade.id && p.ticker.toUpperCase() == ticker && sameDay(p.date, oldDate));
  if (pointFromThisTrade && !otherTradesThatDay) {
    await ManualPriceService.deletePoint(ticker, oldDate);
  }
  // Новая цена — только если правдоподобна, как и при вводе сделки: иначе
  // опечатка переоценила бы всю позицию в графике портфеля.
  if (PriceSanityService.canRecordAsMarketPrice(ticker, trade.pricePerUnit)) {
    await ManualPriceService.setAt(ticker, trade.date, trade.pricePerUnit);
  }
}
