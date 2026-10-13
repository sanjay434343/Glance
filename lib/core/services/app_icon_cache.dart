import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../database/glance_db.dart';
import '../native/glance_native_bridge.dart';

/// High-performance in-memory cache for decoded application icons.
/// Eliminates repeated base64 decoding and SQLite queries during UI scrolls.
class AppIconCache {
  static final Map<String, Uint8List> _bytesCache = {};
  static final Map<String, Future<Uint8List?>> _inFlightLoads = {};

  /// Synchronously retrieve cached decoded icon bytes if available.
  static Uint8List? getSync(String packageName) {
    return _bytesCache[packageName];
  }

  /// Manually store base64 or decoded bytes in memory.
  static void cacheBase64(String packageName, String base64String) {
    if (base64String.isEmpty) return;
    try {
      _bytesCache[packageName] = base64Decode(base64String);
    } catch (_) {}
  }

  static void cacheBytes(String packageName, Uint8List bytes) {
    _bytesCache[packageName] = bytes;
  }

  /// Asynchronously retrieve icon bytes, checking memory -> database -> native bridge.
  static Future<Uint8List?> loadIcon(String packageName) async {
    if (_bytesCache.containsKey(packageName)) {
      return _bytesCache[packageName];
    }

    if (_inFlightLoads.containsKey(packageName)) {
      return await _inFlightLoads[packageName];
    }

    final future = _loadIconInternal(packageName);
    _inFlightLoads[packageName] = future;
    try {
      return await future;
    } finally {
      _inFlightLoads.remove(packageName);
    }
  }

  static Future<Uint8List?> _loadIconInternal(String packageName) async {
    // 1. Check SQLite database
    try {
      final dbBase64 = await GlanceDatabase.instance.getAppIcon(packageName);
      if (dbBase64 != null && dbBase64.isNotEmpty) {
        final bytes = base64Decode(dbBase64);
        _bytesCache[packageName] = bytes;
        return bytes;
      }
    } catch (_) {}

    // 2. Fallback to Android Native Bridge
    try {
      final nativeBase64 = await GlanceNativeBridge.getAppIcon(packageName);
      if (nativeBase64 != null && nativeBase64.isNotEmpty) {
        final bytes = base64Decode(nativeBase64);
        _bytesCache[packageName] = bytes;
        await GlanceDatabase.instance.saveAppIcon(packageName, nativeBase64);
        return bytes;
      }
    } catch (_) {}

    return null;
  }
}

/// A lightweight, frame-rate optimized widget for rendering app icons.
class AppIconWidget extends StatefulWidget {
  final String packageName;
  final double size;
  final Widget fallbackIcon;
  final BorderRadius? borderRadius;

  const AppIconWidget({
    super.key,
    required this.packageName,
    this.size = 52,
    required this.fallbackIcon,
    this.borderRadius,
  });

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolveIcon();
  }

  @override
  void didUpdateWidget(covariant AppIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      _resolveIcon();
    }
  }

  void _resolveIcon() {
    final cached = AppIconCache.getSync(widget.packageName);
    if (cached != null) {
      _bytes = cached;
      return;
    }

    AppIconCache.loadIcon(widget.packageName).then((bytes) {
      if (mounted) {
        setState(() {
          _bytes = bytes;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pixelSize = (widget.size * 2).toInt();

    if (_bytes != null) {
      Widget image = Image.memory(
        _bytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: pixelSize,
        cacheHeight: pixelSize,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => widget.fallbackIcon,
      );

      if (widget.borderRadius != null) {
        image = ClipRRect(
          borderRadius: widget.borderRadius!,
          child: image,
        );
      }
      return image;
    }

    return widget.fallbackIcon;
  }
}
