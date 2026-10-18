import 'dart:convert';
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
  final prevY = m == 1 ? y - 1 : y;
  final prevM = m == 1 ? 12 : m - 1;

  Future<void> cat(String id) => BudgetService.saveCategory(BudgetCategory(id: id, name: id, emoji: '•'));
  Future<void> item(String id, double amount, [BudgetSource source = BudgetSource.auto]) =>
      BudgetService.setItem(y, m, id, BudgetItem(amount: amount, source: source));

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('invest_tracker_budget_test_');
    Hive.init(hiveDir.path);
    await BudgetService.init();
  });

  setUp(() async {
    await BudgetService.replaceAll(const {});
    await BudgetService.ensureStarted();
    for (final id in ['a', 'b', 'c']) {
      await cat(id);
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

  test('сначала пополам и закреплённые, потом авто туда, где свободнее', () async {
    await item('a', 25000);
    await item('b', 3000);
    await item('c', 4500, BudgetSource.half);
    final v = BudgetService.view(y, m);
    // Свободно 40 000 и 15 000. «Пополам» 2 300 + 2 200 → 37 700 и 12 800.
    expect(v.lineFor('c')!.plan, [2300, 2200]);
    expect(v.lineFor('a')!.plan, [25000, 0]);
    expect(v.lineFor('b')!.plan, [0, 3000]);
    expect(v.rest(0), 12700);
    expect(v.rest(1), 9800);
  });

  test('авто делит трату, только если целиком не помещается', () async {
    await item('a', 30000);
    await item('b', 20000);
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.plan, [30000, 0]);
    expect(v.lineFor('b')!.plan, [5000, 15000]);
  });

  test('с аванса — целиком, даже если не хватает', () async {
    await item('a', 20000, BudgetSource.advance);
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.plan, [0, 20000]);
    expect(v.rest(1), -5000);
  });

  test('одна трата на категорию: повторная заменяет', () async {
    await item('a', 3000);
    await item('a', 5000);
    final v = BudgetService.view(y, m);
    expect(v.lines.where((l) => l.category.id == 'a'), hasLength(1));
    expect(v.lineFor('a')!.planTotal, 5000);
  });

  test('убрать трату вместе с отметками и вернуть', () async {
    await item('a', 3000);
    await BudgetService.markLeft(y, m, 'a');
    final before = BudgetService.monthData(y, m)!;
    await BudgetService.removeItem(y, m, 'a');
    expect(BudgetService.view(y, m).lineFor('a'), isNull);
    await BudgetService.restoreMonth(before);
    expect(BudgetService.view(y, m).lineFor('a')!.doneTotal, 3000);
  });

  test('после отметки авто не перекладывает трату', () async {
    await item('a', 5000);
    await BudgetService.markLeft(y, m, 'a', payout: 0);
    await BudgetService.saveMonth(
      year: y,
      month: m,
      income: [35000, 45000],
      dayOverride: [null, null],
      living: 30000,
      extras: const [],
    );
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [5000, 0]);
    await BudgetService.clearCell(y, m, 'a', 0);
    expect(BudgetService.view(y, m).lineFor('a')!.plan, [0, 5000]);
  });

  test('перенос на следующий месяц не заполняет его', () async {
    await item('a', 5000, BudgetSource.half);
    await BudgetService.markLeft(y, m, 'a', payout: 0);
    await BudgetService.moveToNext(y, m, 'a');
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 2500);
    final next = BudgetService.view(nextY, nextM);
    expect(next.filled, isFalse);
    expect(next.lineFor('a')!.carryTotal, 2500);
    await BudgetService.undoMove(y, m, 'a');
    expect(BudgetService.view(y, m).lineFor('a')!.planTotal, 5000);
    expect(BudgetService.monthData(nextY, nextM), isNull);
  });

  test('будущий месяц пустой, копирование переносит доходы и траты без отметок', () async {
    await item('a', 4000);
    await BudgetService.markLeft(y, m, 'a');
    expect(BudgetService.view(nextY, nextM).filled, isFalse);
    await BudgetService.copyMonth((y, m), (nextY, nextM));
    final next = BudgetService.view(nextY, nextM);
    expect(next.filled, isTrue);
    expect(next.data.income, [70000, 45000]);
    expect(next.lineFor('a')!.planTotal, 4000);
    expect(next.doneTotal, 0);
  });

  test('сброс месяца делает его пустым', () async {
    await item('a', 4000);
    await BudgetService.markLeft(y, m, 'a');
    await BudgetService.resetMonth(y, m);
    final v = BudgetService.view(y, m);
    expect(v.filled, isFalse);
    expect(v.lines, isEmpty);
    expect(v.data.income, [0, 0]);
  });

  test('отложить всё с выплаты', () async {
    await item('a', 3000, BudgetSource.half);
    await item('b', 2000, BudgetSource.salary);
    final ids = await BudgetService.markAllPayout(y, m, 0);
    expect(ids, hasLength(2));
    final v = BudgetService.view(y, m);
    expect(v.doneFor(0), 3500);
    expect(v.doneFor(1), 0);
  });

  test('нераспределённое добавляется к трате', () async {
    await item('a', 1000);
    await BudgetService.addToItem(y, m, 'a', 2000);
    await BudgetService.addToItem(y, m, 'b', 500);
    final v = BudgetService.view(y, m);
    expect(v.lineFor('a')!.planTotal, 3000);
    expect(v.lineFor('b')!.planTotal, 500);
  });

  test('старый формат переводится в траты месяца', () async {
    final dump = <String, String>{
      'cats': jsonEncode([
        {'id': 'x', 'n': 'Отпуск', 'e': '•', 'm': 'monthly', 'a': 5000, 's': 'half'},
        {'id': 'z', 'n': 'Зал', 'e': '•', 'm': 'monthly', 'a': 0, 's': 'auto'},
      ]),
      'm:${BudgetService.monthKey(y, m)}': jsonEncode({
        'y': y,
        'm': m,
        'i': [70000, 45000],
        'l': 30000,
        'a': {'z': 3000},
        'e': [],
      }),
      'm:${BudgetService.monthKey(prevY, prevM)}': jsonEncode({
        'y': prevY,
        'm': prevM,
        'i': [70000, 45000],
        'l': 30000,
        'f': {
          'x': [1000, 1500],
        },
        'e': [],
      }),
    };
    await BudgetService.replaceAll(dump);
    final cur = BudgetService.view(y, m);
    expect(cur.filled, isTrue);
    expect(cur.lineFor('x')!.source, BudgetSource.half);
    expect(cur.lineFor('x')!.planTotal, 5000);
    expect(cur.lineFor('z')!.planTotal, 3000);
    final prev = BudgetService.view(prevY, prevM);
    expect(prev.lineFor('x')!.plan, [1000, 1500]);
    expect(BudgetService.category('x')!.name, 'Отпуск');
  });
}
