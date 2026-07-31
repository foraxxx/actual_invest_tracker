import 'package:home_widget/home_widget.dart';
import 'analytics_service.dart';

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
