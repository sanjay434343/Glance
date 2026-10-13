import 'dart:convert';

import '../database/glance_db.dart';
import '../embedding/embedding_engine.dart';
import '../models/memory_models.dart';
import '../native/glance_native_bridge.dart';
import '../temporal/temporal_query_resolver.dart';
import 'query_analyzer.dart';

/// Hybrid retrieval engine fusing SQLite FTS5 BM25 lexical search, vector similarity, temporal windowing, and metadata relevance.
/// Now upgraded with AI Query Analyzer for intelligent intent-driven search.
class HybridRetriever {
  final GlanceDatabase db;
  final IEmbeddingModel embeddingEngine;

  HybridRetriever({
    required this.db,
    required this.embeddingEngine,
  });

  /// Executes intelligent hybrid search over offline SQLite storage.
  /// Uses AI Query Analyzer to understand intent, then combines smart DB search
  /// with legacy FTS5/vector paths for comprehensive retrieval.
  Future<List<RetrievalCandidate>> retrieve({
    required String userQuery,
    int candidateLimit = 30,
    int finalLimit = 8,
    double minimumScore = 0.10,
  }) async {
    // ── 1. AI Query Analysis ─────────────────────────────────────────────
    final analyzed = QueryAnalyzer.analyze(userQuery);

    // Skip search for conversational queries
    if (analyzed.intent == QueryIntent.conversational) {
      return [];
    }

    // ── 2. Smart DB search based on analyzed intent ──────────────────────
    List<Memory> dbResults = [];

    switch (analyzed.intent) {
      case QueryIntent.appUsage:
        if (analyzed.appName != null) {
          // Try type-filtered search first
          dbResults = await db.searchMemoriesSmart(
            sourceApp: analyzed.appName,
            type: analyzed.typeFilter,
            startTime: analyzed.timeRange?.startTime,
            endTime: analyzed.timeRange?.endTime,
            limit: candidateLimit,
          );
          // Fallback: search without type filter
          if (dbResults.isEmpty) {
            dbResults = await db.searchMemoriesSmart(
              sourceApp: analyzed.appName,
              startTime: analyzed.timeRange?.startTime,
              endTime: analyzed.timeRange?.endTime,
              limit: candidateLimit,
            );
          }
          // Broader keyword fallback
          if (dbResults.isEmpty) {
            dbResults = await db.searchMemoriesSmart(
              keywords: [analyzed.appName!],
              limit: candidateLimit,
            );
          }
        }
        break;

      case QueryIntent.clipboardSearch:
        dbResults = await db.searchMemoriesSmart(
          type: 'copied_text',
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          startTime: analyzed.timeRange?.startTime,
          endTime: analyzed.timeRange?.endTime,
          limit: candidateLimit,
        );
        // Fallback: get all clipboard items if keyword search returned nothing
        if (dbResults.isEmpty && analyzed.keywords.isNotEmpty) {
          dbResults = await db.getMemoriesByType('copied_text', limit: candidateLimit);
        }
        break;

      case QueryIntent.screenshotSearch:
        if (analyzed.keywords.isEmpty) {
          dbResults = await db.getAllVisualMemories(
            startTime: analyzed.timeRange?.startTime,
            endTime: analyzed.timeRange?.endTime,
            limit: 500,
          );
        } else {
          dbResults = await db.searchMemoriesSmart(
            type: 'visual',
            keywords: analyzed.keywords,
            startTime: analyzed.timeRange?.startTime,
            endTime: analyzed.timeRange?.endTime,
            limit: 500,
          );
          if (dbResults.isEmpty) {
            dbResults = await db.getAllVisualMemories(
              startTime: analyzed.timeRange?.startTime,
              endTime: analyzed.timeRange?.endTime,
              limit: 500,
            );
          }
        }

        // Bridge directly to native device media so the entire set of device images is pulled
        try {
          final deviceMedia = await GlanceNativeBridge.getRecentMedia();
          final existingPaths = dbResults
              .map((m) => m.filePath ?? m.thumbnailPath)
              .where((p) => p != null && p.isNotEmpty)
              .toSet();

          for (final m in deviceMedia) {
            final p = (m['filePath'] as String? ?? '').trim();
            if (p.isEmpty || existingPaths.contains(p)) continue;

            final ts = m['capturedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
            if (analyzed.timeRange != null) {
              if (ts < analyzed.timeRange!.startTime || ts > analyzed.timeRange!.endTime) {
                continue;
              }
            }

            final title = m['title'] as String? ?? 'Image';
            final type = m['type'] as String? ?? 'photo';

            if (analyzed.keywords.isNotEmpty) {
              final lowerTitle = title.toLowerCase();
              final matchesKw = analyzed.keywords.any((kw) => lowerTitle.contains(kw.toLowerCase()));
              if (!matchesKw) continue;
            }

            final newMem = Memory(
              id: 'media_${m['id'] ?? p.hashCode}',
              type: type,
              title: title,
              content: 'Captured $type: $title',
              source: (type == 'screenshot') ? 'System Screen' : 'Camera',
              sourceApp: (type == 'screenshot') ? 'System Screen' : 'Camera',
              filePath: p,
              thumbnailPath: p,
              capturedAt: ts,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );

            dbResults.add(newMem);
            existingPaths.add(p);
            // Save to SQLite asynchronously so it persists
            db.insertMemory(newMem);
          }
        } catch (_) {}
        break;

      case QueryIntent.callLogSearch:
        // 1. Fetch live native call logs to ensure 100% complete real-time data
        try {
          final liveLogs = await GlanceNativeBridge.getCallLogs();
          for (final call in liveLogs) {
            final callerName = call['callerName'] as String? ?? 'Phone Call';
            final phoneNum = call['phoneNumber'] as String? ?? '';
            final callType = call['callType'] as String? ?? 'Call';
            final duration = call['durationSeconds'] as int? ?? 0;
            final ts = call['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
            final title = '$callType: $callerName';
            final durStr = duration > 0 ? ' (${duration}s)' : '';
            final content = '$callType with $callerName ($phoneNum)$durStr';

            final mem = Memory(
              id: 'call_${callType}_${phoneNum}_$ts',
              type: 'call_log',
              title: title,
              content: content,
              source: 'Phone',
              sourceApp: 'Phone',
              capturedAt: ts,
              createdAt: ts,
              updatedAt: ts,
            );
            db.insertMemory(mem);
          }
        } catch (_) {}

        // 2. Query DB for all call log memories
        dbResults = await db.searchMemoriesSmart(
          type: 'call_log',
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          startTime: analyzed.timeRange?.startTime,
          endTime: analyzed.timeRange?.endTime,
          limit: 500,
        );

        // Fallback: If keywords were overly restrictive, retrieve all call logs
        if (dbResults.isEmpty) {
          dbResults = await db.searchMemoriesSmart(
            type: 'call_log',
            limit: 500,
          );
        }
        break;

      case QueryIntent.messageSearch:
        try {
          final liveSms = await GlanceNativeBridge.getSmsMessages();
          for (final sms in liveSms) {
            final sender = sms['sender'] as String? ?? 'SMS';
            final body = sms['body'] as String? ?? '';
            final smsType = sms['smsType'] as String? ?? 'Received SMS';
            final ts = sms['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
            final title = '$smsType: $sender';

            final mem = Memory(
              id: 'sms_${sender}_$ts',
              type: 'sms',
              title: title,
              content: body,
              source: 'Messages',
              sourceApp: 'Messages',
              capturedAt: ts,
              createdAt: ts,
              updatedAt: ts,
            );
            db.insertMemory(mem);
          }
        } catch (_) {}

        dbResults = await db.searchMemoriesSmart(
          type: 'sms',
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          limit: 500,
        );
        if (dbResults.isEmpty) {
          dbResults = await db.searchMemoriesSmart(type: 'sms', limit: 500);
        }
        break;

      case QueryIntent.notificationSearch:
        dbResults = await db.searchMemoriesSmart(
          type: 'notification',
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          sourceApp: analyzed.appName,
          startTime: analyzed.timeRange?.startTime,
          endTime: analyzed.timeRange?.endTime,
          limit: candidateLimit,
        );
        break;

      case QueryIntent.calendarSearch:
        try {
          final events = await GlanceNativeBridge.getCalendarEvents();
          for (final ev in events) {
            final title = ev['title'] as String? ?? 'Meeting';
            final desc = ev['description'] as String? ?? '';
            final ts = ev['startTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;
            final mem = Memory(
              id: 'cal_${title}_$ts',
              type: 'calendar_event',
              title: title,
              content: desc.isNotEmpty ? desc : title,
              source: 'Calendar',
              sourceApp: 'Calendar',
              capturedAt: ts,
              createdAt: ts,
              updatedAt: ts,
            );
            db.insertMemory(mem);
          }
        } catch (_) {}

        dbResults = await db.searchMemoriesSmart(
          sourceApp: 'Calendar',
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          startTime: analyzed.timeRange?.startTime,
          endTime: analyzed.timeRange?.endTime,
          limit: candidateLimit,
        );
        if (dbResults.isEmpty) {
          dbResults = await db.searchMemoriesSmart(
            keywords: ['meeting', 'calendar', 'event', ...analyzed.keywords],
            limit: candidateLimit,
          );
        }
        break;

      case QueryIntent.timeSearch:
        dbResults = await db.searchMemoriesSmart(
          sourceApp: analyzed.appName,
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          startTime: analyzed.timeRange?.startTime,
          endTime: analyzed.timeRange?.endTime,
          limit: candidateLimit,
        );
        // If no results with keywords, try time window only
        if (dbResults.isEmpty && analyzed.timeRange != null) {
          dbResults = await db.getMemoriesInTimeWindow(
            analyzed.timeRange!.startTime,
            analyzed.timeRange!.endTime,
          );
        }
        break;

      case QueryIntent.contentSearch:
        dbResults = await db.searchMemoriesSmart(
          query: userQuery,
          keywords: analyzed.keywords.isNotEmpty ? analyzed.keywords : null,
          startTime: analyzed.timeRange?.startTime,
          endTime: analyzed.timeRange?.endTime,
          limit: candidateLimit,
        );
        // Broader fallback
        if (dbResults.isEmpty && analyzed.keywords.isNotEmpty) {
          dbResults = await db.searchMemoriesSmart(
            keywords: analyzed.keywords,
            limit: candidateLimit,
          );
        }
        break;

      case QueryIntent.conversational:
        break;
    }

    // ── 3. Legacy FTS5 and vector search (if implemented) ────────────────
    final ftsChunks = await db.searchFTS5(userQuery, limit: candidateLimit);

    List<MapEntry<MemoryChunk, double>> vectorResults = [];
    try {
      final queryVector = await embeddingEngine.generateEmbedding(userQuery);
      vectorResults = await db.searchVectorCosine(queryVector, limit: candidateLimit);
    } catch (_) {}

    // ── 4. Build scored candidates from all sources ──────────────────────
    final candidateMap = <String, RetrievalCandidate>{};

    // Process smart DB results (primary path)
    for (int i = 0; i < dbResults.length; i++) {
      final mem = dbResults[i];
      if (candidateMap.containsKey(mem.id)) continue;

      // Create a virtual chunk from the memory content
      final chunk = MemoryChunk(
        id: '${mem.id}_chunk0',
        memoryId: mem.id,
        chunkIndex: 0,
        content: mem.content,
        tokenCount: (mem.content.split(' ').length * 1.25).ceil(),
        createdAt: mem.createdAt,
      );

      double relevanceScore = _calculateRelevanceScore(mem, analyzed, i, dbResults.length);
      double tempScore = _calculateTemporalScore(mem, analyzed.timeRange);
      double metaScore = _calculateMetadataScore(mem, userQuery);

      double finalScore = (relevanceScore * 0.50) + (metaScore * 0.25) + (tempScore * 0.25);

      candidateMap[mem.id] = RetrievalCandidate(
        memory: mem,
        chunk: chunk,
        vectorScore: relevanceScore,
        ftsScore: metaScore,
        temporalScore: tempScore,
        metadataScore: metaScore,
        finalScore: finalScore.clamp(0.0, 1.0),
      );
    }

    // Process legacy vector results if any
    for (final entry in vectorResults) {
      final chunk = entry.key;
      final vecSim = entry.value;
      if (candidateMap.containsKey(chunk.memoryId)) continue;

      final mem = await db.getMemory(chunk.memoryId);
      if (mem == null) continue;

      double tempScore = _calculateTemporalScore(mem, analyzed.timeRange);
      double metaScore = _calculateMetadataScore(mem, userQuery);
      double ftsScore = ftsChunks.any((c) => c.id == chunk.id) ? 0.8 : 0.0;

      double finalScore = (vecSim * 0.45) + (ftsScore * 0.35) + (tempScore * 0.10) + (metaScore * 0.10);

      if (finalScore >= minimumScore) {
        candidateMap[chunk.memoryId] = RetrievalCandidate(
          memory: mem,
          chunk: chunk,
          vectorScore: vecSim,
          ftsScore: ftsScore,
          temporalScore: tempScore,
          metadataScore: metaScore,
          finalScore: finalScore,
        );
      }
    }

    // Process legacy FTS5 results not already included
    for (final chunk in ftsChunks) {
      if (candidateMap.containsKey(chunk.memoryId)) continue;
      final mem = await db.getMemory(chunk.memoryId);
      if (mem == null) continue;

      double tempScore = _calculateTemporalScore(mem, analyzed.timeRange);
      double metaScore = _calculateMetadataScore(mem, userQuery);

      double finalScore = (0.2 * 0.45) + (1.0 * 0.35) + (tempScore * 0.10) + (metaScore * 0.10);

      if (finalScore >= minimumScore) {
        candidateMap[chunk.memoryId] = RetrievalCandidate(
          memory: mem,
          chunk: chunk,
          vectorScore: 0.2,
          ftsScore: 1.0,
          temporalScore: tempScore,
          metadataScore: metaScore,
          finalScore: finalScore,
        );
      }
    }

    // ── 5. Sort, filter unmatched items, and deduplicate ─────────────────
    final candidates = candidateMap.values.toList();

    // Filter out completely unmatched memories so only relevant items are returned
    final hasSpecificQuery = analyzed.keywords.isNotEmpty ||
        analyzed.appName != null ||
        analyzed.typeFilter != null;

    final isVisualSearch = analyzed.typeFilter == 'visual' ||
        analyzed.intent == QueryIntent.screenshotSearch;
    final isCallSearch = analyzed.intent == QueryIntent.callLogSearch ||
        analyzed.typeFilter == 'call_log' ||
        userQuery.toLowerCase().contains('call') ||
        userQuery.toLowerCase().contains('incoming') ||
        userQuery.toLowerCase().contains('outgoing') ||
        userQuery.toLowerCase().contains('missed');
    final isSmsSearch = analyzed.intent == QueryIntent.messageSearch ||
        analyzed.typeFilter == 'sms' ||
        userQuery.toLowerCase().contains('sms') ||
        userQuery.toLowerCase().contains('message');
    final isBroadQuery = analyzed.keywords.isEmpty ||
        userQuery.toLowerCase().contains('all') ||
        userQuery.toLowerCase().contains('entire') ||
        userQuery.toLowerCase().contains('have') ||
        userQuery.toLowerCase().contains('my data');

    final filtered = candidates.where((c) {
      if (isVisualSearch) {
        final isVisual = c.memory.type == 'screenshot' ||
            c.memory.type == 'photo' ||
            c.memory.type == 'camera_capture' ||
            c.memory.filePath != null ||
            c.memory.thumbnailPath != null;
        return isVisual;
      }

      if (isCallSearch) {
        final isCall = c.memory.type == 'call_log' ||
            c.memory.sourceApp?.toLowerCase() == 'phone' ||
            c.memory.title.toLowerCase().contains('call') ||
            c.memory.content.toLowerCase().contains('call');
        return isCall || c.finalScore >= 0.15;
      }

      if (isSmsSearch) {
        final isSms = c.memory.type == 'sms' ||
            c.memory.sourceApp?.toLowerCase() == 'messages' ||
            c.memory.title.toLowerCase().contains('sms') ||
            c.memory.content.toLowerCase().contains('sms');
        return isSms || c.finalScore >= 0.15;
      }

      if (!hasSpecificQuery) return c.finalScore >= 0.15;

      final hasTopicalMatch = c.vectorScore > 0.15 ||
          c.ftsScore > 0.15 ||
          c.metadataScore > 0.10 ||
          c.finalScore >= 0.18;

      return hasTopicalMatch;
    }).toList();

    filtered.sort((a, b) => b.finalScore.compareTo(a.finalScore));

    // If top candidate has a strong match, discard items that score far below it (unless broad visual/call/count search)
    if (!isVisualSearch && !isCallSearch && !isSmsSearch && !analyzed.isCountQuery && filtered.isNotEmpty && filtered.first.finalScore >= 0.50) {
      final topScore = filtered.first.finalScore;
      filtered.removeWhere((c) => c.finalScore < topScore * 0.42);
    }

    final toReturn = filtered.isNotEmpty ? filtered : candidates;
    final effectiveFinalLimit = (isVisualSearch || isBroadQuery || isCallSearch || isSmsSearch || analyzed.isCountQuery)
        ? 300
        : finalLimit;
    return _applyMMRDeduplication(toReturn, effectiveFinalLimit);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SCORING FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Calculates relevance score based on how well the memory matches the analyzed query.
  double _calculateRelevanceScore(Memory mem, AnalyzedQuery analyzed, int rank, int total) {
    double score = 0.0;

    // Position-based score (earlier SQL results are more relevant)
    score += (1.0 - (rank / total.clamp(1, 100))) * 0.2;

    // App name match
    if (analyzed.appName != null) {
      final appLower = analyzed.appName!.toLowerCase();
      if (mem.sourceApp?.toLowerCase().contains(appLower) == true) score += 0.35;
      if (mem.title.toLowerCase().contains(appLower)) score += 0.15;
      if (mem.sourcePackage?.toLowerCase().contains(appLower) == true) score += 0.25;
    }

    // Type match
    final isVisual = mem.type == 'screenshot' ||
        mem.type == 'photo' ||
        mem.type == 'camera_capture' ||
        mem.filePath != null ||
        mem.thumbnailPath != null;

    if (analyzed.typeFilter != null) {
      if (analyzed.typeFilter == 'visual' && isVisual) {
        score += 0.40;
      } else if (mem.type == analyzed.typeFilter) {
        score += 0.35;
      } else if (analyzed.typeFilter == 'copied_text' && mem.type == 'clipboard') {
        score += 0.35;
      }
    }

    // Keyword match in content, title, and tags
    List<String> tags = [];
    if (mem.summary != null && mem.summary!.isNotEmpty) {
      try {
        final map = jsonDecode(mem.summary!) as Map<String, dynamic>;
        if (map['tags'] is List) {
          tags.addAll((map['tags'] as List).map((e) => e.toString().toLowerCase()));
        }
        if (map['keywords'] is List) {
          tags.addAll((map['keywords'] as List).map((e) => e.toString().toLowerCase()));
        }
      } catch (_) {}
    }

    final isCall = mem.type == 'call_log' ||
        mem.sourceApp?.toLowerCase() == 'phone' ||
        mem.title.toLowerCase().contains('call') ||
        mem.content.toLowerCase().contains('call');
    if (analyzed.intent == QueryIntent.callLogSearch && isCall) {
      score += 0.45;
      final contentLower = '${mem.title} ${mem.content}'.toLowerCase();
      for (final type in analyzed.targetCallTypes) {
        if (contentLower.contains(type.toLowerCase())) {
          score += 0.25;
          break;
        }
      }
    }

    final isSms = mem.type == 'sms' ||
        mem.sourceApp?.toLowerCase() == 'messages' ||
        mem.title.toLowerCase().contains('sms') ||
        mem.content.toLowerCase().contains('sms');
    if (analyzed.intent == QueryIntent.messageSearch && isSms) {
      score += 0.45;
    }

    for (final kw in analyzed.keywords) {
      final kwLower = kw.toLowerCase();
      if (mem.content.toLowerCase().contains(kwLower)) score += 0.15;
      if (mem.title.toLowerCase().contains(kwLower)) score += 0.15;
      
      // Boost score if keyword matches a generated tag
      if (tags.any((t) => t.contains(kwLower))) {
        score += 0.25;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  /// Temporal scoring: awards 1.0 when matching requested timeRange; allows historical memories without penalty.
  double _calculateTemporalScore(Memory memory, TimeRange? timeRange) {
    if (timeRange != null) {
      if (memory.capturedAt >= timeRange.startTime && memory.capturedAt <= timeRange.endTime) {
        return 1.0;
      }
      return 0.1;
    }
    // When no explicit time range is requested, allow historical data (1 year, 10 years ago)
    // to compete equally based on actual content and relevance.
    return 0.75;
  }

  /// Metadata relevance scoring — matches source app and type mentions in query.
  double _calculateMetadataScore(Memory memory, String query) {
    final lower = query.toLowerCase();
    double score = 0.0;

    if (memory.sourceApp != null && lower.contains(memory.sourceApp!.toLowerCase())) {
      score += 0.5;
    }
    if (memory.type.isNotEmpty && lower.contains(memory.type.toLowerCase())) {
      score += 0.3;
    }

    // Boost call logs for call queries
    final isCall = memory.type == 'call_log' ||
        memory.sourceApp?.toLowerCase() == 'phone' ||
        memory.title.toLowerCase().contains('call') ||
        memory.content.toLowerCase().contains('call');
    if (isCall &&
        (lower.contains('call') ||
            lower.contains('incoming') ||
            lower.contains('outgoing') ||
            lower.contains('missed') ||
            lower.contains('phone') ||
            lower.contains('dial'))) {
      score += 0.6;
    }

    // Boost SMS for message queries
    final isSms = memory.type == 'sms' ||
        memory.sourceApp?.toLowerCase() == 'messages' ||
        memory.title.toLowerCase().contains('sms') ||
        memory.content.toLowerCase().contains('sms');
    if (isSms &&
        (lower.contains('sms') ||
            lower.contains('message') ||
            lower.contains('text'))) {
      score += 0.6;
    }

    // Boost visual memories for image/photo queries
    final isVisual = memory.type == 'screenshot' ||
        memory.type == 'photo' ||
        memory.type == 'camera_capture' ||
        memory.filePath != null ||
        memory.thumbnailPath != null;
    if (isVisual &&
        (lower.contains('image') ||
            lower.contains('photo') ||
            lower.contains('pic') ||
            lower.contains('screen') ||
            lower.contains('camera') ||
            lower.contains('media'))) {
      score += 0.4;
    }
    // Boost clipboard matches for copy/paste queries
    if ((memory.type == 'copied_text' || memory.type == 'clipboard') &&
        (lower.contains('cop') || lower.contains('paste') || lower.contains('clip'))) {
      score += 0.4;
    }
    return score.clamp(0.0, 1.0);
  }

  /// Maximal Marginal Relevance (MMR) to prevent duplicate chunk selection.
  List<RetrievalCandidate> _applyMMRDeduplication(
    List<RetrievalCandidate> candidates,
    int limit,
  ) {
    final selected = <RetrievalCandidate>[];
    final seenMemoryIds = <String>{};

    for (final cand in candidates) {
      if (seenMemoryIds.contains(cand.memory.id)) continue;
      selected.add(cand);
      seenMemoryIds.add(cand.memory.id);
      if (selected.length >= limit) break;
    }

    return selected;
  }
}
