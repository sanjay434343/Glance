import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../database/glance_db.dart';
import 'gemma_mediapipe_service.dart';
import 'image_compression_service.dart';
import 'document_extraction_service.dart';

/// Structured vision analysis result from Gemma MediaPipe.
class VisionAnalysisResult {
  final String title;
  final String subtitle;
  final String description;
  final List<String> tags;
  final String rawJson;
  final double inferenceSec;

  VisionAnalysisResult({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.tags,
    required this.rawJson,
    required this.inferenceSec,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'summary': description,
      'tags': tags,
      'inference_sec': inferenceSec,
    };
  }
}

/// Represents a single queued vision extraction task.
class VisionTask {
  final String memoryId;
  final String imagePath;
  final Completer<VisionAnalysisResult?> completer;
  final DateTime enqueuedAt;
  final int capturedAt;
  String? compressedPath;

  VisionTask({
    required this.memoryId,
    required this.imagePath,
    required this.completer,
    required this.enqueuedAt,
    required this.capturedAt,
    this.compressedPath,
  });
}

/// Vision Queue Status for UI listeners.
class VisionQueueStatus {
  final int queueLength;
  final bool isProcessing;
  final String? currentTaskMemoryId;
  final String? currentTaskStatus;

  VisionQueueStatus({
    required this.queueLength,
    required this.isProcessing,
    this.currentTaskMemoryId,
    this.currentTaskStatus,
  });
}

/// Vision Service for Glance.
/// Manages Gemma MediaPipe vision model initialization, sequential queue processing of
/// screenshots/photos, and auto-persisting vision metadata to SQLite.
class VisionService {
  static final VisionService instance = VisionService._internal();
  VisionService._internal();

  bool _isInitializing = false;
  bool _isReady = false;
  String? _initError;

  final Queue<VisionTask> _queue = Queue<VisionTask>();
  final Set<String> _processedMemoryIds = {};
  final Set<String> _processedImagePaths = {};
  bool _isProcessingQueue = false;

  final StreamController<VisionQueueStatus> _statusController =
      StreamController<VisionQueueStatus>.broadcast();

  Stream<VisionQueueStatus> get statusStream => _statusController.stream;
  bool get isReady => _isReady;
  String? get initError => _initError;
  int get queueLength => _queue.length;
  bool get isProcessing => _isProcessingQueue;

  /// Initialize Gemma MediaPipe vision model engine.
  Future<bool> initialize() async {
    if (_isReady) return true;
    if (_isInitializing) return false;

    _isInitializing = true;
    _initError = null;
    _notifyStatus("Loading Gemma MediaPipe Vision model...");

    try {
      final success = await GemmaMediaPipeService.instance.initModel(preferredBackend: 'AUTO');
      if (success) {
        _isReady = true;
        _isInitializing = false;
        final hw = await GemmaMediaPipeService.instance.fetchHardwareInfo();
        _notifyStatus("Ready (${hw.activeBackend})");
        // Defer batch image processing slightly so UI stays completely fluid
        Future.delayed(const Duration(milliseconds: 1000), () {
          processAllExistingImages();
        });
        return true;
      } else {
        _isInitializing = false;
        _isReady = false;
        _initError = "Failed to initialize Gemma MediaPipe engine";
        _notifyStatus("Engine Init Error");
        return false;
      }
    } catch (e, stack) {
      _isInitializing = false;
      _isReady = false;
      _initError = e.toString();
      debugPrint('[VisionService] Error initializing Gemma Engine: $e\n$stack');
      _notifyStatus("Error: $e");
      return false;
    }
  }

