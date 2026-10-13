# ==============================================================================
# GLANCE - COMPREHENSIVE PRODUCTION PROGUARD RULES
# Covers: MediaPipe GenAI / Vision, TensorFlow Lite, ONNX Runtime, ML Kit,
# SQLite, Vector Extensions, JNI, GPU/CPU Hardware Delegates, and Android APIs.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CORE FLUTTER & ANDROID FRAMEWORK
# ------------------------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep interface io.flutter.** { *; }
-dontwarn io.flutter.**

-keep class com.example.glance.** { *; }
-keepclassmembers class com.example.glance.** { *; }

# Keep native entry points & JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

-keep @androidx.annotation.Keep class * { *; }

# ------------------------------------------------------------------------------
# 2. GOOGLE MEDIAPIPE (Tasks GenAI, Tasks Vision, LlmInference, MPImage)
# ------------------------------------------------------------------------------
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

-keep class com.google.mediapipe.tasks.genai.** { *; }
-keep class com.google.mediapipe.tasks.vision.** { *; }
-keep class com.google.mediapipe.framework.** { *; }
-keep class com.google.mediapipe.framework.image.** { *; }

# MediaPipe C++ JNI Bridges & Native JNI Loaders
-keepclasseswithmembernames class com.google.mediapipe.** {
    native <methods>;
}

# ------------------------------------------------------------------------------
# 3. TENSORFLOW LITE & GPU / CPU DELEGATES (Vulkan, OpenCL, Hexagon, NNAPI)
# ------------------------------------------------------------------------------
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.nnapi.** { *; }
-keep class org.tensorflow.lite.support.** { *; }

-keepclasseswithmembernames class org.tensorflow.lite.** {
    native <methods>;
}

# ------------------------------------------------------------------------------
# 4. ONNX RUNTIME (CPU, NNAPI, GPU Execution Providers)
# ------------------------------------------------------------------------------
-keep class ai.onnxruntime.** { *; }
-keep interface ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

-keepclasseswithmembernames class ai.onnxruntime.** {
    native <methods>;
}

# ------------------------------------------------------------------------------
# 5. GOOGLE ML KIT (Text Recognition, Entity Extraction, Vision)
# ------------------------------------------------------------------------------
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.internal.vision.** { *; }

# ML Kit Entity Extraction models and assets
-keep class com.google.mlkit.nl.entityextraction.** { *; }
-keep class com.google.mlkit.vision.text.** { *; }

# Google Play Services & Firebase ML Transport
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.common.**
-keep class com.google.android.datatransport.** { *; }
-dontwarn com.google.android.datatransport.**

# ------------------------------------------------------------------------------
# 6. SQLITE, VECTOR EXTENSIONS & DRIFT DATABASE
# ------------------------------------------------------------------------------
-keep class org.sqlite.** { *; }
-keep class io.requery.android.database.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# sqlite_vector native bridge bindings
-keep class * implements sqlite3.** { *; }
-keep class sqlite3.** { *; }
-dontwarn sqlite3.**

# ------------------------------------------------------------------------------
# 7. ANDROID SYSTEM HARDWARE, OPENGL, EGL & VULKAN REFLECTION
# ------------------------------------------------------------------------------
-keep class android.opengl.** { *; }
-keep class javax.microedition.khronos.** { *; }
-dontwarn android.opengl.**

# Hardware inspection, battery, memory, display metrics
-keepclassmembers class android.os.Build { *; }
-keepclassmembers class android.app.ActivityManager { *; }
-keepclassmembers class android.app.ActivityManager$MemoryInfo { *; }

# ------------------------------------------------------------------------------
# 8. BACKGROUND SERVICES, NOTIFICATION LISTENER & BROADCAST RECEIVERS
# ------------------------------------------------------------------------------
-keep public class com.example.glance.GlanceForegroundService extends android.app.Service
-keep public class com.example.glance.GlanceNotificationService extends android.service.notification.NotificationListenerService
-keep public class androidx.work.** { *; }
-dontwarn androidx.work.**

# ------------------------------------------------------------------------------
# 9. GENERAL SERIALIZATION & PROTOBUF
# ------------------------------------------------------------------------------
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Keep enum values for reflection and type safe lookup
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
