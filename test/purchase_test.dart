import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/models/purchase.dart';

Purchase trade({required bool sell}) => Purchase(
      id: sell ? 'sell' : 'buy',
      date: DateTime(2024),
      ticker: 'TEST',
      name: 'Test',
      type: AssetType.stock,
      quantity: 10,
      pricePerUnit: 100,
      fee: 5,
      isSell: sell,
    );

void main() {
  test('покупка включает комиссию в списание', () {
    expect(trade(sell: false).settlementAmount, 1005);
    expect(trade(sell: false).cashFlow, -1005);
  });

  test('продажа вычитает комиссию из зачисления', () {
    expect(trade(sell: true).settlementAmount, 995);
    expect(trade(sell: true).cashFlow, 995);
  });
}
