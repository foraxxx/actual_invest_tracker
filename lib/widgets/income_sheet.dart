import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/income.dart';
import '../services/analytics_service.dart';
import '../services/dividend_history_service.dart';
import '../services/dividend_tax_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/storage_service.dart';

/// Сколько должно прийти по выплате: на одну бумагу, сколько бумаг и итог
/// после налога. Для подсказки в форме и для блока «Выплата пришла?».
class ExpectedPayout {
  /// Выплата на одну бумагу до налога.
  final double perUnit;
  final double units;

  /// Дата отсечки (дивиденд) или дата купона.
  final DateTime date;
  final bool isBond;

  const ExpectedPayout({required this.perUnit, required this.units, required this.date, required this.isBond});

  double get gross => perUnit * units;
  double net(double taxRate) => gross * (1 - taxRate);
}

/// Ставка налога по умолчанию: дивиденды — 13%, купоны — без налога.
double defaultTaxRate(bool isBond) => isBond ? 0 : 0.13;

/// Выплата, которая пришла (или придёт) [paid]: дивиденд с последней отсечкой
/// не раньше чем за 45 дней, купон с датой в пределах 10 дней.
ExpectedPayout? expectedPayoutFor(String ticker, DateTime paid, {required bool isBond}) {
  if (isBond) {
    MoexPayoutLike? best;
    for (final p in PayoutForecastService.payoutsFor(ticker)) {
      if (p.kind != 'Купон' || p.amount <= 0) continue;
      final diff = paid.difference(p.date).inDays.abs();
      if (diff > 10) continue;
      if (best == null || diff < paid.difference(best.date).inDays.abs()) {
        best = MoexPayoutLike(p.date, p.amount);
      }
    }
    if (best == null) return null;
    final day = DateTime(best.date.year, best.date.month, best.date.day, 23, 59, 59);
    final units = AnalyticsService.holdingsAt(date: day)[ticker]?.qty ??
        AnalyticsService.holdingsAt(date: day)[ticker.toUpperCase()]?.qty ??
        0;
    if (units <= 0) return null;
    return ExpectedPayout(perUnit: best.amount, units: units, date: best.date, isBond: true);
  }
  final record = DividendHistoryService.of(ticker)?.paidBy(paid);
  if (record == null) return null;
  final units = DividendTaxService.sharesAtCutoff(ticker, record.date);
  if (units <= 0) return null;
  return ExpectedPayout(perUnit: record.amount, units: units, date: record.date, isBond: false);
}

/// Дата и сумма купона — без зависимости от модели биржи.
class MoexPayoutLike {
  final DateTime date;
  final double amount;
  const MoexPayoutLike(this.date, this.amount);
}

