package com.investtracker.app.widget

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import com.investtracker.app.R
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Собирает одну раскладку виджета под конкретный размер (в точках): что
 * показать — из конструктора, как — из оформления.
 *
 * Размер карточки, отступ под тень и высота «по содержимому» задаются
 * только на Android 12+ (флаг modern) — на старых версиях этих вызовов нет.
 */
@SuppressLint("NewApi")
object WidgetRenderer {
    private val ru = Locale("ru")
    private val months = arrayOf(
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    )

    /** Цвета текущего оформления. */
    private class Colors(st: StyleCfg) {
        val text = 0xFF000000.toInt() or st.text
        val dim = 0x94000000.toInt() or st.text
        val line = 0x24000000 or st.text
        val up = 0xFF000000.toInt() or st.up
        val down = 0xFF000000.toInt() or st.down
        val accent = 0xFF000000.toInt() or st.accent
    }

    /** Название размера: столбцы и ряды клеток. */
    fun sizeName(widthDp: Float, heightDp: Float): String {
        val cols = when {
            widthDp < 200f -> 2
            widthDp < 300f -> 3
            else -> 4
        }
        val rows = if (heightDp < 130f) 1 else 2
        return "s$cols$rows"
    }

    private fun layoutOf(name: String) = when (name) {
        "s21" -> R.layout.widget_small
        "s31", "s41" -> R.layout.widget_wide
        "s22" -> R.layout.widget_square
        "s32" -> R.layout.widget_mid
        else -> R.layout.widget_large
    }

