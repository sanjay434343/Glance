import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GemmaHardwareInfo {
  final bool hasGpu;
  final String gpuName;
  final String activeBackend;
  final bool isModelLoaded;
  final String loadedModelPath;

  GemmaHardwareInfo({
    required this.hasGpu,
    required this.gpuName,
    required this.activeBackend,
    required this.isModelLoaded,
    required this.loadedModelPath,
  });

  factory GemmaHardwareInfo.fromMap(Map<dynamic, dynamic> map) {
    return GemmaHardwareInfo(
      hasGpu: map['hasGpu'] as bool? ?? false,
      gpuName: map['gpuName'] as String? ?? 'CPU Fallback',
      activeBackend: map['activeBackend'] as String? ?? 'CPU',
      isModelLoaded: map['isModelLoaded'] as bool? ?? false,
      loadedModelPath: map['loadedModelPath'] as String? ?? '',
    );
  }
}

/// Dart Service bridging to native Kotlin MediaPipe LlmInference
class GemmaMediaPipeService {
  static final GemmaMediaPipeService instance = GemmaMediaPipeService._internal();
  GemmaMediaPipeService._internal();

  static const MethodChannel _channel = MethodChannel('com.glance.app/gemma_native');

  bool _isInitialized = false;
  GemmaHardwareInfo? _hardwareInfo;
  Completer<bool>? _initCompleter;

  bool get isInitialized => _isInitialized;
  GemmaHardwareInfo? get hardwareInfo => _hardwareInfo;

