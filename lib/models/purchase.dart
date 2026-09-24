import 'package:hive/hive.dart';

part 'purchase.g.dart';

@HiveType(typeId: 1)
enum AssetType {
  @HiveField(0)
  stock, // акция
  @HiveField(1)
  bond, // облигация
  @HiveField(2)
  etf, // фонд
  @HiveField(3)
  currency, // валюта
  @HiveField(4)
  other,
}

/// Покупка (или продажа, если quantity отрицательное — опционально) актива
@HiveType(typeId: 2)
class Purchase extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String ticker; // например SBER, AAPL, RU000A1023T8

  @HiveField(3)
  String name; // человекочитаемое имя

  @HiveField(4)
  AssetType type;

  @HiveField(5)
  double quantity;

  @HiveField(6)
  double pricePerUnit;

  @HiveField(7)
  double fee; // комиссия брокера

  @HiveField(8)
  String currency;

  @HiveField(9)
  String? note;

  @HiveField(10)
  String? sector; // сектор экономики, для статистики по отраслям

  @HiveField(11)
  bool isSell; // true — это продажа, false — покупка

  /// Если сделка засчитана в план (галка "учитывать в плане" на форме) —
  /// id этого плана. По нему PlanApplyService/StorageService пересчитывают
  /// прогресс плана из фактических сделок, а не из отдельного счётчика —
  /// поэтому удаление или правка сделки не расходится с прогрессом плана.
  @HiveField(12)
  String? planId;

  /// Сколько бумаг из сделки засчитано в план [planId]. null — вся сделка.
  ///
  /// Нужно, когда покупка больше, чем плану осталось добрать: в план идёт
  /// ровно недостающее, а остаток остаётся обычной покупкой без плана.
  /// Раньше план в таком случае становился перевыполненным — 25 из 20.
  ///
  /// Поле необязательное намеренно: у всех прежних сделок оно пустое и
  /// означает «вся сделка», как и было. Переносить данные не нужно, старые
  /// бэкапы читаются без изменений.
  @HiveField(13)
  double? planQuantity;

  /// Сколько бумаг сделки фактически идёт в план: не больше самой сделки,
  /// даже если её потом отредактировали и уменьшили.
  double get quantityInPlan {
    if (planId == null) return 0;
    final q = planQuantity;
    return q == null ? quantity : q.clamp(0, quantity).toDouble();
  }

  Purchase({
    required this.id,
    required this.date,
    required this.ticker,
    required this.name,
    required this.type,
    required this.quantity,
    required this.pricePerUnit,
    this.fee = 0,
    this.currency = 'RUB',
    this.note,
    this.sector,
    this.isSell = false,
    this.planId,
    this.planQuantity,
  });

  /// Знаковое количество: продажа уменьшает позицию
  double get signedQuantity => isSell ? -quantity : quantity;

  /// Денежный поток сделки: покупка — расход (отрицательный), продажа — приход (положительный)
  double get cashFlow => isSell ? (quantity * pricePerUnit - fee) : -(quantity * pricePerUnit + fee);

  /// Денежная сумма операции после комиссии.
  ///
  /// Для покупки это полная сумма списания, для продажи — чистая сумма
  /// зачисления. В отличие от старого [total], корректно работает для обеих
  /// сторон сделки.
  double get settlementAmount =>
      isSell ? quantity * pricePerUnit - fee : quantity * pricePerUnit + fee;

  /// Историческое имя оставлено для совместимости с UI. Новые расчёты должны
  /// использовать [settlementAmount].
  double get total => quantity * pricePerUnit + fee;
}
