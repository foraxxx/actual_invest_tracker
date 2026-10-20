package com.investtracker.app

import com.investtracker.app.widget.PortfolioWidgetProvider
import com.investtracker.app.widget.WidgetData
import com.investtracker.app.widget.WidgetUpdateWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Приложение присылает снимок для виджета на экране телефона.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "invest_tracker/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val json = call.arguments as? String
                        if (json != null) {
                            WidgetData.saveSnapshot(this, json)
                            PortfolioWidgetProvider.updateAll(this)
                            WidgetUpdateWorker.schedule(this)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
