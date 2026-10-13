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
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * High-speed, resumable background model downloader implemented in pure Kotlin.
 * Streams directly to disk with large 256KB buffer, automatic redirect handling,
 * live foreground notification with percentage, total size, download size & speed,
 * and throttled, zero-overhead progress reporting to Flutter.
 */
class ModelDownloader(private val context: Context? = null) : EventChannel.StreamHandler {

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "glance_model_download_channel"
        private const val NOTIFICATION_ID = 4099
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isDownloading = false

    @Volatile
    private var isCancelled = false

    private var activeConnection: HttpURLConnection? = null
    private var downloadThread: Thread? = null

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

            val maxProgress = 100
            val indeterminate = totalBytes <= 0L

            val builder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Downloading AI Model ($percent%)")
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setProgress(maxProgress, percent.coerceIn(0, 100), indeterminate)

            getNotificationManager()?.notify(NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            Log.e("ModelDownloader", "Failed to update notification: ${e.message}")
        }
    }

    private fun showDownloadCompleteNotification(destPath: String, totalBytes: Long) {
        if (context == null) return
        try {
            val totalMB = totalBytes.toDouble() / (1024.0 * 1024.0)
            val fileName = File(destPath).name
            val builder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Model Download Complete")
                .setContentText(String.format(java.util.Locale.US, "$fileName (%.1f MB) ready for AI reasoning", totalMB))
                .setOngoing(false)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)

            getNotificationManager()?.notify(NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            Log.e("ModelDownloader", "Failed to show complete notification: ${e.message}")
        }
    }

    private fun cancelDownloadNotification() {
        if (context == null) return
        try {
            getNotificationManager()?.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    /**
     * Starts native high-speed download in a dedicated background worker thread.
     */
    fun startDownload(downloadUrl: String, destinationPath: String): Boolean {
        if (isDownloading) {
            Log.w("ModelDownloader", "Download already in progress.")
            return false
        }

        isDownloading = true
        isCancelled = false

        downloadThread = Thread {
            runDownload(downloadUrl, destinationPath)
        }.apply {
            name = "ModelDownloadWorker"
            priority = Thread.MAX_PRIORITY
            start()
        }

        return true
    }

    /**
     * Cancels any running download immediately.
     */
    fun cancelDownload(): Boolean {
        if (!isDownloading) return false
        isCancelled = true
        try {
            activeConnection?.disconnect()
        } catch (_: Exception) {}
        isDownloading = false
        cancelDownloadNotification()
        postProgress("cancelled", 0L, 0L, 0.0, 0L, "Download cancelled by user")
        return true
    }

    private fun runDownload(initialUrl: String, destinationPath: String) {
        val destFile = File(destinationPath)
        val parentDir = destFile.parentFile
        if (parentDir != null && !parentDir.exists()) {
            parentDir.mkdirs()
        }

        val partFile = File("$destinationPath.downloading")
        var downloadedBytes = if (partFile.exists()) partFile.length() else 0L

        var currentUrl = initialUrl
        var redirects = 0
        val maxRedirects = 10

        try {
            var connection: HttpURLConnection? = null

            // Handle HTTP 301, 302, 303, 307, 308 redirects (HuggingFace / S3 / CDNs)
            while (redirects < maxRedirects) {
                val urlObj = URL(currentUrl)
                connection = (urlObj.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 30000
                    readTimeout = 60000
                    instanceFollowRedirects = false
                    setRequestProperty("User-Agent", "Glance-ModelDownloader/1.0 (Android)")
                    setRequestProperty("Accept-Encoding", "identity") // Raw binary without gzip overhead

                    if (downloadedBytes > 0) {
                        setRequestProperty("Range", "bytes=$downloadedBytes-")
                    }
                }

                connection.connect()
                val responseCode = connection.responseCode

                if (responseCode in 300..399) {
                    val location = connection.getHeaderField("Location")
                    connection.disconnect()
                    if (!location.isNullOrBlank()) {
                        currentUrl = if (location.startsWith("http")) location else URL(urlObj, location).toString()
                        redirects++
                        Log.d("ModelDownloader", "Redirecting ($responseCode) -> $currentUrl")
                        continue
                    }
                }
                break
            }

            if (connection == null) {
                throw Exception("Failed to open connection to $initialUrl")
            }

            activeConnection = connection
            val responseCode = connection.responseCode
            val isPartial = (responseCode == HttpURLConnection.HTTP_PARTIAL)

            if (responseCode != HttpURLConnection.HTTP_OK && responseCode != HttpURLConnection.HTTP_PARTIAL) {
                throw Exception("HTTP Error $responseCode: ${connection.responseMessage}")
            }

            val contentLength = connection.contentLengthLong
            val totalBytes = if (isPartial) {
                downloadedBytes + contentLength
            } else {
                downloadedBytes = 0L // Reset if server doesn't support partial range
                contentLength
            }

            Log.i("ModelDownloader", "Starting high-speed stream to ${partFile.absolutePath}. Total size: $totalBytes bytes, resumeFrom: $downloadedBytes")

            val inputStream = BufferedInputStream(connection.inputStream, 256 * 1024)
            val outputStream = BufferedOutputStream(FileOutputStream(partFile, isPartial), 256 * 1024)

            val buffer = ByteArray(256 * 1024) // 256 KB chunk buffer for maximum I/O throughput
            var bytesRead: Int
            var lastUpdateMs = System.currentTimeMillis()
            var lastUpdateBytes = downloadedBytes
            var smoothedSpeedMBps = 0.0

            postProgress("started", downloadedBytes, totalBytes, 0.0, 0L, null)
            val initialPercent = if (totalBytes > 0) ((downloadedBytes * 100) / totalBytes).toInt() else 0
            updateDownloadNotification(downloadedBytes, totalBytes, 0.0, initialPercent)

            var lastNotificationMs = 0L

            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                if (isCancelled) {
                    outputStream.flush()
                    outputStream.close()
                    inputStream.close()
                    cancelDownloadNotification()
                    return
                }

                outputStream.write(buffer, 0, bytesRead)
                downloadedBytes += bytesRead

                val now = System.currentTimeMillis()
                val deltaMs = now - lastUpdateMs
                if (deltaMs >= 200) { // Throttle progress dispatch to every 200ms to preserve 120 FPS UI
                    val deltaBytes = downloadedBytes - lastUpdateBytes
                    val instantSpeedMBps = (deltaBytes.toDouble() / (1024.0 * 1024.0)) / (deltaMs.toDouble() / 1000.0)
                    smoothedSpeedMBps = if (smoothedSpeedMBps == 0.0) instantSpeedMBps else (0.7 * smoothedSpeedMBps + 0.3 * instantSpeedMBps)

                    val remainingBytes = totalBytes - downloadedBytes
                    val etaSec = if (smoothedSpeedMBps > 0.05) {
                        ((remainingBytes.toDouble() / (1024.0 * 1024.0)) / smoothedSpeedMBps).toLong()
                    } else 0L

                    val percent = if (totalBytes > 0) ((downloadedBytes * 100) / totalBytes).toInt() else 0
                    postProgress("downloading", downloadedBytes, totalBytes, smoothedSpeedMBps, etaSec, null)

                    // Update live notification every 1000ms
                    if (now - lastNotificationMs >= 1000) {
                        updateDownloadNotification(downloadedBytes, totalBytes, smoothedSpeedMBps, percent)
                        lastNotificationMs = now
                    }

                    lastUpdateMs = now
                    lastUpdateBytes = downloadedBytes
                }
            }

            outputStream.flush()
            outputStream.close()
            inputStream.close()

            if (isCancelled) {
                cancelDownloadNotification()
                return
            }

            // Atomic rename from .downloading to destination file
            if (destFile.exists()) {
                destFile.delete()
            }

            val renamed = partFile.renameTo(destFile)
            if (!renamed) {
                // Fallback copy if rename fails across mount points
                partFile.copyTo(destFile, overwrite = true)
                partFile.delete()
            }

            Log.i("ModelDownloader", "Download complete: ${destFile.absolutePath} (${destFile.length()} bytes)")
            isDownloading = false
            showDownloadCompleteNotification(destFile.absolutePath, destFile.length())
            postProgress("completed", destFile.length(), destFile.length(), 0.0, 0L, null)

        } catch (e: Exception) {
            if (!isCancelled) {
                Log.e("ModelDownloader", "Download failed: ${e.message}", e)
                isDownloading = false
                cancelDownloadNotification()
                postProgress("error", downloadedBytes, 0L, 0.0, 0L, e.message ?: "Download failed")
            }
        } finally {
            activeConnection?.disconnect()
            activeConnection = null
            isDownloading = false
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
