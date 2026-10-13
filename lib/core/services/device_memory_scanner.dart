import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../database/glance_db.dart';
import '../models/memory_models.dart';
import '../native/glance_native_bridge.dart';
import '../pipeline/content_pipeline.dart';
import 'image_compression_service.dart';
import 'vision_service.dart';
import 'document_extraction_service.dart';
import 'smart_entity_service.dart';
import 'web_scraper_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Scans real device activity, photos, screenshots, documents, clipboard, and web entries.
class DeviceMemoryScanner {
  final ContentPipeline pipeline;
  final GlanceDatabase db;

  final Set<String> _seenPaths = {};
  final Map<String, int> _lastAppTimestamps = {};
  int _lastCleanDuplicatesTime = 0;

  DeviceMemoryScanner({
    required this.pipeline,
    required this.db,
  });

  /// Triggers full device scan. Returns true ONLY if new items were captured and saved.
  Future<bool> syncDeviceData() async {
    bool hasNewItem = false;
    try {
      // 0. Clean historical duplicate entries in SQLite DB (throttled to once per 30 minutes)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCleanDuplicatesTime > 1800000) {
        _lastCleanDuplicatesTime = now;
        final deletedDups = await db.cleanAllDuplicateMemories();
        if (deletedDups > 0) {
          hasNewItem = true;
        }
      }

      // Load all memories once to find existing items
      final existingMemories = await db.getAllMemories();
      final existingFilePaths = <String>{};
      final existingKeys = <String>{};
      final existingMemByPath = <String, Memory>{};
      final appMemoriesMap = <String, Memory>{};

      for (final m in existingMemories) {
        final fp = m.filePath ?? m.thumbnailPath;
        if (fp != null && fp.isNotEmpty) {
          final trimmed = fp.trim();
          existingFilePaths.add(trimmed);
          _seenPaths.add(trimmed);
          existingMemByPath[trimmed] = m;
        }
        existingKeys.add('${m.type}_${m.title}_${m.capturedAt}');
        if (m.type == 'app_activity' && m.sourcePackage != null) {
          appMemoriesMap[m.sourcePackage!.trim()] = m;
        }
      }

      // Automatically backfill any existing memories missing Base64 copies into the DB
      unawaited(backfillMissingBase64(existingMemories));

      // 1. App Activity (with original app icon)
      final apps = await GlanceNativeBridge.getAppActivity();
      
      for (final app in apps) {
        final pkgName = app['packageName'] as String? ?? 'com.android.app';
        final ts = app['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        
        final lastTs = _lastAppTimestamps[pkgName];
        if (lastTs != null && lastTs >= ts) {
          continue;
        }
        _lastAppTimestamps[pkgName] = ts;

        final Memory? existingMemory = appMemoriesMap[pkgName.trim()];

        final appName = app['appName'] as String? ?? 'App';
        final iconBase64 = app['appIconBase64'] as String? ?? '';
        final openCount = app['openCount'] as int? ?? 1;
        final usageTimeMs = app['usageTimeMs'] as int? ?? 0;
        
        final statsJson = jsonEncode({
          'openCount': openCount,
          'usageTimeMs': usageTimeMs,
        });

        // Always record persistent daily usage snapshot in app_usage_history table
        final todayKey = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
        await db.upsertAppUsageHistory(
          packageName: pkgName,
          appName: appName,
          dateKey: todayKey,
          usageTimeMs: usageTimeMs,
          openCount: openCount,
          timestamp: ts,
        );

        if (existingMemory != null) {
          // Only update SQLite if capturedAt timestamp or usage stats actually changed
          if (existingMemory.capturedAt != ts || existingMemory.summary != statsJson) {
            if (iconBase64.isNotEmpty) {
              await db.saveAppIcon(pkgName, iconBase64);
            }
            final updated = Memory(
              id: existingMemory.id,
              type: existingMemory.type,
              title: existingMemory.title,
              content: existingMemory.content,
              source: existingMemory.source,
              sourceApp: existingMemory.sourceApp,
              sourcePackage: pkgName,
              url: existingMemory.url,
              filePath: existingMemory.filePath,
              thumbnailPath: null,
              imageBase64: iconBase64.isNotEmpty ? iconBase64 : existingMemory.imageBase64,
              summary: statsJson,
              capturedAt: ts,
              createdAt: existingMemory.createdAt,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
            await db.insertMemory(updated);
            hasNewItem = true;
          }
        } else {
          // Create a new memory
          final item = IngestionItem(
            type: 'app_activity',
            title: appName,
            rawContent: 'Used $appName ($pkgName)',
            sourceApp: appName,
            imageBase64: iconBase64.isNotEmpty ? iconBase64 : null,
          );

          final memory = await pipeline.processIngestion(item);
          if (iconBase64.isNotEmpty) {
            await db.saveAppIcon(pkgName, iconBase64);
          }
          final updated = Memory(
            id: memory.id,
            type: memory.type,
            title: memory.title,
            content: memory.content,
            source: memory.source,
            sourceApp: memory.sourceApp,
            sourcePackage: pkgName,
            url: memory.url,
            filePath: memory.filePath,
            thumbnailPath: null,
            imageBase64: iconBase64.isNotEmpty ? iconBase64 : null,
            summary: statsJson,
            capturedAt: ts,
            createdAt: memory.createdAt,
            updatedAt: memory.updatedAt,
          );
          await db.insertMemory(updated);
          hasNewItem = true;
        }
      }

      // 2. Visual (Screenshots & Photos)
      final media = await GlanceNativeBridge.getRecentMedia();
      for (final m in media) {
        try {
          final path = (m['filePath'] as String? ?? '').trim();
          if (path.isEmpty || existingFilePaths.contains(path)) {
            // If already in DB, only auto-enqueue if vision has NEVER processed it
            if (path.isNotEmpty) {
              final existingMem = existingMemByPath[path];
              if (existingMem != null && !existingMem.isProcessed) {
                VisionService.instance.enqueue(
                  memoryId: existingMem.id,
                  imagePath: path,
                );
              }
            }
            continue;
          }
          _seenPaths.add(path);
          existingFilePaths.add(path);

          final title = m['title'] as String? ?? 'Screenshot';
          final type = m['type'] as String? ?? 'screenshot';
          final ts = m['capturedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
          final compressedPath = await ImageCompressionService.compressForVisionAI(path);
          final base64Image = await ImageCompressionService.createBase64Thumbnail(compressedPath ?? path);

          final item = IngestionItem(
            type: type,
            title: title,
            rawContent: 'Captured $type: $title',
            sourceApp: type == 'screenshot' ? 'System Screen' : 'Camera',
            filePath: path,
            imagePath: path,
            thumbnailPath: compressedPath ?? path,
            imageBase64: base64Image,
            capturedAt: ts,
          );

          await pipeline.processIngestion(item);
          hasNewItem = true;
        } catch (itemErr) {
          debugPrint('[DeviceMemoryScanner] Error ingesting media item: $itemErr');
        }
      }

      // 3. Documents & Files (Automated scan via MediaStore, Downloads & Documents folders)
      final allFoundDocs = <Map<String, dynamic>>[];
      try {
        final docs = await GlanceNativeBridge.getRecentDocuments();
        allFoundDocs.addAll(docs);
      } catch (e) {
        debugPrint('[DeviceMemoryScanner] Bridge getRecentDocuments note: $e');
      }

      // Also directly scan /storage/emulated/0/Download and Documents folders in Dart
      final downloadDirs = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Downloads'),
        Directory('/storage/emulated/0/Documents'),
      ];
      final extensions = {'pdf', 'doc', 'docx', 'txt', 'md', 'epub', 'xlsx', 'xls', 'csv', 'pptx', 'ppt'};

      for (final dir in downloadDirs) {
        if (dir.existsSync()) {
          try {
            final entities = dir.listSync(recursive: false, followLinks: false);
            for (final entity in entities) {
              if (entity is File && !entity.path.split(Platform.pathSeparator).last.startsWith('.')) {
                final ext = entity.path.contains('.') ? entity.path.split('.').last.toLowerCase() : '';
                if (extensions.contains(ext)) {
                  final path = entity.path;
                  if (!allFoundDocs.any((d) => d['filePath'] == path)) {
                    final filename = entity.uri.pathSegments.last;
                    allFoundDocs.add({
                      'filename': filename,
                      'filePath': path,
                      'fileType': ext,
                      'sizeBytes': entity.lengthSync(),
                      'modifiedAt': entity.lastModifiedSync().millisecondsSinceEpoch,
                    });
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('[DeviceMemoryScanner] Dart folder scan note: $e');
          }
        }
      }

      for (final doc in allFoundDocs) {
        final path = (doc['filePath'] as String? ?? '').trim();
        if (path.isEmpty || _seenPaths.contains(path) || existingFilePaths.contains(path)) continue;
        _seenPaths.add(path);
        existingFilePaths.add(path);

        final filename = doc['filename'] as String? ?? 'Document';
        final type = doc['fileType'] as String? ?? 'pdf';
        final ts = doc['modifiedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        final item = IngestionItem(
          type: type.isNotEmpty ? type : 'pdf',
          title: filename,
          rawContent: 'Document $filename located at $path',
          sourceApp: 'Files',
          filePath: path,
        );

        final memory = await pipeline.processIngestion(item);
        final updated = Memory(
          id: memory.id,
          type: memory.type,
          title: memory.title,
          content: memory.content,
          source: memory.source,
          sourceApp: 'Files',
          filePath: path,
          capturedAt: ts,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        );
        await db.insertMemory(updated);
        hasNewItem = true;
      }

      // Automatically extract text and process all unindexed documents
      unawaited(DocumentExtractionService.instance.processUnprocessedDocuments());

      // 4. Clipboard Text is no longer automatically scanned. User must manually tap Paste in Capture Screen.

      // 5. Call Logs (Caller name, number, duration, call type, timestamp)
      final callLogs = await GlanceNativeBridge.getCallLogs();
      for (final call in callLogs) {
        final callerName = call['callerName'] as String? ?? 'Phone Call';
        final phoneNum = call['phoneNumber'] as String? ?? '';
        final callType = call['callType'] as String? ?? 'Call';
        final duration = call['durationSeconds'] as int? ?? 0;
        final ts = call['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final title = '$callType: $callerName';
        final sigKey = 'call_log_${title}_$ts';

        if (_seenPaths.contains(sigKey) || existingKeys.contains(sigKey)) continue;
        _seenPaths.add(sigKey);
        existingKeys.add(sigKey);

        final durStr = duration > 0 ? ' (${duration}s)' : '';
        final item = IngestionItem(
          type: 'call_log',
          title: title,
          rawContent: '$callType with $callerName ($phoneNum)$durStr at ${DateTime.fromMillisecondsSinceEpoch(ts)}',
          sourceApp: 'Phone',
        );

        final memory = await pipeline.processIngestion(item);
        final updated = Memory(
          id: memory.id,
          type: 'call_log',
          title: title,
          content: '$callType with $callerName ($phoneNum)$durStr',
          source: memory.source,
          sourceApp: 'Phone',
          capturedAt: ts,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        );
        await db.insertMemory(updated);
        hasNewItem = true;
      }

      // 6. SMS Messages (Sender, Body, Type, Timestamp)
      final smsList = await GlanceNativeBridge.getSmsMessages();
      for (final sms in smsList) {
        final sender = sms['sender'] as String? ?? 'SMS';
        final body = sms['body'] as String? ?? '';
        final smsType = sms['smsType'] as String? ?? 'Received SMS';
        final ts = sms['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final title = '$smsType: $sender';
        final sigKey = 'sms_${title}_$ts';

        if (_seenPaths.contains(sigKey) || existingKeys.contains(sigKey)) continue;
        _seenPaths.add(sigKey);
        existingKeys.add(sigKey);

        final item = IngestionItem(
          type: 'sms',
          title: title,
          rawContent: body,
          sourceApp: 'Messages',
        );

        final memory = await pipeline.processIngestion(item);
        final updated = Memory(
          id: memory.id,
          type: 'sms',
          title: title,
          content: body,
          source: memory.source,
          sourceApp: 'Messages',
          capturedAt: ts,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        );
        await db.insertMemory(updated);
        hasNewItem = true;
      }

      // 7. Calendar Events & Meetings
      final events = await GlanceNativeBridge.getCalendarEvents();
      for (final ev in events) {
        final title = ev['title'] as String? ?? 'Meeting';
        final desc = ev['description'] as String? ?? '';

        final lowerTitle = title.toLowerCase();
        final lowerDesc = desc.toLowerCase();
        final isHoliday = lowerTitle.contains('holiday') ||
            lowerTitle.contains('festival') ||
            lowerTitle.contains('birthday') ||
            lowerDesc.contains('holiday') ||
            lowerDesc.contains('public holiday') ||
            lowerDesc.contains('government holiday');
        if (isHoliday) continue;

        final startMs = ev['startTimestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final location = ev['location'] as String? ?? '';
        final sigKey = 'notification_${title}_$startMs';

        if (_seenPaths.contains(sigKey) || existingKeys.contains(sigKey)) continue;
        _seenPaths.add(sigKey);
        existingKeys.add(sigKey);

        final locStr = location.isNotEmpty ? ' at $location' : '';
        final item = IngestionItem(
          type: 'notification',
          title: title,
          rawContent: 'Meeting/Event: $title$locStr. $desc',
          sourceApp: 'Calendar',
        );

        final memory = await pipeline.processIngestion(item);
        final updated = Memory(
          id: memory.id,
          type: 'notification',
          title: title,
          content: '$desc$locStr',
          source: memory.source,
          sourceApp: 'Calendar',
          capturedAt: startMs,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        );
        await db.insertMemory(updated);
        hasNewItem = true;
      }

      // 8. App Notifications (WhatsApp, Telegram, Messages, System)
      final notifications = await GlanceNativeBridge.getRecentNotifications();
      for (final notif in notifications) {
        final pkgName = notif['packageName'] as String? ?? '';
        final appName = notif['appName'] as String? ?? 'Notification';
        final title = notif['title'] as String? ?? '';
        final text = notif['text'] as String? ?? '';
        final ts = notif['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final displayTitle = title.isNotEmpty ? '$appName: $title' : '$appName Notification';
        final sigKey = 'notification_${displayTitle}_$ts';

        if (_seenPaths.contains(sigKey) || existingKeys.contains(sigKey)) continue;
        _seenPaths.add(sigKey);
        existingKeys.add(sigKey);

        final item = IngestionItem(
          type: 'notification',
          title: displayTitle,
          rawContent: text.isNotEmpty ? text : displayTitle,
          sourceApp: appName,
        );

        final memory = await pipeline.processIngestion(item);
        
        // Extract and push smart entities into summary for RAG retrieval
        String? notifSummary;
        try {
          notifSummary = await SmartEntityService.instance.extractAndBuildSummary(
            '$displayTitle\n$text',
          );
        } catch (_) {}

        final updated = Memory(
          id: memory.id,
          type: 'notification',
          title: displayTitle,
          content: text,
          source: memory.source,
          sourceApp: appName,
          sourcePackage: pkgName,
          summary: notifSummary,
          capturedAt: ts,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        );
        await db.insertMemory(updated);
        hasNewItem = true;
      }
    } catch (e) {
      debugPrint('DeviceMemoryScanner error: $e');
    }
    return hasNewItem;
  }

  /// Records an app opening event immediately and places it at the top of recent activity.
  Future<Memory> recordAppOpened(String appName, String packageName, {String? iconBase64}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = IngestionItem(
      type: 'app_activity',
      title: appName,
      rawContent: 'Opened $appName ($packageName)',
      sourceApp: appName,
    );

    final memory = await pipeline.processIngestion(item);
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      await db.saveAppIcon(packageName, iconBase64);
    }
    final updated = Memory(
      id: memory.id,
      type: memory.type,
      title: memory.title,
      content: memory.content,
      source: memory.source,
      sourceApp: memory.sourceApp,
      sourcePackage: packageName,
      thumbnailPath: null,
      imageBase64: iconBase64,
      capturedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await db.insertMemory(updated);
    return updated;
  }

  /// Scans SQLite database for any legacy memories (screenshots/photos/icons) missing
  /// Base64 copies, compresses them in the background, and saves them directly to DB.
  Future<void> backfillMissingBase64(List<Memory> memories) async {
    try {
      for (final mem in memories) {
        if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) continue;

        // Visual captures (screenshots/photos)
        if (mem.filePath != null || mem.thumbnailPath != null) {
          final targetPath = mem.thumbnailPath ?? mem.filePath;
          if (targetPath != null && targetPath.isNotEmpty && File(targetPath).existsSync()) {
            final b64 = await ImageCompressionService.createBase64Thumbnail(targetPath);
            if (b64 != null && b64.isNotEmpty) {
              await db.updateMemoryImageBase64(mem.id, b64);
            }
          }
        } else if (mem.type == 'app_activity' && mem.sourcePackage != null && mem.sourcePackage!.isNotEmpty) {
          final iconB64 = await db.getAppIcon(mem.sourcePackage!);
          if (iconB64 != null && iconB64.isNotEmpty) {
            await db.updateMemoryImageBase64(mem.id, iconB64);
          }
        }
      }
    } catch (e) {
      debugPrint('[DeviceMemoryScanner] Note during base64 backfill: $e');
    }
  }

  /// Classifies input text as location (Google Maps URL), web URL, or copied text.
  static Map<String, String> classifyInputText(String text) {
    final lower = text.toLowerCase().trim();

    // 1. Google Maps / Location links
    final isMapUrl = lower.contains('maps.google.') ||
        lower.contains('google.com/maps') ||
        lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('waze.com') ||
        lower.contains('apple.com/maps') ||
        RegExp(r'@-?\d+\.\d+,-?\d+\.\d+').hasMatch(lower) ||
        (lower.contains('maps') && lower.contains('http'));

    if (isMapUrl) {
      return {
        'type': 'location',
        'title': 'Saved Map Location',
        'url': text,
        'content': 'Map Location: $text',
      };
    }

    // 2. Web URLs
    final isWebUrl = lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.') ||
        RegExp(r'^(https?:\/\/)?([\w\d\-]+\.)+[\w\d\-]+(\/[\w\d\-\.\?%&=#]*)*$', caseSensitive: false).hasMatch(text);

    if (isWebUrl) {
      String host = 'Web Link';
      try {
        final uri = Uri.parse(text.startsWith('http') ? text : 'https://$text');
        if (uri.host.isNotEmpty) host = uri.host;
      } catch (_) {}
      return {
        'type': 'url',
        'title': 'Bookmark: $host',
        'url': text,
        'content': 'Website link: $text',
      };
    }

    // 3. Regular copied text
    final displayTitle = text.length > 25 ? '${text.substring(0, 25)}...' : text;
    return {
      'type': 'copied_text',
      'title': displayTitle,
      'url': '',
      'content': text,
    };
  }

  /// Manually records the current clipboard text.
  Future<bool> recordClipboardText({String? overrideText}) async {
    try {
      String text = (overrideText ?? '').trim();
      int ts = DateTime.now().millisecondsSinceEpoch;

      if (text.isEmpty) {
        final clip = await GlanceNativeBridge.getClipboardText();
        if (clip != null) {
          text = (clip['text'] as String? ?? '').trim();
          ts = clip['timestamp'] as int? ?? ts;
        }
      }

      if (text.isNotEmpty) {
        final classified = classifyInputText(text);

        String type = classified['type']!;
        String title = classified['title']!;
        String url = classified['url']!;
        String content = classified['content']!;
        String? thumbnailPath;

        // If it's a website URL, fetch hero thumbnail and scrape page content
        if (type == 'url' || type == 'webpage') {
          type = 'webpage';
          try {
            final scraped = await WebScraperService.instance.scrapeUrl(url.isNotEmpty ? url : text);
            if (scraped['title'] != null && scraped['title'].toString().trim().isNotEmpty) {
              title = scraped['title'].toString().trim();
            }
            if (scraped['content'] != null && scraped['content'].toString().trim().isNotEmpty) {
              content = scraped['content'].toString().trim();
            }
            if (scraped['thumbnailPath'] != null) {
              thumbnailPath = scraped['thumbnailPath'].toString();
            }
          } catch (e) {
            debugPrint('[DeviceMemoryScanner] Scrape error: $e');
          }
        }

        final shaHash = Memory.computeShaHash(
          title: title,
          type: type,
          content: content,
          sourceApp: 'Clipboard',
        );

        final hasSha = await db.hasMemoryWithShaHash(shaHash);
        final existingMemories = await db.getAllMemories();
        final isAlreadySaved = hasSha || existingMemories.any(
          (m) => (m.type == type || m.type == 'copied_text' || m.type == 'url') &&
              (m.content.trim() == content || (url.isNotEmpty && m.url == url))
        );

        if (!isAlreadySaved) {
          final item = IngestionItem(
            type: type,
            title: title,
            rawContent: content,
            url: url.isNotEmpty ? url : null,
            sourceApp: 'Clipboard',
          );

          final memory = await pipeline.processIngestion(item);

          // Extract and push smart entities into summary for RAG retrieval
          String? clipSummary;
          try {
            clipSummary = await SmartEntityService.instance.extractAndBuildSummary(
              content,
            );
          } catch (_) {}

          final updated = Memory(
            id: memory.id,
            type: type,
            title: title,
            content: content,
            source: memory.source,
            sourceApp: 'Clipboard',
            url: url.isNotEmpty ? url : null,
            thumbnailPath: thumbnailPath,
            summary: clipSummary,
            capturedAt: ts,
            createdAt: memory.createdAt,
            updatedAt: memory.updatedAt,
          );
          await db.insertMemory(updated);
          return true;
        }
      }
    } catch (e) {
      debugPrint('recordClipboardText error: $e');
    }
    return false;
  }

  /// Dedicated scanner method to crawl, index, and extract all device documents and PDFs.
  Future<int> scanAndIngestAllDocuments() async {
    int importedCount = 0;
    try {
      // Ensure Manage External Storage permission is granted on Android 11+
      try {
        final isManageGranted = await Permission.manageExternalStorage.isGranted;
        if (!isManageGranted) {
          final status = await Permission.manageExternalStorage.request();
          debugPrint('[DeviceMemoryScanner] manageExternalStorage request result: $status');
        }
        await [
          Permission.storage,
          Permission.photos,
        ].request();
      } catch (permErr) {
        debugPrint('[DeviceMemoryScanner] Permission request note: $permErr');
      }

      final existingMemories = await db.getAllMemories();
      final existingFilePaths = existingMemories
          .where((m) => m.filePath != null && m.filePath!.isNotEmpty)
          .map((m) => m.filePath!)
          .toSet();

      final docs = await GlanceNativeBridge.getRecentDocuments();
      debugPrint('[DeviceMemoryScanner] Native bridge returned ${docs.length} documents.');

      // Also directly scan /storage/emulated/0/Download and /storage/emulated/0/Documents in Dart as immediate fallback
      final downloadDirs = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Downloads'),
        Directory('/storage/emulated/0/Documents'),
      ];

      final extensions = {'pdf', 'doc', 'docx', 'txt', 'md', 'epub', 'xlsx', 'xls', 'csv', 'pptx', 'ppt'};
      final allFoundDocs = List<Map<String, dynamic>>.from(docs);

      for (final dir in downloadDirs) {
        if (dir.existsSync()) {
          try {
            final entities = dir.listSync(recursive: false, followLinks: false);
            for (final entity in entities) {
              if (entity is File && !entity.path.split(Platform.pathSeparator).last.startsWith('.')) {
                final ext = entity.path.contains('.') ? entity.path.split('.').last.toLowerCase() : '';
                if (extensions.contains(ext)) {
                  final path = entity.path;
                  if (!allFoundDocs.any((d) => d['filePath'] == path)) {
                    final filename = entity.uri.pathSegments.last;
                    allFoundDocs.add({
                      'filename': filename,
                      'filePath': path,
                      'fileType': ext,
                      'sizeBytes': entity.lengthSync(),
                      'modifiedAt': entity.lastModifiedSync().millisecondsSinceEpoch,
                    });
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('[DeviceMemoryScanner] Dart scan note: $e');
          }
        }
      }

      for (final doc in allFoundDocs) {
        final path = (doc['filePath'] as String? ?? '').trim();
        if (path.isEmpty || existingFilePaths.contains(path)) continue;

        existingFilePaths.add(path);
        _seenPaths.add(path);

        final filename = doc['filename'] as String? ?? 'Document';
        final type = doc['fileType'] as String? ?? 'pdf';
        final ts = doc['modifiedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        final item = IngestionItem(
          type: type.isNotEmpty ? type : 'pdf',
          title: filename,
          rawContent: 'Document $filename located at $path',
          sourceApp: 'Files',
          filePath: path,
        );

        final memory = await pipeline.processIngestion(item);
        final updated = Memory(
          id: memory.id,
          type: memory.type,
          title: memory.title,
          content: memory.content,
          source: memory.source,
          sourceApp: 'Files',
          filePath: path,
          capturedAt: ts,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        );
        await db.insertMemory(updated);
        importedCount++;
      }

      // Process any unprocessed documents
      await DocumentExtractionService.instance.processUnprocessedDocuments();
    } catch (e) {
      debugPrint('[DeviceMemoryScanner] Error scanning all documents: $e');
    }
    return importedCount;
  }
}
