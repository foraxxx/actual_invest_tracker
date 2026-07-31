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

  /// Сколько уже куплено в счёт этого плана — накапливается только через
  /// галку "Учитывать в ближайшем плане этого месяца" на форме покупки,
  /// НЕ пересчитывается автоматически из всех сделок по тикеру.
  @HiveField(10)
  double purchasedQuantity;

  /// Средняя цена покупок, накопленных через ту же галку (взвешенная по
  /// количеству).
  @HiveField(11)
  double purchasedAvgPrice;

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
  });

  double? get estimatedTotal =>
      targetPrice != null ? targetPrice! * targetQuantity : null;
}
