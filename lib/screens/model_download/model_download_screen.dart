import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/gemma_mediapipe_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/theme/theme.dart';

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  static const String gemma3nUrl =
      'https://huggingface.co/arpitx35/gemma-3n-E2B-it-int4/resolve/main/gemma-3n-E2B-it-int4.task';
  static const String modelFileName = 'gemma-3n-E2B-it-int4.task';

  StreamSubscription<ModelDownloadProgress>? _progressSub;
  ModelDownloadProgress? _currentProgress;
  bool _isDownloading = false;
  bool _isAutoLoading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _currentProgress = ModelDownloadService.instance.currentProgress;
    _isDownloading = _currentProgress?.isDownloading ?? false;
    _listenToDownloadStream();
  }

  void _listenToDownloadStream() {
    _progressSub = ModelDownloadService.instance.progressStream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _currentProgress = progress;
          _isDownloading = progress.isDownloading;
        });

        if (progress.isCompleted) {
          _onDownloadCompleted();
        } else if (progress.isError) {
          setState(() {
            _statusMessage = 'Error: ${progress.error ?? "Download failed"}';
          });
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Download stream error: $e';
        });
      },
    );
  }

  Future<void> _onDownloadCompleted() async {
    setState(() {
      _isAutoLoading = true;
      _statusMessage = 'Verifying model file and initializing on GPU / Vulkan...';
    });

    final targetPath = await ModelDownloadService.getTargetFilePath(fileName: modelFileName);
    final success = await GemmaMediaPipeService.instance.initModel(
      customModelPath: targetPath,
      preferredBackend: 'AUTO',
    );

    if (!mounted) return;
    setState(() {
      _isAutoLoading = false;
      _statusMessage = success
          ? 'Model loaded & ready for local AI memory reasoning!'
          : 'Model saved to media store. Ready to load from Settings.';
    });
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Connecting to HuggingFace CDN & allocating stream...';
      _currentProgress = null;
    });

    final started = await ModelDownloadService.instance.startDownload(
      gemma3nUrl,
      targetFileName: modelFileName,
    );
    if (!started && mounted) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Failed to start download process.';
      });
    }
  }

  Future<void> _cancelDownload() async {
    await ModelDownloadService.instance.cancelDownload();
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download cancelled.';
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return '--';
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    return '${mins}m ${remSecs}s';
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppTheme.getScaffoldBackground(isDark);
    final cardBorder = AppTheme.getCardBorder(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subColor = AppTheme.getSecondaryText(isDark);
    const accentColor = Color(0xFF3478F6);

    final progress = _currentProgress?.progress ?? 0.0;
    final downloadedBytes = _currentProgress?.downloadedBytes ?? 0;
    final totalBytes = _currentProgress?.totalBytes ?? 0;
    final speedMBps = _currentProgress?.speedMBps ?? 0.0;
    final etaSeconds = _currentProgress?.etaSeconds ?? 0;
    final isCompleted = _currentProgress?.isCompleted ?? false;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: 24,
            color: textColor,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Model Download',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),

            // ── TOP MODEL HEADER ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Text(
                    'Gemma 3N E2B IT',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Google On-Device Multimodal AI • ~2.4 GB',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),

            // ── MIDDLE: BIG CIRCULAR PROGRESS INDICATOR ──
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 230,
                  height: 230,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background Track
                      SizedBox(
                        width: 230,
                        height: 230,
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 14,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      // Active Progress Arc
                      SizedBox(
                        width: 230,
                        height: 230,
                        child: CircularProgressIndicator(
                          value: isCompleted
                              ? 1.0
                              : (_isDownloading
                                  ? (totalBytes > 0
                                      ? progress.clamp(0.0, 1.0)
                                      : null)
                                  : (downloadedBytes > 0 && totalBytes > 0
                                      ? progress.clamp(0.0, 1.0)
                                      : 0.0)),
                          strokeWidth: 14,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCompleted
                                ? const Color(0xFF10B981)
                                : (_isAutoLoading
                                    ? const Color(0xFF10B981)
                                    : accentColor),
                          ),
                        ),
                      ),
                      // Center Content: Downloaded MB and Total MB
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isAutoLoading) ...[
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Loading to RAM...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Initializing weights',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subColor,
                                ),
                              ),
                            ] else ...[
                              Text(
                                isCompleted
                                    ? '100%'
                                    : (totalBytes > 0
                                        ? '${(progress * 100).toInt()}%'
                                        : (_isDownloading ? '...' : '0%')),
                                style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                  letterSpacing: -1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                totalBytes > 0
                                    ? '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}'
                                    : (_isDownloading
                                        ? '${_formatBytes(downloadedBytes)} / 2.4 GB'
                                        : '0 MB / 2.4 GB'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: subColor,
                                ),
                              ),
                              if (_isDownloading && speedMBps > 0) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${speedMBps.toStringAsFixed(1)} MB/s',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                              if (_isDownloading && etaSeconds > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatEta(etaSeconds)} left',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: (isCompleted || _isAutoLoading)
                        ? const Color(0xFF10B981)
                        : subColor,
                  ),
                ),
              ),

            // ── BOTTOM: CANCEL AND DOWNLOAD BUTTONS ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(
                children: [
                  // Cancel Button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isDownloading ? _cancelDownload : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: Colors.red,
                        disabledForegroundColor:
                            subColor.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: _isDownloading
                              ? Colors.red.withValues(alpha: 0.6)
                              : cardBorder.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Download Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isDownloading || _isAutoLoading)
                          ? null
                          : _startDownload,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: isCompleted
                            ? const Color(0xFF10B981)
                            : accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isDark
                            ? Colors.white12
                            : Colors.black12,
                        disabledForegroundColor: subColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: Text(
                        _isDownloading
                            ? 'Downloading...'
                            : (_isAutoLoading
                                ? 'Loading RAM...'
                                : (isCompleted
                                    ? 'Re-Download'
                                    : 'Download')),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
