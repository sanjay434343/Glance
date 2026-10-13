package com.example.glance

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject

/**
 * High-Speed Multi-Threaded Resumable Model Downloader.
 *
 * Supports:
 * - Resuming from existing `.downloading` file using state metadata (`.downloading.meta`).
 * - Partitioning remaining bytes across 4 parallel threads using HTTP Range requests.
 * - Single-stream fallback with `Range: bytes=X-` resume if chunking is not available.
 * - Atomic rename to target file upon 100% completion.
 */
class ModelDownloader(private val context: Context? = null) : EventChannel.StreamHandler {

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "glance_model_download_channel"
        private const val NOTIFICATION_ID = 4099
        private const val NUM_THREADS = 4
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isDownloading = false

    private val isCancelled = AtomicBoolean(false)
    private var executorService = Executors.newFixedThreadPool(NUM_THREADS + 1)
    private val activeFutures = mutableListOf<Future<*>>()

    init {
        createNotificationChannel()
    }

    private fun getNotificationManager(): NotificationManager? {
        return context?.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && context != null) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "AI Model Download",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress when downloading AI model files"
                setShowBadge(false)
            }
            getNotificationManager()?.createNotificationChannel(channel)
        }
    }

    private fun updateDownloadNotification(
        downloadedBytes: Long,
        totalBytes: Long,
        speedMBps: Double,
        percent: Int
    ) {
        if (context == null) return
        try {
            val downloadedMB = (downloadedBytes.toDouble() / (1024.0 * 1024.0)).coerceAtLeast(0.0)
            val totalMB = (totalBytes.toDouble() / (1024.0 * 1024.0)).coerceAtLeast(0.0)

            val text = if (totalBytes > 0) {
                String.format(
                    java.util.Locale.US,
                    "%.1f MB / %.1f MB (%.1f MB/s) • %d%%",
                    downloadedMB,
                    totalMB,
                    speedMBps,
                    percent
                )
            } else {
                String.format(
                    java.util.Locale.US,
                    "%.1f MB downloaded (%.1f MB/s)",
                    downloadedMB,
                    speedMBps
                )
            }

            val builder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Downloading AI Model")
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setProgress(100, percent, totalBytes <= 0L)
                .setPriority(NotificationCompat.PRIORITY_LOW)

            getNotificationManager()?.notify(NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {}
    }

    private fun cancelDownloadNotification() {
        try {
            getNotificationManager()?.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
    }

    private fun showDownloadCompleteNotification(filePath: String, sizeBytes: Long) {
        if (context == null) return
        try {
            val sizeMB = sizeBytes.toDouble() / (1024.0 * 1024.0)
            val builder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("AI Model Download Complete")
                .setContentText(String.format(java.util.Locale.US, "Gemma Model ready (%.1f MB)", sizeMB))
                .setOngoing(false)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)

            getNotificationManager()?.notify(NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {}
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    fun startDownload(downloadUrl: String, destinationPath: String): Boolean {
        if (isDownloading) {
            Log.w("ModelDownloader", "Download already in progress.")
            return false
        }

        isDownloading = true
        isCancelled.set(false)

        executorService.execute {
            runResumableDownload(downloadUrl, destinationPath)
        }

        return true
    }

    fun cancelDownload(): Boolean {
        if (!isDownloading) return false
        isCancelled.set(true)
        synchronized(activeFutures) {
            for (f in activeFutures) {
                f.cancel(true)
            }
            activeFutures.clear()
        }
        isDownloading = false
        cancelDownloadNotification()
        postProgress("cancelled", 0L, 0L, 0.0, 0L, "Download cancelled by user")
        return true
    }

    private fun resolveFinalUrlAndContentLength(initialUrl: String): Pair<String, Long> {
        var currentUrl = initialUrl
        var redirects = 0
        val maxRedirects = 10

        while (redirects < maxRedirects) {
            val urlObj = URL(currentUrl)
            val connection = (urlObj.openConnection() as HttpURLConnection).apply {
                requestMethod = "HEAD"
                connectTimeout = 30000
                readTimeout = 30000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "Glance-ModelDownloader/2.0 (Android; Resumable)")
            }

            connection.connect()
            val code = connection.responseCode

            if (code in 300..399) {
                val loc = connection.getHeaderField("Location")
                connection.disconnect()
                if (!loc.isNullOrBlank()) {
                    currentUrl = if (loc.startsWith("http")) loc else URL(urlObj, loc).toString()
                    redirects++
                    continue
                }
            }

            val length = connection.contentLengthLong
            connection.disconnect()
            return Pair(currentUrl, length)
        }

        return Pair(currentUrl, -1L)
    }

    data class ChunkInfo(val index: Int, val start: Long, var current: Long, val end: Long)

    private fun loadMeta(metaFile: File): List<ChunkInfo>? {
        if (!metaFile.exists()) return null
        return try {
            val json = JSONObject(metaFile.readText())
            val arr = json.getJSONArray("chunks")
            val list = mutableListOf<ChunkInfo>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                list.add(
                    ChunkInfo(
                        obj.getInt("index"),
                        obj.getLong("start"),
                        obj.getLong("current"),
                        obj.getLong("end")
                    )
                )
            }
            list
        } catch (_: Exception) {
            null
        }
    }

    private fun saveMeta(metaFile: File, totalBytes: Long, chunks: List<ChunkInfo>) {
        try {
            val root = JSONObject()
            root.put("totalBytes", totalBytes)
            val arr = JSONArray()
            for (c in chunks) {
                val obj = JSONObject()
                obj.put("index", c.index)
                obj.put("start", c.start)
                obj.put("current", c.current)
                obj.put("end", c.end)
                arr.put(obj)
            }
            root.put("chunks", arr)
            metaFile.writeText(root.toString())
        } catch (_: Exception) {}
    }

    private fun runResumableDownload(initialUrl: String, destinationPath: String) {
        val destFile = File(destinationPath)
        val parentDir = destFile.parentFile
        if (parentDir != null && !parentDir.exists()) {
            parentDir.mkdirs()
        }

        val partFile = File("$destinationPath.downloading")
        val metaFile = File("$destinationPath.downloading.meta")

        try {
            val (finalUrl, totalBytes) = resolveFinalUrlAndContentLength(initialUrl)
            Log.i("ModelDownloader", "Connecting -> URL: $finalUrl, Total Content Length: $totalBytes bytes")

            // If target file already exists and matches expected size, mark complete
            if (destFile.exists() && (totalBytes <= 0 || destFile.length() == totalBytes)) {
                isDownloading = false
                showDownloadCompleteNotification(destFile.absolutePath, destFile.length())
                postProgress("completed", destFile.length(), destFile.length(), 0.0, 0L, null)
                return
            }

            // Check if server doesn't provide Content-Length: use single-stream with partial resume
            if (totalBytes <= 0L) {
                runSingleStreamResume(finalUrl, partFile, destFile)
                return
            }

            // Determine chunks (resume previous state if metadata is valid)
            var chunks = loadMeta(metaFile)
            val isMetaValid = chunks != null && chunks.size == NUM_THREADS &&
                    partFile.exists() && partFile.length() == totalBytes

            if (!isMetaValid) {
                // Initialize clean chunks and pre-allocate file
                val raf = RandomAccessFile(partFile, "rw")
                raf.setLength(totalBytes)
                raf.close()

                val chunkSize = totalBytes / NUM_THREADS
                val newChunks = mutableListOf<ChunkInfo>()
                for (i in 0 until NUM_THREADS) {
                    val s = i * chunkSize
                    val e = if (i == NUM_THREADS - 1) totalBytes - 1 else (s + chunkSize - 1)
                    newChunks.add(ChunkInfo(i, s, s, e))
                }
                chunks = newChunks
                saveMeta(metaFile, totalBytes, chunks)
            }

            val validChunks = chunks!!

            // Calculate already downloaded bytes across all chunks
            var initialDownloaded = 0L
            for (c in validChunks) {
                initialDownloaded += (c.current - c.start)
            }

            val progressBytes = AtomicLong(initialDownloaded)
            Log.i("ModelDownloader", "Resuming download at $initialDownloaded / $totalBytes bytes (${(initialDownloaded * 100 / totalBytes)}%)")

            postProgress("started", initialDownloaded, totalBytes, 0.0, 0L, null)
            val initPct = ((initialDownloaded * 100) / totalBytes).toInt().coerceIn(0, 100)
            updateDownloadNotification(initialDownloaded, totalBytes, 0.0, initPct)

            // Progress reporting loop
            val progressTracker = executorService.submit {
                var lastBytes = initialDownloaded
                var lastTime = System.currentTimeMillis()
                var smoothedSpeed = 0.0
                var lastNotifTime = 0L

                while (!isCancelled.get() && isDownloading) {
                    try {
                        Thread.sleep(250)
                    } catch (_: InterruptedException) {
                        break
                    }

                    val now = System.currentTimeMillis()
                    val currentDownloaded = progressBytes.get()
                    val deltaBytes = currentDownloaded - lastBytes
                    val deltaMs = now - lastTime

                    if (deltaMs > 0) {
                        val instantSpeed = (deltaBytes.toDouble() / (1024.0 * 1024.0)) / (deltaMs.toDouble() / 1000.0)
                        smoothedSpeed = if (smoothedSpeed == 0.0) instantSpeed else (0.7 * smoothedSpeed + 0.3 * instantSpeed)

                        val remaining = (totalBytes - currentDownloaded).coerceAtLeast(0L)
                        val etaSec = if (smoothedSpeed > 0.05) {
                            ((remaining.toDouble() / (1024.0 * 1024.0)) / smoothedSpeed).toLong()
                        } else 0L

                        val percent = ((currentDownloaded * 100) / totalBytes).toInt().coerceIn(0, 100)
                        postProgress("downloading", currentDownloaded, totalBytes, smoothedSpeed, etaSec, null)

                        if (now - lastNotifTime >= 1000) {
                            updateDownloadNotification(currentDownloaded, totalBytes, smoothedSpeed, percent)
                            lastNotifTime = now
                            saveMeta(metaFile, totalBytes, validChunks)
                        }

                        lastBytes = currentDownloaded
                        lastTime = now
                    }

                    if (currentDownloaded >= totalBytes) {
                        break
                    }
                }
            }

            // Launch workers for unfinished chunks
            val futures = mutableListOf<Future<*>>()
            for (chunk in validChunks) {
                if (chunk.current <= chunk.end) {
                    val worker = executorService.submit {
                        downloadChunk(finalUrl, partFile, chunk, progressBytes)
                    }
                    futures.add(worker)
                }
            }

            synchronized(activeFutures) {
                activeFutures.clear()
                activeFutures.addAll(futures)
            }

            for (f in futures) {
                f.get()
            }
            progressTracker.cancel(true)

            if (isCancelled.get()) {
                saveMeta(metaFile, totalBytes, validChunks)
                cancelDownloadNotification()
                return
            }

            // Download completed: remove metafile and atomically rename
            if (metaFile.exists()) {
                metaFile.delete()
            }
            if (destFile.exists()) {
                destFile.delete()
            }
            val renamed = partFile.renameTo(destFile)
            if (!renamed) {
                partFile.copyTo(destFile, overwrite = true)
                partFile.delete()
            }

            Log.i("ModelDownloader", "Resumed model download completed successfully! Size: ${destFile.length()} bytes")
            isDownloading = false
            showDownloadCompleteNotification(destFile.absolutePath, destFile.length())
            postProgress("completed", destFile.length(), destFile.length(), 0.0, 0L, null)

        } catch (e: Exception) {
            if (!isCancelled.get()) {
                Log.e("ModelDownloader", "Download error: ${e.message}", e)
                isDownloading = false
                cancelDownloadNotification()
                postProgress("error", 0L, 0L, 0.0, 0L, e.message ?: "Download failed")
            }
        } finally {
            isDownloading = false
        }
    }

    private fun downloadChunk(
        urlStr: String,
        file: File,
        chunk: ChunkInfo,
        progressCounter: AtomicLong
    ) {
        val startByte = chunk.current
        val endByte = chunk.end
        if (startByte > endByte) return

        val url = URL(urlStr)
        val connection = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 30000
            readTimeout = 45000
            setRequestProperty("User-Agent", "Glance-ModelDownloader/2.0 (Android; Resumable)")
            setRequestProperty("Range", "bytes=$startByte-$endByte")
        }

        connection.connect()
        val responseCode = connection.responseCode
        if (responseCode != HttpURLConnection.HTTP_PARTIAL && responseCode != HttpURLConnection.HTTP_OK) {
            throw Exception("Chunk ${chunk.index} ($startByte-$endByte) HTTP $responseCode")
        }

        val raf = RandomAccessFile(file, "rw")
        raf.seek(startByte)

        val input = connection.inputStream.buffered(128 * 1024)
        val buffer = ByteArray(128 * 1024)
        var bytesRead: Int

        try {
            while (input.read(buffer).also { bytesRead = it } != -1) {
                if (isCancelled.get()) break
                raf.write(buffer, 0, bytesRead)
                chunk.current += bytesRead
                progressCounter.addAndGet(bytesRead.toLong())
            }
        } finally {
            try { input.close() } catch (_: Exception) {}
            try { raf.close() } catch (_: Exception) {}
            try { connection.disconnect() } catch (_: Exception) {}
        }
    }

    private fun runSingleStreamResume(
        urlStr: String,
        partFile: File,
        destFile: File
    ) {
        var downloaded = if (partFile.exists()) partFile.length() else 0L
        val url = URL(urlStr)
        val conn = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 30000
            readTimeout = 60000
            setRequestProperty("User-Agent", "Glance-ModelDownloader/2.0 (Android; Resumable)")
            if (downloaded > 0) {
                setRequestProperty("Range", "bytes=$downloaded-")
            }
        }
        conn.connect()

        val isPartial = (conn.responseCode == HttpURLConnection.HTTP_PARTIAL)
        val totalBytes = if (isPartial) downloaded + conn.contentLengthLong else conn.contentLengthLong
        if (!isPartial) downloaded = 0L

        val input = conn.inputStream.buffered(256 * 1024)
        val output = partFile.outputStream().buffered(256 * 1024)
        val buf = ByteArray(256 * 1024)
        var bytesRead: Int

        try {
            while (input.read(buf).also { bytesRead = it } != -1) {
                if (isCancelled.get()) break
                output.write(buf, 0, bytesRead)
                downloaded += bytesRead
                val pct = if (totalBytes > 0) ((downloaded * 100) / totalBytes).toInt().coerceIn(0, 100) else 0
                postProgress("downloading", downloaded, totalBytes, 0.0, 0L, null)
                updateDownloadNotification(downloaded, totalBytes, 0.0, pct)
            }
            output.flush()
        } finally {
            output.close()
            input.close()
            conn.disconnect()
        }

        if (!isCancelled.get()) {
            if (destFile.exists()) destFile.delete()
            partFile.renameTo(destFile)
            isDownloading = false
            showDownloadCompleteNotification(destFile.absolutePath, destFile.length())
            postProgress("completed", destFile.length(), destFile.length(), 0.0, 0L, null)
        }
    }

    private fun postProgress(
        status: String,
        downloadedBytes: Long,
        totalBytes: Long,
        speedMBps: Double,
        etaSeconds: Long,
        error: String?
    ) {
        val payload = mapOf(
            "status" to status,
            "downloadedBytes" to downloadedBytes,
            "totalBytes" to totalBytes,
            "speedMBps" to speedMBps,
            "etaSeconds" to etaSeconds,
            "progress" to if (totalBytes > 0) (downloadedBytes.toDouble() / totalBytes.toDouble()) else 0.0,
            "error" to error
        )

        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (_: Exception) {}
        }
    }
}
