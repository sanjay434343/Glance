import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Represents a primary memory entry in Glance.
class Memory {
  final String id;
  final String type; // screenshot, photo, pdf, url, copied_text, note, etc.
  final String title;
  final String content;
  final String? source;
  final String? sourceApp;
  final String? sourcePackage;
  final String? url;
  final String? filePath;
  final String? thumbnailPath;
  final String? imageBase64;
  final String? summary;
  final String? shaHash;
  final int capturedAt;
  final int createdAt;
  final int updatedAt;
  final String? sessionId;
  final String? locationId;
  final String? deviceId;
  final bool isFavorite;
  final bool isArchived;
  final bool isHidden;
  final bool isProcessed;

  Memory({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.source,
    this.sourceApp,
    this.sourcePackage,
    this.url,
    this.filePath,
    this.thumbnailPath,
    this.imageBase64,
    this.summary,
    this.shaHash,
    required this.capturedAt,
    required this.createdAt,
    required this.updatedAt,
    this.sessionId,
    this.locationId,
    this.deviceId,
    this.isFavorite = false,
    this.isArchived = false,
    this.isHidden = false,
    this.isProcessed = false,
  });

  Memory copyWith({
    String? id,
    String? type,
    String? title,
    String? content,
    String? source,
    String? sourceApp,
    String? sourcePackage,
    String? url,
    String? filePath,
    String? thumbnailPath,
    String? imageBase64,
    String? summary,
    String? shaHash,
    int? capturedAt,
    int? createdAt,
    int? updatedAt,
    String? sessionId,
    String? locationId,
    String? deviceId,
    bool? isFavorite,
    bool? isArchived,
    bool? isHidden,
    bool? isProcessed,
  }) {
    return Memory(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      source: source ?? this.source,
      sourceApp: sourceApp ?? this.sourceApp,
      sourcePackage: sourcePackage ?? this.sourcePackage,
      url: url ?? this.url,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      imageBase64: imageBase64 ?? this.imageBase64,
      summary: summary ?? this.summary,
      shaHash: shaHash ?? this.shaHash,
      capturedAt: capturedAt ?? this.capturedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionId: sessionId ?? this.sessionId,
      locationId: locationId ?? this.locationId,
      deviceId: deviceId ?? this.deviceId,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isHidden: isHidden ?? this.isHidden,
      isProcessed: isProcessed ?? this.isProcessed,
    );
  }

  /// Returns true if memory has a direct Base64 image copy in the database.
  bool get hasBase64Image => imageBase64 != null && imageBase64!.trim().isNotEmpty;

  /// Returns the image or thumbnail file path for visual rendering.
  String? get imagePath => filePath ?? thumbnailPath;

