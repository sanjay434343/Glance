import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/database/glance_db.dart';
import '../../core/models/memory_models.dart';
import 'widgets/related_memories_carousel.dart';

class ImageDetailScreen extends StatefulWidget {
  final Memory memory;
  final List<Memory>? sameTimeMemories;

  const ImageDetailScreen({
    super.key,
    required this.memory,
    this.sameTimeMemories,
  });

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen> {
  late List<Memory> _images;
  int _selectedIndex = 0;
  late PageController _pageController;

  List<Memory> _deduplicateSameTimeMemories(List<Memory> input) {
    final List<Memory> result = [];
    for (final mem in input) {
      bool isExactDuplicate = false;
      for (final existing in result) {
        final sameFile =
            (mem.filePath ?? '') == (existing.filePath ?? '') &&
            (mem.thumbnailPath ?? '') == (existing.thumbnailPath ?? '');
        final sameTitle = mem.title.trim() == existing.title.trim();
        final sameContent = mem.content.trim() == existing.content.trim();
        final sameTime = mem.capturedAt == existing.capturedAt;

        if (sameFile && sameTitle && sameContent && sameTime) {
          isExactDuplicate = true;
          break;
        }
        if (mem.filePath != null &&
            mem.filePath!.isNotEmpty &&
            mem.filePath == existing.filePath &&
            sameContent) {
          isExactDuplicate = true;
          break;
        }
      }
      if (!isExactDuplicate) {
        result.add(mem);
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _images = _deduplicateSameTimeMemories(
      widget.sameTimeMemories != null && widget.sameTimeMemories!.isNotEmpty
          ? widget.sameTimeMemories!
          : [widget.memory],
    );

    _selectedIndex = _images.indexWhere((m) => m.id == widget.memory.id);
    if (_selectedIndex == -1) _selectedIndex = 0;

    _pageController = PageController(initialPage: _selectedIndex);

    if (widget.sameTimeMemories == null) {
      _loadSameTimeImages();
    }
  }

  Future<void> _loadSameTimeImages() async {
    try {
      final startTime = widget.memory.capturedAt - 60000;
      final endTime = widget.memory.capturedAt + 60000;
      final rangeMemories = await GlanceDatabase.instance
          .getMemoriesInTimeWindow(startTime, endTime);
      final imageTypes = {'screenshot', 'photo', 'camera_capture'};
      final sameTime = rangeMemories
          .where((m) => imageTypes.contains(m.type.toLowerCase()))
          .toList();

      if (sameTime.isNotEmpty) {
        if (!sameTime.any((m) => m.id == widget.memory.id)) {
          sameTime.add(widget.memory);
        }
        sameTime.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
        final deduped = _deduplicateSameTimeMemories(sameTime);
        if (mounted) {
          setState(() {
            _images = deduped;
            _selectedIndex = _images.indexWhere(
              (m) => m.id == widget.memory.id,
            );
            if (_selectedIndex == -1) _selectedIndex = 0;
            _pageController = PageController(initialPage: _selectedIndex);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getCleanTitle(Memory mem) {
    // 1. Try reading title from JSON in mem.summary
    try {
      if (mem.summary != null && mem.summary!.isNotEmpty) {
        final map = jsonDecode(mem.summary!) as Map<String, dynamic>;
        if (map['title'] != null && map['title'].toString().trim().isNotEmpty) {
          final t = map['title'].toString().trim();
          if (t != 'Captured Image' &&
              t != 'Captured Screenshot' &&
              t != 'Image Capture' &&
              !t.toLowerCase().startsWith('photo_') &&
              !t.toLowerCase().startsWith('screenshot_')) {
            return t;
          }
        }
      }
    } catch (_) {}

    // 2. Try mem.title if it's not a generic default
    String title = mem.title.trim();
    if (title.isNotEmpty) {
      final lower = title.toLowerCase();
      if (!lower.startsWith('photo_') &&
          !lower.startsWith('screenshot_') &&
          !lower.startsWith('com.') &&
          lower != 'photo' &&
          lower != 'screenshot' &&
          lower != 'image capture' &&
          lower != 'captured image' &&
          lower != 'captured screenshot' &&
          lower != 'photo memory' &&
          lower != 'screenshot memory') {
        return title;
      }
    }

    // 3. Try clean filename if not generic
    if (mem.filePath != null && mem.filePath!.isNotEmpty) {
      final file = File(mem.filePath!);
      final fileName = file.uri.pathSegments.last;
      if (fileName.isNotEmpty &&
          !fileName.startsWith('photo_') &&
          !fileName.startsWith('screenshot_')) {
        return fileName;
      }
    }

    final typeLower = mem.type.toLowerCase();
    if (typeLower == 'screenshot') {
      return 'Captured Screenshot';
    }
    if (typeLower == 'photo' || typeLower == 'camera_capture') {
      return 'Captured Image';
    }
    return title.isNotEmpty ? title : 'Captured Image';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Expressive M3 palette with pure white background in light mode
    final bgColor = isDark ? const Color(0xFF121315) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final buttonColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFF1A1D21); // Dark button background
    final buttonIconColor = isDark
        ? Colors.white
        : Colors.white; // White icons on dark buttons

    final currentMemory = _images.length > _selectedIndex
        ? _images[_selectedIndex]
        : widget.memory;
    final cleanTitle = _getCleanTitle(currentMemory);
    final dateStr = DateFormat(
      'MMM d, yyyy • h:mm a',
    ).format(DateTime.fromMillisecondsSinceEpoch(currentMemory.capturedAt));

    // Extract JSON metadata (title, subtitle, description, tags)
    String? jsonSubtitle;
    String? jsonDescription;
    List<String> tags = [];

    try {
      if (currentMemory.summary != null && currentMemory.summary!.isNotEmpty) {
        final map = jsonDecode(currentMemory.summary!) as Map<String, dynamic>;
        if (map['subtitle'] != null &&
            map['subtitle'].toString().trim().isNotEmpty) {
          jsonSubtitle = map['subtitle'].toString().trim();
        }
        if (map['description'] != null &&
            map['description'].toString().trim().isNotEmpty) {
          jsonDescription = map['description'].toString().trim();
        } else if (map['summary'] != null &&
            map['summary'].toString().trim().isNotEmpty) {
          jsonDescription = map['summary'].toString().trim();
        }
        if (map['tags'] is List) {
          tags.addAll(
            (map['tags'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
        } else if (map['keywords'] is List) {
          tags.addAll(
            (map['keywords'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
        }
      }
    } catch (_) {}

    if (tags.isEmpty) {
      if (currentMemory.type.toLowerCase() == 'screenshot') {
        tags.add('Screenshot');
      }
      if (currentMemory.type.toLowerCase() == 'photo' ||
          currentMemory.type.toLowerCase() == 'camera_capture') {
        tags.add('Photo');
      }
      tags.addAll(['Vision AI', 'Image']);
    }
    tags = tags.toSet().toList(); // Deduplicate

    final isProcessing = currentMemory.summary == null || currentMemory.summary!.trim().isEmpty;

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
                child: Icon(
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
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: buttonColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: buttonIconColor,
                  size: 20,
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

            // Hero Image Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              width: double.infinity,
              height: 380,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
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
                    // The Image
                    PageView.builder(
                      controller: _pageController,
                      itemCount: _images.length,
                      onPageChanged: (index) =>
                          setState(() => _selectedIndex = index),
                      itemBuilder: (context, index) {
                        final mem = _images[index];
                        if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
                          return Image.memory(
                            base64Decode(mem.imageBase64!.trim()),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          );
                        }
                        final path = (mem.filePath != null && mem.filePath!.isNotEmpty)
                            ? mem.filePath
                            : mem.thumbnailPath;
                        if (path != null && path.isNotEmpty && (path.startsWith('content://') || File(path).existsSync())) {
                          return Image.file(File(path), fit: BoxFit.cover);
                        }
                        return Container(
                          color: isDark ? Colors.grey[900] : Colors.grey[300],
                          child: Icon(
                            Icons.image_outlined,
                            size: 64,
                            color: textSecondary,
                          ),
                        );
                      },
                    ),

                    // Top Right Floating Button
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () {
                          final mem = _images[_selectedIndex];
                          final path = (mem.filePath != null && mem.filePath!.isNotEmpty)
                              ? mem.filePath
                              : mem.thumbnailPath;
                          final imgFile = (path != null && path.isNotEmpty && (path.startsWith('content://') || File(path).existsSync()))
                              ? File(path)
                              : null;
                          final hasB64 = mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty;

                          if (imgFile != null || hasB64) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  backgroundColor: Colors.black,
                                  body: Stack(
                                    children: [
                                      Center(
                                        child: InteractiveViewer(
                                          minScale: 0.5,
                                          maxScale: 4.0,
                                          child: imgFile != null
                                              ? Image.file(imgFile)
                                              : Image.memory(base64Decode(mem.imageBase64!.trim())),
                                        ),
                                      ),
                                      Positioned(
                                        top: 40,
                                        left: 10,
                                        child: IconButton(
                                          icon: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fullscreen_rounded,
                            color: Colors.black87,
                            size: 24,
                          ),
                        ),
                      ),
                    ),

                    // Bottom Left Pill (Date)
                    Positioned(
                      bottom: 20,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
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
                  // Title Section
                  Text(
                    cleanTitle,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'DMSans',
                      fontWeight: FontWeight.bold,
                      fontSize: 26,
                      letterSpacing: 0,
                      height: 1.3,
                    ),
                  ),

                  if (jsonSubtitle != null && jsonSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      jsonSubtitle,
                      style: TextStyle(
                        color: textSecondary,
                        fontFamily: 'DMSans',
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Description and Tags Section
                  if (isProcessing)
                    Shimmer.fromColors(
                      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 200,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            width: 80,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: List.generate(
                              3,
                              (index) => Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 70,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // Description Section
                    if (jsonDescription != null &&
                        jsonDescription.isNotEmpty) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                color: Theme.of(context).primaryColor,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'DESCRIPTION',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            jsonDescription,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              fontWeight: FontWeight.w400,
                              color: textColor.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Tags Section Header
                    Row(
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TAGS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags
                          .map(
                            (t) => Container(
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
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).primaryColor,
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
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 32),
                  RelatedMemoriesCarousel(
                    currentMemory: currentMemory,
                    tags: tags,
                    isDark: isDark,
                    primaryColor: Theme.of(context).primaryColor,
                  ),

                  const SizedBox(height: 48), // Bottom padding
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


}
