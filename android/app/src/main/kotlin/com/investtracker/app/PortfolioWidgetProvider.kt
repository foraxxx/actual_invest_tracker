package com.investtracker.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Виджет "Портфель" на главном экране Android.
/// Данные (стоимость портфеля, P&L) сохраняются Flutter-стороной через
/// HomeWidgetService при каждом открытии приложения или изменении данных —
/// сам виджет ничего не считает и не работает без открытия приложения хотя бы раз.
class PortfolioWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.portfolio_widget).apply {
                val value = widgetData.getString("portfolio_value", "—")
                val pnl = widgetData.getString("portfolio_pnl", "")
                val pnlPositive = widgetData.getBoolean("portfolio_pnl_positive", true)

                setTextViewText(R.id.widget_value, value)
                setTextViewText(R.id.widget_pnl, pnl)
                setTextColor(
                    R.id.widget_pnl,
                    if (pnlPositive) 0xFFB9F6CA.toInt() else 0xFFFFCDD2.toInt()
                )

                // Тап по виджету открывает приложение
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_value, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