    fun build(
        context: Context,
        widthDp: Float,
        heightDp: Float,
        state: WidgetState?,
        click: PendingIntent,
        modern: Boolean,
        eye: PendingIntent? = null,
    ): RemoteViews {
        val name = sizeName(widthDp, heightDp)
        val v = RemoteViews(context.packageName, layoutOf(name))
        v.setOnClickPendingIntent(R.id.root, click)
        if (eye != null) v.setOnClickPendingIntent(R.id.eye, eye)
        val st = state?.style ?: StyleCfg()
        val sc = state?.size(name) ?: SizeCfg.defaults(name)
        val c = Colors(st)
        val shadow = modern && st.shadow != "none"

        frame(v, st, sc, widthDp, heightDp, modern)
        paint(v, c)

        if (state == null) {
            v.setTextViewText(R.id.title, "Invest Tracker")
            v.setTextViewText(R.id.value, "—")
            v.setTextViewText(R.id.day, "Откройте приложение")
            v.setTextColor(R.id.day, c.dim)
            v.setViewVisibility(R.id.total, View.GONE)
            for (id in intArrayOf(R.id.budget_box, R.id.list_box, R.id.chart_box, R.id.bl_box, R.id.month_box, R.id.div, R.id.vdiv, R.id.right)) {
                v.setViewVisibility(id, View.GONE)
            }
            return v
        }

        header(v, state, sc, c, name)

        // Размер карточки и графика в точках — для картинки графика.
        val cardW = widthDp * sc.width / 100f - if (shadow) 12f else 0f
        val cardH = heightDp * (if (modern) sc.height else 100) / 100f - if (shadow) 12f else 0f
        val contentW = cardW - 28f
        val valueH = when (name) {
            "s21", "s31", "s41" -> 25f
            "s32" -> 32f
            else -> 30f
        }
        val headerH = 13f + valueH + (if (sc.today) 14f else 0f) + (if (sc.total) 15f else 0f)
        val fit = modern && sc.fit

        when (name) {
            "s21" -> {
                if (sc.budgetOnly) {
                    v.setViewVisibility(R.id.hdr, View.GONE)
                    budgetBlock(v, state, c, withNext = true)
                } else {
                    v.setViewVisibility(R.id.budget_box, View.GONE)
                }
            }
            "s31", "s41" -> {
                hideAll(v, R.id.budget_box, R.id.list_box, R.id.chart_box)
                when (sc.slot) {
                    "budget" -> {
                        v.setViewVisibility(R.id.budget_box, View.VISIBLE)
                        budgetBlock(v, state, c, withNext = true)
                    }
                    "chart" -> chart(v, context, state, c, (contentW - 25f) / 2f, 52f)
                    "payouts", "leaders" -> list(v, state, c, sc.slot, wide = true)
                    else -> hideAll(v, R.id.right, R.id.vdiv)
                }
            }
            "s22", "s32" -> {
                hideAll(v, R.id.div, R.id.budget_box, R.id.list_box, R.id.chart_box, R.id.bl_box)
                if (fit) v.setViewLayoutHeight(R.id.slot, ViewGroup.LayoutParams.WRAP_CONTENT.toFloat(), TypedValue.COMPLEX_UNIT_PX)
                val lineH = if (sc.slot == "chartBudget") 30f else 0f
                val chartH = if (fit) 56f else max(30f, cardH - 24f - headerH - 8f - lineH)
                when (sc.slot) {
                    "chart", "chartBudget" -> {
                        chart(v, context, state, c, contentW, chartH)
                        if (fit) v.setViewLayoutHeight(R.id.chart_box, 56f, TypedValue.COMPLEX_UNIT_DIP)
                        if (sc.slot == "chartBudget") budgetLine(v, state, c)
                    }
                    "budget" -> {
                        v.setViewVisibility(R.id.div, View.VISIBLE)
                        v.setViewVisibility(R.id.budget_box, View.VISIBLE)
                        budgetBlock(v, state, c, withNext = true)
                    }
                    "payouts", "leaders" -> {
                        v.setViewVisibility(R.id.div, View.VISIBLE)
                        list(v, state, c, sc.slot, wide = false)
                    }
                    else -> v.setViewVisibility(R.id.slot, View.GONE)
                }
            }
            else -> {
                hideAll(v, R.id.budget_box, R.id.list_box, R.id.month_box, R.id.chart_box)
                if (sc.chart) {
                    val chartH = if (fit) 60f else max(30f, cardH - 24f - headerH - 8f)
                    chart(v, context, state, c, (contentW - 25f) * 0.58f, chartH)
                    if (fit) v.setViewLayoutHeight(R.id.chart_box, 60f, TypedValue.COMPLEX_UNIT_DIP)
                }
                when (sc.slot) {
                    "budget" -> budgetColumn(v, state, c)
                    "payouts", "leaders" -> list(v, state, c, sc.slot, wide = false)
                    else -> hideAll(v, R.id.right, R.id.vdiv)
                }
            }
        }
        return v
    }

    private fun hideAll(v: RemoteViews, vararg ids: Int) {
        for (id in ids) v.setViewVisibility(id, View.GONE)
    }

    // --- Карточка и цвета ---