  /// Computes SHA-256 fingerprint for memory item using name, size, type, content, and file metadata.
  static String computeShaHash({
    required String title,
    required String type,
    required String content,
    String? filePath,
    String? sourceApp,
    String? sourcePackage,
  }) {
    int fileSize = content.length;
    String fileDescriptor = '';
    if (filePath != null && filePath.isNotEmpty) {
      try {
        final f = File(filePath);
        if (f.existsSync()) {
          fileSize = f.lengthSync();
          fileDescriptor = f.path.trim();
        }
      } catch (_) {}
    }

    final rawSig = 'name:${title.trim()}|type:${type.trim()}|size:$fileSize|path:$fileDescriptor|pkg:${sourcePackage ?? sourceApp ?? ''}|content:${content.trim()}';
    final bytes = utf8.encode(rawSig);
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'content': content,
      'source': source,
      'source_app': sourceApp,
      'source_package': sourcePackage,
      'url': url,
      'file_path': filePath,
      'thumbnail_path': thumbnailPath,
      'image_base64': imageBase64,
      'summary': summary,
      'sha_hash': shaHash ?? computeShaHash(
        title: title,
        type: type,
        content: content,
        filePath: filePath ?? thumbnailPath,
        sourceApp: sourceApp,
        sourcePackage: sourcePackage,
      ),
      'captured_at': capturedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'session_id': sessionId,
      'location_id': locationId,
      'device_id': deviceId,
      'is_favorite': isFavorite ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_hidden': isHidden ? 1 : 0,
      'is_processed': isProcessed ? 1 : 0,
    };
  }

  factory Memory.fromMap(Map<String, dynamic> map) {
    return Memory(
      id: map['id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      source: map['source'] as String?,
      sourceApp: map['source_app'] as String?,
      sourcePackage: map['source_package'] as String?,
      url: map['url'] as String?,
      filePath: map['file_path'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      imageBase64: map['image_base64'] as String?,
      summary: map['summary'] as String?,
      shaHash: map['sha_hash'] as String?,
      capturedAt: map['captured_at'] as int,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      sessionId: map['session_id'] as String?,
      locationId: map['location_id'] as String?,
      deviceId: map['device_id'] as String?,
      isFavorite: (map['is_favorite'] as int?) == 1,
      isArchived: (map['is_archived'] as int?) == 1,
      isHidden: (map['is_hidden'] as int?) == 1,
      isProcessed: (map['is_processed'] as int?) == 1,
    );
  }
}

/// Represents a text chunk derived from a Memory for RAG indexing.
class MemoryChunk {
  final String id;
  final String memoryId;
  final int chunkIndex;
  final String content;
  final int tokenCount;
  final int createdAt;

  MemoryChunk({
    required this.id,
    required this.memoryId,
    required this.chunkIndex,
    required this.content,
    required this.tokenCount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'memory_id': memoryId,
      'chunk_index': chunkIndex,
      'content': content,
      'token_count': tokenCount,
      'created_at': createdAt,
    };
  }

  factory MemoryChunk.fromMap(Map<String, dynamic> map) {
    return MemoryChunk(
      id: map['id'] as String,
      memoryId: map['memory_id'] as String,
      chunkIndex: map['chunk_index'] as int,
      content: map['content'] as String,
      tokenCount: map['token_count'] as int,
      createdAt: map['created_at'] as int,
    );
  }
}

/// Represents a vector embedding for a MemoryChunk.
class MemoryEmbedding {
  final String chunkId;
  final List<double> embedding;

  MemoryEmbedding({
    required this.chunkId,
    required this.embedding,
  });

  Map<String, dynamic> toMap() {
    return {
      'chunk_id': chunkId,
      'embedding': jsonEncode(embedding),
    };
  }

  factory MemoryEmbedding.fromMap(Map<String, dynamic> map) {
    final raw = map['embedding'];
    List<double> parsed;
    if (raw is String) {
      parsed = (jsonDecode(raw) as List).map((e) => (e as num).toDouble()).toList();
    } else if (raw is List) {
      parsed = raw.map((e) => (e as num).toDouble()).toList();
    } else {
      parsed = [];
    }
    return MemoryEmbedding(
      chunkId: map['chunk_id'] as String,
      embedding: parsed,
    );
  }
}

/// Graph relationship edge between two memories.
class MemoryRelationship {
  final String id;
  final String sourceMemoryId;
  final String targetMemoryId;
  final String relationshipType;
  final double strength;
  final int createdAt;

  MemoryRelationship({
    required this.id,
    required this.sourceMemoryId,
    required this.targetMemoryId,
    required this.relationshipType,
    required this.strength,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source_memory_id': sourceMemoryId,
      'target_memory_id': targetMemoryId,
      'relationship_type': relationshipType,
      'strength': strength,
      'created_at': createdAt,
    };
  }

  factory MemoryRelationship.fromMap(Map<String, dynamic> map) {
    return MemoryRelationship(
      id: map['id'] as String,
      sourceMemoryId: map['source_memory_id'] as String,
      targetMemoryId: map['target_memory_id'] as String,
      relationshipType: map['relationship_type'] as String,
      strength: (map['strength'] as num).toDouble(),
      createdAt: map['created_at'] as int,
    );
  }
}

/// Collection metadata model.
class CollectionModel {
  final String id;
  final String name;
  final String description;
  final String type;
  final int createdAt;

  CollectionModel({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.createdAt,
  });
}

/// Tag metadata model.
class TagModel {
  final String id;
  final String name;

  TagModel({required this.id, required this.name});
}

/// Location metadata model.
class LocationData {
  final String id;
  final double latitude;
  final double longitude;
  final double accuracy;
  final String placeName;
  final String city;
  final String country;

  LocationData({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.placeName,
    required this.city,
    required this.country,
  });
}

/// App activity session model.
class SessionData {
  final String id;
  final int startedAt;
  final int? endedAt;
  final String sourceApp;

  SessionData({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.sourceApp,
  });
}
