package com.investtracker.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.investtracker.app.MainActivity
import com.investtracker.app.R
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Виджет «Графит». Четыре раскладки под размер: 2×1, 4×1, 2×2 и 4×2.
 * На Android 12 и новее система сама выбирает раскладку при каждом
 * изменении размера — без пересчёта и без запуска приложения.
 */
class PortfolioWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, manager, id)
        WidgetUpdateWorker.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, id)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdateWorker.schedule(context)
    }

    override fun onDisabled(context: Context) {
        WidgetUpdateWorker.cancel(context)
    }

    companion object {
        private const val GREEN = 0xFF3EE6A8.toInt()
        private const val RED = 0xFFFF6B7A.toInt()
        private const val TEXT = 0xFFF2F2F4.toInt()
        private const val DIM = 0xFF8B8F98.toInt()

        private val months = arrayOf(
            "января", "февраля", "марта", "апреля", "мая", "июня",
            "июля", "августа", "сентября", "октября", "ноября", "декабря",
        )

        fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, PortfolioWidgetProvider::class.java))

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (id in ids(context)) render(context, manager, id)
        }

        private enum class Kind { SMALL, WIDE, SQUARE, LARGE }

        private fun layoutOf(kind: Kind) = when (kind) {
            Kind.SMALL -> R.layout.widget_small
            Kind.WIDE -> R.layout.widget_wide
            Kind.SQUARE -> R.layout.widget_square
            Kind.LARGE -> R.layout.widget_large
        }

        /** Граница между раскладками, dp. */
        private const val WIDE_FROM = 240f
        private const val TALL_FROM = 130f

        private fun kindFor(widthDp: Float, heightDp: Float): Kind = when {
            widthDp >= WIDE_FROM && heightDp >= TALL_FROM -> Kind.LARGE
            heightDp >= TALL_FROM -> Kind.SQUARE
            widthDp >= WIDE_FROM -> Kind.WIDE
            else -> Kind.SMALL
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val state = WidgetData.state(context)
            val options = manager.getAppWidgetOptions(id)
            val views: RemoteViews
            if (Build.VERSION.SDK_INT >= 31) {
                // Система берёт самую большую раскладку, которая помещается.
                val chartSize = chartSizeDp(options)
                val map = LinkedHashMap<SizeF, RemoteViews>()
                map[SizeF(100f, 40f)] = build(context, Kind.SMALL, state, chartSize)
                map[SizeF(WIDE_FROM, 40f)] = build(context, Kind.WIDE, state, chartSize)
                map[SizeF(100f, TALL_FROM)] = build(context, Kind.SQUARE, state, chartSize)
                map[SizeF(WIDE_FROM, TALL_FROM)] = build(context, Kind.LARGE, state, chartSize)
                views = RemoteViews(map)
            } else {
                // Старые версии: ширина в портретной ориентации — минимальная,
                // высота — максимальная.
                val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110).toFloat()
                val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 40).toFloat()
                views = build(context, kindFor(w, h), state, SizeF(max(w * 0.5f - 30f, 80f), max(h - 120f, 40f)))
            }
            manager.updateAppWidget(id, views)
        }

        /** Размер графика в раскладке 4×2 по самому большому размеру виджета. */
        private fun chartSizeDp(options: Bundle): SizeF {
            var w = 0f
            var h = 0f
            if (Build.VERSION.SDK_INT >= 31) {
                @Suppress("DEPRECATION")
                val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                if (sizes != null) {
                    for (s in sizes) {
                        if (s.width >= WIDE_FROM && s.height >= TALL_FROM) {
                            w = max(w, s.width)
                            h = max(h, s.height)
                        }
                    }
                }
            }
            if (w <= 0f) {
                w = 340f
                h = 180f
            }
            // Левая колонка — чуть больше половины без отступов; сверху над
            // графиком четыре строки текста.
            return SizeF(max((w - 32f - 25f) * 1.1f / 2.1f, 80f), max(h - 26f - 96f, 36f))
        }

        private fun build(context: Context, kind: Kind, state: WidgetState?, chartDp: SizeF): RemoteViews {
            val v = RemoteViews(context.packageName, layoutOf(kind))
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            v.setOnClickPendingIntent(android.R.id.background, pending)

            if (state == null) {
                v.setTextViewText(R.id.title, "Invest Tracker")
                v.setTextViewText(R.id.value, "—")
                v.setTextViewText(R.id.day, "Откройте приложение")
                v.setTextColor(R.id.day, DIM)
                if (kind != Kind.SMALL) emptyBudget(v, 1, "Данные появятся после первого запуска")
                if (kind == Kind.SQUARE || kind == Kind.LARGE) v.setViewVisibility(R.id.total, View.GONE)
                if (kind == Kind.LARGE) {
                    v.setTextViewText(R.id.time, "")
                    v.setViewVisibility(R.id.chart, View.GONE)
                    v.setViewVisibility(R.id.chart_empty, View.GONE)
                    hideBlock(v, 2)
                }
                return v
            }

            v.setTextViewText(R.id.title, state.title)
            v.setTextViewText(R.id.value, if (state.hidden) "••• ••• ₽" else money(state.value))

            // Изменение за сегодня.
            val dayRub = state.dayRub
            if (dayRub == null) {
                v.setTextViewText(R.id.day, "Нет цен с биржи")
                v.setTextColor(R.id.day, DIM)
            } else {
                val up = dayRub >= 0
                val arrow = if (up) "▲ " else "▼ "
                val pct = state.dayPct?.let { percent(abs(it)) }
                val text = when {
                    state.hidden -> arrow + (pct ?: "") + " сегодня"
                    kind == Kind.SMALL -> arrow + money(abs(dayRub)) + (if (pct != null) " · $pct" else "")
                    kind == Kind.LARGE -> arrow + money(abs(dayRub)) + (if (pct != null) " · $pct" else "") + " сегодня"
                    kind == Kind.SQUARE -> arrow + money(abs(dayRub)) + " · сегодня"
                    else -> arrow + money(abs(dayRub)) + " сегодня"
                }
                v.setTextViewText(R.id.day, text)
                v.setTextColor(R.id.day, if (up) GREEN else RED)
            }

            if (kind == Kind.SQUARE || kind == Kind.LARGE) {
                val sb = SpannableStringBuilder("за всё время ")
                val amount = if (state.hidden) {
                    state.profitPct?.let { signed(it) + "%" } ?: "•••"
                } else {
                    signedMoney(state.profit)
                }
                val start = sb.length
                sb.append(amount)
                sb.setSpan(ForegroundColorSpan(if (state.profit >= 0) GREEN else RED), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.setSpan(StyleSpan(android.graphics.Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                v.setTextViewText(R.id.total, sb)
                v.setViewVisibility(R.id.total, View.VISIBLE)
            }

            if (kind == Kind.LARGE) {
                v.setTextViewText(R.id.time, timeText(state.updatedAt))
                if (state.chart.size >= 2) {
                    v.setImageViewBitmap(R.id.chart, chart(context, state.chart, chartDp))
                    v.setViewVisibility(R.id.chart, View.VISIBLE)
                    v.setViewVisibility(R.id.chart_empty, View.GONE)
                } else {
                    v.setViewVisibility(R.id.chart, View.GONE)
                    v.setViewVisibility(R.id.chart_empty, View.VISIBLE)
                }
            }

            if (kind != Kind.SMALL) budget(v, kind, state)
            return v
        }

        // --- Бюджет ---

        private fun budget(v: RemoteViews, kind: Kind, state: WidgetState) {
            val today = WidgetData.dayOf(System.currentTimeMillis())
            val pays = state.payouts.sortedBy { it.day }
            val current = pays.lastOrNull { it.day <= today }
            val upcoming = pays.filter { it.day > today }
            val next = upcoming.firstOrNull()

            if (pays.isEmpty() || pays.all { it.plan <= 0.5 }) {
                emptyBudget(v, 1, "Бюджет не заполнен")
                if (kind == Kind.LARGE) hideBlock(v, 2)
                return
            }

            var second: WidgetPayout? = next
            if (current != null && current.plan > 0.5) {
                if (current.left > 0.5) {
                    left(v, 1, current, state.hidden)
                } else {
                    v.setTextViewText(R.id.b1_title, payTitle(current))
                    val done = SpannableStringBuilder("Всё отложено ✓")
                    done.setSpan(ForegroundColorSpan(GREEN), 0, done.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    v.setTextViewText(R.id.b1_main, done)
                    if (next != null) {
                        v.setTextViewText(R.id.b1_sub, "дальше " + lowerFirst(next.name) + " " + dateText(next.day))
                        v.setViewVisibility(R.id.b1_sub, View.VISIBLE)
                    } else {
                        v.setViewVisibility(R.id.b1_sub, View.GONE)
                    }
                    v.setViewVisibility(R.id.b1_bar, View.GONE)
                }
            } else if (next != null) {
                // С прошедшей выплаты откладывать нечего — показываем ближайшую.
                left(v, 1, next, state.hidden)
                second = upcoming.getOrNull(1)
            } else {
                emptyBudget(v, 1, "Бюджет не заполнен")
            }

            if (kind == Kind.LARGE) {
                if (second == null) hideBlock(v, 2) else left(v, 2, second, state.hidden)
            }
        }

        private fun left(v: RemoteViews, block: Int, p: WidgetPayout, hidden: Boolean) {
            val ids = blockIds(block)
            v.setViewVisibility(ids[0], View.VISIBLE)
            v.setTextViewText(ids[0], payTitle(p))
            v.setViewVisibility(ids[1], View.VISIBLE)
            if (p.plan <= 0.5) {
                v.setTextViewText(ids[1], dim("ещё не распределено"))
                v.setViewVisibility(ids[2], View.GONE)
                v.setViewVisibility(ids[3], View.GONE)
                return
            }
            val done = ((p.plan - p.left) / p.plan).coerceIn(0.0, 1.0)
            if (hidden) {
                val sb = SpannableStringBuilder(dim("отложено "))
                sb.append(String.format(Locale("ru"), "%d%%", Math.round(done * 100)))
                v.setTextViewText(ids[1], sb)
                v.setViewVisibility(ids[2], View.GONE)
            } else {
                val sb = SpannableStringBuilder(dim("осталось "))
                sb.append(money(p.left))
                v.setTextViewText(ids[1], sb)
                v.setTextViewText(ids[2], "из " + money(p.plan))
                v.setViewVisibility(ids[2], View.VISIBLE)
            }
            v.setViewVisibility(ids[3], View.VISIBLE)
            v.setProgressBar(ids[3], 1000, (done * 1000).toInt(), false)
        }

        private fun emptyBudget(v: RemoteViews, block: Int, text: String) {
            val ids = blockIds(block)
            v.setViewVisibility(ids[0], View.VISIBLE)
            v.setTextViewText(ids[0], "Бюджет")
            v.setViewVisibility(ids[1], View.VISIBLE)
            v.setTextViewText(ids[1], dim(text))
            v.setViewVisibility(ids[2], View.GONE)
            v.setViewVisibility(ids[3], View.GONE)
        }

        private fun hideBlock(v: RemoteViews, block: Int) {
            for (id in blockIds(block)) v.setViewVisibility(id, View.GONE)
        }

        private fun blockIds(block: Int): IntArray = if (block == 1) {
            intArrayOf(R.id.b1_title, R.id.b1_main, R.id.b1_sub, R.id.b1_bar)
        } else {
            intArrayOf(R.id.b2_title, R.id.b2_main, R.id.b2_sub, R.id.b2_bar)
        }

        private fun dim(text: String): SpannableStringBuilder {
            val sb = SpannableStringBuilder(text)
            sb.setSpan(ForegroundColorSpan(DIM), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            sb.setSpan(AbsoluteSizeSpan(11, true), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            sb.setSpan(StyleSpan(android.graphics.Typeface.NORMAL), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            return sb
        }

        private fun payTitle(p: WidgetPayout) = p.name + " " + dateText(p.day)

        private fun lowerFirst(s: String) =
            if (s.isEmpty()) s else s.substring(0, 1).lowercase(Locale("ru")) + s.substring(1)

        // --- Форматирование ---

        private val moneyFormat: DecimalFormat by lazy {
            val symbols = DecimalFormatSymbols(Locale("ru"))
            symbols.groupingSeparator = ' '
            DecimalFormat("#,##0", symbols)
        }

        private fun money(v: Double) = moneyFormat.format(Math.round(v)) + " ₽"

        private fun signedMoney(v: Double) = (if (v >= 0) "+" else "−") + money(abs(v))

        private fun percent(v: Double) = String.format(Locale("ru"), "%.2f%%", v)

        private fun signed(v: Double) = (if (v >= 0) "+" else "−") + String.format(Locale("ru"), "%.2f", abs(v))

        private fun dateText(day: Int) = "${day % 100} ${months[(day / 100 % 100) - 1]}"

        private fun timeText(millis: Long): String {
            val c = Calendar.getInstance()
            c.timeInMillis = millis
            return if (WidgetData.dayOf(millis) == WidgetData.dayOf(System.currentTimeMillis())) {
                String.format(Locale("ru"), "%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
            } else {
                dateText(WidgetData.dayOf(millis))
            }
        }

        // --- График ---

        private fun chart(context: Context, values: List<Double>, sizeDp: SizeF): Bitmap {
            val density = context.resources.displayMetrics.density
            val w = (sizeDp.width * density).toInt().coerceIn(120, 1400)
            val h = (sizeDp.height * density).toInt().coerceIn(40, 600)
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)

            val lo = values.minOrNull() ?: 0.0
            val hi = values.maxOrNull() ?: 0.0
            val span = if (hi - lo < 1e-6) 1.0 else hi - lo
            val stroke = 2f * density
            val top = stroke * 2
            val bottom = h - stroke
            val xs = FloatArray(values.size) { i -> stroke + (w - 2 * stroke) * i / (values.size - 1).toFloat() }
            val ys = FloatArray(values.size) { i ->
                if (hi - lo < 1e-6) (top + bottom) / 2 else (bottom - (bottom - top) * ((values[i] - lo) / span)).toFloat()
            }

            val line = Path()
            line.moveTo(xs[0], ys[0])
            for (i in 1 until xs.size) {
                // Плавная линия: кривая через середины отрезков.
                val cx = (xs[i - 1] + xs[i]) / 2
                line.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i])
            }
            val fill = Path(line)
            fill.lineTo(xs.last(), h.toFloat())
            fill.lineTo(xs[0], h.toFloat())
            fill.close()

            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
            fillPaint.shader = LinearGradient(
                0f, min(ys.minOrNull() ?: 0f, bottom), 0f, h.toFloat(),
                Color.argb(56, 255, 255, 255), Color.argb(0, 255, 255, 255), Shader.TileMode.CLAMP,
            )
            canvas.drawPath(fill, fillPaint)

            val linePaint = Paint(Paint.ANTI_ALIAS_FLAG)
            linePaint.style = Paint.Style.STROKE
            linePaint.strokeWidth = stroke
            linePaint.strokeCap = Paint.Cap.ROUND
            linePaint.strokeJoin = Paint.Join.ROUND
            linePaint.color = TEXT
            canvas.drawPath(line, linePaint)
            return bmp
        }
    }
}
