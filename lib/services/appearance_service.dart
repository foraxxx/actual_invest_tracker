import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Что писать во второй строке бумаги в составе портфеля.
enum HoldingSubtitle { quantityAndPrice, share, profitRub, profitPct }

extension HoldingSubtitleX on HoldingSubtitle {
  String get title => switch (this) {
        HoldingSubtitle.quantityAndPrice => 'Количество',
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

extension CardStyleX on CardStyle {
  String get title => switch (this) {
        CardStyle.glass => 'Со свечением',
        CardStyle.flat => 'Плоские',
      };
}

/// Как разбит состав портфеля на группы по типу бумаг.
enum HoldingsGrouping { headers, collapsible }

extension HoldingsGroupingX on HoldingsGrouping {
  String get title => switch (this) {
        HoldingsGrouping.headers => 'Заголовки',
        HoldingsGrouping.collapsible => 'Сворачиваемые',
      };
}

/// Где показывать значения, когда палец лежит на графике.
enum ChartHints {
  /// На месте суммы над графиком — сам график ничем не закрыт.
  above,

  /// Тонкая строка поверх графика и подписи дат у линий.
  inline,
}

extension ChartHintsX on ChartHints {
  String get title => switch (this) {
        ChartHints.above => 'Над графиком',
        ChartHints.inline => 'На графике',
      };
}

/// Как выглядят свёрнутые разделы главной.
enum SectionPreview { line, preview }

extension SectionPreviewX on SectionPreview {
  String get title => switch (this) {
        SectionPreview.line => 'Строка',
        SectionPreview.preview => 'С превью',
      };
}

/// Сетка календаря выплат.
enum PayoutCalendarStyle { threeColumns, twoColumns }

extension PayoutCalendarStyleX on PayoutCalendarStyle {
  String get title => switch (this) {
        PayoutCalendarStyle.threeColumns => '3 столбца',
        PayoutCalendarStyle.twoColumns => '2 столбца',
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
  ///
  /// Хранится под новым ключом: вкладку «Выплаты» убрали, и номера после неё
  /// сдвинулись. Старое значение пересчитывается: «Выплаты» (3) → «Портфель»,
  /// «Планы» (4) → 3, «Настройки» (5) → 4.
  static int get startTab {
    final current = int.tryParse(_box.get('startTabV2') ?? '');
    if (current != null) return current.clamp(0, 4);
    return switch (int.tryParse(_box.get('startTab') ?? '') ?? 0) {
      4 => 3,
      5 => 4,
      final i when i >= 0 && i < 3 => i,
      _ => 0,
    };
  }

  static Future<void> setStartTab(int value) async {
    await _box.put('startTabV2', '$value');
    version.value++;
  }

  /// Учитывать ли плановые покупки в прогнозе стоимости портфеля.
  ///
  /// Пишется мимо [_setFlag] намеренно: тот увеличивает [version], а на неё
  /// подписан корень приложения — переключение галки в форме прогноза
  /// перестраивало бы весь интерфейс. Обновление карточки на главной идёт
  /// через собственный уведомитель прогноза.
  static bool get forecastWithPlans => _flag('forecastWithPlans');

  static Future<void> setForecastWithPlans(bool value) => _box.put('forecastWithPlans', value ? '1' : '0');

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

  // --- Состав портфеля и графики ---

  static HoldingsGrouping get holdingsGrouping => HoldingsGrouping.values.firstWhere(
        (g) => g.name == _box.get('holdingsGrouping'),
        orElse: () => HoldingsGrouping.headers,
      );

  static Future<void> setHoldingsGrouping(HoldingsGrouping value) async {
    await _box.put('holdingsGrouping', value.name);
    version.value++;
  }

  /// Свёрнутые группы состава портфеля (имена типов бумаг).
  ///
  /// Пишется мимо [version], как и [forecastWithPlans]: сворачивание группы
  /// перерисовывает только главную, а не всё приложение.
  static Set<String> get collapsedGroups {
    final raw = _box.get('collapsedGroups') ?? '';
    return raw.split(',').where((e) => e.isNotEmpty).toSet();
  }

  static Future<void> setGroupCollapsed(String group, bool collapsed) {
    final groups = collapsedGroups;
    if (collapsed) {
      groups.add(group);
    } else {
      groups.remove(group);
    }
    return _box.put('collapsedGroups', groups.join(','));
  }

  static ChartHints get chartHints => ChartHints.values.firstWhere(
        (h) => h.name == _box.get('chartHints'),
        orElse: () => ChartHints.above,
      );

  static Future<void> setChartHints(ChartHints value) async {
    await _box.put('chartHints', value.name);
    version.value++;
  }

  static SectionPreview get sectionPreview => SectionPreview.values.firstWhere(
        (p) => p.name == _box.get('sectionPreview'),
        orElse: () => SectionPreview.preview,
      );

  static Future<void> setSectionPreview(SectionPreview value) async {
    await _box.put('sectionPreview', value.name);
    version.value++;
  }

  static PayoutCalendarStyle get payoutCalendar => PayoutCalendarStyle.values.firstWhere(
        (c) => c.name == _box.get('payoutCalendar'),
        orElse: () => PayoutCalendarStyle.threeColumns,
      );

  static Future<void> setPayoutCalendar(PayoutCalendarStyle value) async {
    await _box.put('payoutCalendar', value.name);
    version.value++;
  }

  /// Последняя открытая вкладка «Распределения» на главной. Мимо [version]:
  /// переключение вкладки не должно перестраивать всё приложение.
  static String? get allocationTab => _box.get('allocationTab');

  static Future<void> setAllocationTab(String value) => _box.put('allocationTab', value);
}
