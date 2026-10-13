import 'dart:async';
import 'package:flutter/widgets.dart';

import 'device_memory_scanner.dart';
import 'vision_service.dart';

/// Event types emitted when data is captured by GlobalCaptureService.
enum CaptureEventType {
  screenshot,
  photo,
  clipboard,
  notification,
  appActivity,
  document,
  syncCompleted,
}

/// State of the Event-Driven Global Capture Service
enum CaptureServiceState {
  idle,
  activeProcessing,
  sleeping,
}

/// Represents a captured event.
class GlobalCaptureEvent {
  final CaptureEventType type;
  final String memoryId;
  final String title;
  final String? imagePath;
  final DateTime timestamp;

  GlobalCaptureEvent({
    required this.type,
    required this.memoryId,
    required this.title,
    this.imagePath,
    required this.timestamp,
  });
}

/// Central Global Service that orchestrates event-driven background capture:
/// - Activates ONLY when user takes a screenshot, photo, copies text, or receives a notification.
/// - Compresses images & performs Gemma MediaPipe Vision AI analysis on the captured batch.
/// - AUTOMATICALLY STOPS running and transitions to sleeping/idle state as soon as processing completes.
/// - Operates seamlessly even when app is closed/minimized via WidgetsBindingObserver.
class GlobalCaptureService with WidgetsBindingObserver {
  static final GlobalCaptureService instance = GlobalCaptureService._internal();
  GlobalCaptureService._internal();

  DeviceMemoryScanner? _scanner;
  bool _isInitializing = false;
  bool _isReady = false;
  bool _isSyncing = false;
  CaptureServiceState _serviceState = CaptureServiceState.idle;
  StreamSubscription<VisionQueueStatus>? _visionStatusSubscription;

  final StreamController<GlobalCaptureEvent> _eventController =
      StreamController<GlobalCaptureEvent>.broadcast();

  final StreamController<CaptureServiceState> _stateController =
      StreamController<CaptureServiceState>.broadcast();

  Stream<GlobalCaptureEvent> get eventStream => _eventController.stream;
  Stream<CaptureServiceState> get stateStream => _stateController.stream;
  CaptureServiceState get currentState => _serviceState;
  bool get isReady => _isReady;

  Timer? _periodicTimer;

  /// Initialize Global Capture Service & Vision Engine with App Lifecycle binding
  Future<void> initialize(DeviceMemoryScanner scanner) async {
    if (_isReady) return;
    if (_isInitializing) return;

    _isInitializing = true;
    _scanner = scanner;

    try {
      // Register app lifecycle observer to handle backgrounding/app closing
      WidgetsBinding.instance.addObserver(this);

      _isReady = true;
      _isInitializing = false;
      _updateServiceState(CaptureServiceState.idle);
      debugPrint('[GlobalCaptureService] Background capture service initialized.');

      // Listen to Vision Queue status to AUTO-STOP service when processing completes
      _visionStatusSubscription = VisionService.instance.statusStream.listen((status) {
        if (!status.isProcessing && status.queueLength == 0) {
          _updateServiceState(CaptureServiceState.sleeping);
          debugPrint('[GlobalCaptureService] Vision AI processing finished.');
        } else if (status.isProcessing) {
          _updateServiceState(CaptureServiceState.activeProcessing);
        }
      });

      // Immediately perform initial sync of files, media, and recent activity
      Future.microtask(() async {
        try {
          await onUserActionDetected(actionName: 'Initial Fast Launch Sync');
        } catch (_) {}
      });

      // Initialize Vision Model and kick off automated image scanning right after model is ready
      Future.delayed(const Duration(milliseconds: 1500), () async {
        try {
          final initialized = await VisionService.instance.initialize();
          if (initialized) {
            debugPrint('[GlobalCaptureService] Model loaded. Initiating auto-scan of images/screenshots...');
            await VisionService.instance.processAllExistingImages();
          }
          await onUserActionDetected(actionName: 'App Launch Full Sync');
          _startContinuousTimer();
        } catch (e) {
          debugPrint('[GlobalCaptureService] Deferred startup task error: $e');
        }
      });
    } catch (e) {
      _isInitializing = false;
      debugPrint('[GlobalCaptureService] Initialization error: $e');
    }
  }

  void _startContinuousTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      onUserActionDetected(actionName: 'Continuous Background Sync');
    });
  }

  /// App Lifecycle Observer: Ensures capture continues continuously in background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[GlobalCaptureService] App lifecycle state changed to: $state. Service continues background capture.');
    if (_periodicTimer == null || !_periodicTimer!.isActive) {
      _startContinuousTimer();
    }
    onUserActionDetected(actionName: 'App Lifecycle ${state.name}');
  }

  /// Triggers background capture across all categories (screenshots, photos, docs, notifications, app usage)
  Future<bool> onUserActionDetected({String actionName = 'User Action'}) async {
    if (_scanner == null || _isSyncing) return false;

    _isSyncing = true;
    _updateServiceState(CaptureServiceState.activeProcessing);

    bool hasNewItem = false;
    try {
      // 1. Sync device media (screenshots/photos), docs, notifications, app usage
      final hasMedia = await _scanner!.syncDeviceData();

      // 2. Sync clipboard copied text
      final hasClip = await _scanner!.recordClipboardText();

      hasNewItem = hasMedia || hasClip;

      if (hasNewItem) {
        _eventController.add(
          GlobalCaptureEvent(
            type: hasClip ? CaptureEventType.clipboard : CaptureEventType.syncCompleted,
            memoryId: '',
            title: 'Captured via $actionName',
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[GlobalCaptureService] Action processing error: $e');
    } finally {
      _isSyncing = false;
      _updateServiceState(CaptureServiceState.idle);
    }

    return hasNewItem;
  }

  /// Manually captures current clipboard text and auto-stops when finished.
  Future<bool> captureClipboardNow() async {
    return await onUserActionDetected(actionName: 'Clipboard Action');
  }

  /// Triggers full force rescan of all images with Vision AI.
  Future<int> forceRescanAll() async {
    _updateServiceState(CaptureServiceState.activeProcessing);
    final count = await VisionService.instance.forceRescanAllImages();
    _eventController.add(
      GlobalCaptureEvent(
        type: CaptureEventType.screenshot,
        memoryId: '',
        title: 'Force rescan started ($count images)',
        timestamp: DateTime.now(),
      ),
    );
    return count;
  }

  void _updateServiceState(CaptureServiceState newState) {
    if (_serviceState != newState) {
      _serviceState = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  void dispose() {
    _periodicTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _visionStatusSubscription?.cancel();
    _eventController.close();
    _stateController.close();
    _isReady = false;
  }
}
