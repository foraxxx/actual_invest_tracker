package com.investtracker.app.widget

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/** Позиция, цену которой виджет обновляет с биржи сам. */
class WidgetPosition(
    val secid: String,
    val board: String,
    val market: String,
    val qty: Double,
    /** Курс валюты бумаги к рублю на момент снимка. */
    val rate: Double,
    val price: Double,
    val prevClose: Double?,
)

class WidgetPayout(val name: String, val day: Int, val plan: Double, val left: Double)

/** Снимок из приложения. */
class WidgetSnapshot(
    val source: String,
    val title: String,
    val at: Long,
    val pricesAt: Long,
    val hidden: Boolean,
    val fixed: Double,
    val value: Double,
    val profit: Double,
    val positions: List<WidgetPosition>,
    val chart: List<Pair<Int, Double>>,
    val payouts: List<WidgetPayout>,
)

/** Что показать прямо сейчас. */
class WidgetState(
    val title: String,
    val value: Double,
    val dayRub: Double?,
    val dayPct: Double?,
    val profit: Double,
    val profitPct: Double?,
    val updatedAt: Long,
    val hidden: Boolean,
    val chart: List<Double>,
    val payouts: List<WidgetPayout>,
)

/**
 * Хранение данных виджета: снимок из приложения, свежие цены с биржи и
 * точки графика по дням. Всё лежит в одном небольшом файле настроек.
 */
object WidgetData {
    private const val PREFS = "invest_tracker_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_LIVE = "live"
    private const val KEY_LIVE_AT = "liveAt"
    private const val KEY_HIST = "hist"
    private const val KEY_HIST_SRC = "histSrc"
    private const val HIST_DAYS = 40

    val moscow: TimeZone = TimeZone.getTimeZone("Europe/Moscow")

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun dayOf(millis: Long, zone: TimeZone = TimeZone.getDefault()): Int {
        val c = Calendar.getInstance(zone)
        c.timeInMillis = millis
        return c.get(Calendar.YEAR) * 10000 + (c.get(Calendar.MONTH) + 1) * 100 + c.get(Calendar.DAY_OF_MONTH)
    }

    /** Новый снимок из приложения: старые цены виджета больше не нужны. */
    fun saveSnapshot(context: Context, json: String) {
        val snap = parse(json) ?: return
        val p = prefs(context)
        val hist = if (p.getString(KEY_HIST_SRC, null) == snap.source) readHist(p) else sortedMapOf<Int, Double>()
        // Готовый график из приложения точнее накопленного виджетом.
        for ((d, v) in snap.chart) hist[d] = v
        hist[dayOf(System.currentTimeMillis())] = snap.value
        p.edit()
            .putString(KEY_SNAPSHOT, json)
            .remove(KEY_LIVE)
            .remove(KEY_LIVE_AT)
            .putString(KEY_HIST_SRC, snap.source)
            .putString(KEY_HIST, writeHist(hist))
            .apply()
    }

    fun snapshot(context: Context): WidgetSnapshot? =
        prefs(context).getString(KEY_SNAPSHOT, null)?.let { parse(it) }

    fun liveAt(context: Context): Long = prefs(context).getLong(KEY_LIVE_AT, 0L)

    /** Свежие цены с биржи: бумага → (цена, закрытие прошлого дня). */
    fun saveLive(context: Context, prices: Map<String, Pair<Double, Double?>>) {
        val p = prefs(context)
        val o = JSONObject()
        for ((k, v) in prices) {
            val a = JSONArray().put(v.first)
            if (v.second != null) a.put(v.second!!)
            o.put(k, a)
        }
        p.edit().putString(KEY_LIVE, o.toString()).putLong(KEY_LIVE_AT, System.currentTimeMillis()).apply()
        state(context)?.let { recordDay(context, it.value) }
    }

