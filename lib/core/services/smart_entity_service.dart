import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

import '../database/glance_db.dart';
import '../models/memory_models.dart';

/// Service responsible for extracting and validating smart entities (OTPs, Phone numbers,
/// URLs, Emails, Addresses, DateTimes) from memories and saving them into SQLite `summary`
/// so that the RAG retrieval engine and search system can instantly query them.
class SmartEntityService {
  static final SmartEntityService instance = SmartEntityService._internal();
  SmartEntityService._internal();

  // ── Validation Helpers ─────────────────────────────────────────────────────

  static bool isValidPhoneNumber(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');

    if (digits.length < 10 || digits.length > 15) return false;
    if (RegExp(r'^(100|050|000|038|062|085|\s)+$').hasMatch(cleaned)) return false;
    if (RegExp(r'(\d{2,3})\s+\1\s+\1').hasMatch(cleaned)) return false;

    final isStandardPhone = RegExp(
      r'^\+?[0-9]{1,4}?[-.\s]?\(?[0-9]{1,4}?\)?[-.\s]?[0-9]{3,4}[-.\s]?[0-9]{3,4}$',
    ).hasMatch(cleaned);
    final isMobile = RegExp(r'^(\+91[\-\s]?)?[6-9]\d{9}$').hasMatch(digits);

    return isStandardPhone || isMobile;
  }

  static bool isValidUrl(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '').trim();

    final degreeAbbr = RegExp(
      r'^(B|M|D)\.(Sc|Se|E|Tech|Com|Ed|A|Phil|Pharm|Arch)$',
      caseSensitive: false,
    );
    if (degreeAbbr.hasMatch(cleaned)) return false;

    if (cleaned.startsWith('http://') ||
        cleaned.startsWith('https://') ||
        cleaned.startsWith('www.')) {
      return true;
    }

    final webDomain = RegExp(
      r'^[a-zA-Z0-9][-a-zA-Z0-9]*\.(com|org|net|edu|gov|io|ai|in|co|app)(\/.*)?$',
      caseSensitive: false,
    );
    return webDomain.hasMatch(cleaned);
  }

  static bool isValidEmail(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.trim();
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(cleaned);
  }

  static bool isValidAddress(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.trim();
    return cleaned.length >= 6 && RegExp(r'[a-zA-Z]').hasMatch(cleaned);
  }

  static bool isValidDateTime(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.trim();
    if (RegExp(r'^\d{1,3}$').hasMatch(cleaned)) return false;
    return cleaned.length >= 4;
  }

  // ── Extraction Logic ───────────────────────────────────────────────────────

  /// Extracts validated smart entities from raw text.
  /// Returns a map of type -> list of extracted values, e.g.:
  /// { 'OTP': ['123456'], 'PHONE': ['+1234567890'], 'EMAIL': ['test@gmail.com'] }
  Future<Map<String, List<String>>> extractEntities(String text) async {
    final Map<String, List<String>> result = {};
    final trimmed = text.trim();
    if (trimmed.length < 4) return result;

    void addEntity(String type, String value) {
      final val = value.trim();
      if (val.isEmpty) return;
      result.putIfAbsent(type, () => []);
      if (!result[type]!.contains(val)) {
        result[type]!.add(val);
      }
    }

    // 1. Extract OTPs / PINs
    final otpRegExp = RegExp(r'(?<!\d)(\d{4,8})(?!\d)');
    final matches = otpRegExp.allMatches(trimmed);
    for (final match in matches) {
      final otpStr = match.group(1)!;
      final startIndex = (match.start - 30).clamp(0, trimmed.length);
      final endIndex = (match.end + 30).clamp(0, trimmed.length);
      final surrounding = trimmed.substring(startIndex, endIndex).toLowerCase();

      if (surrounding.contains('otp') ||
          surrounding.contains('pin') ||
          surrounding.contains('code') ||
          surrounding.contains('verification') ||
          surrounding.contains('password')) {
        addEntity('OTP_PIN', otpStr);
      }
    }

    // 2. ML Kit Entity Extractor for Phone, Email, URL, Address, DateTime
    try {
      final sampleText = trimmed.length > 1500 ? trimmed.substring(0, 1500) : trimmed;
      final entityExtractor = EntityExtractor(language: EntityExtractorLanguage.english);
      final rawEntities = await entityExtractor
          .annotateText(sampleText)
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
      await entityExtractor.close();

      for (final annotation in rawEntities) {
        final type = annotation.entities.first.type;
        final entText = annotation.text;

        if (type == EntityType.phone && isValidPhoneNumber(entText)) {
          addEntity('PHONE', entText);
        } else if (type == EntityType.url && isValidUrl(entText)) {
          addEntity('URL', entText);
        } else if (type == EntityType.email && isValidEmail(entText)) {
          addEntity('EMAIL', entText);
        } else if (type == EntityType.address && isValidAddress(entText)) {
          addEntity('ADDRESS', entText);
        } else if (type == EntityType.dateTime && isValidDateTime(entText)) {
          addEntity('DATETIME', entText);
        }
      }
    } catch (e) {
      debugPrint('[SmartEntityService] ML Kit extraction error: $e');
    }

    return result;
  }

  /// Extracts entities from text and merges them into the memory's `summary` JSON field.
  /// Returns a clean JSON string with an `entities` object and `tags` list.
  Future<String?> extractAndBuildSummary(String text, {String? existingSummary}) async {
    final entities = await extractEntities(text);
    if (entities.isEmpty && (existingSummary == null || existingSummary.isEmpty)) {
      return null;
    }

    Map<String, dynamic> summaryMap = {};
    if (existingSummary != null && existingSummary.isNotEmpty) {
      try {
        final decoded = jsonDecode(existingSummary);
        if (decoded is Map<String, dynamic>) {
          summaryMap = Map<String, dynamic>.from(decoded);
        } else if (decoded is List) {
          summaryMap['tags'] = decoded;
        }
      } catch (_) {}
    }

    // Merge entities map
    final existingEntities = summaryMap['entities'] is Map ? Map<String, dynamic>.from(summaryMap['entities'] as Map) : <String, dynamic>{};
    for (final entry in entities.entries) {
      existingEntities[entry.key] = entry.value;
    }
    if (existingEntities.isNotEmpty) {
      summaryMap['entities'] = existingEntities;
    }

    // Merge into searchable tags list: e.g. ["PHONE: 9876543210", "OTP_PIN: 4829"]
    final List<String> tagList = summaryMap['tags'] is List
        ? (summaryMap['tags'] as List).map((e) => e.toString()).toList()
        : <String>[];

    for (final entry in entities.entries) {
      for (final val in entry.value) {
        final tag = '${entry.key}: $val';
        if (!tagList.contains(tag)) {
          tagList.add(tag);
        }
        if (!tagList.contains(val)) {
          tagList.add(val);
        }
      }
    }
    if (tagList.isNotEmpty) {
      summaryMap['tags'] = tagList;
    }

    return jsonEncode(summaryMap);
  }

  /// Helper to extract entities and immediately update a Memory in GlanceDatabase.
  Future<Memory> enrichMemoryWithEntities(Memory memory, {GlanceDatabase? dbInstance}) async {
    final db = dbInstance ?? GlanceDatabase.instance;
    final textToAnalyze = '${memory.title}\n${memory.content}'.trim();
    final newSummary = await extractAndBuildSummary(textToAnalyze, existingSummary: memory.summary);

    if (newSummary != null && newSummary != memory.summary) {
      final updated = memory.copyWith(
        summary: newSummary,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await db.insertMemory(updated);
      return updated;
    }
    return memory;
  }
}