/// Число без лишних нулей и с точкой: 535.00 → «535», 0.0296 → «0.0296».
String plainNumber(double v, {int maxDecimals = 4}) {
  var s = v.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Форма выплаты по бумаге — открывается из её карточки.
///
/// Вводится то, что пришло на счёт. Сумма до налога и налог считаются сами:
/// по умолчанию 13% у дивидендов и без налога у купонов, ставку можно
/// поменять. Если выплата известна по истории — сумма подставляется сама, а
/// сверху видно, откуда она взялась.
///
/// [initialDate] и [initialAmount] — для подтверждения ожидаемой выплаты с
/// другой суммой.
Future<void> showAddIncomeSheet(
  BuildContext context, {
  required String ticker,
  required String name,
  required bool isBond,
  DateTime? initialDate,
  double? initialAmount,
  String? title,
}) {
  final amountCtrl = TextEditingController(text: initialAmount == null ? '' : Fmt.priceInput(initialAmount));
  final type = isBond ? IncomeType.coupon : IncomeType.dividend;
  String currency = 'RUB';
  DateTime date = initialDate ?? DateTime.now();
  if (date.isAfter(DateTime.now())) date = DateTime.now();
  double taxRate = defaultTaxRate(isBond);
  // Своя сумма налога вместо ставки — если брокер удержал не ровно 13%.
  double? customTax;
  bool amountTouched = initialAmount != null;
  String? error;

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        final expected = currency == 'RUB' ? expectedPayoutFor(ticker, date, isBond: isBond) : null;
        final expectedNet = expected?.net(taxRate);
        // Пока сумму не трогали — подставляем ожидаемую.
        if (!amountTouched && expectedNet != null) {
          final text = Fmt.priceInput((expectedNet * 100).round() / 100);
          // Менять текст поля во время сборки нельзя — после кадра.
          if (amountCtrl.text != text) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (amountTouched) return;
              amountCtrl.text = text;
              setSheetState(() {});
            });
          }
        }
        final net = double.tryParse(amountCtrl.text.replaceAll(',', '.').replaceAll(' ', ''));
        final tax = net == null
            ? null
            : customTax ?? (taxRate >= 1 ? 0.0 : net / (1 - taxRate) - net);
        final gross = net == null || tax == null ? null : net + tax;
        final perUnitNet = net != null && expected != null && expected.units > 0 ? net / expected.units : null;
        final unitWord = isBond ? 'облигацию' : 'акцию';
        final taxLabel = customTax != null ? 'Налог' : 'Налог ${(taxRate * 100).round()}%';

        Widget line(String a, String b, {Color? color}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(a, style: TextStyle(fontSize: 13, color: ctx.dim))),
                  Text(b, style: TextStyle(fontSize: 13, color: color)),
                ],
              ),
            );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: title ?? (isBond ? 'Новый купон' : 'Новая выплата'),
                subtitle: name,
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppDateField(
                      value: date,
                      label: 'Дата поступления',
                      lastDate: DateTime.now(),
                      firstDate: DateTime(2010),
                      onPicked: (d) => setSheetState(() => date = d),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
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
              if (expected != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: ctx.accent.withOpacity(0.12),
                    borderRadius: AppRadius.all(AppRadius.sm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: ctx.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${isBond ? 'Купон' : 'Дивиденд'} ${plainNumber(expected.perUnit)} ₽, '
                          '${isBond ? 'выплата' : 'отсечка'} ${Fmt.dayShort(expected.date)}, '
                          'у вас ${Fmt.qty(expected.units)} шт. '
                          'Ожидалось ≈ ${Fmt.money(expected.net(taxRate))}'
                          '${amountTouched ? '' : ' — подставлено'}',
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AppTextField(
                controller: amountCtrl,
                label: 'Пришло на счёт',
                number: true,
                onChanged: (_) => setSheetState(() => amountTouched = true),
              ),
              if (net != null && net > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  decoration: BoxDecoration(
                    color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
                    borderRadius: AppRadius.all(AppRadius.sm),
                  ),
                  child: Column(
                    children: [
                      if (expectedNet != null && amountTouched && (net - expectedNet).abs() >= 1)
                        line('Разница с ожидаемым', Fmt.signedMoney(net - expectedNet),
                            color: AppColors.pnl(net - expectedNet)),
                      if (gross != null) line('До налога', Fmt.money(gross, decimals: 2)),
                      if (tax != null) line(taxLabel, Fmt.money(tax, decimals: 2)),
                      if (perUnitNet != null)
                        line('На $unitWord после налога', '${plainNumber(perUnitNet)} ₽'),
                    ],
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () async {
                    final r = await _pickTax(ctx, taxRate, customTax);
                    if (r != null) {
                      setSheetState(() {
                        taxRate = r.$1;
                        customTax = r.$2;
                      });
                    }
                  },
                  child: const Text('Изменить налог'),
                ),
              ),
              if (error != null) ...[
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              GradientButton(
                label: initialDate != null ? 'Подтвердить' : 'Добавить',
                onPressed: () {
                  if (net == null || net <= 0 || gross == null || tax == null) {
                    setSheetState(() => error = 'Укажите, сколько пришло на счёт');
                    return;
                  }
                  if (tax < 0) {
                    setSheetState(() => error = 'Налог не может быть отрицательным');
                    return;
                  }
                  StorageService.addIncome(Income(
                    id: const Uuid().v4(),
                    date: date,
                    ticker: ticker.toUpperCase(),
                    name: name.trim().isEmpty ? ticker : name,
                    type: type,
                    amountGross: (gross * 100).round() / 100,
                    taxPaid: (tax * 100).round() / 100,
                    currency: currency,
                  ));
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Записать ожидаемую выплату одним нажатием: сумма — как ожидалось.
Future<void> confirmExpectedPayout({
  required String ticker,
  required String name,
  required ExpectedPayout expected,
  required DateTime paidDate,
}) async {
  final rate = defaultTaxRate(expected.isBond);
  final gross = (expected.gross * 100).round() / 100;
  final tax = (gross * rate * 100).round() / 100;
  final now = DateTime.now();
  await StorageService.addIncome(Income(
    id: const Uuid().v4(),
    date: paidDate.isAfter(now) ? now : paidDate,
    ticker: ticker.toUpperCase(),
    name: name.trim().isEmpty ? ticker : name,
    type: expected.isBond ? IncomeType.coupon : IncomeType.dividend,
    amountGross: gross,
    taxPaid: tax,
  ));
}

/// Выбор налога: ставка 0 / 13 / 15% или своя сумма. Возвращает (ставка,
/// своя сумма или null).
Future<(double, double?)?> _pickTax(BuildContext context, double rate, double? custom) {
  final ctrl = TextEditingController(text: custom == null ? '' : Fmt.priceInput(custom));
  return showDialog<(double, double?)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Налог с выплаты'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in const [0.0, 0.13, 0.15])
            Pressable(
              onTap: () => Navigator.pop(ctx, (r, null)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: Text(r == 0 ? 'Без налога' : '${(r * 100).round()}%')),
                    if (custom == null && (r - rate).abs() < 1e-9)
                      Icon(Icons.check_rounded, size: 18, color: ctx.accent),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          AppTextField(controller: ctrl, label: 'Или сумма налога, ₽', number: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        TextButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.replaceAll(',', '.').replaceAll(' ', ''));
            Navigator.pop(ctx, v == null ? null : (rate, v));
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}
