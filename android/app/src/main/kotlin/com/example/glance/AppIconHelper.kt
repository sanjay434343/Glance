package com.example.glance

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.LruCache
import java.io.ByteArrayOutputStream

/**
 * High-performance shared in-memory LRU cache for Android app icons.
 * Prevents repetitive Canvas redraws, bitmap scaling, PNG compression,
 * and Base64 encoding across AppMonitor, MainActivity, and background services.
 */
object AppIconHelper {
    private val iconCache = LruCache<String, String>(250)

    fun getIconBase64(pm: PackageManager, packageName: String): String {
        iconCache.get(packageName)?.let { return it }
        return try {
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val drawable = pm.getApplicationIcon(appInfo)
            getIconBase64(drawable, packageName)
        } catch (_: Exception) {
            ""
        }
    }

    fun getIconBase64(drawable: Drawable, packageName: String? = null): String {
        if (packageName != null) {
            iconCache.get(packageName)?.let { return it }
        }

        var tempBitmap: Bitmap? = null
        val bitmap: Bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val w = drawable.intrinsicWidth.coerceAtLeast(1)
            val h = drawable.intrinsicHeight.coerceAtLeast(1)
            val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(b)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            tempBitmap = b
            b
        }

        val scaledBitmap = if (bitmap.width > 64 || bitmap.height > 64) {
            Bitmap.createScaledBitmap(bitmap, 64, 64, true)
        } else {
            bitmap
        }

        val stream = ByteArrayOutputStream(4096)
        scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        val byteArray = stream.toByteArray()
        val base64 = Base64.encodeToString(byteArray, Base64.NO_WRAP)

        // Clean up temporary bitmaps to prevent native heap fragmentation
        if (scaledBitmap != bitmap) {
            try { scaledBitmap.recycle() } catch (_: Exception) {}
        }
        tempBitmap?.let {
            try { it.recycle() } catch (_: Exception) {}
        }

        if (packageName != null && base64.isNotEmpty()) {
            iconCache.put(packageName, base64)
        }

        return base64
    }

    fun clear() {
        iconCache.evictAll()
    }
}
