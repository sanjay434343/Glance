import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:archive/archive.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

import '../database/glance_db.dart';
import '../models/memory_models.dart';
import 'smart_entity_service.dart';
import 'vision_service.dart';
import 'gemma_mediapipe_service.dart';

class DocumentProcessingStatus {
  final bool isProcessing;
  final String? currentTitle;
  final int remainingCount;

  const DocumentProcessingStatus({
    required this.isProcessing,
    this.currentTitle,
    this.remainingCount = 0,
  });
}

class DocumentExtractionService {
  static final DocumentExtractionService instance = DocumentExtractionService._internal();
  DocumentExtractionService._internal();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  final _statusController = StreamController<DocumentProcessingStatus>.broadcast();
  Stream<DocumentProcessingStatus> get statusStream => _statusController.stream;

  DocumentProcessingStatus _currentStatus = const DocumentProcessingStatus(isProcessing: false);
  DocumentProcessingStatus get currentStatus => _currentStatus;

  void _updateStatus(bool isProcessing, {String? title, int remaining = 0}) {
    _isProcessing = isProcessing;
    _currentStatus = DocumentProcessingStatus(
      isProcessing: isProcessing,
      currentTitle: title,
      remainingCount: remaining,
    );
    if (!_statusController.isClosed) {
      _statusController.add(_currentStatus);
    }
  }

  final Set<String> _processedDocIds = {};

