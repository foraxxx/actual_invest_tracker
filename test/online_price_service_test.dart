import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/online_price_service.dart';

void main() {
  test('old cached quote remains compatible and defaults to one item per lot', () {
    final price = OnlinePrice.fromJson({
      'p': 321.5,
      't': '2026-08-02T12:00:00.000',
      'n': 'Бумага',
      'b': 'TQBR',
    });

    expect(price, isNotNull);
    expect(price!.lotSize, 1);
  });

  test('lot size is persisted with the cached quote', () {
    final price = OnlinePrice(
      price: 321.5,
      fetchedAt: DateTime(2026, 8, 2, 12),
      shortName: 'Бумага',
      board: 'TQBR',
      lotSize: 10,
    );

    expect(price.toJson()['l'], 10);
  });
}
