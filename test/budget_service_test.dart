import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/services/budget_service.dart';

void main() {
  late Directory hiveDir;
  final now = DateTime.now();
  final y = now.year;
  final m = now.month;
  final nextY = m == 12 ? y + 1 : y;
  final nextM = m == 12 ? 1 : m + 1;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('invest_tracker_budget_test_');
    Hive.init(hiveDir.path);
    await BudgetService.init();
  });

  setUp(() async {
    await BudgetService.replaceAll(const {});
    await BudgetService.ensureStarted();
    // Только свои категории — стандартные без сумм не мешают, но так проще.
    for (final c in BudgetService.categories) {
      await BudgetService.deleteCategory(c.id);
    }
    await BudgetService.saveMonth(
      year: y,
      month: m,
      income: [70000, 45000],
      dayOverride: [null, null],
      living: 30000,
      extras: const [],
    );
  });

  test('стандартные категории создаются при первом входе', () async {
    await BudgetService.replaceAll(const {});
    await BudgetService.ensureStarted();
    expect(BudgetService.categories.map((c) => c.name), contains('Инвестиции'));
    expect(BudgetService.categories, hasLength(12));
    expect(BudgetService.categories.firstWhere((c) => c.name == 'Интернет').isPayment, isTrue);
  });

  test('день выплаты: число и последний день', () {
    expect(const PayDay.day(15).inMonth(2026, 2), 15);
    expect(const PayDay.lastDay().inMonth(2026, 2), 28);
    expect(const PayDay.lastDay().inMonth(2028, 2), 29);
    expect(const PayDay.day(31).inMonth(2026, 11), 30);
  });

  test('сначала пополам, потом авто туда, где свободнее', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 25000));
    await BudgetService.saveCategory(const BudgetCategory(id: 'b', name: 'B', emoji: '•', amount: 3000));
    await BudgetService.saveCategory(const BudgetCategory(id: 'c', name: 'C', emoji: '•', amount: 4500, source: BudgetSource.half));
    final v = BudgetService.view(y, m);
    // Свободно 40 000 и 15 000. «Пополам» 2 300 + 2 200 → 37 700 и 12 800.
    // A целиком с зарплаты → 12 700 и 12 800, B целиком с аванса.
    expect(v.lineFor('c')!.plan, [2300, 2200]);
    expect(v.lineFor('a')!.plan, [25000, 0]);
    expect(v.lineFor('b')!.plan, [0, 3000]);
    expect(v.rest(0), 12700);
    expect(v.rest(1), 9800);
    expect(v.freeTotal, 22500);
  });

  test('авто делит категорию, только если целиком не помещается', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 30000));
    await BudgetService.saveCategory(const BudgetCategory(id: 'b', name: 'B', emoji: '•', amount: 20000));
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.plan, [30000, 0]);
    // После A свободно 10 000 и 15 000: B целиком не влезает никуда.
    expect(v.lineFor('b')!.plan, [5000, 15000]);
  });

  test('нехватка видна отрицательным остатком', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 60000));
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.plan, [40000, 20000]);
    expect(v.rest(1), -5000);
  });

  test('с зарплаты и с аванса — целиком, даже если там тесно', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 20000, source: BudgetSource.advance));
    await BudgetService.saveCategory(const BudgetCategory(id: 'b', name: 'B', emoji: '•', amount: 3000, source: BudgetSource.salary));
    await BudgetService.saveCategory(const BudgetCategory(id: 'c', name: 'C', emoji: '•', amount: 4000));
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.plan, [0, 20000]);
    expect(v.lineFor('b')!.plan, [3000, 0]);
    // Авто — туда, где свободнее: 37 000 против −5 000.
    expect(v.lineFor('c')!.plan, [4000, 0]);
    expect(v.rest(1), -5000);
  });

  test('выплата только на один месяц', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 4000));
    await BudgetService.setMonthSource(y, m, 'a', BudgetSource.advance);
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [0, 4000]);
    expect(BudgetService.view(nextY, nextM).lineFor('a')!.plan, [4000, 0]);
    await BudgetService.setMonthSource(y, m, 'a', null);
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [4000, 0]);
  });

  test('сброс месяца убирает всё и откатывает переносы', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 4000));
    await BudgetService.setMonthAmount(y, m, 'a', 6000);
    await BudgetService.addEntry(y, m, 'a', 0, 1000);
    await BudgetService.moveToNext(y, m, 'a');
    expect(BudgetService.view(nextY, nextM).lineFor('a')!.carryTotal, 5000);

    await BudgetService.resetMonth(y, m);
    final v = BudgetService.view(y, m);
    expect(v.stored, isTrue);
    expect(v.lineFor('a')!.planTotal, 4000);
    expect(v.lineFor('a')!.doneTotal, 0);
    // Суммы выплат взялись из соседнего месяца.
    expect(v.data.income, [70000, 45000]);
    expect(BudgetService.view(nextY, nextM).lineFor('a')!.carryTotal, 0);
  });

  test('после отметки авто не перекладывает категорию', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 5000));
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [5000, 0]);
    await BudgetService.markLeft(y, m, 'a', payout: 0);
    // Зарплата стала меньше аванса — без фиксации «A» уехала бы на аванс.
    await BudgetService.saveMonth(
      year: y,
      month: m,
      income: [35000, 45000],
      dayOverride: [null, null],
      living: 30000,
      extras: const [],
    );
    final line = BudgetService.view(y, m).lineFor('a')!;
    expect(line.plan, [5000, 0]);
    expect(line.cellDone(0), isTrue);
    // Отметку сняли — категория снова раскладывается сама.
    await BudgetService.clearCell(y, m, 'a', 0);
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [0, 5000]);
  });

  test('доли округляются до сотни', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 5000, source: BudgetSource.half));
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [2500, 2500]);
    await BudgetService.markLeft(y, m, 'a', payout: 0);
    // Сумма поменялась после отметки — доли те же, но круглые.
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 3333, source: BudgetSource.half));
    final plan = BudgetService.view(y, m).lineFor('a')!.plan;
    expect(plan[0] % 100, 0);
    expect(plan[0] + plan[1], 3333);
  });

  test('трата из копилки уменьшает накопленное', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'c', name: 'C', emoji: '•', amount: 1000));
    await BudgetService.addEntry(y, m, 'c', 0, 10000);
    expect(BudgetService.balance('c'), 10000);
    final id = await BudgetService.addSpend('c', 4000, now);
    expect(BudgetService.balance('c'), 6000);
    await BudgetService.deleteSpend(id!);
    expect(BudgetService.balance('c'), 10000);
  });

  test('цель достигнута и срок прошёл', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'c', name: 'C', emoji: '•', amount: 1000, target: 5000));
    expect(BudgetService.goalReached(BudgetService.category('c')!), isFalse);
    await BudgetService.addEntry(y, m, 'c', 0, 5000);
    expect(BudgetService.goalReached(BudgetService.category('c')!), isTrue);

    final past = DateTime(y, m - 2);
    await BudgetService.saveCategory(BudgetCategory(
      id: 'old',
      name: 'Old',
      emoji: '•',
      mode: BudgetMode.toDate,
      target: 9000,
      targetYear: past.year,
      targetMonth: past.month,
    ));
    expect(BudgetService.overdueShortfall(BudgetService.category('old')!), 9000);
    // У платежа целей нет.
    await BudgetService.saveCategory(
        const BudgetCategory(id: 'p', name: 'P', emoji: '•', amount: 500, target: 100, kind: BudgetKind.payment));
    expect(BudgetService.goalReached(BudgetService.category('p')!), isFalse);
  });

  test('отложить всё с выплаты', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 3000, source: BudgetSource.half));
    await BudgetService.saveCategory(const BudgetCategory(id: 'b', name: 'B', emoji: '•', amount: 2000, source: BudgetSource.salary));
    final ids = await BudgetService.markAllPayout(y, m, 0);
    expect(ids, hasLength(2));
    final v = BudgetService.view(y, m);
    expect(v.doneFor(0), 3500);
    expect(v.doneFor(1), 0);
  });

  test('своя сумма на месяц и «убрать из месяца»', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 3000));
    await BudgetService.setMonthAmount(y, m, 'a', 0);
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 0);
    // В следующем месяце — обычная сумма.
    expect(BudgetService.view(nextY, nextM).lineFor('a')!.planTotal, 3000);
    await BudgetService.setMonthAmount(y, m, 'a', 5000);
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 5000);
    await BudgetService.setMonthAmount(y, m, 'a', null);
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 3000);
  });

  test('отметка, снятие и перенос на следующий месяц', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 5000, source: BudgetSource.half));
    final ids = await BudgetService.markLeft(y, m, 'a', payout: 0);
    expect(ids, hasLength(1));
    var line = BudgetService.view(y, m).lineFor('a')!;
    expect(line.cellDone(0), isTrue);
    expect(line.doneTotal, 2500);

    await BudgetService.addEntry(y, m, 'a', 1, 1000);
    await BudgetService.moveToNext(y, m, 'a');
    line = BudgetService.view(y, m).lineFor('a')!;
    expect(line.planTotal, 3500);
    expect(line.leftTotal, 0);
    final next = BudgetService.view(nextY, nextM).lineFor('a')!;
    expect(next.carryTotal, 1500);
    expect(next.planTotal, 6500);

    await BudgetService.undoMove(y, m, 'a');
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 5000);
    expect(BudgetService.view(nextY, nextM).lineFor('a')!.carryTotal, 0);

    await BudgetService.clearCell(y, m, 'a', 0);
    expect(BudgetService.view(y, m).lineFor('a')!.done[0], 0);
  });

  test('остаток направляется в категорию', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 0));
    await BudgetService.direct(y, m, 'a', 10000);
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.planTotal, 10000);
    // Сначала с зарплаты — там свободно больше.
    expect(v.lineFor('a')!.plan[0], 10000);
    await BudgetService.undoDirect(y, m, 'a');
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 0);
  });

  test('копить к дате: остаток цели на оставшиеся месяцы', () async {
    final ty = y + 1;
    await BudgetService.saveCategory(BudgetCategory(
      id: 'trip',
      name: 'Отпуск',
      emoji: '•',
      mode: BudgetMode.toDate,
      target: 60000,
      targetYear: ty,
      targetMonth: m,
    ));
    // 13 месяцев включая текущий: 60 000 / 13 ≈ 4 616 → 4 700.
    expect(BudgetService.view(y, m).lineFor('trip')!.planTotal, 4700);
  });

  test('бэкап бюджета восстанавливается', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 5000));
    await BudgetService.markLeft(y, m, 'a');
    final dump = BudgetService.exportAll();
    await BudgetService.replaceAll(const {});
    expect(BudgetService.categories, isEmpty);
    await BudgetService.replaceAll(dump);
    expect(BudgetService.category('a')?.name, 'A');
    expect(BudgetService.savedTotal('a'), 5000);
  });

  test('годовые итоги', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 4000));
    await BudgetService.markLeft(y, m, 'a');
    final totals = BudgetService.yearTotals(y);
    expect(totals.single.$2, 4000);
    expect(totals.single.$3, 4000);
    expect(BudgetService.status(y, m).state, BudgetMonthState.current);
  });
}
