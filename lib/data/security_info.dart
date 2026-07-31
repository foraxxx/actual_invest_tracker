import '../models/purchase.dart';

/// Запись справочника: тикер, название, тип, сектор
class SecurityInfo {
  final String ticker;
  final String name;
  final AssetType type;
  final String sector;

  const SecurityInfo({
    required this.ticker,
    required this.name,
    required this.type,
    required this.sector,
  });
}
