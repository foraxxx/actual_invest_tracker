import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/widgets/portfolio_treemap.dart';
import 'package:invest_tracker/widgets/updated_ago.dart';

/// Раскладка карты портфеля и подпись «обновлено … назад».
void main() {
  group('squarify', () {
    const field = Rect.fromLTWH(0, 0, 320, 240);

    void expectCovers(List<double> values) {
      final rects = squarify(values, field);
      expect(rects.length, values.length);
      final area = rects.fold(0.0, (s, r) => s + r.width * r.height);
      expect(area, closeTo(field.width * field.height, 1e-6));
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(-1e-9));
        expect(r.top, greaterThanOrEqualTo(-1e-9));
        expect(r.right, lessThanOrEqualTo(field.right + 1e-9));
        expect(r.bottom, lessThanOrEqualTo(field.bottom + 1e-9));
      }
    }

    test('площади плиток заполняют поле и не выходят за край', () {
      expectCovers([1097705, 188213, 178465, 125307, 106604, 18549, 14362, 10470]);
      expectCovers([1]);
      expectCovers([5, 5, 5, 5]);
    });

    test('случайные портфели', () {
      final random = math.Random(7);
      for (int i = 0; i < 200; i++) {
        final n = 1 + random.nextInt(30);
        final values = List.generate(n, (_) => math.pow(random.nextDouble(), 3) * 1000 + 0.01)
            .map((e) => e.toDouble())
            .toList()
          ..sort((a, b) => b.compareTo(a));
        expectCovers(values);
      }
    });

    test('площадь плитки пропорциональна доле', () {
      final rects = squarify([3, 1], field);
      final a0 = rects[0].width * rects[0].height;
      final a1 = rects[1].width * rects[1].height;
      expect(a0 / a1, closeTo(3, 1e-9));
    });

    test('пустой набор и нулевое поле не падают', () {
      expect(squarify([], field), isEmpty);
      expect(squarify([1, 2], Rect.zero), [Rect.zero, Rect.zero]);
    });
  });

  group('UpdatedAgo.label', () {
    final now = DateTime(2026, 10, 13, 15, 30);

    test('недавно', () {
      expect(UpdatedAgo.label(now.subtract(const Duration(seconds: 20)), now), 'обновлено только что');
      expect(UpdatedAgo.label(now.subtract(const Duration(minutes: 7)), now), 'обновлено 7 мин назад');
    });

    test('давно', () {
      expect(UpdatedAgo.label(DateTime(2026, 10, 13, 9, 5), now), 'обновлено в 09:05');
      expect(UpdatedAgo.label(DateTime(2026, 10, 12, 18, 45), now), 'обновлено вчера в 18:45');
      expect(UpdatedAgo.label(DateTime(2026, 10, 1, 10, 0), now), 'обновлено 01.10 в 10:00');
      expect(UpdatedAgo.label(null, now), 'ещё не обновлялось');
    });
  });
}