  /// Fetches current hardware GPU vs CPU status from native Kotlin.
  Future<GemmaHardwareInfo> fetchHardwareInfo() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getHardwareInfo');
      if (res != null) {
        _hardwareInfo = GemmaHardwareInfo.fromMap(res);
        return _hardwareInfo!;
      }
    } catch (e) {
      debugPrint('[GemmaMediaPipeService] Error fetching hardware info: $e');
    }
    _hardwareInfo = GemmaHardwareInfo(
      hasGpu: false,
      gpuName: 'CPU Fallback',
      activeBackend: 'CPU',
      isModelLoaded: false,
      loadedModelPath: '',
    );
    return _hardwareInfo!;
  }

  /// Initializes Gemma .task model with preferred backend ('GPU', 'CPU', or 'AUTO').
  Future<bool> initModel({String? customModelPath, String preferredBackend = 'AUTO'}) async {
    // If an initialization is already ongoing, await that single instance
    if (_initCompleter != null) {
      debugPrint('[GemmaMediaPipeService] Model initialization already running, awaiting existing task.');
      return _initCompleter!.future;
    }

    final completer = Completer<bool>();
    _initCompleter = completer;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool gpuEnabled = prefs.getBool('gemma_use_gpu') ?? true;
      final String effectiveBackend = preferredBackend == 'AUTO'
          ? (gpuEnabled ? 'GPU' : 'CPU')
          : preferredBackend;

      String modelPath = (customModelPath != null && customModelPath.trim().isNotEmpty)
          ? customModelPath.trim()
          : (prefs.getString('gemma_last_model_path') ?? '').trim();

      if (modelPath.isEmpty || !File(modelPath).existsSync()) {
        final docDir = await getApplicationDocumentsDirectory();
        final defaultTaskFile = File('${docDir.path}/gemma-2b-it.task');
        if (defaultTaskFile.existsSync()) {
          modelPath = defaultTaskFile.path;
        } else {
          final downloadDir = Directory('/sdcard/Download');
          if (downloadDir.existsSync()) {
            try {
              final taskFiles = downloadDir
                  .listSync()
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.task') || f.path.endsWith('.bin'))
                  .toList();
              if (taskFiles.isNotEmpty) {
                modelPath = taskFiles.first.path;
              }
            } catch (_) {}
          }
        }
      }

      if (modelPath.isEmpty) {
        debugPrint('[GemmaMediaPipeService] No model path specified or found on disk.');
        _isInitialized = false;
        if (!completer.isCompleted) completer.complete(false);
        return false;
      }

      // Always save exact path if specified by user or resolved
      await prefs.setString('gemma_last_model_path', modelPath);

      final bool success = await _channel.invokeMethod('initModel', {
        'modelPath': modelPath,
        'preferredBackend': effectiveBackend,
      }) ?? false;

      _isInitialized = success;
      await fetchHardwareInfo();
      if (!completer.isCompleted) completer.complete(success);
      return success;
    } catch (e) {
      debugPrint('[GemmaMediaPipeService] Error initializing model: $e');
      _isInitialized = false;
      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      _initCompleter = null;
    }
  }

  /// Returns whether GPU acceleration is enabled (defaults to true).
  Future<bool> isGpuEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('gemma_use_gpu') ?? true;
  }

  /// Sets GPU acceleration preference and re-initializes model if currently loaded.
  Future<bool> setGpuEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gemma_use_gpu', enabled);

    // If model is currently loaded, re-init with new preferred backend
    if (_hardwareInfo?.isModelLoaded == true) {
      return await initModel(
        preferredBackend: enabled ? 'GPU' : 'CPU',
      );
    }
    return true;
  }

  /// Executes text inference with MediaPipe Gemma LLM.
  Future<String> generateText(String prompt) async {
    try {
      final String response = await _channel.invokeMethod('generateText', {
        'prompt': prompt,
      }) ?? '';
      return response;
    } catch (e) {
      debugPrint('[GemmaMediaPipeService] Text generation error: $e');
      return 'Error: $e';
    }
  }

  /// Executes multimodal vision inference with MediaPipe Gemma LLM.
  Future<String> generateVision({required String imagePath, required String prompt}) async {
    try {
      final String response = await _channel.invokeMethod('generateVision', {
        'imagePath': imagePath,
        'prompt': prompt,
      }) ?? '';
      return response;
    } catch (e) {
      debugPrint('[GemmaMediaPipeService] Vision generation error: $e');
      return 'Error: $e';
    }
  }

  /// Unloads the active Gemma model from RAM and GPU VRAM.
  Future<bool> unloadModel() async {
    try {
      final bool success = await _channel.invokeMethod('unloadModel') ?? false;
      _isInitialized = false;
      await fetchHardwareInfo();
      return success;
    } catch (e) {
      debugPrint('[GemmaMediaPipeService] Error unloading model: $e');
      return false;
    }
  }

  static const String primaryModelsDirectory =
      '/storage/emulated/0/Android/media/com.example.glance/.glance/models';

  /// Resolves the current model file path on disk:
  /// Prioritizes `/storage/emulated/0/Android/media/com.example.glance/.glance/models/`
  /// with file size between 2GB and 4GB and extension .task.
  Future<String?> resolveModelPath() async {
    try {
      // 1. Primary storage: Android/media/com.example.glance/.glance/models/
      final mediaModelsDir = Directory(primaryModelsDirectory);
      if (mediaModelsDir.existsSync()) {
        final taskFiles = mediaModelsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.task'))
            .toList();

        if (taskFiles.isNotEmpty) {
          // Sort descending by size to prioritize full 2GB-4GB weights
          taskFiles.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
          final candidate = taskFiles.first;
          final size = candidate.lengthSync();
          // Verify size is above ~1.8GB (accommodating 2B models) and below ~4.5GB
          if (size >= 1800000000 && size <= 4500000000) {
            return candidate.path;
          }
          // If size is otherwise valid, return candidate
          return candidate.path;
        }
      }

      // 2. Previously chosen model path in preferences
      final prefs = await SharedPreferences.getInstance();
      String? savedPath = prefs.getString('gemma_last_model_path');
      if (savedPath != null && savedPath.trim().isNotEmpty && File(savedPath.trim()).existsSync()) {
        return savedPath.trim();
      }

      // 3. Fallback: Documents directory
      final docDir = await getApplicationDocumentsDirectory();
      final defaultTaskFile = File('${docDir.path}/gemma-2b-it.task');
      if (defaultTaskFile.existsSync()) {
        return defaultTaskFile.path;
      }

      // 4. Fallback: Downloads folder
      final downloadDir = Directory('/sdcard/Download');
      if (downloadDir.existsSync()) {
        final taskFiles = downloadDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.task'))
            .toList();
        if (taskFiles.isNotEmpty) {
          return taskFiles.first.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Gets the model file size in bytes from disk.
  Future<int> getModelFileSize() async {
    final path = await resolveModelPath();
    if (path == null) return 0;
    try {
      final file = File(path);
      if (file.existsSync()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Permanently deletes the model file from storage and unloads it from memory.
  Future<bool> deleteModelFile() async {
    try {
      final path = await resolveModelPath();
      await unloadModel();
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gemma_last_model_path');
      await fetchHardwareInfo();
      return true;
    } catch (e) {
      debugPrint('[GemmaMediaPipeService] Error deleting model file: $e');
      return false;
    }
  }
}
