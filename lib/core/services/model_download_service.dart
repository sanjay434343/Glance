import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class ModelDownloadProgress {
  final String status; // 'started', 'downloading', 'completed', 'cancelled', 'error'
  final int downloadedBytes;
  final int totalBytes;
  final double speedMBps;
  final int etaSeconds;
  final double progress; // 0.0 to 1.0
  final String? error;

  ModelDownloadProgress({
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedMBps,
    required this.etaSeconds,
    required this.progress,
    this.error,
  });

  factory ModelDownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    return ModelDownloadProgress(
      status: map['status'] as String? ?? 'unknown',
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      speedMBps: (map['speedMBps'] as num?)?.toDouble() ?? 0.0,
      etaSeconds: (map['etaSeconds'] as num?)?.toInt() ?? 0,
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      error: map['error'] as String?,
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isDownloading => status == 'downloading' || status == 'started';
  bool get isError => status == 'error';
  bool get isCancelled => status == 'cancelled';
}

/// Service connecting to native Kotlin high-speed background downloader.
class ModelDownloadService {
  static final ModelDownloadService instance = ModelDownloadService._internal();
  ModelDownloadService._internal();

  static const MethodChannel _methodChannel = MethodChannel('com.glance.app/model_downloader');
  static const EventChannel _eventChannel = EventChannel('com.glance.app/model_downloader_progress');

  static const String modelsStorageDir = '/storage/emulated/0/Android/media/com.example.glance/.glance/models';
  static const String defaultModelName = 'gemma-2b-it.task';

  ModelDownloadProgress? _lastProgress;
  ModelDownloadProgress? get currentProgress => _lastProgress;

  StreamController<ModelDownloadProgress>? _streamController;

  Stream<ModelDownloadProgress> get progressStream {
    if (_streamController == null) {
      _streamController = StreamController<ModelDownloadProgress>.broadcast();
      _eventChannel.receiveBroadcastStream().listen(
        (event) {
          final progress = ModelDownloadProgress.fromMap(Map<dynamic, dynamic>.from(event as Map));
          _lastProgress = progress;
          _streamController?.add(progress);
        },
        onError: (e) {
          _streamController?.addError(e);
        },
      );
    }
    return _streamController!.stream;
  }

  /// Ensures target storage directory exists with .nomedia tag.
  static Future<Directory> ensureModelsDirectory() async {
    final dir = Directory(modelsStorageDir);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    try {
      final nomedia = File('${dir.path}/.nomedia');
      if (!await nomedia.exists()) {
        await nomedia.create();
      }
    } catch (_) {}
    return dir;
  }

  /// Extracts the filename from the download URL, defaulting to gemma-3n-E2B-it-int4.task.
  static String extractFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        if (last.endsWith('.task') || last.endsWith('.bin')) {
          return last;
        }
      }
    } catch (_) {}
    return 'gemma-3n-E2B-it-int4.task';
  }

  /// Resolves target destination file path for downloaded .task model.
  static Future<String> getTargetFilePath({String? fileName}) async {
    await ensureModelsDirectory();
    final name = (fileName != null && fileName.trim().isNotEmpty)
        ? (fileName.endsWith('.task') ? fileName.trim() : '${fileName.trim()}.task')
        : 'gemma-3n-E2B-it-int4.task';
    return '$modelsStorageDir/$name';
  }

  /// Starts high-speed resumable model download via native Kotlin engine.
  Future<bool> startDownload(String url, {String? targetFileName}) async {
    try {
      final resolvedName = targetFileName ?? extractFileNameFromUrl(url);
      final destPath = await getTargetFilePath(fileName: resolvedName);
      final bool started = await _methodChannel.invokeMethod('startDownload', {
        'url': url.trim(),
        'destinationPath': destPath,
      }) ?? false;
      return started;
    } catch (e) {
      return false;
    }
  }

  /// Cancels active model download.
  Future<bool> cancelDownload() async {
    try {
      final bool cancelled = await _methodChannel.invokeMethod('cancelDownload') ?? false;
      return cancelled;
    } catch (_) {
      return false;
    }
  }
}
