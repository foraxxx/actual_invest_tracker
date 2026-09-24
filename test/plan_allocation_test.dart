import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/models/plan.dart';
import 'package:invest_tracker/models/purchase.dart';
import 'package:invest_tracker/services/plan_apply_service.dart';

/// Засчитывание покупки в план.
///
/// Покупка больше, чем плану осталось добрать, раньше перевыполняла его —
/// 25 из 20. Теперь в план идёт ровно недостающее, а остаток остаётся
/// обычной покупкой без плана.
void main() {
  Plan plan({double target = 20, double done = 15}) => Plan(
        id: 'p',
        ticker: 'SBER',
        name: 'Сбербанк',
        type: AssetType.stock,
        targetQuantity: target,
        createdAt: DateTime(2026, 1, 1),
        purchasedQuantity: done,
      );

  Purchase buy(double qty, {String? planId, double? planQuantity}) => Purchase(
        id: 'b',
        date: DateTime(2026, 9, 24),
        ticker: 'SBER',
        name: 'Сбербанк',
        type: AssetType.stock,
        quantity: qty,
        pricePerUnit: 284,
        planId: planId,
        planQuantity: planQuantity,
      );

  group('сколько засчитать в план', () {
    test('покупка больше остатка: только недостающее', () {
      expect(PlanApplyService.allocation(plan(), 10), 5);
    });

    test('покупка меньше остатка: вся покупка', () {
      expect(PlanApplyService.allocation(plan(), 3), 3);
    });

    test('ровно остаток: закрывает план', () {
      expect(PlanApplyService.allocation(plan(), 5), 5);
    });

    test('план уже добран — ничего', () {
      expect(PlanApplyService.allocation(plan(done: 20), 10), 0);
      expect(PlanApplyService.remaining(plan(done: 25)), 0);
    });

    test('нулевая покупка — ничего', () {
      expect(PlanApplyService.allocation(plan(), 0), 0);
    });
  });

  group('засчитанная часть сделки', () {
    test('сделка без плана ничего в план не несёт', () {
      expect(buy(10).quantityInPlan, 0);
    });

    test('пустое поле — вся сделка, как у сделок до появления поля', () {
      expect(buy(10, planId: 'p').quantityInPlan, 10);
    });

    test('частичное засчитывание', () {
      expect(buy(10, planId: 'p', planQuantity: 5).quantityInPlan, 5);
    });

    test('после уменьшения сделки засчитанное не больше самой сделки', () {
      // Сделку на 10 шт с засчитанными 5 отредактировали до 3 — в плане не
      // может числиться больше, чем куплено.
      expect(buy(3, planId: 'p', planQuantity: 5).quantityInPlan, 3);
    });
  });
}
