import 'package:hive/hive.dart';
import 'purchase.dart';

part 'plan.g.dart';

@HiveType(typeId: 5)
enum PlanStatus {
  @HiveField(0)
  active,
  @HiveField(1)
  done,
  @HiveField(2)
  cancelled,
}

/// Плановая (будущая) покупка
@HiveType(typeId: 6)
class Plan extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String ticker;

  @HiveField(2)
  String name;

  @HiveField(3)
  AssetType type;

  @HiveField(4)
  double targetQuantity;

  @HiveField(5)
  double? targetPrice; // желаемая цена входа, опционально

  @HiveField(6)
  DateTime? targetDate; // к какой дате хочет успеть

  @HiveField(7)
  PlanStatus status;

  @HiveField(8)
  String? note;

  @HiveField(9)
  DateTime createdAt;

  /// Сколько уже куплено в счёт этого плана. Пересчитывается StorageService
  /// из сделок, у которых Purchase.planId == этот план (галка "учитывать
  /// в плане" на форме покупки) — не ручной счётчик, поэтому удаление или
  /// правка такой сделки автоматически обновляет и это значение. Поле
  /// оставлено как обычный Hive-field (не getter) ради совместимости со
  /// старыми бэкапами, где оно действительно копилось вручную.
  @HiveField(10)
  double purchasedQuantity;

  /// Средняя цена сделок, засчитанных в план (взвешенная по количеству) —
  /// см. purchasedQuantity.
  @HiveField(11)
  double purchasedAvgPrice;

  /// План «на месяц»: купить в течение месяца, а не к конкретному числу.
  /// Тогда [targetDate] — последний день этого месяца. null у старых планов
  /// значит «к дате».
  @HiveField(12)
  bool? wholeMonth;

  bool get isMonthPlan => wholeMonth == true;

  Plan({
    required this.id,
    required this.ticker,
    required this.name,
    required this.type,
    required this.targetQuantity,
    this.targetPrice,
    this.targetDate,
    this.status = PlanStatus.active,
    this.note,
    required this.createdAt,
    this.purchasedQuantity = 0.0,
    this.purchasedAvgPrice = 0.0,
    this.wholeMonth,
  });

  double? get estimatedTotal =>
      targetPrice != null ? targetPrice! * targetQuantity : null;

  /// Отдельная копия — чтобы вернуть удалённый план.
  Plan copy() => Plan(
        id: id,
        ticker: ticker,
        name: name,
        type: type,
        targetQuantity: targetQuantity,
        targetPrice: targetPrice,
        targetDate: targetDate,
        status: status,
        note: note,
        createdAt: createdAt,
        purchasedQuantity: purchasedQuantity,
        purchasedAvgPrice: purchasedAvgPrice,
        wholeMonth: wholeMonth,
      );
}
