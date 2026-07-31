import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Что писать во второй строке бумаги в составе портфеля.
enum HoldingSubtitle { quantityAndPrice, share, profitRub, profitPct }

extension HoldingSubtitleX on HoldingSubtitle {
  String get title => switch (this) {
        HoldingSubtitle.quantityAndPrice => 'Количество и цена',
        HoldingSubtitle.share => 'Доля в портфеле',
        HoldingSubtitle.profitRub => 'Прибыль в рублях',
        HoldingSubtitle.profitPct => 'Прибыль в процентах',
      };
}

/// Плотность списков.
enum ListDensity { comfortable, compact }

extension ListDensityX on ListDensity {
  String get title => switch (this) {
        ListDensity.comfortable => 'Обычная',
        ListDensity.compact => 'Плотная',
      };

  /// Множитель вертикальных отступов внутри карточек списка.
  double get scale => this == ListDensity.compact ? 0.62 : 1;
}

/// Оформление карточек.
enum CardStyle { glass, flat }

enum HomeWidgetPage { portfolio, profit, income, forecast }

extension HomeWidgetPageX on HomeWidgetPage {
  String get title => switch (this) {
        HomeWidgetPage.portfolio => 'Стоимость портфеля',
        HomeWidgetPage.profit => 'Общий результат',
        HomeWidgetPage.income => 'Полученные выплаты',
        HomeWidgetPage.forecast => 'Ожидаемые выплаты',
      };
}

enum HomeWidgetStyle { emerald, midnight, violet, graphite }

extension HomeWidgetStyleX on HomeWidgetStyle {
  String get title => switch (this) {
        HomeWidgetStyle.emerald => 'Изумрудный',
        HomeWidgetStyle.midnight => 'Ночной',
        HomeWidgetStyle.violet => 'Фиолетовый',
        HomeWidgetStyle.graphite => 'Графитовый',
      };
}

extension CardStyleX on CardStyle {
  String get title => switch (this) {
        CardStyle.glass => 'Со свечением',
        CardStyle.flat => 'Плоские',
      };
}

/// Настройки внешнего вида, которые не про цвет: что показывать, насколько
/// плотно и что прятать от посторонних глаз.
class AppearanceService {
  static const boxName = 'appearance';

  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  /// Показаны ли суммы прямо сейчас. Живёт только в памяти: при следующем
  /// запуске приложение снова прячет их.
  static final ValueNotifier<bool> revealed = ValueNotifier(false);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static bool _flag(String key, {bool byDefault = false}) {
    final value = _box.get(key);
    if (value == null) return byDefault;
    return value == '1';
  }

  static Future<void> _setFlag(String key, bool value) async {
    await _box.put(key, value ? '1' : '0');
    version.value++;
  }

  // --- Скрытие сумм ---

  static bool get hideAmounts => _flag('hideAmounts');

  static Future<void> setHideAmounts(bool value) async {
    revealed.value = false;
    await _setFlag('hideAmounts', value);
  }

  /// Нужно ли прятать сумму прямо сейчас.
  static bool get amountsHidden => hideAmounts && !revealed.value;

  /// Нажатие по любой скрытой сумме открывает все сразу — прятать их обратно
  /// тоже одним нажатием.
  static void toggleReveal() => revealed.value = !revealed.value;

  // --- Списки и навигация ---

  static ListDensity get density => ListDensity.values.firstWhere(
        (d) => d.name == _box.get('density'),
        orElse: () => ListDensity.comfortable,
      );

  static Future<void> setDensity(ListDensity value) async {
    await _box.put('density', value.name);
    version.value++;
  }

  static HoldingSubtitle get holdingSubtitle => HoldingSubtitle.values.firstWhere(
        (s) => s.name == _box.get('holdingSubtitle'),
        orElse: () => HoldingSubtitle.quantityAndPrice,
      );

  static Future<void> setHoldingSubtitle(HoldingSubtitle value) async {
    await _box.put('holdingSubtitle', value.name);
    version.value++;
  }

  static bool get showNavLabels => _flag('showNavLabels', byDefault: true);

  static Future<void> setShowNavLabels(bool value) => _setFlag('showNavLabels', value);

  /// Вкладка, которая открывается при входе в портфель.
  static int get startTab => int.tryParse(_box.get('startTab') ?? '') ?? 0;

  static Future<void> setStartTab(int value) async {
    await _box.put('startTab', '$value');
    version.value++;
  }

  // --- Внешний вид ---

  static bool get monoDigits => _flag('monoDigits');

  static Future<void> setMonoDigits(bool value) => _setFlag('monoDigits', value);

  static CardStyle get cardStyle => CardStyle.values.firstWhere(
        (c) => c.name == _box.get('cardStyle'),
        orElse: () => CardStyle.glass,
      );

  static Future<void> setCardStyle(CardStyle value) async {
    await _box.put('cardStyle', value.name);
    version.value++;
  }

  static List<HomeWidgetPage> get homeWidgetPages {
    final raw = _box.get('homeWidgetPages') ?? 'portfolio,profit';
    final selected = raw
        .split(',')
        .map((name) {
          for (final value in HomeWidgetPage.values) {
            if (value.name == name) return value;
          }
          return null;
        })
        .whereType<HomeWidgetPage>()
        .toList();
    return selected.isEmpty ? [HomeWidgetPage.portfolio] : selected;
  }

  static Future<void> setHomeWidgetPages(List<HomeWidgetPage> pages) async {
    final safe = pages.isEmpty ? [HomeWidgetPage.portfolio] : pages;
    await _box.put('homeWidgetPages', safe.map((p) => p.name).join(','));
    version.value++;
  }

  static HomeWidgetStyle get homeWidgetStyle => HomeWidgetStyle.values.firstWhere(
        (style) => style.name == _box.get('homeWidgetStyle'),
        orElse: () => HomeWidgetStyle.emerald,
      );

  static Future<void> setHomeWidgetStyle(HomeWidgetStyle style) async {
    await _box.put('homeWidgetStyle', style.name);
    version.value++;
  }
}
