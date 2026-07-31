package com.investtracker.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class PortfolioWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val ACTION_NEXT = "com.investtracker.app.WIDGET_NEXT"
        private const val STATE_PREFS = "PortfolioWidgetState"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it, widgetData) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_NEXT) return
        val manager = AppWidgetManager.getInstance(context)
        val requestedId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        val ids = if (requestedId >= 0) intArrayOf(requestedId) else
            manager.getAppWidgetIds(ComponentName(context, PortfolioWidgetProvider::class.java))
        val data = HomeWidgetPlugin.getData(context)
        val state = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
        val count = data.getInt("widget_page_count", 1).coerceAtLeast(1)
        ids.forEach { id ->
            val next = (state.getInt("page_$id", 0) + 1) % count
            state.edit().putInt("page_$id", next).apply()
            render(context, manager, id, data)
        }
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences
    ) {
        val count = data.getInt("widget_page_count", 1).coerceAtLeast(1)
        val state = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
        val page = state.getInt("page_$widgetId", 0).coerceIn(0, count - 1)
        val style = data.getString("widget_style", "emerald") ?: "emerald"
        val background = when (style) {
            "midnight" -> R.drawable.widget_background_midnight
            "violet" -> R.drawable.widget_background_violet
            "graphite" -> R.drawable.widget_background_graphite
            else -> R.drawable.widget_background
        }

        val views = RemoteViews(context.packageName, R.layout.portfolio_widget).apply {
            setInt(R.id.widget_root, "setBackgroundResource", background)
            setTextViewText(R.id.widget_title, data.getString("widget_${page}_title", "Портфель"))
            setTextViewText(R.id.widget_value, data.getString("widget_${page}_value", "—"))
            setTextViewText(R.id.widget_pnl, data.getString("widget_${page}_subtitle", ""))
            setTextViewText(R.id.widget_page, "${page + 1}/$count")
            val positive = data.getBoolean("widget_${page}_positive", true)
            setTextColor(R.id.widget_value, if (positive) 0xFFFFFFFF.toInt() else 0xFFFFCDD2.toInt())

            val nextIntent = Intent(context, PortfolioWidgetProvider::class.java).apply {
                action = ACTION_NEXT
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                widgetId,
                nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            setOnClickPendingIntent(R.id.widget_root, pending)
        }
        manager.updateAppWidget(widgetId, views)
    }
}
