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
  });

  test('день выплаты: число и последний день', () {
    expect(const PayDay.day(15).inMonth(2026, 2), 15);
    expect(const PayDay.lastDay().inMonth(2026, 2), 28);
    expect(const PayDay.lastDay().inMonth(2028, 2), 29);
    expect(const PayDay.day(31).inMonth(2026, 11), 30);
  });

  test('с зарплаты, с аванса и пополам', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 25000, source: BudgetSource.salary));
    await BudgetService.saveCategory(const BudgetCategory(id: 'b', name: 'B', emoji: '•', amount: 3000, source: BudgetSource.advance));
    await BudgetService.saveCategory(const BudgetCategory(id: 'c', name: 'C', emoji: '•', amount: 4500, source: BudgetSource.half));
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.plan, [25000, 0]);
    expect(v.lineFor('b')!.plan, [0, 3000]);
    expect(v.lineFor('c')!.planTotal, 4500);
    expect(v.lineFor('c')!.plan[0], 2300);
    // 70 000 − 30 000 − 25 000 − 2 300 = 12 700; 45 000 − 30 000 − 3 000 − 2 200 = 9 800
    expect(v.rest(0), 12700);
    expect(v.rest(1), 9800);
    expect(v.freeTotal, 22500);
  });

  test('«выровнять» оставляет одинаково с обеих выплат', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 20000, source: BudgetSource.salary));
    await BudgetService.saveCategory(const BudgetCategory(id: 'inv', name: 'Инв', emoji: '•', amount: 6000, source: BudgetSource.balance));
    final v = BudgetService.view(y, m);
    // Свободно до выравнивания: 20 000 и 15 000 → 6 000 делится 5 500 / 500,
    // и с обеих выплат остаётся по 14 500.
    expect(v.lineFor('inv')!.plan, [5500, 500]);
    expect(v.rest(0), v.rest(1));
  });

  test('нехватка видна отрицательным остатком', () async {
    await BudgetService.saveCategory(const BudgetCategory(id: 'a', name: 'A', emoji: '•', amount: 16100, source: BudgetSource.advance));
    final v = BudgetService.view(y, m);
    expect(v.rest(1), -1100);
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
