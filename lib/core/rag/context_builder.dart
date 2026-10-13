import 'dart:convert';

import 'package:glance/core/models/memory_models.dart';

import '../database/glance_db.dart';
import 'query_analyzer.dart';

/// Context Builder for compact, precise on-device GGUF LLM context creation.
/// Formats memories intelligently and provides exact statistical aggregations
/// for count, call log, usage, media, and notification queries.
class ContextBuilder {
  static const int targetTokens = 550;
  static const int maxTokens = 750;

  static const String systemPrompt = """
You are Glance AI, an on-device personal memory assistant.
Answer the user's question clearly, accurately, and naturally based strictly on the retrieved memories. Never invent memories, dates, URLs, applications or events. If the evidence is insufficient, clearly state that you could not find enough information.

Rules:
1. Answer directly what the user is asking. Do not talk about phone calls, call statistics, or unrelated memory types unless the user explicitly asked about them.
2. Format for maximum readability and clarity:
   - For lists, multiple items, or recaps: Begin with a brief introductory sentence, then present each item on its own separate line using standard markdown bullets (- Item). Never combine multiple bullet items into a single line.
   - For direct questions: Provide a clear, cohesive paragraph first, followed by clean bullet points if helpful.
   - For count or breakdown queries: State the total count clearly, then provide a distinct bulleted breakdown.
3. Highlight key information (**App Name**, **Date/Time**, **Subject**, **Count**) in bold.
4. Output in clean markdown. Strictly NO emojis anywhere in the answer.
""";

