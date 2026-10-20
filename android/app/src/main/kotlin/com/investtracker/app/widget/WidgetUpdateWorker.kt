package com.investtracker.app.widget

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Обновляет цены для виджета раз в полчаса.
 *
 * Чтобы не тратить батарею:
 * - работает, только пока на телефоне стоит хотя бы один виджет;
 * - система запускает его, только когда есть сеть и заряд не низкий, и сама
 *   откладывает запуск, пока телефон спит;
 * - вне торговых часов Мосбиржи в сеть не ходит вовсе;
 * - на каждый режим торгов — один короткий запрос только по своим бумагам;
 * - Flutter не запускается: всё считается здесь, по снимку из приложения.
 */
class WidgetUpdateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val context = applicationContext
        if (PortfolioWidgetProvider.ids(context).isEmpty()) {
            cancel(context)
            return Result.success()
        }
        val snap = WidgetData.snapshot(context)
        val now = System.currentTimeMillis()
        val fresh = now - maxOf(snap?.pricesAt ?: 0L, WidgetData.liveAt(context)) < 20 * 60 * 1000L
        if (snap != null && snap.positions.isNotEmpty() && isTradingTime() && !fresh) {
            try {
                val prices = fetch(snap.positions)
                if (prices.isNotEmpty()) WidgetData.saveLive(context, prices)
            } catch (e: Exception) {
                // Нет связи — покажем прежние цены, следующая попытка через полчаса.
            }
        }
        // Перерисовываем всегда: могла смениться дата выплаты в бюджете.
        PortfolioWidgetProvider.updateAll(context)
        return Result.success()
    }

    private fun fetch(positions: List<WidgetPosition>): Map<String, Pair<Double, Double?>> {
        val result = HashMap<String, Pair<Double, Double?>>()
        val groups = positions.groupBy { it.market + "/" + it.board }
        for ((_, list) in groups) {
            val market = list[0].market
            val board = list[0].board
            // Биржа отдаёт не больше десяти бумаг за запрос.
            for (chunk in list.map { it.secid }.distinct().chunked(10)) {
                try {
                    result.putAll(fetchBoard(market, board, chunk))
                } catch (e: Exception) {
                    // Один режим не ответил — остальные всё равно обновим.
                }
            }
        }
        return result
    }

    private fun fetchBoard(market: String, board: String, secids: List<String>): Map<String, Pair<Double, Double?>> {
        val query = "iss.meta=off&iss.only=securities,marketdata" +
            "&securities.columns=SECID,PREVPRICE,PREVLEGALCLOSEPRICE,FACEVALUE" +
            "&marketdata.columns=SECID,LAST,LCURRENTPRICE,MARKETPRICE" +
            "&securities=" + URLEncoder.encode(secids.joinToString(","), "UTF-8")
        val url = URL("https://iss.moex.com/iss/engines/stock/markets/$market/boards/$board/securities.json?$query")
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 10000
        conn.readTimeout = 10000
        conn.setRequestProperty("Accept", "application/json")
        try {
            if (conn.responseCode != 200) return emptyMap()
            val body = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val json = JSONObject(body)
            val sec = rows(json, "securities")
            val md = rows(json, "marketdata").associateBy { it.optString("SECID") }
            val bonds = market == "bonds"
            val result = HashMap<String, Pair<Double, Double?>>()
            for (s in sec) {
                val id = s.optString("SECID")
                if (id.isEmpty()) continue
                val m = md[id]
                val raw = listOf(
                    num(m, "LAST"), num(m, "LCURRENTPRICE"), num(m, "MARKETPRICE"),
                    num(s, "PREVPRICE"), num(s, "PREVLEGALCLOSEPRICE"),
                ).firstOrNull { it != null && it > 0 } ?: continue
                val prevRaw = num(s, "PREVLEGALCLOSEPRICE")?.takeIf { it > 0 } ?: num(s, "PREVPRICE")?.takeIf { it > 0 }
                // Облигации котируются в процентах от номинала.
                val face = if (bonds) num(s, "FACEVALUE")?.takeIf { it > 0 } else null
                val k = if (face != null) face / 100 else 1.0
                result[id] = Pair(raw * k, prevRaw?.let { it * k })
            }
            return result
        } finally {
            conn.disconnect()
        }
    }

    private fun rows(json: JSONObject, name: String): List<JSONObject> {
        val t = json.optJSONObject(name) ?: return emptyList()
        val cols = t.optJSONArray("columns") ?: return emptyList()
        val data = t.optJSONArray("data") ?: return emptyList()
        val result = ArrayList<JSONObject>()
        for (i in 0 until data.length()) {
            val row = data.optJSONArray(i) ?: continue
            val o = JSONObject()
            for (c in 0 until cols.length()) o.put(cols.getString(c), row.opt(c))
            result.add(o)
        }
        return result
    }

    private fun num(o: JSONObject?, key: String): Double? {
        if (o == null || !o.has(key) || o.isNull(key)) return null
        val d = o.optDouble(key)
        return if (d.isNaN()) null else d
    }

    companion object {
        private const val WORK = "invest_tracker_widget_update"

        /**
         * Торговые часы Мосбиржи по Москве: в будни с 7:00 до полуночи
         * (утренняя, основная и вечерняя сессии), в выходные с 10:00 до 19:30.
         */
        fun isTradingTime(): Boolean {
            val c = Calendar.getInstance(WidgetData.moscow)
            val minutes = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
            val weekend = c.get(Calendar.DAY_OF_WEEK).let { it == Calendar.SATURDAY || it == Calendar.SUNDAY }
            return if (weekend) minutes in (10 * 60)..(19 * 60 + 30) else minutes >= 7 * 60
        }

        fun schedule(context: Context) {
            if (PortfolioWidgetProvider.ids(context).isEmpty()) return
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()
            val request = PeriodicWorkRequest.Builder(WidgetUpdateWorker::class.java, 30, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context.applicationContext).cancelUniqueWork(WORK)
        }
    }
}
