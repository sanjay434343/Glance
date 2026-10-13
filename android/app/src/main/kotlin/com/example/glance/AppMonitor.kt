package com.example.glance

import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import java.io.ByteArrayOutputStream

object AppMonitor {
    fun fetchAppActivity(context: Context): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val pm = context.packageManager
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - (1000 * 60 * 60 * 24)

        val packageLatestTime = mutableMapOf<String, Long>()
        val packageOpenCount = mutableMapOf<String, Int>()

        if (usm != null) {
            try {
                val usageStatsMap = usm.queryAndAggregateUsageStats(startTime, endTime)
                val events = usm.queryEvents(startTime, endTime)
                val event = android.app.usage.UsageEvents.Event()

                while (events.hasNextEvent()) {
                    events.getNextEvent(event)
                    if (event.eventType == android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED ||
                        event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                        val pkgName = event.packageName
                        if (pkgName != null && pkgName != context.packageName) {
                            packageLatestTime[pkgName] = event.timeStamp
                            packageOpenCount[pkgName] = (packageOpenCount[pkgName] ?: 0) + 1
                        }
                    }
                }

                for ((pkgName, timestamp) in packageLatestTime) {
                    try {
                        val launchIntent = pm.getLaunchIntentForPackage(pkgName)
                        if (launchIntent == null) continue // Skip background/system services that have no UI

                        val appInfo = pm.getApplicationInfo(pkgName, 0)
                        val appName = pm.getApplicationLabel(appInfo).toString()
                        val iconBase64 = AppIconHelper.getIconBase64(pm.getApplicationIcon(appInfo), pkgName)
                        
                        val openCount = packageOpenCount[pkgName] ?: 1
                        val usageTimeMs = usageStatsMap[pkgName]?.totalTimeInForeground ?: 0L

                        val item = mapOf(
                            "appName" to appName,
                            "packageName" to pkgName,
                            "activity" to "Opened App",
                            "openCount" to openCount,
                            "usageTimeMs" to usageTimeMs,
                            "timestamp" to timestamp,
                            "appIconBase64" to iconBase64
                        )
                        list.add(item)
                    } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
        }
        list.sortByDescending { (it["timestamp"] as? Long) ?: 0L }
        return list
    }
}