    private fun frame(v: RemoteViews, st: StyleCfg, sc: SizeCfg, w: Float, h: Float, modern: Boolean) {
        val (fill, stroke, edge, shadowRes) = when (st.radius) {
            "small" -> listOf(R.drawable.wfill_s, R.drawable.wstroke_s, R.drawable.wedge_s, R.drawable.wshadow_s)
            "large" -> listOf(R.drawable.wfill_l, R.drawable.wstroke_l, R.drawable.wedge_l, R.drawable.wshadow_l)
            else -> listOf(R.drawable.wfill_sys, R.drawable.wstroke_sys, R.drawable.wedge_sys, R.drawable.wshadow_sys)
        }
        v.setImageViewResource(R.id.fill, fill)
        v.setInt(R.id.fill, "setColorFilter", 0xFF000000.toInt() or st.bg)
        v.setInt(R.id.fill, "setImageAlpha", st.bgAlpha * 255 / 100)

        val borderAlpha = st.borderAlpha * 255 / 100
        val borderColor = 0xFF000000.toInt() or st.borderColor
        when (st.border) {
            "none" -> hideAll(v, R.id.stroke, R.id.edge)
            "edge" -> {
                v.setImageViewResource(R.id.stroke, stroke)
                v.setInt(R.id.stroke, "setColorFilter", borderColor)
                v.setInt(R.id.stroke, "setImageAlpha", borderAlpha / 3)
                v.setViewVisibility(R.id.edge, View.VISIBLE)
                v.setImageViewResource(R.id.edge, edge)
                v.setInt(R.id.edge, "setColorFilter", borderColor)
                v.setInt(R.id.edge, "setImageAlpha", min(255, borderAlpha * 2))
                v.setInt(R.id.edge, "setImageLevel", 4000)
            }
            else -> {
                v.setImageViewResource(R.id.stroke, stroke)
                v.setInt(R.id.stroke, "setColorFilter", borderColor)
                v.setInt(R.id.stroke, "setImageAlpha", borderAlpha)
            }
        }

        if (!modern) return
        if (st.shadow != "none") {
            v.setViewVisibility(R.id.shadow, View.VISIBLE)
            v.setImageViewResource(R.id.shadow, shadowRes)
            v.setInt(R.id.shadow, "setImageAlpha", if (st.shadow == "strong") 255 else 150)
            for (side in intArrayOf(RemoteViews.MARGIN_LEFT, RemoteViews.MARGIN_TOP, RemoteViews.MARGIN_RIGHT, RemoteViews.MARGIN_BOTTOM)) {
                v.setViewLayoutMargin(R.id.inner, side, 6f, TypedValue.COMPLEX_UNIT_DIP)
            }
        }
        val vertical = when (sc.align) {
            "top" -> Gravity.TOP
            "bottom" -> Gravity.BOTTOM
            else -> Gravity.CENTER_VERTICAL
        }
        v.setInt(R.id.root, "setGravity", Gravity.CENTER_HORIZONTAL or vertical)
        if (sc.width < 100) {
            v.setViewLayoutWidth(android.R.id.background, w * sc.width / 100f, TypedValue.COMPLEX_UNIT_DIP)
        }
        if (sc.fit) {
            val wrap = ViewGroup.LayoutParams.WRAP_CONTENT.toFloat()
            v.setViewLayoutHeight(android.R.id.background, wrap, TypedValue.COMPLEX_UNIT_PX)
            v.setViewLayoutHeight(R.id.inner, wrap, TypedValue.COMPLEX_UNIT_PX)
            v.setViewLayoutHeight(R.id.content, wrap, TypedValue.COMPLEX_UNIT_PX)
        } else if (sc.height < 100) {
            v.setViewLayoutHeight(android.R.id.background, h * sc.height / 100f, TypedValue.COMPLEX_UNIT_DIP)
        }
    }

    private val textIds = intArrayOf(
        R.id.value, R.id.b1_main, R.id.b2_main, R.id.bl_val,
        R.id.r1_name, R.id.r2_name, R.id.r3_name, R.id.r1_val, R.id.r2_val, R.id.r3_val,
    )
    private val dimIds = intArrayOf(
        R.id.title, R.id.time, R.id.total, R.id.b1_title, R.id.b1_sub, R.id.b2_title, R.id.b2_sub,
        R.id.l_title, R.id.r1_sub, R.id.r2_sub, R.id.r3_sub, R.id.bl_title, R.id.m_text, R.id.chart_empty,
    )
    private val bars = intArrayOf(R.id.b1_bar, R.id.b2_bar, R.id.bl_bar, R.id.m_bar)

    private fun barFg(bar: Int) = when (bar) {
        R.id.b1_bar -> R.id.b1_bar_fg
        R.id.b2_bar -> R.id.b2_bar_fg
        R.id.bl_bar -> R.id.bl_bar_fg
        else -> R.id.m_bar_fg
    }

