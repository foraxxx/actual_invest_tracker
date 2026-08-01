import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/models/purchase.dart';
import 'package:invest_tracker/services/broker_import_service.dart';

void main() {
  test('разбирает сделки, выплаты и движения из HTML Сбера', () {
    const html = '''
      <html><body>за период с 20.09.2025 по 31.12.2025
      <table>
        <tr><td>Наименование</td><td>Код</td><td>ISIN ценной бумаги</td><td>Эмитент</td><td>Вид, Категория, Тип, иная информация</td><td>Выпуск</td></tr>
        <tr><td>БалтЛизП15</td><td>RU000A10ATW2</td><td>RU000A10ATW2</td><td>Балтлизинг</td><td>Облигация</td><td></td></tr>
        <tr><td>ТКСХолд ао</td><td>T</td><td>RU000A107UL4</td><td>Т-Технологии</td><td>Акция обыкновенная</td><td></td></tr>
      </table>
      <table>
        <tr><td>Дата заключения</td><td>Дата расчетов</td><td>Время заключения</td><td>Наименование ЦБ</td><td>Код ЦБ</td><td>Валюта</td><td>Вид</td><td>Количество, шт.</td><td>Цена</td><td>Сумма</td><td>НКД</td><td>Комиссия Брокера</td><td>Комиссия Биржи</td><td>Номер сделки</td><td>Комментарий</td><td>Статус сделки</td></tr>
        <tr><td>22.09.2025</td><td>23.09.2025</td><td>10:23:31</td><td>БалтЛизП15</td><td>RU000A10ATW2</td><td>RUB</td><td>Покупка</td><td>2</td><td>108.5</td><td>2 170.00</td><td>35.06</td><td>6.51</td><td>0.19</td><td>42</td><td></td><td>ЗИ</td></tr>
      </table>
      <table>
        <tr><td>Дата</td><td>Торговая площадка</td><td>Описание операции</td><td>Валюта</td><td>Сумма зачисления</td><td>Сумма списания</td></tr>
        <tr><td>20.09.2025</td><td>Основной рынок</td><td>Зачисление д/с</td><td>RUB</td><td>2 000.00</td><td>0.00</td></tr>
        <tr><td>21.09.2025</td><td>Основной рынок</td><td>Списание д/с</td><td>RUB</td><td>0.00</td><td>500.00</td></tr>
        <tr><td>26.09.2025</td><td>Основной рынок</td><td>Зачисление д/с (купон 7 по БалтЛизП15)</td><td>RUB</td><td>116.88</td><td>0.00</td></tr>
        <tr><td>13.10.2025</td><td>Основной рынок</td><td>Дивиденды ТКСХолд ао; ISIN RU000A107UL4; Налог удержан Дополнительная информация: Дивиденды 70.00 RUR по курсу ЦБ 1</td><td>RUB</td><td>61.00</td><td>0.00</td></tr>
        <tr><td>23.09.2025</td><td>Основной рынок</td><td>Комиссия Биржи от 22.09.2025</td><td>RUB</td><td>0.00</td><td>3.16</td></tr>
      </table>
      </body></html>
    ''';

    final result = BrokerImportService.parse(
      Broker.sber,
      Uint8List.fromList(utf8.encode(html)),
    );

    expect(result.trades, hasLength(1));
    expect(result.trades.single.ticker, 'RU000A10ATW2');
    expect(result.trades.single.assetType, AssetType.bond);
    expect(result.trades.single.pricePerUnit, 1085);
    expect(result.trades.single.fee, closeTo(41.76, 0.001));

    expect(result.payouts, hasLength(2));
    final coupon = result.payouts.firstWhere((p) => p.isCoupon);
    expect(coupon.ticker, 'RU000A10ATW2');
    expect(coupon.amount, 116.88);
    final dividend = result.payouts.firstWhere((p) => !p.isCoupon);
    expect(dividend.ticker, 'T');
    expect(dividend.amount, 70);
    expect(dividend.taxPaid, 9);

    expect(result.cashMoves, hasLength(2));
    expect(result.cashMoves[0].amount, 2000);
    expect(result.cashMoves[1].amount, -500);
    expect(result.period, contains('20.09.2025'));
  });
}
