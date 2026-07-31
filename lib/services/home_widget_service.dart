import 'package:home_widget/home_widget.dart';
import 'analytics_service.dart';
import 'appearance_service.dart';
import 'theme_service.dart';

/// Обновляет виджет на главном экране телефона (стоимость портфеля + P&L).
/// Виджет офлайн — просто показывает последние данные, которые приложение
/// сохранило при последнем открытии; сам он ничего не считает и не тянет
/// из интернета.
class HomeWidgetService {
  static const _androidWidgetName = 'PortfolioWidgetProvider';

  /// Пересчитывает текущие цифры и сохраняет их для виджета.
  /// Вызывать после любого изменения данных (или просто при открытии приложения).
  static Future<void> update() async {
    try {
      final value = AnalyticsService.currentPortfolioValueRub();
      final pnl = AnalyticsService.totalUnrealizedPnlRub();
      final holdings = AnalyticsService.currentHoldings();
      final costBasisTotal = holdings.values.fold(0.0, (s, h) => s + h.costBasisRub);
      final pnlPct = costBasisTotal == 0 ? 0.0 : (pnl / costBasisTotal) * 100;
      final totalProfit = pnl + AnalyticsService.totalRealizedPnlRub() + AnalyticsService.totalIncome();
      final income = AnalyticsService.totalIncome();
      final forecast = AnalyticsService.totalDividendForecastRub();
      final invested = AnalyticsService.totalInvested();
      final allTimePct = invested == 0 ? 0.0 : totalProfit / invested * 100;
      final timeline = AnalyticsService.portfolioValueTimeline();
      final sparkValues = timeline.length > 48 ? timeline.sublist(timeline.length - 48) : timeline;
      String money(double amount) => _formatMoney(amount);

      final content = <HomeWidgetPage, ({String title, String value, String subtitle, bool positive})>{
        HomeWidgetPage.portfolio: (
          title: 'Стоимость портфеля',
          value: money(value),
          subtitle: holdings.isEmpty
              ? 'Нет открытых позиций'
              : 'За всё время ${allTimePct >= 0 ? "+" : ""}${allTimePct.toStringAsFixed(1)}%',
          positive: allTimePct >= 0,
        ),
        HomeWidgetPage.profit: (
          title: 'Общий результат',
          value: '${totalProfit >= 0 ? "+" : ""}${money(totalProfit)}',
          subtitle: 'Продажи, выплаты и открытые позиции',
          positive: totalProfit >= 0,
        ),
        HomeWidgetPage.income: (
          title: 'Полученные выплаты',
          value: money(income),
          subtitle: 'Дивиденды и купоны',
          positive: income >= 0,
        ),
        HomeWidgetPage.forecast: (
          title: 'Ожидаемые выплаты',
          value: money(forecast),
          subtitle: 'Прогноз на ближайшие 12 месяцев',
          positive: forecast >= 0,
        ),
      };
      final pages = AppearanceService.homeWidgetPages;
      await HomeWidget.saveWidgetData<int>('widget_page_count', pages.length);
      await HomeWidget.saveWidgetData<String>(
        'widget_accent',
        ThemeService.accentColor.value.value.toRadixString(16).padLeft(8, '0'),
      );
      await HomeWidget.saveWidgetData<bool>('widget_hide_amounts', AppearanceService.hideAmounts);
      await HomeWidget.saveWidgetData<String>(
        'widget_sparkline',
        sparkValues.map((point) => point.value.toStringAsFixed(2)).join(','),
      );
      for (var i = 0; i < pages.length; i++) {
        final page = content[pages[i]]!;
        await HomeWidget.saveWidgetData<String>('widget_${i}_title', page.title);
        await HomeWidget.saveWidgetData<String>('widget_${i}_value', page.value);
        await HomeWidget.saveWidgetData<String>('widget_${i}_subtitle', page.subtitle);
        await HomeWidget.saveWidgetData<bool>('widget_${i}_positive', page.positive);
        await HomeWidget.saveWidgetData<bool>('widget_${i}_show_chart', pages[i] == HomeWidgetPage.portfolio);
      }

      await HomeWidget.saveWidgetData<String>('portfolio_value', _formatMoney(value));
      await HomeWidget.saveWidgetData<String>(
        'portfolio_pnl',
        holdings.isEmpty ? 'Нет позиций' : '${pnl >= 0 ? "+" : ""}${_formatMoney(pnl)} (${pnlPct.toStringAsFixed(1)}%)',
      );
      await HomeWidget.saveWidgetData<bool>('portfolio_pnl_positive', pnl >= 0);

      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (_) {
      // Виджет — необязательная функция: если платформа не поддерживает его
      // (например, эмулятор без лаунчера), тихо игнорируем ошибку, не мешая
      // работе самого приложения.
    }
  }

  static String _formatMoney(double value) {
    final rounded = value.round();
    final str = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return '${rounded < 0 ? "-" : ""}$buffer ₽';
  }
}
