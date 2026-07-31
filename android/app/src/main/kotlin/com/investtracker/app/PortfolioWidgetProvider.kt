package com.investtracker.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class PortfolioWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val ACTION_NEXT = "com.investtracker.app.WIDGET_NEXT"
        private const val ACTION_TOGGLE_AMOUNT = "com.investtracker.app.WIDGET_TOGGLE_AMOUNT"
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
        if (intent.action != ACTION_NEXT && intent.action != ACTION_TOGGLE_AMOUNT) return
        val manager = AppWidgetManager.getInstance(context)
        val requestedId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        val ids = if (requestedId >= 0) intArrayOf(requestedId) else
            manager.getAppWidgetIds(ComponentName(context, PortfolioWidgetProvider::class.java))
        val data = HomeWidgetPlugin.getData(context)
        val state = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
        val count = data.getInt("widget_page_count", 1).coerceAtLeast(1)
        ids.forEach { id ->
            if (intent.action == ACTION_TOGGLE_AMOUNT) {
                val revealed = state.getBoolean("revealed_$id", false)
                state.edit().putBoolean("revealed_$id", !revealed).apply()
            } else {
                val next = (state.getInt("page_$id", 0) + 1) % count
                state.edit().putInt("page_$id", next).apply()
            }
            render(context, manager, id, data)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
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
        if (!data.getBoolean("widget_hide_amounts", false)) {
            state.edit().putBoolean("revealed_$widgetId", false).apply()
        }
        val background = when (style) {
            "midnight" -> R.drawable.widget_background_midnight
            "violet" -> R.drawable.widget_background_violet
            "graphite" -> R.drawable.widget_background_graphite
            else -> R.drawable.widget_background
        }

        val views = RemoteViews(context.packageName, R.layout.portfolio_widget).apply {
            setInt(R.id.widget_root, "setBackgroundResource", background)
            setTextViewText(R.id.widget_title, data.getString("widget_${page}_title", "Портфель"))
            val hideAmounts = data.getBoolean("widget_hide_amounts", false)
            val revealed = state.getBoolean("revealed_$widgetId", false)
            val actualValue = data.getString("widget_${page}_value", "—")
            setTextViewText(R.id.widget_value, if (hideAmounts && !revealed) "•••••• ₽" else actualValue)
            setTextViewText(R.id.widget_pnl, data.getString("widget_${page}_subtitle", ""))
            setTextViewText(R.id.widget_page, "${page + 1}/$count")
            val positive = data.getBoolean("widget_${page}_positive", true)
            setTextColor(R.id.widget_value, if (positive) 0xFFFFFFFF.toInt() else 0xFFFFCDD2.toInt())
            val availableHeight = manager.getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 120)
            val showChart = data.getBoolean("widget_${page}_show_chart", false) && availableHeight >= 100
            setViewVisibility(R.id.widget_chart, if (showChart) View.VISIBLE else View.GONE)
            if (showChart) {
                val points = data.getString("widget_sparkline", "")
                    .orEmpty()
                    .split(',')
                    .mapNotNull { it.toFloatOrNull() }
                setImageViewBitmap(R.id.widget_chart, sparkline(points, positive))
            }

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

            val revealIntent = Intent(context, PortfolioWidgetProvider::class.java).apply {
                action = ACTION_TOGGLE_AMOUNT
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            val revealPending = PendingIntent.getBroadcast(
                context,
                widgetId + 100000,
                revealIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            setOnClickPendingIntent(R.id.widget_value, revealPending)

            val openPending = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            setOnClickPendingIntent(R.id.widget_open, openPending)
        }
        manager.updateAppWidget(widgetId, views)
    }

    private fun sparkline(values: List<Float>, positive: Boolean): Bitmap {
        val width = 600
        val height = 90
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        if (values.size < 2) return bitmap
        val canvas = Canvas(bitmap)
        val min = values.minOrNull() ?: return bitmap
        val max = values.maxOrNull() ?: return bitmap
        val range = (max - min).takeIf { it > 0.0001f } ?: 1f
        val lineColor = if (positive) Color.rgb(185, 246, 202) else Color.rgb(255, 205, 210)
        val path = Path()
        values.forEachIndexed { index, value ->
            val x = index.toFloat() / (values.size - 1) * width
            val y = height - 8f - ((value - min) / range) * (height - 18f)
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        val fill = Path(path).apply {
            lineTo(width.toFloat(), height.toFloat())
            lineTo(0f, height.toFloat())
            close()
        }
        canvas.drawPath(fill, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = lineColor
            alpha = 38
            style = Paint.Style.FILL
        })
        canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = lineColor
            strokeWidth = 5f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            style = Paint.Style.STROKE
        })
        return bitmap
    }
}
