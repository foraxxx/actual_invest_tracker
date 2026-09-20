import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/price_sanity_service.dart';

/// Проверка цены сделки на правдоподобность.
///
/// Задача теста — зафиксировать границу, за которой цена считается опечаткой.
/// Она важна в обе стороны: слишком строгий порог начнёт мешать записывать
/// настоящие сделки, слишком мягкий пропустит ошибку, которая переоценит всю
/// позицию в истории портфеля.
void main() {
  group('порог подозрительной цены', () {
    test('обычное расхождение с рынком проходит', () {
      // Реальная сделка почти никогда не совпадает с текущей котировкой
      // копейка в копейку — проценты расхождения это норма.
      expect(PriceSanityService.isSuspicious(548.10, 543.59), isFalse);
      expect(PriceSanityService.isSuspicious(500.0, 543.59), isFalse);
      expect(PriceSanityService.isSuspicious(700.0, 543.59), isFalse);
    });

    test('цена втрое ниже рыночной отбраковывается', () {
      // Тот самый случай: продажа ОФЗ записана по 193.76 вместо 548 —
      // из-за этого переоценилась вся позиция и график провалился.
      expect(PriceSanityService.isSuspicious(193.76, 548.10), isTrue);
    });

    test('лишний ноль отбраковывается', () {
      expect(PriceSanityService.isSuspicious(5481.0, 548.10), isTrue);
    });

    test('ровно на границе считается подозрительной', () {
      expect(PriceSanityService.isSuspicious(200.0, 100.0), isTrue);
      expect(PriceSanityService.isSuspicious(50.0, 100.0), isTrue);
    });

    test('чуть внутри границы проходит', () {
      expect(PriceSanityService.isSuspicious(199.0, 100.0), isFalse);
      expect(PriceSanityService.isSuspicious(50.5, 100.0), isFalse);
    });

    test('без рыночной цены сравнивать не с чем — пропускаем', () {
      // Бумага, которой нет ни в котировках, ни в истории цен: запретить ввод
      // было бы хуже, чем пропустить возможную опечатку.
      expect(PriceSanityService.isSuspicious(193.76, null), isFalse);
      expect(PriceSanityService.isSuspicious(193.76, 0), isFalse);
    });

    test('нулевая или отрицательная цена не считается подозрительной здесь', () {
      // Такие значения отсекаются раньше, на валидации формы.
      expect(PriceSanityService.isSuspicious(0, 548.10), isFalse);
      expect(PriceSanityService.isSuspicious(-10, 548.10), isFalse);
    });
  });

  group('текст предупреждения', () {
    test('говорит, в какую сторону и во сколько раз расхождение', () {
      final low = PriceSanityService.warning(193.76, 548.10);
      expect(low, contains('ниже'));
      expect(low, contains('548.10'));

      final high = PriceSanityService.warning(5481.0, 548.10);
      expect(high, contains('выше'));
    });
  });
}