  /// Scans all existing image/screenshot memories in SQLite database
  /// and enqueues any unprocessed images for vision extraction.
  Future<int> processAllExistingImages() async {
    try {
      final db = GlanceDatabase.instance;
      final memories = await db.getAllMemories();

      int enqueuedCount = 0;
      for (final mem in memories) {
        final filePath = (mem.filePath ?? mem.thumbnailPath ?? '').trim();
        final type = mem.type.toLowerCase();

        final isImage =
            filePath.isNotEmpty &&
            (type == 'screenshot' ||
                type == 'photo' ||
                type == 'camera_capture' ||
                filePath.endsWith('.jpg') ||
                filePath.endsWith('.jpeg') ||
                filePath.endsWith('.png') ||
                filePath.endsWith('.webp'));

        if (isImage) {
          final isStalePrompt = (mem.summary != null && mem.summary!.contains('04 18')) ||
              (mem.content.contains('04 18') && mem.content.contains('Monday 25'));
          if ((!mem.isProcessed || isStalePrompt) &&
              !_processedMemoryIds.contains(mem.id) &&
              !_processedImagePaths.contains(filePath)) {
            enqueue(memoryId: mem.id, imagePath: filePath, force: isStalePrompt);
            enqueuedCount++;
          } else {
            _processedMemoryIds.add(mem.id);
            if (filePath.isNotEmpty) _processedImagePaths.add(filePath);
          }
        }
      }
      debugPrint('[VisionService] Enqueued $enqueuedCount existing images for Gemma vision processing');
      return enqueuedCount;
    } catch (e) {
      debugPrint('[VisionService] Error scanning existing images: $e');
      return 0;
    }
  }

  /// Force rescan and re-process all image/screenshot memories in SQLite.
  Future<int> forceRescanAllImages() async {
    try {
      _processedMemoryIds.clear();
      _processedImagePaths.clear();

      final db = GlanceDatabase.instance;
      final memories = await db.getAllMemories();

      int enqueuedCount = 0;
      for (final mem in memories) {
        final filePath = (mem.filePath ?? mem.thumbnailPath ?? '').trim();
        final type = mem.type.toLowerCase();

        final isImage =
            filePath.isNotEmpty &&
            (type == 'screenshot' ||
                type == 'photo' ||
                type == 'camera_capture' ||
                filePath.endsWith('.jpg') ||
                filePath.endsWith('.jpeg') ||
                filePath.endsWith('.png') ||
                filePath.endsWith('.webp'));

        if (isImage) {
          if (mem.isProcessed) {
            final resetMem = mem.copyWith(
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              isProcessed: false,
            );
            await db.insertMemory(resetMem);
          }

          enqueue(memoryId: mem.id, imagePath: filePath, force: true);
          enqueuedCount++;
        }
      }
      _notifyStatus("Force rescan started ($enqueuedCount images)");
      return enqueuedCount;
    } catch (e) {
      debugPrint('[VisionService] Error during force rescan: $e');
      return 0;
    }
  }

  /// Enqueue an image/screenshot for background Gemma vision extraction.
  Future<VisionAnalysisResult?> enqueue({
    required String memoryId,
    required String imagePath,
    bool force = false,
  }) async {
    final normPath = imagePath.trim();
    if (normPath.isEmpty || (!normPath.startsWith('content://') && !File(normPath).existsSync())) {
      return null;
    }

    if (!force) {
      if (_processedMemoryIds.contains(memoryId) ||
          _processedImagePaths.contains(normPath)) {
        return null;
      }
    }

    if (_queue.any((t) => t.memoryId == memoryId || t.imagePath == normPath)) {
      return null;
    }

    int memoryCapturedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final db = GlanceDatabase.instance;
      final existing =
          await db.getMemory(memoryId) ??
          await db.getMemoryByFilePath(normPath);
      if (existing != null) {
        memoryCapturedAt = existing.capturedAt;
        if (!force && existing.isProcessed) {
          _processedMemoryIds.add(memoryId);
          _processedImagePaths.add(normPath);
          return null;
        }
      }
    } catch (_) {}

    final completer = Completer<VisionAnalysisResult?>();
    final task = VisionTask(
      memoryId: memoryId,
      imagePath: normPath,
      completer: completer,
      enqueuedAt: DateTime.now(),
      capturedAt: memoryCapturedAt,
    );

