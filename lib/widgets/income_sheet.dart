import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../design/fields.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/income.dart';
import '../services/storage_service.dart';

/// Форма новой выплаты по конкретной бумаге — открывается из её карточки.
///
/// Бумага уже известна, поэтому ни поиска, ни выбора типа нет: у облигации
/// выплата — купон, у акции и фонда — дивиденд. Кнопка есть у любой бумаги,
/// в том числе проданной: купон или дивиденд может прийти уже после продажи.
Future<void> showAddIncomeSheet(
  BuildContext context, {
  required String ticker,
  required String name,
  required bool isBond,
}) {
  final amountCtrl = TextEditingController();
  final taxCtrl = TextEditingController(text: '0');
  final type = isBond ? IncomeType.coupon : IncomeType.dividend;
  String currency = 'RUB';
  DateTime date = DateTime.now();
  String? error;

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: isBond ? 'Новый купон' : 'Новый дивиденд',
                subtitle: name,
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(controller: amountCtrl, label: 'Сумма до налога', number: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(controller: taxCtrl, label: 'Налог удержан', number: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppDateField(
                      value: date,
                      label: 'Дата',
                      lastDate: DateTime.now(),
                      firstDate: DateTime(2010),
                      onPicked: (d) => setSheetState(() => date = d),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 22),
              GradientButton(
                label: 'Добавить выплату',
                icon: Icons.check_rounded,
                colors: const [Color(0xFF0FA97E), Color(0xFF16D796)],
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.').replaceAll(' ', ''));
                  final tax = double.tryParse(taxCtrl.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0;
                  if (amount == null || amount <= 0) {
                    setSheetState(() => error = 'Укажите сумму выплаты');
                    return;
                  }
                  if (tax < 0 || tax > amount) {
                    setSheetState(() => error = 'Налог не может быть больше суммы выплаты');
                    return;
                  }
                  StorageService.addIncome(Income(
                    id: const Uuid().v4(),
                    date: date,
                    ticker: ticker.toUpperCase(),
                    name: name.trim().isEmpty ? ticker : name,
                    type: type,
                    amountGross: amount,
                    taxPaid: tax,
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
