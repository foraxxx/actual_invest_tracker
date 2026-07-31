import '../models/deposit.dart';
import 'currency_service.dart';
import 'storage_service.dart';

/// Одно движение денег по счёту.
class CashMove {
  final DateTime date;
  final double amountRub; // + приход, − расход
  final String title;
  final CashMoveKind kind;

  /// id записи в боксе пополнений — только у ручных операций, чтобы их можно
  /// было удалить.
  final String? depositId;

  const CashMove({
    required this.date,
    required this.amountRub,
    required this.title,
    required this.kind,
    this.depositId,
  });
}

enum CashMoveKind { deposit, autoDeposit, withdrawal, buy, sell, payout }

/// Итог по счёту на сегодня.
class CashSummary {
  /// Сумма всех пополнений — и записанных вручную, и восстановленных по
  /// сделкам. Только растёт.
  final double invested;

  /// Сколько из вложенного уже вернулось на руки.
  final double withdrawn;

  /// Свободные деньги на счёте: пришли, но пока не вложены в бумаги.
  final double cash;

  /// Все полученные дивиденды и купоны, за вычетом удержанного налога.
  final double payouts;

  /// Часть [invested], которую приложение определило само по сделкам.
  final double autoInvested;

  final List<CashMove> moves;

  const CashSummary({
    required this.invested,
    required this.withdrawn,
    required this.cash,
    required this.payouts,
    required this.autoInvested,
    required this.moves,
  });

  /// Своих денег сейчас в работе. Именно от этой величины считается прибыль:
  /// выведенное уже вернулось к тебе и не должно исчезать из результата.
  double get netInvested => invested - withdrawn;
}

/// Денежный счёт портфеля.
///
/// Пополнения пользователь не записывает — приложение восстанавливает их по
/// сделкам: идём по операциям в порядке дат и держим баланс. Если на покупку
/// денег на счёте не хватает, недостающая сумма и есть пополнение в этот день.
/// Получается ровно то же число, как если бы пополнения записывались вовремя
/// и аккуратно.
///
/// Выводы автоматически определить нельзя: деньги, лежащие на счёте, ничем не
/// отличаются от снятых. Поэтому вывод — единственное, что заводится руками.
class CashService {
  CashService._();

  /// Ручная запись: положительная сумма — пополнение, отрицательная — вывод.
  /// Отдельная модель не нужна, хватает существующих «пополнений».
  static bool isWithdrawal(Deposit d) => d.amount < 0;

  static CashSummary summary() {
    final moves = <CashMove>[];

    for (final d in StorageService.deposits) {
      final rub = CurrencyService.toRub(d.amount.abs(), d.currency, date: d.date);
      final withdrawal = isWithdrawal(d);
      moves.add(CashMove(
        date: d.date,
        amountRub: withdrawal ? -rub : rub,
        title: d.note?.isNotEmpty == true
            ? d.note!
            : (withdrawal ? 'Вывод со счёта' : 'Пополнение счёта'),
        kind: withdrawal ? CashMoveKind.withdrawal : CashMoveKind.deposit,
        depositId: d.id,
      ));
    }

    for (final p in StorageService.purchases) {
      final gross = CurrencyService.toRub(p.quantity * p.pricePerUnit, p.currency, date: p.date);
      final fee = CurrencyService.toRub(p.fee, p.currency, date: p.date);
      moves.add(CashMove(
        date: p.date,
        // Комиссия платится в обе стороны: при покупке добавляется к расходу,
        // при продаже вычитается из того, что пришло на счёт.
        amountRub: p.isSell ? gross - fee : -(gross + fee),
        title: '${p.isSell ? "Продажа" : "Покупка"} ${p.ticker}',
        kind: p.isSell ? CashMoveKind.sell : CashMoveKind.buy,
      ));
    }

    for (final i in StorageService.incomes) {
      moves.add(CashMove(
        date: i.date,
        amountRub: CurrencyService.toRub(i.amountNet, i.currency, date: i.date),
        title: 'Выплата ${i.ticker}',
        kind: CashMoveKind.payout,
      ));
    }

    moves.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      // В один день сначала приходы: иначе покупка «не увидит» продажу той же
      // датой и приложение придумает лишнее пополнение.
      return b.amountRub.compareTo(a.amountRub);
    });

    double cash = 0;
    double invested = 0;
    double withdrawn = 0;
    double payouts = 0;
    double autoInvested = 0;
    final result = <CashMove>[];

    for (final m in moves) {
      switch (m.kind) {
        case CashMoveKind.deposit:
          invested += m.amountRub;
          cash += m.amountRub;
        case CashMoveKind.withdrawal:
          withdrawn += -m.amountRub;
          cash += m.amountRub;
        case CashMoveKind.payout:
          payouts += m.amountRub;
          cash += m.amountRub;
        case CashMoveKind.sell:
          cash += m.amountRub;
        case CashMoveKind.buy:
          final cost = -m.amountRub;
          if (cash + 1e-6 < cost) {
            final missing = cost - (cash < 0 ? 0 : cash);
            invested += missing;
            autoInvested += missing;
            result.add(CashMove(
              date: m.date,
              amountRub: missing,
              title: 'Пополнение под покупку',
              kind: CashMoveKind.autoDeposit,
            ));
            cash = 0;
          } else {
            cash -= cost;
          }
        case CashMoveKind.autoDeposit:
          break;
      }
      result.add(m);
    }

    result.sort((a, b) => b.date.compareTo(a.date));

    return CashSummary(
      invested: invested,
      withdrawn: withdrawn,
      cash: cash < 0 ? 0 : cash,
      payouts: payouts,
      autoInvested: autoInvested,
      moves: result,
    );
  }
}
