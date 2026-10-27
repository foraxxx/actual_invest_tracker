package com.investtracker.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import com.investtracker.app.MainActivity

/**
 * Виджет на экране телефона. Раскладка зависит от размера (2×1, 3×1, 4×1,
 * 2×2, 3×2, 4×2), содержимое и оформление — от конструктора в приложении.
 *
 * На Android 12 и новее система сообщает точные размеры виджета (обычно
 * два: для вертикального и горизонтального экрана), и для каждого заранее
 * готовится своя раскладка — при повороте и изменении размера ничего не
 * пересчитывается.
 */
class PortfolioWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, manager, id)
        WidgetUpdateWorker.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE_HIDDEN) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_HIDDEN, !prefs.getBoolean(KEY_HIDDEN, false)).apply()
            updateAll(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdateWorker.schedule(context)
    }

    override fun onDisabled(context: Context) {
        WidgetUpdateWorker.cancel(context)
    }

    companion object {
        const val ACTION_TOGGLE_HIDDEN = "com.investtracker.app.widget.TOGGLE_HIDDEN"
        private const val PREFS = "widget_local"
        private const val KEY_HIDDEN = "hidden"

        /** Суммы на виджете скрыты — переключается кнопкой-глазом на самом виджете. */
        fun hidden(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_HIDDEN, false)

        fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, PortfolioWidgetProvider::class.java))

        fun updateAll(context: Context) {
            val ids = ids(context)
            if (ids.isEmpty()) return
            val manager = AppWidgetManager.getInstance(context)
            // Снимок разбирается один раз на все виджеты.
            val state = WidgetData.state(context)
            for (id in ids) render(context, manager, id, state)
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int, known: WidgetState? = null) {
            val state = known ?: WidgetData.state(context)
            val options = manager.getAppWidgetOptions(id)
            val click = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val eye = PendingIntent.getBroadcast(
                context, 1,
                Intent(context, PortfolioWidgetProvider::class.java).setAction(ACTION_TOGGLE_HIDDEN),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val views: RemoteViews
            if (Build.VERSION.SDK_INT >= 31) {
                @Suppress("DEPRECATION")
                val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    ?.distinct()?.take(8)
                val list = if (sizes.isNullOrEmpty()) {
                    // Лаунчер не сообщил размеры — типичные точки перехода.
                    listOf(SizeF(160f, 82f), SizeF(244f, 82f), SizeF(340f, 82f), SizeF(160f, 190f), SizeF(244f, 190f), SizeF(340f, 190f))
                } else {
                    sizes
                }
                val map = LinkedHashMap<SizeF, RemoteViews>()
                for (s in list) map[s] = WidgetRenderer.build(context, s.width, s.height, state, click, true, eye)
                views = if (map.size == 1) map.values.first() else RemoteViews(map)
            } else {
                // Старые версии: ширина в портретной ориентации — минимальная,
                // высота — максимальная.
                val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 160).toFloat()
                val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 82).toFloat()
                views = WidgetRenderer.build(context, w, h, state, click, false, eye)
            }
            manager.updateAppWidget(id, views)
        }
    }
}
