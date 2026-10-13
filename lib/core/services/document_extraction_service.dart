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
import 'vision_service.dart';

class DocumentExtractionService {
  static final DocumentExtractionService instance = DocumentExtractionService._internal();
  DocumentExtractionService._internal();

  bool _isProcessing = false;

  /// Process all unprocessed documents in the background.
  /// Yields (aborts) immediately if VisionService queue has new images.
  Future<void> processUnprocessedDocuments() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final db = GlanceDatabase.instance;
      final memories = await db.getAllMemories();

      for (final mem in memories) {
        // Yield to VisionService if an image arrives in the queue
        if (VisionService.instance.queueLength > 0) {
          debugPrint('[DocumentExtractionService] Yielding to VisionService queue...');
          break;
        }

        final type = mem.type.toLowerCase();
        if (!mem.isProcessed && (type == 'pdf' || type == 'document')) {
          await _processSingleDocument(mem, db);
        }
      }
    } catch (e) {
      debugPrint('[DocumentExtractionService] Error scanning docs: $e');
    } finally {
      _isProcessing = false;
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

      if (ext == 'pdf') {
        final document = PdfDocument(inputBytes: bytes);
        final textExtractor = PdfTextExtractor(document);
        extractedText = textExtractor.extractText();
        document.dispose();

        if (extractedText.trim().isEmpty) {
          const channel = MethodChannel('com.glance.app/native_bridge');
          final List<dynamic>? imagePaths = await channel.invokeMethod('renderPdfToImages', {'pdfPath': path});

          if (imagePaths != null && imagePaths.isNotEmpty) {
            final textRecognizer = TextRecognizer();
            final ocrSb = StringBuffer();
            for (final dynamic imgPath in imagePaths) {
              if (VisionService.instance.queueLength > 0) {
                 // Clean up immediately if yielding
                 textRecognizer.close();
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
            }
            textRecognizer.close();
            extractedText = ocrSb.toString();
          }
        }
      } else if (ext == 'docx' || ext == 'pptx' || ext == 'xlsx') {
        final archive = ZipDecoder().decodeBytes(bytes);
        final sb = StringBuffer();

        for (final file in archive) {
          final fileName = file.name;
          if ((ext == 'docx' && fileName == 'word/document.xml') ||
              (ext == 'pptx' && fileName.startsWith('ppt/slides/slide') && fileName.endsWith('.xml')) ||
              (ext == 'xlsx' && fileName == 'xl/sharedStrings.xml')) {

            final content = utf8.decode(file.content as List<int>);
            final text = content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
            sb.writeln(text.trim());
          }
        }
        extractedText = sb.toString();
      }

      final finalText = extractedText.trim().isNotEmpty ? extractedText.trim() : "No readable text found in this document.";
      
      List<String> tags = [];
      if (finalText.length > 5 && finalText != "No readable text found in this document.") {
        try {
          final entityExtractor = EntityExtractor(language: EntityExtractorLanguage.english);
          final foundEntities = await entityExtractor.annotateText(finalText);
          entityExtractor.close();
          for (final annotation in foundEntities) {
            tags.add('${annotation.entities.first.type.name.toUpperCase()}: ${annotation.text}');
          }
        } catch (_) {}
      }

      // Update memory with extracted text, tags, and mark as processed
      final updatedMem = mem.copyWith(
        content: finalText,
        summary: tags.isNotEmpty ? jsonEncode(tags) : mem.summary,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isProcessed: true,
      );

      await db.insertMemory(updatedMem);
      debugPrint('[DocumentExtractionService] Finished processing ${mem.title}');

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