    private fun readLive(p: SharedPreferences): Map<String, Pair<Double, Double?>> {
        val raw = p.getString(KEY_LIVE, null) ?: return emptyMap()
        return try {
            val o = JSONObject(raw)
            val result = HashMap<String, Pair<Double, Double?>>()
            val keys = o.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                val a = o.getJSONArray(k)
                result[k] = Pair(a.getDouble(0), if (a.length() > 1) a.getDouble(1) else null)
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun recordDay(context: Context, value: Double) {
        val p = prefs(context)
        val hist = readHist(p)
        hist[dayOf(System.currentTimeMillis())] = value
        p.edit().putString(KEY_HIST, writeHist(hist)).apply()
    }

    private fun readHist(p: SharedPreferences): java.util.SortedMap<Int, Double> {
        val result = sortedMapOf<Int, Double>()
        val raw = p.getString(KEY_HIST, null) ?: return result
        try {
            val a = JSONArray(raw)
            for (i in 0 until a.length()) {
                val e = a.getJSONArray(i)
                result[e.getInt(0)] = e.getDouble(1)
            }
        } catch (e: Exception) {
        }
        return result
    }

    private fun writeHist(hist: java.util.SortedMap<Int, Double>): String {
        val a = JSONArray()
        val keep = hist.keys.toList().takeLast(HIST_DAYS)
        for (d in keep) a.put(JSONArray().put(d).put(hist[d]))
        return a.toString()
    }

    /** Стоимость и изменения с учётом свежих цен. null — снимка ещё нет. */
    fun state(context: Context): WidgetState? {
        val p = prefs(context)
        val snap = snapshot(context) ?: return null
        val live = readLive(p)
        val liveAt = p.getLong(KEY_LIVE_AT, 0L)

        var value = snap.fixed
        var dayRub = 0.0
        var dayBase = 0.0
        var anyDay = false
        for (pos in snap.positions) {
            val l = live[pos.secid]
            val price = l?.first ?: pos.price
            val prev = l?.second ?: pos.prevClose
            value += pos.qty * price * pos.rate
            if (prev != null && prev > 0) {
                anyDay = true
                dayRub += pos.qty * (price - prev) * pos.rate
                dayBase += pos.qty * prev * pos.rate
            }
        }
        val profit = snap.profit + (value - snap.value)
        val invested = value - profit
        val hist = readHist(p)
        hist[dayOf(System.currentTimeMillis())] = value
        val fromDay = dayOf(System.currentTimeMillis() - 31L * 24 * 3600 * 1000)
        val chart = hist.filterKeys { it >= fromDay }.values.toList()

        return WidgetState(
            title = snap.title,
            value = value,
            dayRub = if (anyDay) dayRub else null,
            dayPct = if (anyDay && dayBase > 0) dayRub / dayBase * 100 else null,
            profit = profit,
            profitPct = if (invested > 1) profit / invested * 100 else null,
            updatedAt = maxOf(snap.pricesAt, liveAt),
            hidden = snap.hidden,
            chart = chart,
            payouts = snap.payouts,
        )
    }

    private fun parse(json: String): WidgetSnapshot? = try {
        val o = JSONObject(json)
        val pos = ArrayList<WidgetPosition>()
        val pa = o.optJSONArray("pos") ?: JSONArray()
        for (i in 0 until pa.length()) {
            val e = pa.getJSONObject(i)
            pos.add(
                WidgetPosition(
                    secid = e.getString("s"),
                    board = e.getString("b"),
                    market = e.getString("m"),
                    qty = e.getDouble("q"),
                    rate = e.optDouble("k", 1.0),
                    price = e.getDouble("p"),
                    prevClose = if (e.has("c")) e.getDouble("c") else null,
                )
            )
        }
        val chart = ArrayList<Pair<Int, Double>>()
        val ca = o.optJSONArray("chart") ?: JSONArray()
        for (i in 0 until ca.length()) {
            val e = ca.getJSONArray(i)
            chart.add(Pair(e.getInt(0), e.getDouble(1)))
        }
        val pays = ArrayList<WidgetPayout>()
        val ya = o.optJSONArray("pay") ?: JSONArray()
        for (i in 0 until ya.length()) {
            val e = ya.getJSONObject(i)
            pays.add(WidgetPayout(e.getString("n"), e.getInt("d"), e.optDouble("plan", 0.0), e.optDouble("left", 0.0)))
        }
        WidgetSnapshot(
            source = o.optString("src", "all"),
            title = o.optString("title", "Портфель"),
            at = o.optLong("at", 0L),
            pricesAt = o.optLong("pricesAt", 0L),
            hidden = o.optBoolean("hidden", false),
            fixed = o.optDouble("fixed", 0.0),
            value = o.optDouble("value", 0.0),
            profit = o.optDouble("profit", 0.0),
            positions = pos,
            chart = chart,
            payouts = pays,
        )
    } catch (e: Exception) {
        null
    }
}
