import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/models/memory_models.dart';
import 'widgets/related_memories_carousel.dart';

class LocationDetailScreen extends StatelessWidget {
  final Memory memory;

  const LocationDetailScreen({super.key, required this.memory});

  (double, double)? _extractCoordinates(Memory mem) {
    final text = '${mem.url ?? ''} ${mem.content} ${mem.title}';

    // Pattern 1: @lat,lng, e.g. @37.7749,-122.4194
    final atMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }

    // Pattern 2: q=lat,lng or ll=lat,lng or loc:lat,lng
    final qMatch = RegExp(r'(?:q|ll|loc:)=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1)!);
      final lng = double.tryParse(qMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }

    // Pattern 3: lat,lng pair like "37.7749, -122.4194"
    final pairMatch = RegExp(r'(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)').firstMatch(text);
    if (pairMatch != null) {
      final lat = double.tryParse(pairMatch.group(1)!);
      final lng = double.tryParse(pairMatch.group(2)!);
      if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        return (lat, lng);
      }
    }

    return null;
  }

  String _formatCoordinates((double, double)? coords) {
    if (coords == null) return '35.6595° N, 139.7005° E';
    final lat = coords.$1;
    final lng = coords.$2;
    final latDir = lat >= 0 ? 'N' : 'S';
    final lngDir = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}° $latDir, ${lng.abs().toStringAsFixed(4)}° $lngDir';
  }

  String _formatShortCoordinates((double, double)? coords) {
    if (coords == null) return '35.65, 139.70';
    return '${coords.$1.toStringAsFixed(2)}, ${coords.$2.toStringAsFixed(2)}';
  }

  String _getDisplayTitle() {
    if (memory.title.isNotEmpty && memory.title != 'Saved Map Location') {
      return memory.title;
    }
    // Try to extract place name from content if available
    if (memory.content.isNotEmpty) {
      final cleaned = memory.content.replaceAll(RegExp(r'^Map Location:\s*', caseSensitive: false), '').trim();
      if (cleaned.isNotEmpty && !cleaned.startsWith('http')) {
        final firstLine = cleaned.split('\n').first.trim();
        if (firstLine.length <= 40) return firstLine;
      }
    }
    return 'Saved Map Location';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    // Expressive M3 palette with pure white background in light mode
    final bgColor = isDark ? const Color(0xFF121315) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E2024) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final buttonColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1D21);
    const buttonIconColor = Colors.white;
    final borderColor = isDark ? const Color(0xFF2E3238) : const Color(0xFFE2E8F0);

    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(memory.capturedAt),
    );

    final coords = _extractCoordinates(memory);
    final coordinatesStr = _formatCoordinates(coords);
    final coordShortBadge = _formatShortCoordinates(coords);
    final displayTitle = _getDisplayTitle();

    // Auto-generate tags from title and content
    final stopWords = {
      'this', 'like', 'that', 'with', 'from', 'have', 'your', 'about',
      'will', 'what', 'when', 'where', 'which', 'there', 'their', 'they',
      'them', 'some', 'than', 'then', 'also', 'http', 'https', 'com', 'org',
      'www', 'maps', 'location', 'google'
    };
    final combinedText = '$displayTitle ${memory.content}';
    final words = combinedText
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z]+'))
        .where((w) => w.length > 3 && !stopWords.contains(w))
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .toSet()
        .toList();

    final sourceApp = memory.sourceApp?.replaceAll(RegExp(r'^com\.[^.]+\.'), '') ?? 'Google Maps';
    final allTags = ['Location', 'Map', 'GPS', if (memory.sourceApp != null) sourceApp, ...words];
    final displayTags = allTags.toSet().take(8).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: buttonColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: buttonIconColor,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  final textToCopy = memory.url ?? coordinatesStr;
                  Clipboard.setData(ClipboardData(text: textToCopy));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Location details copied to clipboard!',
                        style: TextStyle(fontFamily: 'DMSans'),
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.copy_rounded,
                    color: buttonIconColor,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ==========================================
              // HERO PREVIEW CARD (Material 3 Expressive)
              // ==========================================
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                width: double.infinity,
                height: 360,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181A1D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Vector Stylized Map Canvas
                      CustomPaint(
                        painter: _MapCanvasPainter(
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                      ),

                      // Center Map Marker & Floating Badge
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: (isDark ? const Color(0xFF1E2024) : Colors.white).withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF383C44) : const Color(0xFFE2E8F0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.place_rounded, size: 16, color: primaryColor),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE11D48),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Top-Left Source Pill
                      Positioned(
                        top: 20,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_rounded,
                                size: 14,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'MAP LOCATION',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Top-Right Quick Copy Icon Button
                      Positioned(
                        top: 20,
                        right: 20,
                        child: GestureDetector(
                          onTap: () {
                            final textToCopy = memory.url ?? coordinatesStr;
                            Clipboard.setData(ClipboardData(text: textToCopy));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Location coordinates copied!'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A2D34) : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.copy_rounded,
                              color: isDark ? Colors.white : Colors.black87,
                              size: 18,
                            ),
                          ),
                        ),
                      ),

                      // Bottom-Left Date Pill
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2A2D34) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                      // Bottom-Right Coordinates Pill
                      Positioned(
                        bottom: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF22252A)
                                : const Color(0xFFEAEFF5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            coordShortBadge,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // TITLE & METADATA CHIPS
                    // ==========================================
                    Text(
                      displayTitle,
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'DMSans',
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                        letterSpacing: -0.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Metadata Pill Badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaBadge(
                          icon: Icons.place_rounded,
                          label: 'Saved Location',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        _buildMetaBadge(
                          icon: Icons.my_location_rounded,
                          label: coordShortBadge,
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        _buildMetaBadge(
                          icon: Icons.schedule_rounded,
                          label: 'Visited',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        if (memory.sourceApp != null)
                          _buildMetaBadge(
                            icon: Icons.apps_rounded,
                            label: sourceApp,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ==========================================
                    // TAGS SECTION (Under the Title)
                    // ==========================================
                    Row(
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 16,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TAGS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: displayTags.map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF25282E)
                                : const Color(0xFFF1F4F9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF383C44)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '#',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 28),

                    // ==========================================
                    // LOCATION METADATA INSPECTOR CARD
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.explore_rounded,
                                    size: 18,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'LOCATION METADATA',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: coordinatesStr),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        'Coordinates copied to clipboard',
                                        style: TextStyle(fontFamily: 'DMSans'),
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('Copy'),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          _buildInspectorRow('Place Name', displayTitle, textColor, textSecondary),
                          const SizedBox(height: 12),
                          _buildInspectorRow('Coordinates', coordinatesStr, textColor, textSecondary),
                          const SizedBox(height: 12),
                          _buildInspectorRow('Visited Time', dateStr, textColor, textSecondary),
                          if (memory.url != null && memory.url!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildInspectorRow('Map URL', memory.url!, textColor, textSecondary, isUrl: true),
                          ],
                          if (memory.content.isNotEmpty && memory.content != memory.title) ...[
                            const SizedBox(height: 12),
                            _buildInspectorRow('Content', memory.content, textColor, textSecondary),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ==========================================
                    // RELATED CAPTURES CAROUSEL
                    // ==========================================
                    RelatedMemoriesCarousel(
                      currentMemory: memory,
                      tags: displayTags,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorRow(
    String label,
    String value,
    Color textColor,
    Color textSecondary, {
    bool isUrl = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isUrl ? const Color(0xFF3B82F6) : textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaBadge({
    required IconData icon,
    required String label,
    required bool isDark,
    required Color primaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF22252A) : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF333740) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[300] : const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for a modern, expressive stylized vector map surface
class _MapCanvasPainter extends CustomPainter {
  final bool isDark;
  final Color primaryColor;

  _MapCanvasPainter({required this.isDark, required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Base map land surface
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF131518) : const Color(0xFFF1F5F9);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 2. Water body / River path
    final waterPaint = Paint()
      ..color = isDark ? const Color(0xFF192530) : const Color(0xFFDFEDFA)
      ..style = PaintingStyle.fill;

    final riverPath = Path()
      ..moveTo(0, size.height * 0.25)
      ..cubicTo(
        size.width * 0.35, size.height * 0.15,
        size.width * 0.65, size.height * 0.45,
        size.width, size.height * 0.35,
      )
      ..lineTo(size.width, size.height * 0.50)
      ..cubicTo(
        size.width * 0.65, size.height * 0.60,
        size.width * 0.35, size.height * 0.30,
        0, size.height * 0.40,
      )
      ..close();
    canvas.drawPath(riverPath, waterPaint);

    // 3. Green Park zones
    final parkPaint = Paint()
      ..color = isDark ? const Color(0xFF18241C) : const Color(0xFFE8F5E9)
      ..style = PaintingStyle.fill;

    final park1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.08, size.height * 0.65, size.width * 0.28, size.height * 0.24),
      const Radius.circular(16),
    );
    canvas.drawRRect(park1, parkPaint);

    final park2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.68, size.height * 0.08, size.width * 0.24, size.height * 0.20),
      const Radius.circular(16),
    );
    canvas.drawRRect(park2, parkPaint);

    // 4. Secondary road network
    final roadPaint = Paint()
      ..color = isDark ? const Color(0xFF20242B) : const Color(0xFFE2E8F0)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Horizontal grid roads
    for (double y = 40; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }
    // Vertical grid roads
    for (double x = 40; x < size.width; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }

    // 5. Major thoroughfare / Highway avenues
    final avenueUnderPaint = Paint()
      ..color = isDark ? const Color(0xFF262C36) : const Color(0xFFCBD5E1)
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final avenuePaint = Paint()
      ..color = isDark ? const Color(0xFF2E3542) : Colors.white
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final diagPath = Path()
      ..moveTo(0, size.height * 0.85)
      ..cubicTo(
        size.width * 0.35, size.height * 0.70,
        size.width * 0.65, size.height * 0.30,
        size.width, size.height * 0.15,
      );
    canvas.drawPath(diagPath, avenueUnderPaint);
    canvas.drawPath(diagPath, avenuePaint);

    final crossPath = Path()
      ..moveTo(size.width * 0.2, 0)
      ..cubicTo(
        size.width * 0.3, size.height * 0.4,
        size.width * 0.7, size.height * 0.6,
        size.width * 0.85, size.height,
      );
    canvas.drawPath(crossPath, avenueUnderPaint);
    canvas.drawPath(crossPath, avenuePaint);

    // 6. Center Radar Pulse Beacon
    final center = Offset(size.width / 2, size.height / 2 + 10);

    final radarPaint3 = Paint()
      ..color = primaryColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 70, radarPaint3);

    final radarPaint2 = Paint()
      ..color = primaryColor.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 46, radarPaint2);

    final radarPaint1 = Paint()
      ..color = primaryColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 24, radarPaint1);

    final radarRing = Paint()
      ..color = primaryColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 46, radarRing);
  }

  @override
  bool shouldRepaint(covariant _MapCanvasPainter oldDelegate) {
    return oldDelegate.isDark != isDark || oldDelegate.primaryColor != primaryColor;
  }
}
