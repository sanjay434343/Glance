import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/pipeline/content_pipeline.dart';
import '../../core/providers/glance_providers.dart';
import '../../core/services/image_compression_service.dart';
import 'widgets/capture_header.dart';
import 'widgets/capture_action_item.dart';
import 'widgets/auto_capture_status.dart';

class CaptureScreen extends ConsumerWidget {
  const CaptureScreen({super.key});

  Future<String> _copyToPermanentStorage(String originalPath) async {
    try {
      final hiddenDir = Directory('/storage/emulated/0/Android/media/com.example.glance/.glance/images');
      if (!await hiddenDir.exists()) {
        await hiddenDir.create(recursive: true);
      }
      final nomedia = File('/storage/emulated/0/Android/media/com.example.glance/.glance/.nomedia');
      if (!await nomedia.exists()) {
        await nomedia.create();
      }
      final fileName = p.basename(originalPath);
      final savedPath = p.join(hiddenDir.path, '${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final newFile = await File(originalPath).copy(savedPath);
      return newFile.path;
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = p.basename(originalPath);
      final savedPath = p.join(appDir.path, '${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final newFile = await File(originalPath).copy(savedPath);
      return newFile.path;
    }
  }

  Future<void> _pickAndSaveImage(
    BuildContext context,
    WidgetRef ref, {
    required String type,
    required String actionLabel,
  }) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
      );
      if (files.isNotEmpty && files.single.path != null) {
        final originalPath = files.single.path!;
        final path = await _copyToPermanentStorage(originalPath);
        final name = files.single.name;
        final pipeline = ref.read(contentPipelineProvider);
        final compressedPath = await ImageCompressionService.compressForVisionAI(path);
        final base64Image = await ImageCompressionService.createBase64Thumbnail(compressedPath ?? path);

        final item = IngestionItem(
          type: type,
          title: name,
          rawContent: 'Captured $type: $name',
          sourceApp: 'Gallery Picker',
          filePath: path,
          imagePath: path,
          thumbnailPath: compressedPath ?? path,
          imageBase64: base64Image,
          capturedAt: DateTime.now().millisecondsSinceEpoch,
        );

        await pipeline.processIngestion(item);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$actionLabel "$name" saved & vision queued!')),
          );
        }
      } else {
        // Fallback: sync recent device screenshots/photos
        final globalService = ref.read(globalCaptureServiceProvider);
        await globalService.onUserActionDetected(actionName: '$actionLabel Sync');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced recent $type entries!')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking $type image: $e');
    }
  }

  void _showInputDialog({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String hintText,
    required String actionLabel,
    required Function(String text) onSave,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: title.contains('Note') ? 4 : 1,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                onSave(text);
                Navigator.of(dialogCtx).pop();
              }
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CaptureHeader(),
              const SizedBox(height: 32),
              
              // Grouped capture actions
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedCamera01, 
                title: 'Screenshot', 
                subtitle: 'Select screenshot from device gallery', 
                isDark: isDark, 
                isFirst: true,
                onTap: () => _pickAndSaveImage(context, ref, type: 'screenshot', actionLabel: 'Screenshot'),
              ),
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedImage01, 
                title: 'Photo', 
                subtitle: 'Select photo from device gallery', 
                isDark: isDark,
                onTap: () => _pickAndSaveImage(context, ref, type: 'photo', actionLabel: 'Photo'),
              ),
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedCopy01, 
                title: 'Paste Text', 
                subtitle: 'Save text from your clipboard', 
                isDark: isDark,
                onTap: () async {
                  final scanner = ref.read(deviceMemoryScannerProvider);
                  final success = await scanner.recordClipboardText();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(success ? 'Clipboard saved & categorized!' : 'No new text found in clipboard.')),
                    );
                  }
                },
              ),
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedFile01, 
                title: 'Add File', 
                subtitle: 'Upload a document or file', 
                isDark: isDark,
                onTap: () async {
                  try {
                    final files = await FilePicker.pickFiles(
                      type: FileType.any,
                    );
                    if (files.isNotEmpty && files.single.path != null) {
                      final originalPath = files.single.path!;
                      final path = await _copyToPermanentStorage(originalPath);
                      final name = files.single.name;
                      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
                      
                      final pipeline = ref.read(contentPipelineProvider);
                      final isImage = {'jpg', 'jpeg', 'png', 'webp'}.contains(ext);
                      
                      final item = IngestionItem(
                        type: isImage ? 'photo' : (ext == 'pdf' ? 'pdf' : 'document'),
                        title: name,
                        rawContent: 'Uploaded file $name',
                        filePath: path,
                        imagePath: isImage ? path : null,
                      );
                      
                      await pipeline.processIngestion(item);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('File "$name" added to Glance memory permanently!')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error picking file: $e')),
                      );
                    }
                  }
                },
              ),
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedLink01, 
                title: 'Save Link', 
                subtitle: 'Bookmark a URL or website', 
                isDark: isDark,
                onTap: () {
                  _showInputDialog(
                    context: context,
                    ref: ref,
                    title: 'Save Web Link',
                    hintText: 'https://example.com...',
                    actionLabel: 'Save Link',
                    onSave: (url) async {
                      final scanner = ref.read(deviceMemoryScannerProvider);
                      final success = await scanner.recordClipboardText(overrideText: url);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? 'Web link saved!' : 'Link already saved.')),
                        );
                      }
                    },
                  );
                },
              ),
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedLocation01, 
                title: 'Add Location', 
                subtitle: 'Pin a place on the map', 
                iconColor: Colors.red, 
                isDark: isDark,
                onTap: () {
                  _showInputDialog(
                    context: context,
                    ref: ref,
                    title: 'Add Map Location Link',
                    hintText: 'Paste Google Maps URL or location link...',
                    actionLabel: 'Save Location',
                    onSave: (locationUrl) async {
                      final scanner = ref.read(deviceMemoryScannerProvider);
                      final success = await scanner.recordClipboardText(overrideText: locationUrl);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? 'Location saved!' : 'Location already saved.')),
                        );
                      }
                    },
                  );
                },
              ),
              CaptureActionItem(
                icon: HugeIcons.strokeRoundedEdit01, 
                title: 'Add Note', 
                subtitle: 'Jot down a quick thought', 
                isDark: isDark, 
                isLast: true,
                onTap: () {
                  _showInputDialog(
                    context: context,
                    ref: ref,
                    title: 'Add Quick Note',
                    hintText: 'Type your note here...',
                    actionLabel: 'Save Note',
                    onSave: (noteText) async {
                      final scanner = ref.read(deviceMemoryScannerProvider);
                      final success = await scanner.recordClipboardText(overrideText: noteText);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? 'Note saved to memory!' : 'Note already exists.')),
                        );
                      }
                    },
                  );
                },
              ),
              
              const SizedBox(height: 32),
              const AutoCaptureStatus(),
              
              const SizedBox(height: 120), // padding for nav bar
            ],
          ),
        ),
      ),
    );
  }
}
