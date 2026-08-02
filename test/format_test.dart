import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/design/format.dart';
import 'package:invest_tracker/models/purchase.dart';

void main() {
  group('Fmt.price', () {
    test('uses two decimal places for regular security prices', () {
      expect(Fmt.price(123.456), '123,46');
      expect(Fmt.price(123.4), '123,4');
    });

    test('uses up to five decimal places for prices below one', () {
      expect(Fmt.price(0.123456), '0,12346');
      expect(Fmt.price(0.00001), '0,00001');
    });

    test('shows bond prices without fractional part', () {
      expect(Fmt.price(1234.56, type: AssetType.bond), '1 235');
      expect(Fmt.price(999.49, isBond: true), '999');
    });

    test('uses the same limits for editable price values', () {
      expect(Fmt.priceInput(123.456), '123.46');
      expect(Fmt.priceInput(0.123456), '0.12346');
      expect(Fmt.priceInput(1234.56, type: AssetType.bond), '1235');
    });
  });
}
