import 'package:hive/hive.dart';

part 'deposit.g.dart';

/// Пополнение брокерского счёта
@HiveType(typeId: 0)
class Deposit extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  double amount;

  @HiveField(3)
  String currency; // RUB, USD, EUR...

  @HiveField(4)
  String? note;

  @HiveField(5)
  String? broker; // например "Т-Инвестиции", "Финам" и тд

  Deposit({
    required this.id,
    required this.date,
    required this.amount,
    this.currency = 'RUB',
    this.note,
    this.broker,
  });
}
