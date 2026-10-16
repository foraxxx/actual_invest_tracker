import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/goal_service.dart';
import 'package:invest_tracker/services/passive_goal_service.dart';
import 'package:invest_tracker/services/payout_picker_service.dart';

/// Цель «пассивный доход» и подбор облигаций по месяцу выплаты.
void main() {
  PassiveMonth month(int m, double sure, [double est = 0]) => PassiveMonth(
        month: DateTime(2027, m),
        sure: {if (sure > 0) 'A': sure},
        estimated: {if (est > 0) 'B': est},
      );

  PassivePlan plan(PassiveMode mode) => PassivePlan(
        goal: PassiveGoal(monthly: 30000, mode: mode),
        months: [for (int m = 1; m <= 12; m++) month(m, m == 1 ? 4600 : 12000, m == 6 ? 2000 : 0)],
        value: 1900000,
        saving: 40000,
        rate: 0,
      );

  test('цель сохраняется и читается', () {
    const g = PassiveGoal(monthly: 30000, mode: PassiveMode.everyMonth, monthlySaving: 40000, name: 'Вторая зарплата');
    final back = PassiveGoal.fromJson(g.toJson())!;
    expect(back.monthly, 30000);
    expect(back.mode, PassiveMode.everyMonth);
    expect(back.monthlySaving, 40000);
    expect(back.name, 'Вторая зарплата');
    expect(PassiveGoal.fromJson({'i': 0}), isNull);
  });

  test('в среднем — выплаты за год ÷ 12, оценки тоже входят', () {
    final p = plan(PassiveMode.average);
    expect(p.annual, 4600 + 12000 * 11 + 2000);
    expect(p.current, closeTo(p.annual / 12, 1e-6));
    expect(p.neededCapital, closeTo(1900000 * 30000 / p.current, 1e-3));
  });

  test('каждый месяц — по самому слабому месяцу', () {
    final p = plan(PassiveMode.everyMonth);
    expect(p.weakest?.month.month, 1);
    expect(p.current, 4600);
    expect(p.neededCapital! > plan(PassiveMode.average).neededCapital!, isTrue);
  });

  test('без роста дорастаем взносами', () {
    final p = plan(PassiveMode.average);
    final need = p.neededCapital! - p.value;
    expect(p.reachMonths, (need / 40000).ceil());
  });

  test('облигация попадает в месяц по графику купонов', () {
    final rows = [
      {
        'SECID': 'BOND1',
        'SHORTNAME': 'Облигация 1',
        'BOARD': 'TQCB',
        'FACEUNIT': 'SUR',
        'FACEVALUE': 1000,
        'COUPONVALUE': 40.0,
        'COUPONPERIOD': 91,
        'NEXTCOUPON': '2026-11-10',
        'MATDATE': '2030-01-01',
        'LAST': 99.0,
        'ACCRUEDINT': 5.0,
        'YIELD': 17.5,
        'LISTLEVEL': 2,
      },
      {
        'SECID': 'BOND2',
        'SHORTNAME': 'Гасится раньше',
        'BOARD': 'TQCB',
        'FACEUNIT': 'SUR',
        'FACEVALUE': 1000,
        'COUPONVALUE': 30.0,
        'COUPONPERIOD': 91,
        'NEXTCOUPON': '2026-11-10',
        'MATDATE': '2026-12-01',
        'LAST': 99.0,
        'YIELD': 16.0,
        'LISTLEVEL': 1,
      },
    ];
    // 10 ноября + 91 день = 9 февраля.
    final feb = PayoutPickerService.bondsFromRows(rows, DateTime(2027, 2));
    expect(feb.map((b) => b.secid), ['BOND1']);
    expect(feb.single.couponDate, DateTime(2027, 2, 9));
    expect(feb.single.price, closeTo(995, 1e-6));
    expect(PayoutPickerService.bondsFromRows(rows, DateTime(2027, 1)), isEmpty);
  });

  test('взносами без роста цель достигается за нужное число месяцев', () {
    expect(GoalService.monthsToReach(current: 0, target: 100, monthly: 10, rate: 0), 10);
  });
}
