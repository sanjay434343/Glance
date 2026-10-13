package com.example.glance

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.ClipboardManager
import android.content.ContentUris
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.provider.CallLog
import android.provider.Telephony
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.Settings
import android.content.Intent
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.glance.app/native_bridge"
    private val GEMMA_CHANNEL = "com.glance.app/gemma_native"
    private val DOWNLOADER_CHANNEL = "com.glance.app/model_downloader"
    private val DOWNLOADER_EVENT_CHANNEL = "com.glance.app/model_downloader_progress"
    private lateinit var gemmaBridge: GemmaMediaPipeBridge
    private lateinit var modelDownloader: ModelDownloader
    private val backgroundExecutor = java.util.concurrent.Executors.newFixedThreadPool(3)
    private val gemmaExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    override fun onDestroy() {
        try {
            modelDownloader.cancelDownload()
            backgroundExecutor.shutdown()
            gemmaExecutor.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        gemmaBridge = GemmaMediaPipeBridge(this)
        modelDownloader = ModelDownloader(this)
        GlanceForegroundService.startService(this)

        // Model Downloader streaming EventChannel & control MethodChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOADER_EVENT_CHANNEL).setStreamHandler(modelDownloader)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOADER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startDownload" -> {
                    val url = call.argument<String>("url") ?: ""
                    val destination = call.argument<String>("destinationPath") ?: ""
                    if (url.isNotBlank() && destination.isNotBlank()) {
                        val started = modelDownloader.startDownload(url, destination)
                        result.success(started)
                    } else {
                        result.error("INVALID_ARGS", "url and destinationPath required", null)
                    }
                }
                "cancelDownload" -> {
                    val cancelled = modelDownloader.cancelDownload()
                    result.success(cancelled)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEMMA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareInfo" -> {
                    result.success(gemmaBridge.getHardwareInfo())
                }
                "initModel" -> {
                    val path = call.argument<String>("modelPath") ?: ""
                    val backend = call.argument<String>("preferredBackend") ?: "AUTO"
                    gemmaExecutor.execute {
                        val success = gemmaBridge.initModel(path, backend)
                        runOnUiThread {
                            result.success(success)
                        }
                    }
                }
                "generateText" -> {
                    val prompt = call.argument<String>("prompt") ?: ""
                    gemmaExecutor.execute {
                        val response = gemmaBridge.generateResponse(prompt)
                        runOnUiThread {
                            result.success(response)
                        }
                    }
                }
                "generateVision" -> {
                    val imagePath = call.argument<String>("imagePath") ?: ""
                    val prompt = call.argument<String>("prompt") ?: ""
                    gemmaExecutor.execute {
                        val response = gemmaBridge.generateVisionResponse(imagePath, prompt)
                        runOnUiThread {
                            result.success(response)
                        }
                    }
                }
                "unloadModel" -> {
                    gemmaExecutor.execute {
                        val success = gemmaBridge.unloadModel()
                        runOnUiThread {
                            result.success(success)
                        }
                    }
                }
                "deleteModel" -> {
                    val path = call.argument<String>("modelPath")
                    gemmaExecutor.execute {
                        val success = gemmaBridge.deleteModelFile(path)
                        runOnUiThread {
                            result.success(success)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->

            when (call.method) {
                "getAppActivity" -> {
                    backgroundExecutor.execute {
                        try {
                            val activityList = AppMonitor.fetchAppActivity(this@MainActivity)
                            runOnUiThread { result.success(activityList) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("APP_ACTIVITY_ERROR", e.message, null) }
                        }
                    }
                }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        backgroundExecutor.execute {
                            try {
                                val iconBase64 = AppIconHelper.getIconBase64(packageManager, packageName)
                                runOnUiThread { result.success(iconBase64) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("ICON_ERROR", e.message, null) }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                "renderPdfToImages" -> {
                    val path = call.argument<String>("pdfPath")
                    if (path != null) {
                        backgroundExecutor.execute {
                            try {
                                val images = renderPdfToImages(path)
                                runOnUiThread { result.success(images) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PDF_RENDER_ERROR", e.message, null) }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "pdfPath required", null)
                    }
                }
                "getRecentMedia" -> {
                    backgroundExecutor.execute {
                        try {
                            val mediaList = fetchRecentMedia()
                            runOnUiThread { result.success(mediaList) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("MEDIA_ERROR", e.message, null) }
                        }
                    }
                }
                "getRecentDocuments" -> {
                    backgroundExecutor.execute {
                        try {
                            val docsList = fetchRecentDocuments()
                            runOnUiThread { result.success(docsList) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DOCS_ERROR", e.message, null) }
                        }
                    }
                }
                "getClipboardText" -> {
                    try {
                        val clip = fetchClipboardText()
                        result.success(clip)
                    } catch (e: Exception) {
                        result.error("CLIPBOARD_ERROR", e.message, null)
                    }
                }
                "getCallLogs" -> {
                    backgroundExecutor.execute {
                        try {
                            val logs = fetchRecentCallLogs()
                            runOnUiThread { result.success(logs) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CALL_LOG_ERROR", e.message, null) }
                        }
                    }
                }
                "getSmsMessages" -> {
                    backgroundExecutor.execute {
                        try {
                            val smsList = fetchRecentSms()
                            runOnUiThread { result.success(smsList) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SMS_ERROR", e.message, null) }
                        }
                    }
                }
                "getCalendarEvents" -> {
                    backgroundExecutor.execute {
                        try {
                            val events = fetchRecentCalendarEvents()
                            runOnUiThread { result.success(events) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CALENDAR_ERROR", e.message, null) }
                        }
                    }
                }
                "getRecentNotifications" -> {
                    val list = synchronized(GlanceNotificationService.capturedNotifications) {
                        ArrayList(GlanceNotificationService.capturedNotifications)
                    }
                    result.success(list)
                }
                "hasNotificationPermission" -> {
                    val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    val hasPerm = flat != null && flat.contains(packageName)
                    result.success(hasPerm)
                }
                "requestNotificationPermission" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "hasUsagePermission" -> {
                    val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
                    val mode = appOps.checkOpNoThrow(
                        android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, 
                        android.os.Process.myUid(), 
                        packageName
                    )
                    result.success(mode == android.app.AppOpsManager.MODE_ALLOWED)
                }
                "requestUsagePermission" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(true)
                }
                "getAllInstalledApps" -> {
                    backgroundExecutor.execute {
                        try {
                            val appList = fetchAllInstalledApps()
                            runOnUiThread { result.success(appList) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("INSTALLED_APPS_ERROR", e.message, null) }
                        }
                    }
                }
                "getGlanceBatteryUsage" -> {
                    try {
                        val cpuTimeMs = android.os.Process.getElapsedCpuTime()
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                        val isIgnoringOptimization = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
                        val deviceBatteryLevel = batteryManager?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100

                        val cpuSeconds = (cpuTimeMs / 1000).coerceAtLeast(1)
                        val estimatedMah = (cpuSeconds * 0.08)
                        val estimatedPercent = (estimatedMah / 45.0).coerceIn(0.1, 5.0)
                        val formattedPercent = String.format(java.util.Locale.US, "%.1f%%", estimatedPercent)

                        val response = mapOf(
                            "appName" to "Glance",
                            "batteryUsagePercent" to formattedPercent,
                            "cpuTimeSeconds" to cpuSeconds,
                            "deviceBatteryLevel" to deviceBatteryLevel,
                            "isIgnoringOptimization" to isIgnoringOptimization,
                            "drainLevel" to if (estimatedPercent < 2.0) "Minimal (< 2%)" else "Normal",
                            "status" to if (isIgnoringOptimization) "Unrestricted Background" else "Optimized by Android"
                        )
                        result.success(response)
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                "openBatterySettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Intent.ACTION_POWER_USAGE_SUMMARY)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("SETTINGS_ERROR", e2.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun fetchRecentCallLogs(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        if (checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            return list
        }
        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )
        val cursor = contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            null,
            null,
            "${CallLog.Calls.DATE} DESC"
        )

        cursor?.use {
            val nameCol = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
            val numCol = it.getColumnIndex(CallLog.Calls.NUMBER)
            val typeCol = it.getColumnIndex(CallLog.Calls.TYPE)
            val dateCol = it.getColumnIndex(CallLog.Calls.DATE)
            val durCol = it.getColumnIndex(CallLog.Calls.DURATION)

            var count = 0
            while (it.moveToNext() && count < 500) {
                val cachedName = if (nameCol >= 0) it.getString(nameCol) else null
                val number = if (numCol >= 0) it.getString(numCol) ?: "Unknown" else "Unknown"
                val callTypeInt = if (typeCol >= 0) it.getInt(typeCol) else CallLog.Calls.INCOMING_TYPE
                val dateMs = if (dateCol >= 0) it.getLong(dateCol) else System.currentTimeMillis()
                val durationSec = if (durCol >= 0) it.getLong(durCol) else 0L

                val callerName = if (!cachedName.isNullOrEmpty()) cachedName else number
                val callTypeStr = when (callTypeInt) {
                    CallLog.Calls.INCOMING_TYPE -> "Incoming Call"
                    CallLog.Calls.OUTGOING_TYPE -> "Outgoing Call"
                    CallLog.Calls.MISSED_TYPE -> "Missed Call"
                    CallLog.Calls.REJECTED_TYPE -> "Rejected Call"
                    else -> "Call Log"
                }

                list.add(mapOf(
                    "callerName" to callerName,
                    "phoneNumber" to number,
                    "callType" to callTypeStr,
                    "durationSeconds" to durationSec,
                    "timestamp" to dateMs
                ))
                count++
            }
        }
        return list
    }

    private fun fetchRecentSms(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        if (checkSelfPermission(android.Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
            return list
        }
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE
        )
        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            null,
            null,
            "${Telephony.Sms.DATE} DESC"
        )

        cursor?.use {
            val addrCol = it.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyCol = it.getColumnIndex(Telephony.Sms.BODY)
            val dateCol = it.getColumnIndex(Telephony.Sms.DATE)
            val typeCol = it.getColumnIndex(Telephony.Sms.TYPE)

            var count = 0
            while (it.moveToNext() && count < 500) {
                val address = if (addrCol >= 0) it.getString(addrCol) ?: "SMS" else "SMS"
                val body = if (bodyCol >= 0) it.getString(bodyCol) ?: "" else ""
                val dateMs = if (dateCol >= 0) it.getLong(dateCol) else System.currentTimeMillis()
                val smsTypeInt = if (typeCol >= 0) it.getInt(typeCol) else Telephony.Sms.MESSAGE_TYPE_INBOX

                val typeStr = if (smsTypeInt == Telephony.Sms.MESSAGE_TYPE_INBOX) "Received SMS" else "Sent SMS"

                list.add(mapOf(
                    "sender" to address,
                    "body" to body,
                    "smsType" to typeStr,
                    "timestamp" to dateMs
                ))
                count++
            }
        }
        return list
    }

    private fun fetchRecentCalendarEvents(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        if (checkSelfPermission(android.Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            return list
        }
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.EVENT_LOCATION
        )
        val cursor = contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            null,
            null,
            "${CalendarContract.Events.DTSTART} DESC"
        )

        cursor?.use {
            val titleCol = it.getColumnIndex(CalendarContract.Events.TITLE)
            val descCol = it.getColumnIndex(CalendarContract.Events.DESCRIPTION)
            val startCol = it.getColumnIndex(CalendarContract.Events.DTSTART)
            val endCol = it.getColumnIndex(CalendarContract.Events.DTEND)
            val locCol = it.getColumnIndex(CalendarContract.Events.EVENT_LOCATION)

            var count = 0
            while (it.moveToNext() && count < 500) {
                val title = if (titleCol >= 0) it.getString(titleCol) ?: "Meeting" else "Meeting"
                val desc = if (descCol >= 0) it.getString(descCol) ?: "" else ""
                val startMs = if (startCol >= 0) it.getLong(startCol) else System.currentTimeMillis()
                val endMs = if (endCol >= 0) it.getLong(endCol) else startMs
                val location = if (locCol >= 0) it.getString(locCol) ?: "" else ""

                val lowerTitle = title.lowercase()
                val lowerDesc = desc.lowercase()
                val isHoliday = lowerTitle.contains("holiday") ||
                        lowerTitle.contains("festival") ||
                        lowerTitle.contains("birthday") ||
                        lowerDesc.contains("holiday") ||
                        lowerDesc.contains("public holiday") ||
                        lowerDesc.contains("government holiday")

                if (isHoliday) continue

                list.add(mapOf(
                    "title" to title,
                    "description" to desc,
                    "startTimestamp" to startMs,
                    "endTimestamp" to endMs,
                    "location" to location
                ))
                count++
            }
        }
        return list
    }

    private fun fetchAllInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val list = mutableListOf<Map<String, Any>>()

        for (appInfo in packages) {
            val packageName = appInfo.packageName
            val appName = pm.getApplicationLabel(appInfo).toString()
            val launchIntent = pm.getLaunchIntentForPackage(packageName)
            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val iconBase64 = try {
                AppIconHelper.getIconBase64(pm.getApplicationIcon(appInfo), packageName)
            } catch (_: Exception) {
                ""
            }

            list.add(mapOf(
                "appName" to appName,
                "packageName" to packageName,
                "hasLaunchIntent" to (launchIntent != null),
                "isSystemApp" to isSystem,
                "iconBase64" to iconBase64
            ))
        }

        list.sortBy { (it["appName"] as? String)?.lowercase() ?: "" }
        return list
    }

    private fun fetchRecentMedia(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val seenPaths = mutableSetOf<String>()

        // 1. MediaStore query across indexed images
        try {
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_TAKEN,
                MediaStore.Images.Media.DATE_ADDED
            )

            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC"
            )

            cursor?.use {
                val idColumn = it.getColumnIndex(MediaStore.Images.Media._ID)
                val nameColumn = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                val dataColumn = it.getColumnIndex(MediaStore.Images.Media.DATA)
                val dateColumn = it.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)

                var count = 0
                while (it.moveToNext() && count < 500) {
                    val id = if (idColumn >= 0) it.getLong(idColumn) else count.toLong()
                    val name = if (nameColumn >= 0) it.getString(nameColumn) ?: "Media_${id}" else "Media_${id}"
                    
                    var path = if (dataColumn >= 0) it.getString(dataColumn) ?: "" else ""
                    if (path.isEmpty()) {
                        path = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id).toString()
                    }

                    if (path.isNotEmpty() && !seenPaths.contains(path)) {
                        seenPaths.add(path)
                        val lowerName = name.lowercase()
                        val pathLower = path.lowercase()
                        val type = when {
                            pathLower.contains("screenshot") || lowerName.contains("screenshot") || lowerName.contains("screen") -> "screenshot"
                            pathLower.contains("download") -> "photo"
                            lowerName.contains("cam") || lowerName.contains("img") || pathLower.contains("dcim") -> "camera_capture"
                            else -> "photo"
                        }

                        val takenCol = it.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
                        val dateTakenMs = if (takenCol >= 0) it.getLong(takenCol) else 0L
                        val dateSec = if (dateColumn >= 0) it.getLong(dateColumn) else 0L
                        val timestamp = when {
                            dateTakenMs > 0 -> dateTakenMs
                            dateSec > 0 -> dateSec * 1000
                            else -> System.currentTimeMillis()
                        }

                        list.add(mapOf(
                            "id" to id.toString(),
                            "title" to name,
                            "filePath" to path,
                            "type" to type,
                            "capturedAt" to timestamp
                        ))
                        count++
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error querying MediaStore: ${e.message}")
        }

        // 2. Focused scan on dedicated Screenshot directories only
        if (list.size < 500) {
            try {
                val storageDir = android.os.Environment.getExternalStorageDirectory()
                val candidateDirs = arrayOf(
                    File(storageDir, "Pictures/Screenshots"),
                    File(storageDir, "DCIM/Screenshots")
                )

                for (dir in candidateDirs) {
                    if (dir.exists() && dir.isDirectory) {
                        val files = dir.listFiles() ?: continue
                        for (entry in files) {
                            if (entry.isFile) {
                                val n = entry.name.lowercase()
                                if (n.endsWith(".jpg") || n.endsWith(".jpeg") || n.endsWith(".png") || n.endsWith(".webp")) {
                                    val path = entry.absolutePath
                                    if (!seenPaths.contains(path)) {
                                        seenPaths.add(path)
                                        list.add(mapOf(
                                            "id" to entry.name,
                                            "title" to entry.name,
                                            "filePath" to path,
                                            "type" to "screenshot",
                                            "capturedAt" to entry.lastModified()
                                        ))
                                    }
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Error scanning screenshots: ${e.message}")
            }
        }

        // Sort all items descending by capturedAt timestamp
        list.sortByDescending { (it["capturedAt"] as? Long) ?: 0L }
        return list
    }

    private fun fetchRecentDocuments(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.DATA,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.SIZE
        )

        val selection = "${MediaStore.Files.FileColumns.DATA} LIKE '%.pdf' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.docx' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.txt' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.md' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.csv' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.xlsx' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.pptx' OR " +
                "${MediaStore.Files.FileColumns.DATA} LIKE '%.epub'"

        val cursor = contentResolver.query(
            MediaStore.Files.getContentUri("external"),
            projection,
            selection,
            null,
            "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
        )

        cursor?.use {
            val idCol = it.getColumnIndex(MediaStore.Files.FileColumns._ID)
            val nameCol = it.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)
            val dataCol = it.getColumnIndex(MediaStore.Files.FileColumns.DATA)
            val dateCol = it.getColumnIndex(MediaStore.Files.FileColumns.DATE_MODIFIED)
            val sizeCol = it.getColumnIndex(MediaStore.Files.FileColumns.SIZE)

            var count = 0
            while (it.moveToNext() && count < 500) {
                val id = if (idCol >= 0) it.getLong(idCol) else count.toLong()
                val name = if (nameCol >= 0) it.getString(nameCol) ?: "Document" else "Document"
                var path = if (dataCol >= 0) it.getString(dataCol) ?: "" else ""
                if (path.isEmpty()) {
                    path = ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), id).toString()
                }
                val dateSec = if (dateCol >= 0) it.getLong(dateCol) else 0L
                val size = if (sizeCol >= 0) it.getLong(sizeCol) else 0L

                val ext = name.substringAfterLast('.', "txt")
                val item = mapOf<String, Any>(
                    "filename" to name,
                    "filePath" to path,
                    "fileType" to ext,
                    "sizeBytes" to size,
                    "modifiedAt" to (dateSec * 1000)
                )
                list.add(item)
                count++
            }
        }
        return list
    }

    private fun fetchClipboardText(): Map<String, Any>? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        if (clipboard != null && clipboard.hasPrimaryClip()) {
            val clipData = clipboard.primaryClip
            if (clipData != null && clipData.itemCount > 0) {
                val text = clipData.getItemAt(0).text?.toString() ?: ""
                if (text.isNotEmpty()) {
                    return mapOf(
                        "text" to text,
                        "timestamp" to System.currentTimeMillis()
                    )
                }
            }
        }
        return null
    }

    private fun renderPdfToImages(pdfPath: String): List<String> {
        val paths = mutableListOf<String>()
        val file = File(pdfPath)
        if (!file.exists()) return paths
        
        val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = PdfRenderer(pfd)
        
        for (i in 0 until renderer.pageCount) {
            val page = renderer.openPage(i)
            // Render at 2x scale for higher quality OCR readability
            val width = page.width * 2
            val height = page.height * 2
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // Fill with white background since PDFs often assume a white sheet
            val canvas = Canvas(bitmap)
            canvas.drawColor(android.graphics.Color.WHITE)
            
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            page.close()
            
            val tempFile = File(cacheDir, "pdf_page_${System.currentTimeMillis()}_$i.jpg")
            val fos = java.io.FileOutputStream(tempFile)
            bitmap.compress(Bitmap.CompressFormat.JPEG, 95, fos)
            fos.flush()
            fos.close()
            
            paths.add(tempFile.absolutePath)
        }
        renderer.close()
        pfd.close()
        return paths
    }
}
