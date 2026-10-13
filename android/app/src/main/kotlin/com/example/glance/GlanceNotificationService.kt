package com.example.glance

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.ArrayDeque

class GlanceNotificationService : NotificationListenerService() {

    companion object {
        val capturedNotifications = ArrayDeque<Map<String, Any>>(105)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val pkgName = sbn.packageName ?: return
        
        // Skip Glance's own notifications
        if (pkgName == packageName) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        val pm = packageManager
        val appName = try {
            val info = pm.getApplicationInfo(pkgName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            pkgName
        }

        val item = mapOf<String, Any>(
            "packageName" to pkgName,
            "appName" to appName,
            "title" to title,
            "text" to text,
            "timestamp" to sbn.postTime
        )

        // Store in synchronized queue (cap at 100 entries with O(1) operations)
        synchronized(capturedNotifications) {
            capturedNotifications.addFirst(item)
            if (capturedNotifications.size > 100) {
                capturedNotifications.removeLast()
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Notification dismissed, no-op
    }
}
