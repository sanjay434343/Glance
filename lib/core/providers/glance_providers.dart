import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/glance_db.dart';
import '../embedding/embedding_engine.dart';
import '../llm/llamadart_service.dart';
import '../models/memory_models.dart';
import '../pipeline/content_pipeline.dart';
import '../rag/hybrid_retriever.dart';
import '../services/device_memory_scanner.dart';
import '../services/gemma_mediapipe_service.dart';
import '../services/global_capture_service.dart';
import '../services/vision_service.dart';

/// Vision Service Singleton Provider
final visionServiceProvider = Provider<VisionService>((ref) {
  return VisionService.instance;
});

/// Gemma MediaPipe Service Singleton Provider
final gemmaServiceProvider = Provider<GemmaMediaPipeService>((ref) {
  return GemmaMediaPipeService.instance;
});

/// Gemma Hardware Info FutureProvider
final gemmaHardwareInfoProvider = FutureProvider<GemmaHardwareInfo>((ref) async {
  return await GemmaMediaPipeService.instance.fetchHardwareInfo();
});

/// Database Singleton Provider
final dbProvider = Provider<GlanceDatabase>((ref) {
  return GlanceDatabase.instance;
});

/// Custom Collections StreamProvider (Updates UI live whenever collections change)
final customCollectionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = ref.watch(dbProvider);
  yield await db.getCollections();
  await for (final _ in db.changeStream) {
    yield await db.getCollections();
  }
});

/// ONNX Embedding Engine Provider
final embeddingEngineProvider = Provider<IEmbeddingModel>((ref) {
  return OnnxMiniLMEmbeddingEngine();
});

/// GPU / Engine Configuration State Notifier
class GpuConfigNotifier extends StateNotifier<LlamaGpuConfig> {
  GpuConfigNotifier() : super(const LlamaGpuConfig());

  void setGpuLayers(int layers) {
    state = state.copyWith(gpuLayers: layers);
  }

  void setTemperature(double temp) {
    state = state.copyWith(temperature: temp);
  }

  void setContextSize(int size) {
    state = state.copyWith(contextSize: size);
  }
}

final gpuConfigProvider = StateNotifierProvider<GpuConfigNotifier, LlamaGpuConfig>((ref) {
  return GpuConfigNotifier();
});

/// Llamadart / Gemma LLM Service Provider
final llamaServiceProvider = Provider<LlamaDartService>((ref) {
  final config = ref.watch(gpuConfigProvider);
  return LlamaDartService(config: config);
});

/// Hybrid RAG Retriever Provider
final hybridRetrieverProvider = Provider<HybridRetriever>((ref) {
  final db = ref.watch(dbProvider);
  final embedding = ref.watch(embeddingEngineProvider);
  return HybridRetriever(db: db, embeddingEngine: embedding);
});

/// 6-Step Content Pipeline Provider
final contentPipelineProvider = Provider<ContentPipeline>((ref) {
  final db = ref.watch(dbProvider);
  final embedding = ref.watch(embeddingEngineProvider);
  return ContentPipeline(db: db, embeddingEngine: embedding);
});

/// Device Memory Scanner Provider
final deviceMemoryScannerProvider = Provider<DeviceMemoryScanner>((ref) {
  final pipeline = ref.watch(contentPipelineProvider);
  final db = ref.watch(dbProvider);
  return DeviceMemoryScanner(pipeline: pipeline, db: db);
});

/// All Captured Memories StreamProvider — debounced to prevent rapid UI rebuilds.
/// Initial data loads immediately; subsequent DB changes are batched with a 3-second
/// debounce so the home list doesn't flicker on every background capture write.
final allMemoriesProvider = StreamProvider<List<Memory>>((ref) {
  final db = ref.watch(dbProvider);
  final controller = StreamController<List<Memory>>();
  Timer? debounce;

  // Load initial data immediately
  db.getAllMemories().then((memories) {
    if (!controller.isClosed) controller.add(memories);
  });

  // Debounce subsequent DB change events (3 seconds of quiet before re-query)
  final sub = db.changeStream.listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 3), () {
      db.getAllMemories().then((memories) {
        if (!controller.isClosed) controller.add(memories);
      });
    });
  });

  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Global Capture Service Provider (Orchestrates real-time background capture & Vision AI)
final globalCaptureServiceProvider = Provider<GlobalCaptureService>((ref) {
  final scanner = ref.watch(deviceMemoryScannerProvider);
  final service = GlobalCaptureService.instance;
  service.initialize(scanner);
  return service;
});
