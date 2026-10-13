import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageCompressionService {
  /// Compresses and resizes an image to 512x512 with 65% JPEG quality.
  /// It runs on a background isolate to prevent UI jank.
  /// Returns the path to the compressed thumbnail file, or null if it fails.
  static Future<String?> compressForVisionAI(String originalPath) async {
    try {
      final originalFile = File(originalPath);
      if (!await originalFile.exists()) return null;

      Directory thumbDir;
      try {
        final hiddenDir = Directory('/storage/emulated/0/Android/media/com.example.glance/.glance/thumbnails');
        if (!await hiddenDir.exists()) {
          await hiddenDir.create(recursive: true);
        }
        thumbDir = hiddenDir;
      } catch (_) {
        final docDir = await getApplicationDocumentsDirectory();
        thumbDir = Directory(path.join(docDir.path, 'thumbnails'));
        if (!await thumbDir.exists()) {
          await thumbDir.create(recursive: true);
        }
      }

      final fileName = '${path.basenameWithoutExtension(originalPath)}_vision_thumb.jpg';
      final thumbPath = path.join(thumbDir.path, fileName);
      
      // Return immediately if this specific image was already compressed
      if (File(thumbPath).existsSync()) {
        return thumbPath;
      }

      // Offload heavy image processing to a background isolate
      final success = await compute(_compressImageIsolate, {
        'input': originalPath,
        'output': thumbPath,
      });
      
      if (success) {
        return thumbPath;
      }
      return null;
    } catch (e) {
      debugPrint('[ImageCompressionService] Error compressing image: $e');
      return null;
    }
  }

  /// Compresses an image file down to a lightweight 256x256 JPEG and encodes it as Base64
  /// to store directly as a permanent copy in the SQLite database (glance.db).
  /// Runs on a background isolate to prevent frame drops.
  static Future<String?> createBase64Thumbnail(String originalPath, {int maxSize = 256, int quality = 65}) async {
    try {
      if (originalPath.isEmpty) return null;
      final file = File(originalPath);
      if (!await file.exists()) return null;

      final base64String = await compute(_fileToBase64Isolate, {
        'path': originalPath,
        'maxSize': maxSize,
        'quality': quality,
      });
      return base64String;
    } catch (e) {
      debugPrint('[ImageCompressionService] Error creating base64 thumbnail: $e');
      return null;
    }
  }

  /// Converts raw image bytes into a resized JPEG Base64 string for database storage.
  static Future<String?> bytesToBase64Thumbnail(Uint8List bytes, {int maxSize = 256, int quality = 65}) async {
    try {
      if (bytes.isEmpty) return null;
      final base64String = await compute(_bytesToBase64Isolate, {
        'bytes': bytes,
        'maxSize': maxSize,
        'quality': quality,
      });
      return base64String;
    } catch (e) {
      debugPrint('[ImageCompressionService] Error encoding bytes to base64: $e');
      return null;
    }
  }

  /// The heavy lifting function that runs in a separate isolate for saving thumbnail files.
  static bool _compressImageIsolate(Map<String, String> args) {
    try {
      final inputPath = args['input']!;
      final outputPath = args['output']!;
      
      final bytes = File(inputPath).readAsBytesSync();
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return false;

      // Resize the image to fit within 256x256 for lightning fast AI processing
      final resizedImage = img.copyResize(decodedImage, width: 256, height: 256, maintainAspect: true);

      // Compress to JPEG with 65% quality
      final compressedBytes = img.encodeJpg(resizedImage, quality: 65);

      File(outputPath).writeAsBytesSync(compressedBytes);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Isolate worker for reading an image file and producing a compact Base64 JPEG copy
  static String? _fileToBase64Isolate(Map<String, dynamic> args) {
    try {
      final filePath = args['path'] as String;
      final maxSize = args['maxSize'] as int;
      final quality = args['quality'] as int;

      final bytes = File(filePath).readAsBytesSync();
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return null;

      final resizedImage = img.copyResize(
        decodedImage,
        width: maxSize,
        height: maxSize,
        maintainAspect: true,
      );

      final jpegBytes = img.encodeJpg(resizedImage, quality: quality);
      return base64Encode(jpegBytes);
    } catch (_) {
      return null;
    }
  }

  /// Isolate worker for resizing and encoding raw bytes to compact Base64
  static String? _bytesToBase64Isolate(Map<String, dynamic> args) {
    try {
      final bytes = args['bytes'] as Uint8List;
      final maxSize = args['maxSize'] as int;
      final quality = args['quality'] as int;

      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return null;

      final resizedImage = img.copyResize(
        decodedImage,
        width: maxSize,
        height: maxSize,
        maintainAspect: true,
      );

      final jpegBytes = img.encodeJpg(resizedImage, quality: quality);
      return base64Encode(jpegBytes);
    } catch (_) {
      return null;
    }
  }
}