  /// Formats retrieved candidates into a compact, type-aware context block
  /// with exact statistical counts for aggregation questions.
  static String buildContext(
    List<RetrievalCandidate> candidates, {
    AnalyzedQuery? analyzed,
    String? userQuestion,
  }) {
    if (candidates.isEmpty) {
      return "No relevant memories found.";
    }

    final sb = StringBuffer();
    sb.writeln("Total matching memories retrieved: ${candidates.length}");

    final qLower = userQuestion?.toLowerCase() ?? '';
    final isCallQuery = qLower.contains('call') ||
        qLower.contains('phone') ||
        qLower.contains('dial') ||
        qLower.contains('missed') ||
        qLower.contains('incoming') ||
        qLower.contains('outgoing');

    final isVisualQuery = qLower.contains('photo') ||
        qLower.contains('image') ||
        qLower.contains('screenshot') ||
        qLower.contains('picture') ||
        qLower.contains('camera') ||
        qLower.contains('gallery');

    final isSmsQuery = qLower.contains('sms') ||
        qLower.contains('text message') ||
        qLower.contains('message') ||
        qLower.contains('inbox');

    // ── Statistical Aggregation for Counts and Breakdown Queries ─────────
    int totalCalls = 0;
    int incomingCalls = 0;
    int outgoingCalls = 0;
    int missedCalls = 0;
    int rejectedCalls = 0;

    int totalVisual = 0;
    int screenshots = 0;
    int photos = 0;

    int totalSms = 0;
    int receivedSms = 0;
    int sentSms = 0;

    for (final cand in candidates) {
      final mem = cand.memory;
      final text = '${mem.type} ${mem.title} ${mem.content}'.toLowerCase();

      // Only count as call if it is an actual call_log or phone app activity/notification
      final isCall = mem.type == 'call_log' ||
          (mem.sourceApp?.toLowerCase() == 'phone' &&
              (text.contains('call') ||
                  text.contains('incoming') ||
                  text.contains('outgoing') ||
                  text.contains('missed') ||
                  text.contains('rejected')));

      if (isCall) {
        totalCalls++;
        if (text.contains('incoming')) {
          incomingCalls++;
        } else if (text.contains('outgoing')) {
          outgoingCalls++;
        } else if (text.contains('missed')) {
          missedCalls++;
        } else if (text.contains('rejected')) {
          rejectedCalls++;
        }
      }

      final isVisual = mem.type == 'screenshot' ||
          mem.type == 'photo' ||
          mem.type == 'camera_capture' ||
          mem.filePath != null ||
          mem.thumbnailPath != null;

      if (isVisual) {
        totalVisual++;
        if (mem.type == 'screenshot' || text.contains('screenshot')) {
          screenshots++;
        } else {
          photos++;
        }
      }

      final isSms = mem.type == 'sms' ||
          (mem.sourceApp?.toLowerCase() == 'messages' && text.contains('sms'));

      if (isSms) {
        totalSms++;
        if (text.contains('received') || text.contains('inbox')) {
          receivedSms++;
        } else {
          sentSms++;
        }
      }
    }

    // Append statistical blocks ONLY if relevant to the user query
    if (totalCalls > 0 && (isCallQuery || analyzed?.typeFilter == 'call_log')) {
      sb.writeln("""
[EXACT CALL STATISTICS FROM DATABASE]
- Total Calls: $totalCalls
- Incoming Calls: $incomingCalls
- Outgoing Calls: $outgoingCalls
- Missed Calls: $missedCalls
- Rejected Calls: $rejectedCalls
---""");
    }

    if (totalVisual > 0 && (isVisualQuery || analyzed?.typeFilter == 'visual' || totalVisual >= 3)) {
      sb.writeln("""
[EXACT MEDIA STATISTICS FROM DATABASE]
- Total Visual Items: $totalVisual
- Screenshots: $screenshots
- Photos / Camera: $photos
---""");
    }

    if (totalSms > 0 && (isSmsQuery || analyzed?.typeFilter == 'sms' || totalSms >= 2)) {
      sb.writeln("""
[EXACT MESSAGE STATISTICS FROM DATABASE]
- Total Messages: $totalSms
- Received Messages: $receivedSms
- Sent Messages: $sentSms
---""");
    }

    int currentEstimatedTokens = (sb.length / 4).ceil();
    final topCandidates = candidates.take(24).toList();

    for (int i = 0; i < topCandidates.length; i++) {
      final cand = topCandidates[i];
      final mem = cand.memory;

      final dateStr = _formatTimestamp(mem.capturedAt);
      final appStr = mem.sourceApp ?? 'Unknown App';
      final textLower = '${mem.type} ${mem.title} ${mem.content}'.toLowerCase();

      String chunkBlock;

      if (mem.type == 'call_log' || (mem.sourceApp?.toLowerCase() == 'phone' && textLower.contains('call'))) {
        chunkBlock = _formatCallLog(i + 1, mem, dateStr);
      } else if (mem.type == 'sms' || (mem.sourceApp?.toLowerCase() == 'messages' && textLower.contains('sms'))) {
        chunkBlock = _formatSms(i + 1, mem, dateStr);
      } else {
        switch (mem.type) {
          case 'app_activity':
            chunkBlock = _formatAppActivity(i + 1, mem, dateStr, appStr);
            break;
          case 'copied_text':
          case 'clipboard':
            chunkBlock = _formatCopiedText(i + 1, mem, dateStr);
            break;
          case 'screenshot':
          case 'photo':
          case 'camera_capture':
            chunkBlock = _formatVisualMemory(i + 1, mem, dateStr);
            break;
          case 'notification':
            chunkBlock = _formatNotification(i + 1, mem, dateStr, appStr);
            break;
          case 'pdf':
          case 'document':
          case 'file':
            chunkBlock = _formatDocument(i + 1, mem, dateStr);
            break;
          default:
            chunkBlock = _formatGeneric(i + 1, mem, dateStr, appStr);
        }
      }

      final estTokens = (chunkBlock.length / 4).ceil();
      if (currentEstimatedTokens + estTokens > maxTokens) break;

      sb.writeln(chunkBlock);
      sb.writeln("---");
      currentEstimatedTokens += estTokens;
    }

    return sb.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TYPE-SPECIFIC FORMATTERS
  // ═══════════════════════════════════════════════════════════════════════

  static String _formatCallLog(int index, Memory mem, String dateStr) {
    String callType = 'Call';
    String contact = mem.title;
    if (mem.title.contains(':')) {
      final parts = mem.title.split(':');
      callType = parts.first.trim();
      contact = parts.sublist(1).join(':').trim();
    }
    return """
[Memory $index] CALL LOG
- Type: $callType
- Contact: $contact
- Date: $dateStr
- Details: ${mem.content}
""";
  }

  static String _formatSms(int index, Memory mem, String dateStr) {
    return """
[Memory $index] SMS
- From/To: ${mem.title}
- Date: $dateStr
- Message: ${mem.content}
""";
  }

  static String _formatAppActivity(
    int index,
    Memory mem,
    String dateStr,
    String appStr,
  ) {
    int openCount = 1;
    String usageStr = '< 1m';
    if (mem.summary != null && mem.summary!.isNotEmpty) {
      try {
        final stats = jsonDecode(mem.summary!);
        openCount = stats['openCount'] ?? 1;
        final usageTimeMs = stats['usageTimeMs'] ?? 0;
        usageStr = _formatDuration(usageTimeMs);
      } catch (_) {}
    }
    final usageInfo = '\n- Opens: $openCount times\n- Usage Time: $usageStr';
    return """
[Memory $index] APP ACTIVITY
- App: $appStr${mem.sourcePackage != null ? ' (${mem.sourcePackage})' : ''}
- Last Active: $dateStr$usageInfo
- Details: ${mem.content}
""";
  }

  static String _formatCopiedText(int index, Memory mem, String dateStr) {
    final contentPreview = mem.content.length > 300
        ? '${mem.content.substring(0, 300)}...'
        : mem.content;
    return """
[Memory $index] COPIED TEXT
- Copied At: $dateStr
- Source: ${mem.sourceApp ?? 'Clipboard'}
- Content: $contentPreview
""";
  }

  static String _formatVisualMemory(int index, Memory mem, String dateStr) {
    return """
[Memory $index] ${mem.type.toUpperCase()}
- Captured: $dateStr
- File: ${mem.title}
- Path: ${mem.filePath ?? 'N/A'}
- Content: ${mem.content}
""";
  }

  static String _formatDocument(
    int index,
    Memory mem,
    String dateStr,
  ) {
    String smartEntitiesStr = '';
    if (mem.summary != null && mem.summary!.isNotEmpty) {
      try {
        final decoded = jsonDecode(mem.summary!);
        if (decoded is Map && decoded['entities'] is Map) {
          final entMap = decoded['entities'] as Map;
          final lines = <String>[];
          for (final entry in entMap.entries) {
            lines.add('${entry.key}: ${(entry.value as List).join(", ")}');
          }
          if (lines.isNotEmpty) {
            smartEntitiesStr = '\n- Smart Entities: ${lines.join(" | ")}';
          }
        } else if (decoded is List) {
          smartEntitiesStr = '\n- Smart Entities: ${decoded.join(" | ")}';
        }
      } catch (_) {}
    }

    final contentPreview = mem.content.length > 500
        ? '${mem.content.substring(0, 500)}...'
        : mem.content;

    return """
[Memory $index] DOCUMENT
- Title: ${mem.title}
- Date: $dateStr$smartEntitiesStr
- Content: $contentPreview
""";
  }

  static String _formatNotification(
    int index,
    Memory mem,
    String dateStr,
    String appStr,
  ) {
    String smartEntitiesStr = '';
    if (mem.summary != null && mem.summary!.isNotEmpty) {
      try {
        final decoded = jsonDecode(mem.summary!);
        if (decoded is Map && decoded['entities'] is Map) {
          final entMap = decoded['entities'] as Map;
          final lines = <String>[];
          for (final entry in entMap.entries) {
            lines.add('${entry.key}: ${(entry.value as List).join(", ")}');
          }
          if (lines.isNotEmpty) {
            smartEntitiesStr = '\n- Smart Entities: ${lines.join(" | ")}';
          }
        } else if (decoded is List) {
          smartEntitiesStr = '\n- Smart Entities: ${decoded.join(" | ")}';
        }
      } catch (_) {}
    }

    return """
[Memory $index] NOTIFICATION
- From: $appStr
- Time: $dateStr
- Title: ${mem.title}$smartEntitiesStr
- Content: ${mem.content}
""";
  }

  static String _formatGeneric(
    int index,
    Memory mem,
    String dateStr,
    String appStr,
  ) {
    final urlStr = mem.url != null ? '\n- URL: ${mem.url}' : '';
    String smartEntitiesStr = '';
    if (mem.summary != null && mem.summary!.isNotEmpty) {
      try {
        final decoded = jsonDecode(mem.summary!);
        if (decoded is Map && decoded['entities'] is Map) {
          final entMap = decoded['entities'] as Map;
          final lines = <String>[];
          for (final entry in entMap.entries) {
            lines.add('${entry.key}: ${(entry.value as List).join(", ")}');
          }
          if (lines.isNotEmpty) {
            smartEntitiesStr = '\n- Smart Entities: ${lines.join(" | ")}';
          }
        } else if (decoded is List) {
          smartEntitiesStr = '\n- Smart Entities: ${decoded.join(" | ")}';
        }
      } catch (_) {}
    }

    return """
[Memory $index] (${mem.type.toUpperCase()})
- Source: $appStr$urlStr
- Date: $dateStr$smartEntitiesStr
- Content: ${mem.content}
""";
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FORMATTING UTILITIES
  // ═══════════════════════════════════════════════════════════════════════

  /// Converts epoch milliseconds into a human-readable relative timestamp.
  static String _formatTimestamp(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}/${dt.month}/${dt.year}';
  }

  /// Converts milliseconds into a human-readable duration string.
  static String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '< 1m';
    final seconds = milliseconds ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remMins = minutes % 60;
    return remMins > 0 ? '${hours}h ${remMins}m' : '${hours}h';
  }
}