  /// Process all unprocessed documents in the background.
  /// Yields (aborts) immediately if VisionService is processing or has images in the queue.
  Future<void> processUnprocessedDocuments() async {
    if (_isProcessing) return;

    // Never process docs and images/Gemma simultaneously: yield immediately
    if (GemmaMediaPipeService.instance.isGenerating ||
        VisionService.instance.isProcessing ||
        VisionService.instance.queueLength > 0) {
      debugPrint('[DocumentExtractionService] Gemma or Vision AI active. Yielding document processing to keep system responsive.');
      return;
    }

    _updateStatus(true);

    try {
      final db = GlanceDatabase.instance;
      final memories = await db.getAllMemories();
      final unprocessed = memories.where((mem) {
        if (mem.isProcessed || _processedDocIds.contains(mem.id)) return false;
        final type = mem.type.toLowerCase();
        final path = (mem.filePath ?? mem.title).toLowerCase();
        return type == 'pdf' ||
            type == 'document' ||
            type == 'doc' ||
            type == 'docx' ||
            type == 'txt' ||
            type == 'md' ||
            type == 'csv' ||
            type == 'epub' ||
            type == 'xlsx' ||
            type == 'pptx' ||
            path.endsWith('.pdf') ||
            path.endsWith('.docx') ||
            path.endsWith('.txt') ||
            path.endsWith('.md') ||
            path.endsWith('.csv') ||
            path.endsWith('.epub') ||
            path.endsWith('.xlsx') ||
            path.endsWith('.pptx');
      }).toList();

      int remaining = unprocessed.length;
      for (final mem in unprocessed) {
        // Dynamic Pause: If user searches with Gemma or Vision AI starts, yield and sleep until idle
        while (GemmaMediaPipeService.instance.isGenerating ||
            VisionService.instance.isProcessing ||
            VisionService.instance.queueLength > 0) {
          debugPrint('[DocumentExtractionService] Gemma / Vision AI active. Pausing document processing...');
          _updateStatus(false, title: 'Paused (AI active)', remaining: remaining);
          await Future.delayed(const Duration(milliseconds: 1200));
        }

        _updateStatus(true, title: mem.title, remaining: remaining);
        
        // Lightweight pacing delay before processing each document so CPU/GC and UI thread remain 60fps
        await Future.delayed(const Duration(milliseconds: 800));

        await _processSingleDocument(mem, db);
        _processedDocIds.add(mem.id);
        remaining--;

        // Pacing delay after processing each document to allow UI animations and user gestures to breathe
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (e) {
      debugPrint('[DocumentExtractionService] Error scanning docs: $e');
    } finally {
      _updateStatus(false);
    }
  }

  Future<void> _processSingleDocument(Memory mem, GlanceDatabase db) async {
    final path = mem.filePath ?? '/storage/emulated/0/Documents/${mem.title}';
    final ext = mem.title.contains('.') ? mem.title.split('.').last.toLowerCase() : 'pdf';

    if (!File(path).existsSync()) return;

    try {
      debugPrint('[DocumentExtractionService] Extracting text for ${mem.title}...');
      final bytes = await File(path).readAsBytes();
      String extractedText = '';
      String? savedThumbnailPath;

      if (ext == 'pdf') {
        final document = PdfDocument(inputBytes: bytes);
        final textExtractor = PdfTextExtractor(document);
        extractedText = textExtractor.extractText();
        document.dispose();

        // Check if a persistent thumbnail already exists
        final thumbsDir = Directory('/data/user/0/com.example.glance/app_flutter/doc_thumbs');
        final existingThumb = File('${thumbsDir.path}/doc_${mem.id}.png');
        if (existingThumb.existsSync()) {
          savedThumbnailPath = existingThumb.path;
        }

        // Only invoke native PDF renderer if thumbnail is missing OR if extractedText is empty and needs OCR
        if (savedThumbnailPath == null || extractedText.trim().isEmpty) {
          try {
            const channel = MethodChannel('com.glance.app/native_bridge');
            final List<dynamic>? imagePaths = await channel.invokeMethod('renderPdfToImages', {'pdfPath': path});

          if (imagePaths != null && imagePaths.isNotEmpty) {
            // Copy the first page to a persistent doc_thumbs directory
            final firstPage = imagePaths.first as String;
            if (File(firstPage).existsSync()) {
              final thumbsDir = Directory('/data/user/0/com.example.glance/app_flutter/doc_thumbs');
              if (!thumbsDir.existsSync()) {
                thumbsDir.createSync(recursive: true);
              }
              final persistentThumb = File('${thumbsDir.path}/doc_${mem.id}.png');
              File(firstPage).copySync(persistentThumb.path);
              savedThumbnailPath = persistentThumb.path;
            }

            // If text was empty, perform OCR (capped at first 3 pages with pacing delays)
            if (extractedText.trim().isEmpty) {
              final textRecognizer = TextRecognizer();
              final ocrSb = StringBuffer();
              for (final dynamic imgPath in imagePaths.take(3)) {
                if (VisionService.instance.isProcessing || VisionService.instance.queueLength > 0) {
                   await textRecognizer.close();
                   for (final p in imagePaths) {
                     try { File(p as String).deleteSync(); } catch (_) {}
                   }
                   return;
                }
                final inputImage = InputImage.fromFilePath(imgPath as String);
                final recognizedText = await textRecognizer.processImage(inputImage);
                ocrSb.writeln(recognizedText.text);

                try {
                  File(imgPath).deleteSync();
                } catch (_) {}

                // Yield to the Flutter UI thread between pages
                await Future.delayed(const Duration(milliseconds: 150));
              }
              await textRecognizer.close();
              extractedText = ocrSb.toString();
              } else {
                // Clean up temporary rendered images
                for (final dynamic imgPath in imagePaths) {
                  try {
                    File(imgPath as String).deleteSync();
                  } catch (_) {}
                }
              }
            }
          } catch (pdfErr) {
            debugPrint('[DocumentExtractionService] PDF render error: $pdfErr');
          }
        }
      } else if (ext == 'txt' || ext == 'md' || ext == 'csv') {
        try {
          extractedText = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          extractedText = String.fromCharCodes(bytes);
        }
      } else if (ext == 'docx' || ext == 'pptx' || ext == 'xlsx' || ext == 'epub') {
        final archive = ZipDecoder().decodeBytes(bytes);
        final sb = StringBuffer();

        for (final file in archive) {
          final fileName = file.name;
          if ((ext == 'docx' && fileName == 'word/document.xml') ||
              (ext == 'pptx' && fileName.startsWith('ppt/slides/slide') && fileName.endsWith('.xml')) ||
              (ext == 'xlsx' && fileName == 'xl/sharedStrings.xml') ||
              (ext == 'epub' && (fileName.endsWith('.html') || fileName.endsWith('.xhtml')))) {

            final content = utf8.decode(file.content as List<int>, allowMalformed: true);
            final text = content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
            sb.writeln(text.trim());
          }
        }
        extractedText = sb.toString();
      }

      final finalText = extractedText.trim().isNotEmpty ? extractedText.trim() : "No readable text found in this document.";
      
      // Extract smart entities (OTP, Phone, Email, URL, Address, DateTime)
      String? updatedSummary = mem.summary;
      if (finalText.length > 5 && finalText != "No readable text found in this document.") {
        try {
          updatedSummary = await SmartEntityService.instance.extractAndBuildSummary(
            finalText,
            existingSummary: mem.summary,
          );
        } catch (_) {}
      }

      // Update memory with extracted text, smart entities, and mark as processed
      final updatedMem = mem.copyWith(
        content: finalText,
        thumbnailPath: savedThumbnailPath ?? mem.thumbnailPath,
        summary: updatedSummary ?? mem.summary,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isProcessed: true,
      );

      await db.insertMemory(updatedMem);
      debugPrint('[DocumentExtractionService] Finished processing ${mem.title} with smart entities');

    } catch (e) {
      debugPrint('[DocumentExtractionService] Failed on ${mem.title}: $e');
      // Mark as processed anyway so we don't infinitely retry failed docs
      final updatedMem = mem.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isProcessed: true,
      );
      await db.insertMemory(updatedMem);
    }
  }
}
