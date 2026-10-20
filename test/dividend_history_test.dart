import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/dividend_history_service.dart';

void main() {
  const dohod = '''
<html><body>
<table><tr><td>Текущая доходность</td><td>15.2%</td></tr></table>
<table>
  <tr><th>Дата объявления дивиденда</th><th>Дата закрытия реестра</th><th>Год для учета дивиденда</th><th>Дивиденд</th></tr>
  <tr><td>n/a</td><td>20.07.2099 (прогноз)</td><td>n/a</td><td>44.53</td></tr>
  <tr><td>21.04.2026</td><td>20.07.2026</td><td>2026</td><td>37.64</td></tr>
  <tr><td>22.04.2025</td><td>18.07.2025</td><td>2025</td><td>34.84</td></tr>
  <tr><td>23.04.2024</td><td>11.07.2024</td><td>2024</td><td>33.3</td></tr>
</table>
</body></html>''';

  test('разбор страницы Доход.ру', () {
    final r = DividendHistoryService.parseDohod(dohod);
    expect(r, hasLength(4));
    final forecast = r.firstWhere((e) => e.forecast);
    expect(forecast.amount, 44.53);
    expect(forecast.date, DateTime(2099, 7, 20));
    final y2026 = r.firstWhere((e) => e.date == DateTime(2026, 7, 20));
    expect(y2026.amount, 37.64);
    expect(y2026.announced, DateTime(2026, 4, 21));
    expect(y2026.forecast, isFalse);
  });

  test('разбор страницы smart-lab: будущие строки — прогноз', () {
    const html = '''
<table>
  <tr><th>Тикер</th><th>дата T-1</th><th>дата отсечки</th><th>период</th><th>дивиденд,руб</th><th>цена акции</th><th>див.доходность</th></tr>
  <tr><td>SBERP</td><td>17.07.2099</td><td>20.07.2099</td><td>2098</td><td>50,10</td><td>300</td><td>16,7%</td></tr>
  <tr><td>SBERP</td><td>17.07.2025</td><td>18.07.2025</td><td>2024</td><td>34,84</td><td>300</td><td>11,6%</td></tr>
</table>''';
    final r = DividendHistoryService.parseSmartLab(html);
    expect(r, hasLength(2));
    expect(r.first.forecast, isTrue);
    expect(r.last.amount, 34.84);
    expect(r.last.forecast, isFalse);
  });

  test('выплаты не теряются, прогноз заменяется свежим', () {
    final old = [
      DividendRecord(date: DateTime(2020, 7, 10), amount: 18.7),
      DividendRecord(date: DateTime(2099, 7, 1), amount: 40, forecast: true),
    ];
    // На сайте старой выплаты уже нет, а прогноз другой.
    final fresh = [
      DividendRecord(date: DateTime(2025, 7, 18), amount: 34.84),
      DividendRecord(date: DateTime(2099, 7, 20), amount: 44.53, forecast: true),
    ];
    final merged = DividendHistoryService.merge(old, fresh, replaceForecasts: true);
    expect(merged.map((e) => e.amount), [18.7, 34.84, 44.53]);
  });

  test('объявленная выплата убирает прогноз рядом с ней', () {
    final merged = DividendHistoryService.merge(
      [DividendRecord(date: DateTime(2099, 7, 20), amount: 44.53, forecast: true)],
      [DividendRecord(date: DateTime(2099, 7, 17), amount: 41.2, announced: DateTime(2099, 4, 20))],
      replaceForecasts: false,
    );
    expect(merged, hasLength(1));
    expect(merged.single.amount, 41.2);
    expect(merged.single.isAnnounced, isTrue);
  });

  test('без свежих данных прогноз остаётся прежним', () {
    final merged = DividendHistoryService.merge(
      [DividendRecord(date: DateTime(2099, 7, 20), amount: 44.53, forecast: true)],
      const [],
      replaceForecasts: false,
    );
    expect(merged.single.forecast, isTrue);
  });

  test('суммы по годам', () {
    final h = DividendHistory(records: [
      DividendRecord(date: DateTime(2024, 7, 11), amount: 33.3),
      DividendRecord(date: DateTime(2024, 12, 20), amount: 5),
      DividendRecord(date: DateTime(2099, 7, 20), amount: 44.53, forecast: true),
    ]);
    final by = h.byYear();
    expect(by[2024]!.paid, closeTo(38.3, 1e-9));
    expect(by[2099]!.forecast, 44.53);
  });
}