    private fun barBg(bar: Int) = when (bar) {
        R.id.b1_bar -> R.id.b1_bar_bg
        R.id.b2_bar -> R.id.b2_bar_bg
        R.id.bl_bar -> R.id.bl_bar_bg
        else -> R.id.m_bar_bg
    }

    private fun paint(v: RemoteViews, c: Colors) {
        for (id in textIds) v.setTextColor(id, c.text)
        for (id in dimIds) v.setTextColor(id, c.dim)
        v.setInt(R.id.div, "setBackgroundColor", c.line)
        v.setInt(R.id.vdiv, "setBackgroundColor", c.line)
        for (b in bars) {
            v.setInt(barBg(b), "setColorFilter", c.text)
            v.setInt(barFg(b), "setColorFilter", c.accent)
        }
    }

    private fun progress(v: RemoteViews, bar: Int, share: Double) {
        v.setViewVisibility(bar, View.VISIBLE)
        v.setInt(barFg(bar), "setImageLevel", (share.coerceIn(0.0, 1.0) * 10000).toInt())
    }

    // --- Шапка ---

    private fun header(v: RemoteViews, s: WidgetState, sc: SizeCfg, c: Colors, name: String) {
        v.setTextViewText(R.id.title, s.title)
        if (sc.time) {
            v.setViewVisibility(R.id.time, View.VISIBLE)
            v.setTextViewText(R.id.time, timeText(s.updatedAt))
        }
        v.setTextViewText(R.id.value, if (s.hidden) "••••••" else money(s.value))
        v.setImageViewResource(R.id.eye, if (s.hidden) R.drawable.weye_off else R.drawable.weye_on)
        v.setInt(R.id.eye, "setColorFilter", c.dim)

        if (!sc.today) {
            v.setViewVisibility(R.id.day, View.GONE)
        } else {
            val dayRub = s.dayRub
            if (dayRub == null) {
                v.setTextViewText(R.id.day, "Нет цен с биржи")
                v.setTextColor(R.id.day, c.dim)
            } else {
                val up = dayRub >= 0
                val arrow = if (up) "▲ " else "▼ "
                val pct = s.dayPct?.let { percent(abs(it)) }
                val main = if (s.hidden) arrow + (pct ?: "") else arrow + money(abs(dayRub)) + (if (pct != null) " · $pct" else "")
                val sb = SpannableStringBuilder(main)
                // Слово «сегодня» — там, где ширины хватает.
                if (name == "s32" || name == "s42" || s.hidden) {
                    val start = sb.length
                    sb.append(" сегодня")
                    sb.setSpan(ForegroundColorSpan(c.dim), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    sb.setSpan(StyleSpan(Typeface.NORMAL), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                v.setTextViewText(R.id.day, sb)
                v.setTextColor(R.id.day, if (up) c.up else c.down)
            }
        }

        if (!sc.total) {
            v.setViewVisibility(R.id.total, View.GONE)
        } else {
            val sb = SpannableStringBuilder("за всё время ")
            val amount = if (s.hidden) {
                s.profitPct?.let { signed(it) + "%" } ?: "•••"
            } else {
                signedMoney(s.profit)
            }
            val start = sb.length
            sb.append(amount)
            sb.setSpan(ForegroundColorSpan(if (s.profit >= 0) c.up else c.down), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            v.setTextViewText(R.id.total, sb)
        }
    }

    // --- График ---

    private fun chart(v: RemoteViews, context: Context, s: WidgetState, c: Colors, wDp: Float, hDp: Float) {
        v.setViewVisibility(R.id.chart_box, View.VISIBLE)
        if (s.chart.size >= 2) {
            v.setImageViewBitmap(R.id.chart, chartBitmap(context, s.chart, wDp, hDp, c.accent))
            v.setViewVisibility(R.id.chart_empty, View.GONE)
        } else {
            v.setViewVisibility(R.id.chart, View.GONE)
            v.setViewVisibility(R.id.chart_empty, View.VISIBLE)
        }
    }

    private fun chartBitmap(context: Context, values: List<Double>, wDp: Float, hDp: Float, color: Int): Bitmap {
        val density = context.resources.displayMetrics.density
        val w = (max(wDp, 40f) * density).toInt().coerceIn(80, 1200)
        val h = (max(hDp, 24f) * density).toInt().coerceIn(40, 500)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        val lo = values.minOrNull() ?: 0.0
        val hi = values.maxOrNull() ?: 0.0
        val flat = hi - lo < 1e-6
        val span = if (flat) 1.0 else hi - lo
        val stroke = 1.8f * density
        val top = stroke * 2
        val bottom = h - stroke
        val xs = FloatArray(values.size) { i -> stroke + (w - 2 * stroke) * i / (values.size - 1).toFloat() }
        val ys = FloatArray(values.size) { i ->
            if (flat) (top + bottom) / 2 else (bottom - (bottom - top) * ((values[i] - lo) / span)).toFloat()
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

        val rgb = color and 0xFFFFFF
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        fillPaint.shader = LinearGradient(
            0f, min(ys.minOrNull() ?: 0f, bottom), 0f, h.toFloat(),
            (0x38 shl 24) or rgb, rgb, Shader.TileMode.CLAMP,
        )
        canvas.drawPath(fill, fillPaint)

        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = stroke
        linePaint.strokeCap = Paint.Cap.ROUND
        linePaint.strokeJoin = Paint.Join.ROUND
        linePaint.color = color
        canvas.drawPath(line, linePaint)
        return bmp
    }

    // --- Бюджет ---

    private class Pays(val current: WidgetPayout?, val next: WidgetPayout?, val upcoming: List<WidgetPayout>)

    private fun pays(s: WidgetState): Pays {
        val today = WidgetData.dayOf(System.currentTimeMillis())
        val sorted = s.payouts.sortedBy { it.day }
        val upcoming = sorted.filter { it.day > today }
        return Pays(sorted.lastOrNull { it.day <= today }, upcoming.firstOrNull(), upcoming)
    }

    private fun emptyBudget(s: WidgetState) = s.payouts.isEmpty() || s.payouts.all { it.plan <= 0.5 }

    /** Ближайшая выплата одним блоком (b1). */
    private fun budgetBlock(v: RemoteViews, s: WidgetState, c: Colors, withNext: Boolean) {
        v.setViewVisibility(R.id.budget_box, View.VISIBLE)
        val p = pays(s)
        val cur = p.current
        when {
            emptyBudget(s) -> emptyBlock(v, c, 1)
            cur != null && cur.plan > 0.5 && cur.left > 0.5 -> left(v, c, 1, cur, s.hidden)
            cur != null && cur.plan > 0.5 -> done(v, c, 1, cur, if (withNext) p.next else null)
            p.next != null -> left(v, c, 1, p.next, s.hidden)
            else -> emptyBlock(v, c, 1)
        }
    }

    /** Правая колонка 4×2: текущая выплата, следующая и итог месяца. */
    private fun budgetColumn(v: RemoteViews, s: WidgetState, c: Colors) {
        v.setViewVisibility(R.id.budget_box, View.VISIBLE)
        val p = pays(s)
        val cur = p.current
        var second: WidgetPayout? = p.next
        when {
            emptyBudget(s) -> {
                emptyBlock(v, c, 1)
                second = null
            }
            cur != null && cur.plan > 0.5 && cur.left > 0.5 -> left(v, c, 1, cur, s.hidden)
            cur != null && cur.plan > 0.5 -> done(v, c, 1, cur, null)
            p.next != null -> {
                left(v, c, 1, p.next, s.hidden)
                second = p.upcoming.getOrNull(1)
            }
            else -> {
                emptyBlock(v, c, 1)
                second = null
            }
        }
        if (second == null) {
            hideAll(v, R.id.b_gap, R.id.b2_title, R.id.b2_main, R.id.b2_sub, R.id.b2_bar)
        } else {
            left(v, c, 2, second, s.hidden)
        }
        val m = s.month
        if (m != null && m.plan > 0.5) {
            v.setViewVisibility(R.id.month_box, View.VISIBLE)
            val share = (m.done / m.plan).coerceIn(0.0, 1.0)
            val sb = SpannableStringBuilder(m.name + ": отложено ")
            val start = sb.length
            sb.append(String.format(ru, "%d%%", Math.round(share * 100)))
            sb.setSpan(ForegroundColorSpan(c.text), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            v.setTextViewText(R.id.m_text, sb)
            progress(v, R.id.m_bar, share)
        }
    }

    /** Ближайшая выплата одной строкой (3×2). */
    private fun budgetLine(v: RemoteViews, s: WidgetState, c: Colors) {
        if (emptyBudget(s)) return
        val p = pays(s)
        val cur = p.current
        val pay = if (cur != null && cur.plan > 0.5 && cur.left > 0.5) cur else p.next ?: return
        v.setViewVisibility(R.id.bl_box, View.VISIBLE)
        v.setTextViewText(R.id.bl_title, payTitle(pay))
        val share = if (pay.plan > 0.5) ((pay.plan - pay.left) / pay.plan).coerceIn(0.0, 1.0) else 0.0
        val sb = SpannableStringBuilder(dim(if (s.hidden) "отложено " else "осталось ", c))
        sb.append(if (s.hidden) String.format(ru, "%d%%", Math.round(share * 100)) else money(pay.left))
        v.setTextViewText(R.id.bl_val, sb)
        progress(v, R.id.bl_bar, share)
    }

    private fun ids(block: Int) = if (block == 1) {
        intArrayOf(R.id.b1_title, R.id.b1_main, R.id.b1_sub, R.id.b1_bar)
    } else {
        intArrayOf(R.id.b2_title, R.id.b2_main, R.id.b2_sub, R.id.b2_bar)
    }

    private fun left(v: RemoteViews, c: Colors, block: Int, p: WidgetPayout, hidden: Boolean) {
        val id = ids(block)
        v.setTextViewText(id[0], payTitle(p))
        if (p.plan <= 0.5) {
            v.setTextViewText(id[1], dim("ещё не распределено", c))
            hideAll(v, id[2], id[3])
            return
        }
        val share = ((p.plan - p.left) / p.plan).coerceIn(0.0, 1.0)
        val sb = SpannableStringBuilder(dim(if (hidden) "отложено " else "осталось ", c))
        sb.append(if (hidden) String.format(ru, "%d%%", Math.round(share * 100)) else money(p.left))
        v.setTextViewText(id[1], sb)
        if (hidden) {
            v.setViewVisibility(id[2], View.GONE)
        } else {
            v.setTextViewText(id[2], "из " + money(p.plan))
        }
        progress(v, id[3], share)
    }

    private fun done(v: RemoteViews, c: Colors, block: Int, p: WidgetPayout, next: WidgetPayout?) {
        val id = ids(block)
        v.setTextViewText(id[0], payTitle(p))
        val sb = SpannableStringBuilder("Всё отложено ✓")
        sb.setSpan(ForegroundColorSpan(c.up), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        v.setTextViewText(id[1], sb)
        if (next != null) {
            v.setTextViewText(id[2], "дальше " + lowerFirst(next.name) + " " + dateText(next.day))
        } else {
            v.setViewVisibility(id[2], View.GONE)
        }
        v.setViewVisibility(id[3], View.GONE)
    }

    private fun emptyBlock(v: RemoteViews, c: Colors, block: Int) {
        val id = ids(block)
        v.setTextViewText(id[0], "Бюджет")
        v.setTextViewText(id[1], dim("не заполнен", c))
        hideAll(v, id[2], id[3])
    }

    // --- Списки: выплаты по бумагам и лидеры дня ---

    private val rows = intArrayOf(R.id.r1, R.id.r2, R.id.r3)
    private val rowName = intArrayOf(R.id.r1_name, R.id.r2_name, R.id.r3_name)
    private val rowVal = intArrayOf(R.id.r1_val, R.id.r2_val, R.id.r3_val)
    private val rowSub = intArrayOf(R.id.r1_sub, R.id.r2_sub, R.id.r3_sub)

    private fun list(v: RemoteViews, s: WidgetState, c: Colors, kind: String, wide: Boolean) {
        v.setViewVisibility(R.id.list_box, View.VISIBLE)
        for (r in rows) v.setViewVisibility(r, View.GONE)
        if (kind == "payouts") {
            v.setTextViewText(R.id.l_title, "Выплаты по бумагам")
            val items = s.dividends.take(if (wide) 1 else 2)
            if (items.isEmpty()) return emptyRow(v, c, "пока не объявлены")
            items.forEachIndexed { i, d ->
                v.setViewVisibility(rows[i], View.VISIBLE)
                v.setTextViewText(rowName[i], d.name)
                v.setTextViewText(rowVal[i], if (s.hidden) "•••" else money(d.rub))
                v.setTextViewText(rowSub[i], d.kind + " " + dateText(d.day))
            }
        } else {
            v.setTextViewText(R.id.l_title, "Сегодня в портфеле")
            val items = s.leaders.take(if (wide) 2 else 3)
            if (items.isEmpty()) return emptyRow(v, c, "нет цен с биржи")
            items.forEachIndexed { i, (name, pct) ->
                v.setViewVisibility(rows[i], View.VISIBLE)
                v.setTextViewText(rowName[i], name)
                v.setTextViewText(rowVal[i], (if (pct >= 0) "▲ " else "▼ ") + percent(abs(pct)))
                v.setTextColor(rowVal[i], if (pct >= 0) c.up else c.down)
                v.setViewVisibility(rowSub[i], View.GONE)
            }
        }
    }

    private fun emptyRow(v: RemoteViews, c: Colors, text: String) {
        v.setViewVisibility(rows[0], View.VISIBLE)
        v.setTextViewText(rowName[0], text)
        v.setTextColor(rowName[0], c.dim)
        v.setTextViewText(rowVal[0], "")
        v.setViewVisibility(rowSub[0], View.GONE)
    }

    // --- Форматирование ---

    private fun dim(text: String, c: Colors): SpannableStringBuilder {
        val sb = SpannableStringBuilder(text)
        sb.setSpan(ForegroundColorSpan(c.dim), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.setSpan(AbsoluteSizeSpan(11, true), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.setSpan(StyleSpan(Typeface.NORMAL), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return sb
    }

    private fun payTitle(p: WidgetPayout) = p.name + " " + dateText(p.day)

    private fun lowerFirst(s: String) =
        if (s.isEmpty()) s else s.substring(0, 1).lowercase(ru) + s.substring(1)

    private val moneyFormat: DecimalFormat by lazy {
        val symbols = DecimalFormatSymbols(ru)
        symbols.groupingSeparator = ' '
        DecimalFormat("#,##0", symbols)
    }

    private fun money(v: Double) = moneyFormat.format(Math.round(v)) + " ₽"

    private fun signedMoney(v: Double) = (if (v >= 0) "+" else "−") + money(abs(v))

    private fun percent(v: Double) = String.format(ru, "%.2f%%", v)

    private fun signed(v: Double) = (if (v >= 0) "+" else "−") + String.format(ru, "%.2f", abs(v))

    private fun dateText(day: Int) = "${day % 100} ${months[(day / 100 % 100) - 1]}"

    private fun timeText(millis: Long): String {
        val c = Calendar.getInstance()
        c.timeInMillis = millis
        return if (WidgetData.dayOf(millis) == WidgetData.dayOf(System.currentTimeMillis())) {
            String.format(ru, "%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
        } else {
            dateText(WidgetData.dayOf(millis))
        }
    }
}
