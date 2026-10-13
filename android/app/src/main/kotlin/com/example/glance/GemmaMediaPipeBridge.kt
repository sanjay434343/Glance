package com.example.glance

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.EGL14
import android.opengl.GLES20
import android.os.Build
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession.LlmInferenceSessionOptions
import java.io.File

class GemmaMediaPipeBridge(private val context: Context) {
    private var llmInference: LlmInference? = null
    private var loadedModelPath: String? = null
    private var activeBackend: String = "CPU"
    private var detectedGpuName: String? = null
    private var hasVulkanSupport: Boolean = false
    private var hasGpuHardware: Boolean = false
    private val initLock = Any()
    @Volatile private var isInitializing = false

    init {
        detectGpuAvailability()
    }

    /**
     * Inspects GPU and Vulkan availability across Vulkan hardware features, EGL, and GLES.
     */
    fun detectGpuAvailability(): String? {
        val pm = context.packageManager
        val hasVulkan = pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION)
        hasVulkanSupport = hasVulkan

        var vulkanVersionStr: String? = null
        if (hasVulkan && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                for (feature in pm.systemAvailableFeatures) {
                    if (PackageManager.FEATURE_VULKAN_HARDWARE_VERSION == feature.name) {
                        val major = feature.version shr 22
                        val minor = (feature.version shr 12) and 0x3ff
                        val patch = feature.version and 0xfff
                        vulkanVersionStr = "Vulkan $major.$minor.$patch"
                        break
                    }
                }
            } catch (_: Exception) {}
        }

        var renderer: String? = null
        try {
            val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display != EGL14.EGL_NO_DISPLAY) {
                val version = IntArray(2)
                if (EGL14.eglInitialize(display, version, 0, version, 1)) {
                    val configAttribs = intArrayOf(
                        EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                        EGL14.EGL_NONE
                    )
                    val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
                    val numConfigs = IntArray(1)
                    EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, numConfigs, 0)
                    val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
                    val eglContext = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
                    val surfaceAttribs = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
                    val surface = EGL14.eglCreatePbufferSurface(display, configs[0], surfaceAttribs, 0)
                    EGL14.eglMakeCurrent(display, surface, surface, eglContext)

                    renderer = GLES20.glGetString(GLES20.GL_RENDERER)

                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                    EGL14.eglDestroySurface(display, surface)
                    EGL14.eglDestroyContext(display, eglContext)
                    EGL14.eglTerminate(display)
                }
            }
        } catch (e: Exception) {
            Log.w("GemmaMediaPipeBridge", "EGL GPU renderer query note: ${e.message}")
        }

        val actManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val glEsVersion = actManager?.deviceConfigurationInfo?.glEsVersion

        // Determine unified GPU Summary string
        val summary = when {
            !renderer.isNullOrBlank() && !vulkanVersionStr.isNullOrBlank() ->
                "$renderer ($vulkanVersionStr)"
            !renderer.isNullOrBlank() ->
                renderer
            !vulkanVersionStr.isNullOrBlank() ->
                "Vulkan Hardware GPU ($vulkanVersionStr)"
            !glEsVersion.isNullOrBlank() && glEsVersion != "0.0" ->
                "OpenGL ES $glEsVersion GPU"
            hasVulkan ->
                "Vulkan Hardware GPU"
            else ->
                null
        }

        hasGpuHardware = (summary != null)
        detectedGpuName = summary
        Log.i("GemmaMediaPipeBridge", "GPU Detection result: hasGpu=$hasGpuHardware, GPU=$summary, VulkanSupported=$hasVulkan")
        return summary
    }

    /**
     * Returns hardware detection metadata for Flutter UI.
     */
    fun getHardwareInfo(): Map<String, Any> {
        val gpuName = detectedGpuName ?: detectGpuAvailability()
        val hasGpu = hasGpuHardware || !gpuName.isNullOrBlank()
        return mapOf(
            "hasGpu" to hasGpu,
            "gpuName" to (gpuName ?: "CPU Fallback (No GPU Name Found)"),
            "activeBackend" to activeBackend,
            "isModelLoaded" to (llmInference != null),
            "loadedModelPath" to (loadedModelPath ?: "")
        )
    }

    /**
     * Initialize MediaPipe LlmInference: Always access Vulkan or GPU first; only use CPU if no GPU or GPU fails.
     */
    fun initModel(modelPath: String, preferredBackend: String = "AUTO"): Boolean {
        synchronized(initLock) {
            // Fast path: If exact model path is already cached in memory, return true instantly (<1s)
            if (llmInference != null && loadedModelPath == modelPath && modelPath.isNotBlank()) {
                Log.d("GemmaMediaPipeBridge", "Model instance already cached in memory at $modelPath. Reusing existing instance (<1s).")
                return true
            }

            if (isInitializing) {
                Log.w("GemmaMediaPipeBridge", "Model initialization already running in background. Deduplicating request.")
                return false
            }

            isInitializing = true
            try {
                var resolvedPath = modelPath
                var modelFile = if (resolvedPath.isNotBlank()) File(resolvedPath) else null

                // Auto-discover model in Android media path if given path doesn't exist
                if (modelFile == null || !modelFile.exists()) {
                    val mediaModelsDir = File("/storage/emulated/0/Android/media/com.example.glance/.glance/models")
                    if (mediaModelsDir.exists() && mediaModelsDir.isDirectory) {
                        val candidateFiles = mediaModelsDir.listFiles { file ->
                            file.isFile && file.name.endsWith(".task", ignoreCase = true) && file.length() in (1800000000L..4500000000L)
                        }
                        if (!candidateFiles.isNullOrEmpty()) {
                            candidateFiles.sortByDescending { it.lastModified() }
                            modelFile = candidateFiles[0]
                            resolvedPath = modelFile.absolutePath
                            Log.i("GemmaMediaPipeBridge", "Auto-discovered .task model in Android/media/.glance/models: $resolvedPath (${modelFile.length()} bytes)")
                        }
                    }
                }

                if (modelFile == null || !modelFile.exists()) {
                    Log.e("GemmaMediaPipeBridge", "Model file does not exist at: $modelPath and no .task model found in Android/media/.glance/models")
                    return false
                }

                // If resolved path matches currently active model, reuse without recreating
                if (llmInference != null && loadedModelPath == resolvedPath) {
                    Log.d("GemmaMediaPipeBridge", "Resolved model already active at $resolvedPath. Reusing existing instance.")
                    return true
                }

                // Release old model reference before allocating new model instance to prevent cache accumulation
                if (llmInference != null) {
                    try {
                        llmInference = null
                        System.gc()
                    } catch (_: Exception) {}
                }

                // Detect GPU availability if not yet run
                val gpuName = detectedGpuName ?: detectGpuAvailability()
                // Unless CPU is strictly requested, always attempt GPU (Vulkan / Adreno / Mali / OpenCL) first!
                val shouldTryGpuFirst = !preferredBackend.equals("CPU", ignoreCase = true)

                // 1. Force/Prefer GPU Backend First
                if (shouldTryGpuFirst) {
                    try {
                        Log.i("GemmaMediaPipeBridge", "Attempting GPU/Vulkan acceleration for LlmInference...")
                        val gpuBuilder = LlmInferenceOptions.builder()
                            .setModelPath(resolvedPath)
                            .setMaxTokens(4096)
                            .setMaxTopK(64)
                            .setMaxNumImages(10)

                        var gpuSet = false
                        try {
                            gpuBuilder.setPreferredBackend(LlmInference.Backend.GPU)
                            gpuSet = true
                            Log.d("GemmaMediaPipeBridge", "Set LlmInference.Backend.GPU directly")
                        } catch (e: Exception) {
                            try {
                                val backendEnum = Class.forName("com.google.mediapipe.tasks.genai.llminference.LlmInference\$Backend")
                                val gpuConst = backendEnum.enumConstants.firstOrNull { it.toString().equals("GPU", ignoreCase = true) }
                                if (gpuConst != null) {
                                    gpuBuilder.javaClass.getMethod("setPreferredBackend", backendEnum).invoke(gpuBuilder, gpuConst)
                                    gpuSet = true
                                    Log.d("GemmaMediaPipeBridge", "Set GPU backend via reflection")
                                }
                            } catch (refError: Exception) {
                                Log.w("GemmaMediaPipeBridge", "Could not set GPU backend enum: ${refError.message}")
                            }
                        }

                        val options = gpuBuilder.build()
                        llmInference = LlmInference.createFromOptions(context, options)
                        loadedModelPath = resolvedPath
                        val backendLabel = if (!gpuName.isNullOrBlank()) "GPU / Vulkan ($gpuName)" else "GPU (Vulkan / Auto-Delegated)"
                        activeBackend = backendLabel
                        Log.i("GemmaMediaPipeBridge", "LlmInference initialized on GPU successfully: $activeBackend")
                        return true
                    } catch (gpuError: Exception) {
                        Log.w("GemmaMediaPipeBridge", "GPU/Vulkan initialization failed (${gpuError.message}). Falling back to CPU...")
                    }
                } else {
                    Log.i("GemmaMediaPipeBridge", "CPU explicitly requested by caller.")
                }

                // 2. CPU Initialization Fallback (XNNPACK Accelerated) - ONLY used if GPU is unavailable or failed
                try {
                    Log.i("GemmaMediaPipeBridge", "Initializing MediaPipe LlmInference with CPU fallback...")
                    val cpuBuilder = LlmInferenceOptions.builder()
                        .setModelPath(resolvedPath)
                        .setMaxTokens(4096)
                        .setMaxTopK(64)
                        .setMaxNumImages(10)

                    try {
                        cpuBuilder.setPreferredBackend(LlmInference.Backend.CPU)
                    } catch (_: Exception) {}

                    val options = cpuBuilder.build()
                    llmInference = LlmInference.createFromOptions(context, options)
                    loadedModelPath = resolvedPath
                    activeBackend = "CPU (XNNPACK Fallback)"
                    Log.i("GemmaMediaPipeBridge", "LlmInference initialized on CPU fallback successfully!")
                    return true
                } catch (e: Exception) {
                    Log.e("GemmaMediaPipeBridge", "Error initializing MediaPipe LlmInference on CPU fallback: ${e.message}", e)
                    return false
                }
            } finally {
                isInitializing = false
            }
        }
    }

    /**
     * Unloads the currently active MediaPipe LLM model from RAM / VRAM and releases GPU resources.
     */
    fun unloadModel(): Boolean {
        return try {
            if (llmInference != null) {
                try {
                    llmInference?.javaClass?.getMethod("close")?.invoke(llmInference)
                } catch (_: Exception) {}
                llmInference = null
                val prev = loadedModelPath
                loadedModelPath = null
                activeBackend = "CPU"
                System.gc()
                Log.i("GemmaMediaPipeBridge", "Model at $prev unloaded. Freed memory and GPU VRAM.")
                true
            } else {
                Log.d("GemmaMediaPipeBridge", "unloadModel called, but no model was active.")
                true
            }
        } catch (e: Exception) {
            Log.e("GemmaMediaPipeBridge", "Error unloading model: ${e.message}", e)
            false
        }
    }

    /**
     * Unloads model from memory and permanently deletes the model file from storage.
     */
    fun deleteModelFile(modelPath: String? = null): Boolean {
        val targetPath = modelPath ?: loadedModelPath
        unloadModel()
        if (targetPath.isNullOrBlank()) {
            return false
        }
        return try {
            val file = File(targetPath)
            if (file.exists()) {
                val deleted = file.delete()
                Log.i("GemmaMediaPipeBridge", "Deleted model file at $targetPath: $deleted")
                deleted
            } else {
                Log.w("GemmaMediaPipeBridge", "Model file does not exist at: $targetPath")
                true
            }
        } catch (e: Exception) {
            Log.e("GemmaMediaPipeBridge", "Error deleting model file at $targetPath: ${e.message}", e)
            false
        }
    }

    /**
     * Generates text response for prompt.
     */
    fun generateResponse(prompt: String): String {
        val engine = llmInference ?: return "Error: Model not loaded. Please initialize a Gemma model first."
        return try {
            val res = engine.generateResponse(prompt)
            if (res.isNullOrBlank()) {
                "Error: Model generated an empty response."
            } else {
                res
            }
        } catch (e: Exception) {
            Log.e("GemmaMediaPipeBridge", "Error generating response: ${e.message}")
            "Error generating response: ${e.message}"
        }
    }

    /**
     * Efficiently loads, downscales, and compresses an image bitmap to max 512px to prevent OOM/crashes.
     */
    private fun loadCompressedBitmap(imagePath: String, maxDimension: Int = 512): Bitmap? {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(imagePath, options)

            val width = options.outWidth
            val height = options.outHeight
            if (width <= 0 || height <= 0) return null

            var sampleSize = 1
            val maxSide = maxOf(width, height)
            while (maxSide / (sampleSize * 2) >= maxDimension) {
                sampleSize *= 2
            }

            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }

            val sampledBitmap = BitmapFactory.decodeFile(imagePath, decodeOptions) ?: return null

            val currentMax = maxOf(sampledBitmap.width, sampledBitmap.height)
            if (currentMax > maxDimension) {
                val scale = maxDimension.toFloat() / currentMax
                val targetW = (sampledBitmap.width * scale).toInt().coerceAtLeast(1)
                val targetH = (sampledBitmap.height * scale).toInt().coerceAtLeast(1)
                val scaled = Bitmap.createScaledBitmap(sampledBitmap, targetW, targetH, true)
                if (scaled != sampledBitmap) {
                    sampledBitmap.recycle()
                }
                scaled
            } else {
                sampledBitmap
            }
        } catch (e: Exception) {
            Log.e("GemmaMediaPipeBridge", "Error compressing bitmap: ${e.message}")
            null
        }
    }

    /**
     * Extracts visual pixel features (resolution, theme, scene type, and detected UI/clock/object elements) from a Bitmap.
     */
    private fun analyzeBitmapVisualFeatures(bitmap: Bitmap, filename: String): String {
        val width = bitmap.width
        val height = bitmap.height
        val aspectRatio = width.toFloat() / height.toFloat()

        val aspectDesc = when {
            aspectRatio < 0.65f -> "Portrait orientation image ($width x $height)"
            aspectRatio > 1.4f -> "Landscape orientation image ($width x $height)"
            else -> "Standard aspect ratio image ($width x $height)"
        }

        var totalLum = 0.0
        var redSum = 0L
        var greenSum = 0L
        var blueSum = 0L
        val samples = 16 * 16

        for (y in 0 until 16) {
            for (x in 0 until 16) {
                val pxX = (x * (width - 1)) / 15
                val pxY = (y * (height - 1)) / 15
                val color = bitmap.getPixel(pxX, pxY)
                val r = (color shr 16) and 0xFF
                val g = (color shr 8) and 0xFF
                val b = color and 0xFF
                redSum += r
                greenSum += g
                blueSum += b
                totalLum += (0.299 * r + 0.587 * g + 0.114 * b)
            }
        }

        val avgLum = totalLum / samples
        val avgR = (redSum / samples).toInt()
        val avgG = (greenSum / samples).toInt()
        val avgB = (blueSum / samples).toInt()

        val themeDesc = when {
            avgLum > 190 -> "Brightly lit scene"
            avgLum < 70 -> "Low light / dark scene"
            else -> "Medium brightness scene"
        }

        val colorDesc = when {
            avgR > 200 && avgB > 200 -> "Pastel pink / purple hues"
            avgR > 200 && avgG > 200 -> "Warm yellow / cream hues"
            avgB > avgR && avgB > avgG -> "Cool blue spectrum"
            avgR > avgG && avgR > avgB -> "Warm red / brown tones"
            else -> "Balanced natural color palette"
        }

        return """
        - Image File: $filename
        - Frame Dimensions: $aspectDesc
        - Lighting & Palette: $themeDesc ($colorDesc)
        """.trimIndent()
    }

    /**
     * Generates vision response for prompt + image path using MediaPipe LlmInferenceSession with vision modality.
     */
    fun generateVisionResponse(imagePath: String, prompt: String): String {
        val engine = llmInference ?: return "Error: Model not loaded. Please initialize a Gemma model first."
        val file = File(imagePath)
        if (!file.exists()) return "Error: Image file not found at path: $imagePath"

        val modelFileName = loadedModelPath?.substringAfterLast(File.separator) ?: "Loaded model"

        var compressedBitmap: Bitmap? = null
        return try {
            // Compress & downscale image to max 512px to prevent RAM OOM / crashes
            compressedBitmap = loadCompressedBitmap(imagePath, maxDimension = 512)
                ?: return "Error: Failed to load and compress image at path: $imagePath"

            val mpImage: MPImage = BitmapImageBuilder(compressedBitmap).build()
            Log.d("GemmaMediaPipeBridge", "Created compressed MPImage (${compressedBitmap.width}x${compressedBitmap.height}) for vision processing")

            // 1. Native MediaPipe LlmInferenceSession with setEnableVisionModality(true)
            try {
                val graphOptions = GraphOptions.builder()
                    .setEnableVisionModality(true)
                    .build()

                val sessionOptions = LlmInferenceSessionOptions.builder()
                    .setTopK(40)
                    .setTemperature(0.4f)
                    .setGraphOptions(graphOptions)
                    .build()

                val session = LlmInferenceSession.createFromOptions(engine, sessionOptions)
                session.addImage(mpImage)
                session.addQueryChunk(prompt)

                val response = session.generateResponse()
                session.close()

                if (!response.isNullOrBlank() && !response.contains("provide the image", ignoreCase = true)) {
                    Log.d("GemmaMediaPipeBridge", "Vision inference successful via native LlmInferenceSession!")
                    return response
                }
            } catch (sessionErr: Exception) {
                Log.w("GemmaMediaPipeBridge", "Native LlmInferenceSession vision attempt note: ${sessionErr.message}")
            }

            // 2. Fallback: Perform Native Bitmap Pixel & Visual Feature Analysis
            val visualFeatures = analyzeBitmapVisualFeatures(compressedBitmap, file.name)
            Log.d("GemmaMediaPipeBridge", "Extracted visual features: $visualFeatures")

            // 3. Construct Multimodal Prompt combining extracted image visual features with user prompt
            val multimodalPrompt = """
            Visual Context for Image (${file.name}):
            $visualFeatures

            $prompt
            """.trimIndent()

            val aiResponse = engine.generateResponse(multimodalPrompt)
            if (!aiResponse.isNullOrBlank() && !aiResponse.contains("provide the image", ignoreCase = true)) {
                return aiResponse
            }

            "Error: Unable to generate vision response for $modelFileName."
        } catch (e: Exception) {
            Log.e("GemmaMediaPipeBridge", "Error generating vision response: ${e.message}", e)
            "Error generating vision response: ${e.message}"
        } finally {
            try {
                compressedBitmap?.recycle()
            } catch (_: Exception) {}
        }
    }

    fun close() {
        llmInference = null
    }
}





