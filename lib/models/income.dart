import 'package:hive/hive.dart';

part 'income.g.dart';

@HiveType(typeId: 3)
enum IncomeType {
  @HiveField(0)
  dividend,
  @HiveField(1)
  coupon,
}

/// Полученные дивиденды или купоны
@HiveType(typeId: 4)
class Income extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String ticker;

  @HiveField(3)
  String name;

  @HiveField(4)
  IncomeType type;

  @HiveField(5)
  double amountGross; // до налога

  @HiveField(6)
  double taxPaid; // удержанный налог

  @HiveField(7)
  String currency;

  @HiveField(8)
  String? note;

  Income({
    required this.id,
    required this.date,
    required this.ticker,
    required this.name,
    required this.type,
    required this.amountGross,
    this.taxPaid = 0,
    this.currency = 'RUB',
    this.note,
  });

  double get amountNet => amountGross - taxPaid;
}