    final List<VisionTask> tasksList = _queue.toList();
    tasksList.add(task);
    tasksList.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    _queue.clear();
    _queue.addAll(tasksList);

    _notifyStatus("Task enqueued");
    _processNextQueueItem();
    return completer.future;
  }

  Future<void> _processNextQueueItem() async {
    if (_isProcessingQueue || _queue.isEmpty) return;

    _isProcessingQueue = true;
    const batchSize = 10;

    while (_queue.isNotEmpty) {
      final currentBatch = _queue.take(batchSize).toList();

      final uncompressed = currentBatch.where((t) => t.compressedPath == null).toList();
      for (int cIdx = 0; cIdx < uncompressed.length; cIdx++) {
        final t = uncompressed[cIdx];
        _notifyStatus(
          "Compressing batch thumbnail (${cIdx + 1}/${uncompressed.length})",
          currentMemoryId: t.memoryId,
        );

        final cPath = await ImageCompressionService.compressForVisionAI(t.imagePath);
        t.compressedPath = cPath ?? t.imagePath;

        if (cPath != null) {
          final db = GlanceDatabase.instance;
          final mem = await db.getMemory(t.memoryId);
          if (mem != null && mem.thumbnailPath == null) {
            final updated = mem.copyWith(
              thumbnailPath: cPath,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
            await db.insertMemory(updated);
          }
        }
      }

      for (int i = 0; i < currentBatch.length; i++) {
        final task = currentBatch[i];
        _queue.remove(task);

        try {
          _notifyStatus(
            "Batch AI (${i + 1}/${currentBatch.length}) - Queue: ${_queue.length}",
            currentMemoryId: task.memoryId,
          );

          if (!_isReady) {
            final ok = await initialize();
            if (!ok) {
              task.completer.complete(null);
              continue;
            }
          }

          final result = await _analyzeImageFile(task.compressedPath!);
          if (result != null) {
            _processedMemoryIds.add(task.memoryId);
            _processedImagePaths.add(task.imagePath);
            await _updateDatabaseMemory(task.memoryId, result, task.compressedPath);
          }

          task.completer.complete(result);
        } catch (e) {
          debugPrint('[VisionService] Error processing vision task for ${task.memoryId}: $e');
          if (!task.completer.isCompleted) {
            task.completer.complete(null);
          }
        }
      }
    }

    _isProcessingQueue = false;
    _notifyStatus("Idle");
    DocumentExtractionService.instance.processUnprocessedDocuments();
  }

  static const singleVisionPrompt =
      'Analyze the provided image and OCR text context carefully.\n'
      'Identify the main subject, app name, screen topic, text content, objects, and visual context.\n'
      'Output ONLY a valid raw JSON object with NO markdown formatting, NO backticks, and NO extra text.\n'
      'Required JSON format:\n'
      '{\n'
      '  "title": "<concise descriptive title>",\n'
      '  "subtitle": "<one sentence subtitle summarizing main context>",\n'
      '  "description": "<detailed description of visible text, UI elements, objects, and details in the image>",\n'
      '  "tags": ["tag1", "tag2", "tag3", "tag4", "tag5"]\n'
      '}';

  /// Executes Gemma vision inference via GemmaMediaPipeService after MLKit OCR extraction.
  Future<VisionAnalysisResult?> _analyzeImageFile(String imagePath) async {
    final stopwatch = Stopwatch()..start();

    // 1. Run MLKit Text Recognition on the image to capture real text context
    String ocrText = "";
    try {
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      ocrText = recognizedText.text.trim();
    } catch (e) {
      debugPrint('[VisionService] OCR text extraction note: $e');
    }

    // 2. Build enriched prompt with OCR text context
    final StringBuffer fullPrompt = StringBuffer();
    if (ocrText.isNotEmpty) {
      fullPrompt.writeln('Extracted Text Content from Image:');
      fullPrompt.writeln('"""');
      fullPrompt.writeln(ocrText.length > 1500 ? ocrText.substring(0, 1500) : ocrText);
      fullPrompt.writeln('"""');
      fullPrompt.writeln();
    }
    fullPrompt.writeln(singleVisionPrompt);

    final responseText = await GemmaMediaPipeService.instance.generateVision(
      imagePath: imagePath,
      prompt: fullPrompt.toString(),
    );

    stopwatch.stop();

    final trimmedResp = responseText.trim();
    if (trimmedResp.isEmpty ||
        trimmedResp.startsWith('Error') ||
        trimmedResp.startsWith('Model not loaded') ||
        trimmedResp.startsWith('Failed')) {
      debugPrint('[VisionService] Failed vision inference for $imagePath: $responseText');
      return null;
    }

    String cleanText(String t) => t.replaceAll(RegExp(r'\s+'), ' ').trim();

    String title = "";
    String subtitle = "";
    String description = "";
    List<String> extractedTags = [];

    String rawCandidate = responseText
        .replaceAll("```json", "")
        .replaceAll("```", "")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .trim();

    try {
      final startIndex = rawCandidate.indexOf('{');
      final endIndex = rawCandidate.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex >= startIndex) {
        String jsonSub = rawCandidate.substring(startIndex, endIndex + 1);
        jsonSub = jsonSub.replaceAll(RegExp(r',(?=\s*[}\]])'), '');
        final map = jsonDecode(jsonSub) as Map<String, dynamic>;
        title = map['title']?.toString().trim() ?? "";
        subtitle = map['subtitle']?.toString().trim() ?? "";
        description = (map['description'] ?? map['summary'])?.toString().trim() ?? "";
        if (map['tags'] is List) {
          extractedTags = (map['tags'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    if (title.isEmpty) {
      final titleMatch = RegExp(r'"title"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(responseText);
      if (titleMatch != null) {
        title = titleMatch.group(1)?.trim() ?? "";
      }
    }

    if (subtitle.isEmpty) {
      final subtitleMatch = RegExp(r'"subtitle"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(responseText);
      if (subtitleMatch != null) {
        subtitle = subtitleMatch.group(1)?.trim() ?? "";
      }
    }

    if (description.isEmpty) {
      final descMatch = RegExp(r'"description"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(responseText) ??
          RegExp(r'"summary"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(responseText);
      if (descMatch != null) {
        description = descMatch.group(1)?.trim() ?? "";
      }
    }

    if (extractedTags.isEmpty) {
      final tagsMatch = RegExp(r'"tags"\s*:\s*\[(.*?)\]', dotAll: true, caseSensitive: false).firstMatch(responseText);
      if (tagsMatch != null) {
        final tagsStr = tagsMatch.group(1) ?? "";
        extractedTags = tagsStr
            .split(',')
            .map((e) => e.replaceAll(RegExp(r'[^a-zA-Z0-9\s\-]'), '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }

    if (title.isEmpty) {
      if (ocrText.isNotEmpty) {
        final firstLine = ocrText.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        title = firstLine.length > 40 ? '${firstLine.substring(0, 40)}...' : firstLine;
      }
      if (title.isEmpty) {
        final clean = cleanText(responseText);
        if (clean.isEmpty) return null;
        title = clean.length > 50 ? '${clean.substring(0, 50)}...' : clean;
      }
    }

    if (subtitle.isEmpty) {
      if (title.isNotEmpty && ocrText.length > title.length) {
        subtitle = ocrText.substring(title.length).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (subtitle.length > 80) subtitle = '${subtitle.substring(0, 80)}...';
      }
    }

    if (description.isEmpty) {
      if (ocrText.isNotEmpty) {
        description = ocrText;
      } else {
        description = cleanText(responseText);
      }
      if (description.isEmpty) return null;
    }

    if (extractedTags.isEmpty && ocrText.isNotEmpty) {
      extractedTags = ocrText
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(w))
          .take(6)
          .toList();
    }

    final tags = <String>{...extractedTags}.toList();

    final Map<String, dynamic> jsonMap = {
      "title": title,
      "subtitle": subtitle,
      "description": description,
      "summary": description, // For backwards compatibility
      "tags": tags,
    };

    String rawJson = jsonEncode(jsonMap);

    return VisionAnalysisResult(
      title: title,
      subtitle: subtitle,
      description: description,
      tags: tags,
      rawJson: rawJson,
      inferenceSec: stopwatch.elapsedMilliseconds / 1000,
    );
  }

  Future<void> _updateDatabaseMemory(
    String memoryId,
    VisionAnalysisResult result,
    String? thumbnailPath,
  ) async {
    try {
      final db = GlanceDatabase.instance;
      final existingMemory = await db.getMemory(memoryId);

      if (existingMemory == null) return;

      String baseContent = existingMemory.content;
      final visionIdx = baseContent.indexOf('--- [Gemma Vision Intelligence] ---');
      if (visionIdx != -1) {
        baseContent = baseContent.substring(0, visionIdx).trimRight();
      }
      final smolIdx = baseContent.indexOf('--- [SmolVLM Vision Intelligence] ---');
      if (smolIdx != -1) {
        baseContent = baseContent.substring(0, smolIdx).trimRight();
      }

      final contentBuffer = StringBuffer();
      if (baseContent.isNotEmpty) {
        contentBuffer.writeln(baseContent);
      }
      contentBuffer.writeln('\n--- [Gemma Vision Intelligence] ---');
      if (result.title.isNotEmpty) contentBuffer.writeln('Title: ${result.title}');
      if (result.subtitle.isNotEmpty) contentBuffer.writeln('Subtitle: ${result.subtitle}');
      if (result.description.isNotEmpty) contentBuffer.writeln('Description: ${result.description}');
      if (result.tags.isNotEmpty) contentBuffer.writeln('Tags: ${result.tags.join(", ")}');

      String updatedTitle = existingMemory.title;
      final lowerTitle = updatedTitle.toLowerCase().trim();
      if (result.title.isNotEmpty &&
          (updatedTitle.isEmpty ||
              lowerTitle == 'photo' ||
              lowerTitle == 'screenshot' ||
              lowerTitle == 'photo memory' ||
              lowerTitle == 'screenshot memory' ||
              lowerTitle == 'image capture' ||
              lowerTitle == 'captured image' ||
              lowerTitle == 'captured screenshot' ||
              lowerTitle.startsWith('photo_') ||
              lowerTitle.startsWith('screenshot_') ||
              lowerTitle.startsWith('capture from'))) {
        updatedTitle = result.title;
      }

      String? base64Image = existingMemory.imageBase64;
      if (base64Image == null || base64Image.isEmpty) {
        final candidatePath = thumbnailPath ?? existingMemory.imagePath;
        if (candidatePath != null && candidatePath.isNotEmpty) {
          base64Image = await ImageCompressionService.createBase64Thumbnail(candidatePath);
        }
      }

      final updatedMemory = existingMemory.copyWith(
        title: updatedTitle,
        content: contentBuffer.toString().trim(),
        thumbnailPath: thumbnailPath ?? existingMemory.thumbnailPath,
        imageBase64: base64Image,
        summary: result.rawJson,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isProcessed: true,
      );

      await db.insertMemory(updatedMemory);
    } catch (e) {
      debugPrint('[VisionService] Error updating SQLite database for memory $memoryId: $e');
    }
  }

  void _notifyStatus(String statusText, {String? currentMemoryId}) {
    if (!_statusController.isClosed) {
      _statusController.add(
        VisionQueueStatus(
          queueLength: _queue.length,
          isProcessing: _isProcessingQueue,
          currentTaskMemoryId: currentMemoryId,
          currentTaskStatus: statusText,
        ),
      );
    }
  }

  void dispose() {
    _statusController.close();
    _isReady = false;
  }
}
