import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';

import '../database/glance_db.dart';
import '../embedding/embedding_engine.dart';
import '../models/memory_models.dart';
import '../relationships/relationship_engine.dart';
import '../services/image_compression_service.dart';
import '../services/vision_service.dart';

/// Raw input item to ingest into Glance memory pipeline.
class IngestionItem {
  final String type; // screenshot, photo, pdf, url, copied_text, note, app_activity
  final String title;
  final String rawContent;
  final String? sourceApp;
  final String? url;
  final String? filePath;
  final String? imagePath;
  final String? thumbnailPath;
  final String? imageBase64;
  final int? capturedAt;

  IngestionItem({
    required this.type,
    required this.title,
    required this.rawContent,
    this.sourceApp,
    this.url,
    this.filePath,
    this.imagePath,
    this.thumbnailPath,
    this.imageBase64,
    this.capturedAt,
  });
}

/// 6-Step Content Processing & Indexing Pipeline for Glance.
class ContentPipeline {
  final GlanceDatabase db;
  final IEmbeddingModel embeddingEngine;
  final _uuid = const Uuid();

  ContentPipeline({
    required this.db,
    required this.embeddingEngine,
  });

  /// Ingests a new item through the complete 6-step memory indexing pipeline.
  Future<Memory> processIngestion(IngestionItem item) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final memoryId = _uuid.v4();

    // Step 1: Capture & Step 2: Extract OCR / Document text
    String extractedText = item.rawContent;
    String ocrText = "";
    if (item.imagePath != null && item.imagePath!.isNotEmpty) {
      ocrText = await _extractOCRText(item.imagePath!);
      if (ocrText.isNotEmpty) {
        extractedText += '\n$ocrText';
      }
    }

    // Step 3: Normalize & Clean
    final normalizedText = _normalizeText(extractedText);

    // Derive readable title from OCR text if item.title is generic filename
    String memoryTitle = item.title;
    if (ocrText.isNotEmpty &&
        (memoryTitle.toLowerCase().contains('screenshot') ||
            memoryTitle.toLowerCase().contains('media_') ||
            memoryTitle.toLowerCase().contains('img_'))) {
      final firstLine = ocrText.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
      if (firstLine.length > 3) {
        memoryTitle = firstLine.length > 40 ? '${firstLine.substring(0, 40)}...' : firstLine;
      }
    }

    // Compute SHA-256 Hash Key for item using name, size, type, file metadata, and content
    final shaHash = Memory.computeShaHash(
      title: memoryTitle,
      type: item.type,
      content: normalizedText,
      filePath: item.filePath ?? item.imagePath,
      sourceApp: item.sourceApp,
    );

    // If an item with identical SHA hash key already exists, skip creating duplicate
    final existingMemory = await db.getMemoryByShaHash(shaHash);
    if (existingMemory != null) {
      return existingMemory;
    }

    // Generate Base64 copy for database storage if item has an image/thumbnail
    String? base64Image = item.imageBase64;
    if ((base64Image == null || base64Image.isEmpty) &&
        (item.thumbnailPath != null || item.imagePath != null || item.filePath != null)) {
      final imgPath = item.thumbnailPath ?? item.imagePath ?? item.filePath;
      if (imgPath != null && imgPath.isNotEmpty) {
        base64Image = await ImageCompressionService.createBase64Thumbnail(imgPath);
      }
    }

    // Build Primary Memory Record
    final memory = Memory(
      id: memoryId,
      type: item.type,
      title: memoryTitle,
      content: normalizedText,
      source: item.sourceApp,
      sourceApp: item.sourceApp,
      url: item.url,
      filePath: item.filePath,
      thumbnailPath: item.thumbnailPath ?? item.imagePath,
      imageBase64: base64Image,
      shaHash: shaHash,
      capturedAt: item.capturedAt ?? now,
      createdAt: now,
      updatedAt: now,
    );

    // Save Memory Metadata to SQLite
    await db.insertMemory(memory);

    // Step 4: Chunking (Target: 250 tokens, Max: 350, Overlap: 40 tokens)
    final chunks = _chunkContent(memoryId, normalizedText, now);

    // Step 5 & 6: Generate Embeddings and Store in SQLite / FTS5 / Vector Index
    for (final chunk in chunks) {
      await db.insertChunk(chunk);
      final embedding = await embeddingEngine.generateEmbedding(chunk.content);
      await db.insertEmbedding(chunk.id, embedding);
    }

    // Auto-generate relationship graph edges for recent context
    final allMems = (await db.getAllMemories()).take(50).toList();
    final rels = RelationshipEngine.computeRelationships(memory, allMems);
    for (final rel in rels) {
      await db.insertRelationship(rel);
    }

    // Auto-enqueue image into VisionService if imagePath is present
    if (item.imagePath != null && item.imagePath!.isNotEmpty) {
      VisionService.instance.enqueue(
        memoryId: memoryId,
        imagePath: item.imagePath!,
      );
    }

    return memory;
  }

  /// Extracts text from screenshot / photo file via OCR ML Kit interface.
  Future<String> _extractOCRText(String imagePath) async {
    try {
      if (!imagePath.startsWith('content://') && !await File(imagePath).exists()) {
        return "";
      }
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      return recognizedText.text.trim();
    } catch (e) {
      debugPrint('[ContentPipeline] Error extracting OCR text: $e');
      return "";
    }
  }

  /// Cleans whitespace and normalizes content.
  String _normalizeText(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Splits content into 250-token chunks with 40-token overlap.
  List<MemoryChunk> _chunkContent(String memoryId, String content, int createdAt) {
    final words = content.split(' ');
    const int targetWords = 200; // ~250 tokens
    const int overlapWords = 30; // ~40 tokens

    final chunks = <MemoryChunk>[];
    int chunkIndex = 0;

    for (int i = 0; i < words.length; i += (targetWords - overlapWords)) {
      final end = (i + targetWords < words.length) ? i + targetWords : words.length;
      final chunkWords = words.sublist(i, end);
      final chunkText = chunkWords.join(' ');

      if (chunkText.trim().isNotEmpty) {
        chunks.add(MemoryChunk(
          id: _uuid.v4(),
          memoryId: memoryId,
          chunkIndex: chunkIndex++,
          content: chunkText,
          tokenCount: (chunkWords.length * 1.25).ceil(),
          createdAt: createdAt,
        ));
      }

      if (end == words.length) break;
    }

    if (chunks.isEmpty) {
      chunks.add(MemoryChunk(
        id: _uuid.v4(),
        memoryId: memoryId,
        chunkIndex: 0,
        content: content,
        tokenCount: (words.length * 1.25).ceil(),
        createdAt: createdAt,
      ));
    }

    return chunks;
  }
}
