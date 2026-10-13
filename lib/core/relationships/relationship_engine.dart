import 'package:uuid/uuid.dart';

import '../models/memory_models.dart';

/// Relationship generator linking correlated memories in the offline graph database.
class RelationshipEngine {
  static final _uuid = const Uuid();

  /// Analyzes recent memories and automatically connects them with graph edges.
  static List<MemoryRelationship> computeRelationships(
    Memory newMemory,
    List<Memory> existingMemories,
  ) {
    final relationships = <MemoryRelationship>[];
    final now = newMemory.capturedAt;

    for (final existing in existingMemories) {
      if (existing.id == newMemory.id) continue;

      // 1. Same Session
      if (newMemory.sessionId != null && newMemory.sessionId == existing.sessionId) {
        relationships.add(MemoryRelationship(
          id: _uuid.v4(),
          sourceMemoryId: newMemory.id,
          targetMemoryId: existing.id,
          relationshipType: 'same_session',
          strength: 0.9,
          createdAt: now,
        ));
      }

      // 2. Same Application
      if (newMemory.sourceApp != null && newMemory.sourceApp == existing.sourceApp) {
        relationships.add(MemoryRelationship(
          id: _uuid.v4(),
          sourceMemoryId: newMemory.id,
          targetMemoryId: existing.id,
          relationshipType: 'same_app',
          strength: 0.7,
          createdAt: now,
        ));
      }

      // 3. Same URL
      if (newMemory.url != null && newMemory.url == existing.url) {
        relationships.add(MemoryRelationship(
          id: _uuid.v4(),
          sourceMemoryId: newMemory.id,
          targetMemoryId: existing.id,
          relationshipType: 'same_url',
          strength: 0.95,
          createdAt: now,
        ));
      }

      // 4. Same Time Window (within 5 minutes)
      final diff = (newMemory.capturedAt - existing.capturedAt).abs();
      if (diff <= 5 * 60 * 1000) {
        relationships.add(MemoryRelationship(
          id: _uuid.v4(),
          sourceMemoryId: newMemory.id,
          targetMemoryId: existing.id,
          relationshipType: 'same_time_window',
          strength: 0.8,
          createdAt: now,
        ));

        if (newMemory.capturedAt > existing.capturedAt) {
          relationships.add(MemoryRelationship(
            id: _uuid.v4(),
            sourceMemoryId: newMemory.id,
            targetMemoryId: existing.id,
            relationshipType: 'after',
            strength: 0.85,
            createdAt: now,
          ));
        } else {
          relationships.add(MemoryRelationship(
            id: _uuid.v4(),
            sourceMemoryId: newMemory.id,
            targetMemoryId: existing.id,
            relationshipType: 'before',
            strength: 0.85,
            createdAt: now,
          ));
        }
      }

      // 5. Copied text / Screenshot of webpage
      if (newMemory.type == 'copied_text' && existing.type == 'webpage' && diff <= 2 * 60 * 1000) {
        relationships.add(MemoryRelationship(
          id: _uuid.v4(),
          sourceMemoryId: newMemory.id,
          targetMemoryId: existing.id,
          relationshipType: 'copied_from',
          strength: 0.95,
          createdAt: now,
        ));
      }

      if (newMemory.type == 'screenshot' && existing.type == 'webpage' && diff <= 2 * 60 * 1000) {
        relationships.add(MemoryRelationship(
          id: _uuid.v4(),
          sourceMemoryId: newMemory.id,
          targetMemoryId: existing.id,
          relationshipType: 'screenshot_of',
          strength: 0.95,
          createdAt: now,
        ));
      }
    }

    return relationships;
  }
}
