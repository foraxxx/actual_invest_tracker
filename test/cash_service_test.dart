import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/cash_service.dart';

void main() {
  test('денежные показатели считаются только внутри выбранного периода', () {
    final summary = CashSummary(
      invested: 350,
      withdrawn: 40,
      cash: 0,
      payouts: 30,
      autoInvested: 50,
      moves: [
        CashMove(
          date: DateTime(2025, 1, 1),
          amountRub: 100,
          title: 'Старое пополнение',
          kind: CashMoveKind.deposit,
        ),
        CashMove(
          date: DateTime(2025, 7, 1),
          amountRub: 200,
          title: 'Пополнение',
          kind: CashMoveKind.deposit,
        ),
        CashMove(
          date: DateTime(2025, 8, 1),
          amountRub: 50,
          title: 'Автопополнение',
          kind: CashMoveKind.autoDeposit,
        ),
        CashMove(
          date: DateTime(2025, 9, 1),
          amountRub: -40,
          title: 'Вывод',
          kind: CashMoveKind.withdrawal,
        ),
        CashMove(
          date: DateTime(2025, 10, 1),
          amountRub: 30,
          title: 'Выплата',
          kind: CashMoveKind.payout,
        ),
      ],
    );

    final period = CashService.periodSummary(
      summary,
      from: DateTime(2025, 6, 1),
    );

    expect(period.invested, 250);
    expect(period.withdrawn, 40);
    expect(period.payouts, 30);
  });
}
