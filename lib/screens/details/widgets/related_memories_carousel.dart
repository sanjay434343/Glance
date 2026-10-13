import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/glance_db.dart';
import '../../../core/models/memory_models.dart';
import '../../../core/providers/glance_providers.dart';
import '../../../core/services/app_icon_cache.dart';
import '../../../core/theme/theme.dart';
import '../detail_router.dart';

/// Reusable carousel displaying related memories matching current tags/keywords.
/// Uses the exact Hybrid RAG retrieval engine from the Search Screen, and caches
/// results to prevent any flickering or layout jumps on parent rebuilds.
class RelatedMemoriesCarousel extends ConsumerStatefulWidget {
  final Memory currentMemory;
  final List<String> tags;
  final String? title;
  final bool isDark;
  final Color? primaryColor;

  const RelatedMemoriesCarousel({
    super.key,
    required this.currentMemory,
    required this.tags,
    this.title,
    required this.isDark,
    this.primaryColor,
  });

  @override
  ConsumerState<RelatedMemoriesCarousel> createState() => _RelatedMemoriesCarouselState();
}

class _RelatedMemoriesCarouselState extends ConsumerState<RelatedMemoriesCarousel> {
  List<Memory> _memories = const [];
  String? _lastFetchKey;

  @override
  void initState() {
    super.initState();
    _lastFetchKey = _computeFetchKey();
    _fetchRelatedMemories();
  }

  @override
  void didUpdateWidget(covariant RelatedMemoriesCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = _computeFetchKey();
    if (newKey != _lastFetchKey) {
      _lastFetchKey = newKey;
      _fetchRelatedMemories();
    }
  }

  String _computeFetchKey() {
    return '${widget.currentMemory.id}_${widget.tags.join(',')}';
  }

  Future<void> _fetchRelatedMemories() async {
    // Extensive list of generic stop words and category placeholders.
    // We strictly filter these out so they never trigger broad, random-looking matches.
    const genericWords = {
      // English grammatical stop words
      'this', 'that', 'with', 'from', 'have', 'your', 'about', 'will',
      'what', 'when', 'where', 'which', 'there', 'their', 'they', 'them',
      'some', 'than', 'then', 'also', 'http', 'https', 'com', 'org', 'www',
      'the', 'and', 'for', 'are', 'was', 'were', 'been', 'being', 'more',
      'into', 'only', 'over', 'such', 'other', 'each', 'does', 'done',
      'null', 'true', 'false', 'undefined', 'dear', 'user', 'like', 'just',
      // Generic memory types & UI labels that should NOT trigger broad matches
      'image', 'images', 'memory', 'memories', 'captured', 'capture',
      'screenshot', 'screenshots', 'photo', 'photos', 'camera', 'camera_capture',
      'vision', 'vision ai', 'notification', 'notifications',
      'website', 'web', 'page', 'site', 'url', 'link',
      'location', 'locations', 'map', 'maps', 'gps', 'place', 'places',
      'file', 'files', 'document', 'documents', 'doc', 'docs', 'pdf',
      'text', 'copied', 'copy', 'clipboard', 'paste', 'note', 'notes',
      'activity', 'app', 'apps', 'item', 'items', 'detail', 'details', 'general',
      'screen time', 'usage', 'time', 'system'
    };

    final candidateKeywords = <String>{};

    // 1. Specific keywords from the tags passed by the screen
    for (final tag in widget.tags) {
      final clean = tag.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
      if (clean.length >= 3 && !genericWords.contains(clean.toLowerCase())) {
        candidateKeywords.add(clean);
      }
    }

    // 2. Specific app name if known (e.g. "WhatsApp", "YouTube", "Swiggy")
    final sourceApp = widget.currentMemory.sourceApp;
    if (sourceApp != null && sourceApp.isNotEmpty) {
      final cleanApp = sourceApp.replaceAll(RegExp(r'^com\.[^.]+\.'), '').trim();
      if (cleanApp.length >= 3 &&
          !genericWords.contains(cleanApp.toLowerCase()) &&
          !cleanApp.startsWith('com.')) {
        candidateKeywords.add(cleanApp);
      }
    }

    // 3. Meaningful words from title if tags are sparse
    if (candidateKeywords.length < 2 && widget.currentMemory.title.isNotEmpty) {
      final titleWords = widget.currentMemory.title
          .split(RegExp(r'[^a-zA-Z0-9]+'))
          .where((w) => w.length >= 4 && !genericWords.contains(w.toLowerCase()));
      candidateKeywords.addAll(titleWords.take(3));
    }

    // If there are no specific keywords that distinguish this memory,
    // do NOT return random memories — set empty and exit gracefully.
    if (candidateKeywords.isEmpty) {
      if (mounted) {
        setState(() => _memories = const []);
      }
      return;
    }

    final queryStr = candidateKeywords.take(4).join(' ');
    final results = <Memory>[];

    // 4. Retrieve candidates using the Search Screen's Hybrid RAG engine
    try {
      final retriever = ref.read(hybridRetrieverProvider);
      final candidates = await retriever.retrieve(
        userQuery: queryStr,
        candidateLimit: 25,
        finalLimit: 10,
        minimumScore: 0.15,
      );

      for (final candidate in candidates) {
        final mem = candidate.memory;
        if (mem.id != widget.currentMemory.id && !results.any((r) => r.id == mem.id)) {
          results.add(mem);
        }
      }
    } catch (_) {}

    // 5. If RAG returned fewer than 3 results, supplement with Smart DB search on keywords
    if (results.length < 3) {
      try {
        final dbResults = await GlanceDatabase.instance.searchMemoriesSmart(
          keywords: candidateKeywords.take(6).toList(),
          limit: 15,
        );
        for (final mem in dbResults) {
          if (mem.id != widget.currentMemory.id && !results.any((r) => r.id == mem.id)) {
            results.add(mem);
          }
        }
      } catch (_) {}
    }

    // 6. Strictly verify that each candidate memory actually matches at least one keyword
    final verified = results.where((m) {
      final textToCheck = '${m.title} ${m.content} ${m.summary ?? ''} ${m.sourceApp ?? ''} ${m.url ?? ''}'.toLowerCase();
      return candidateKeywords.any((kw) => textToCheck.contains(kw.toLowerCase()));
    }).toList();

    if (mounted) {
      setState(() => _memories = verified);
    }
  }

  String _getCleanTitle(Memory mem) {
    final typeLower = mem.type.toLowerCase();
    if (typeLower == 'screenshot') return 'Screenshot';
    if (typeLower == 'photo' || typeLower == 'camera_capture') return 'Photo';

    String title = mem.title;
    if (typeLower == 'app_activity') {
      if (mem.sourceApp != null && mem.sourceApp!.isNotEmpty && !mem.sourceApp!.startsWith('com.')) {
        return mem.sourceApp!;
      }
    }

    if (title.startsWith('com.') || (title.contains('.') && !title.contains(' '))) {
      if (mem.sourceApp != null && mem.sourceApp!.isNotEmpty && !mem.sourceApp!.startsWith('com.')) {
        return mem.sourceApp!;
      }
      final parts = title.split('.');
      final last = parts.last;
      if (last.isNotEmpty) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }

    if (title.isEmpty) {
      if (mem.content.isNotEmpty) {
        final line = mem.content.split('\n').first.trim();
        return line.length > 24 ? '${line.substring(0, 24)}...' : line;
      }
      return mem.sourceApp ?? 'Captured Item';
    }

    return title.length > 24 ? '${title.substring(0, 24)}...' : title;
  }

  String _getTypeLabel(Memory mem) {
    switch (mem.type.toLowerCase()) {
      case 'screenshot':
        return 'Screenshot';
      case 'photo':
      case 'camera_capture':
        return 'Image';
      case 'location':
        return 'Location';
      case 'webpage':
      case 'url':
        return 'Website';
      case 'pdf':
      case 'document':
      case 'file':
        return 'Document';
      case 'copied_text':
      case 'clipboard':
        return 'Copied Text';
      case 'app_activity':
        return 'App Activity';
      case 'notification':
      case 'sms':
      case 'call_log':
        return 'Notification';
      default:
        return 'Memory';
    }
  }

  Widget _buildMemoryPreviewImage(Memory mem, bool isDark) {
    final typeLower = mem.type.toLowerCase();

    // 1. Prioritize Base64 image copy from database
    if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
      return Image.memory(
        base64Decode(mem.imageBase64!.trim()),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 200,
        cacheHeight: 200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildFallbackTile(mem, isDark),
      );
    }

    // 2. Image / Screenshot / Photo file preview from storage
    final imgPath = mem.thumbnailPath ?? mem.filePath;
    if (imgPath != null && imgPath.trim().isNotEmpty) {
      return Image.file(
        File(imgPath.trim()),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 200,
        cacheHeight: 200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildFallbackTile(mem, isDark),
      );
    }

    // 2. App activity icon from memory cache
    if (typeLower == 'app_activity' && mem.sourcePackage != null && mem.sourcePackage!.trim().isNotEmpty) {
      return Container(
        color: isDark ? const Color(0xFF251A30) : const Color(0xFFF3E8FF),
        alignment: Alignment.center,
        child: AppIconWidget(
          packageName: mem.sourcePackage!.trim(),
          size: 44,
          fallbackIcon: _buildFallbackTile(mem, isDark),
        ),
      );
    }

    return _buildFallbackTile(mem, isDark);
  }

  Widget _buildFallbackTile(Memory mem, bool isDark) {
    final typeLower = mem.type.toLowerCase();

    Color bgColor;
    String assetPath;
    IconData fallbackIcon;
    Color iconColor;

    switch (typeLower) {
      case 'location':
        bgColor = isDark ? const Color(0xFF2A1722) : const Color(0xFFFCE7F3);
        assetPath = 'assets/icons/location.png';
        fallbackIcon = Icons.place_rounded;
        iconColor = Colors.pink;
        break;
      case 'webpage':
      case 'url':
        bgColor = isDark ? const Color(0xFF142236) : const Color(0xFFE0EDFB);
        assetPath = 'assets/icons/website.png';
        fallbackIcon = Icons.language_rounded;
        iconColor = Colors.blueAccent;
        break;
      case 'pdf':
      case 'document':
      case 'file':
        bgColor = isDark ? const Color(0xFF2E2214) : const Color(0xFFFEF3C7);
        assetPath = 'assets/icons/documens.png';
        fallbackIcon = Icons.picture_as_pdf_rounded;
        iconColor = Colors.orange;
        break;
      case 'copied_text':
      case 'clipboard':
        bgColor = isDark ? const Color(0xFF241A2E) : const Color(0xFFF3E8FF);
        assetPath = 'assets/icons/copied_text.png';
        fallbackIcon = Icons.content_copy_rounded;
        iconColor = const Color(0xFF9C27B0);
        break;
      case 'notification':
        bgColor = isDark ? const Color(0xFF162534) : const Color(0xFFE0F2FE);
        assetPath = 'assets/icons/notification.png';
        fallbackIcon = Icons.notifications_rounded;
        iconColor = const Color(0xFF3478F6);
        break;
      case 'app_activity':
        bgColor = isDark ? const Color(0xFF241A2E) : const Color(0xFFF5E8FF);
        assetPath = 'assets/icons/ap_activity.png';
        fallbackIcon = Icons.apps_rounded;
        iconColor = Colors.purpleAccent;
        break;
      default:
        bgColor = isDark ? const Color(0xFF1E2420) : const Color(0xFFE8F5E9);
        assetPath = 'assets/icons/images.png';
        fallbackIcon = Icons.image_rounded;
        iconColor = Colors.green;
        break;
    }

    return Container(
      color: bgColor,
      alignment: Alignment.center,
      child: Image.asset(
        assetPath,
        width: 44,
        height: 44,
        errorBuilder: (_, _, _) => Icon(fallbackIcon, color: iconColor, size: 36),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_memories.isEmpty) {
      return const SizedBox.shrink();
    }

    final effectivePrimaryColor = widget.primaryColor ?? Theme.of(context).primaryColor;
    final textColor = AppTheme.getPrimaryText(widget.isDark);
    final subtitleColor = AppTheme.getSecondaryText(widget.isDark);
    final cardBg = AppTheme.getCardBackground(widget.isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Icon(
              Icons.dashboard_customize_rounded,
              size: 16,
              color: effectivePrimaryColor,
            ),
            const SizedBox(width: 6),
            Text(
              widget.title ?? 'RELATED CAPTURES',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: effectivePrimaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Horizontal Carousel using exact Smart Collection Card style
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _memories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final mem = _memories[index];
              final cleanTitle = _getCleanTitle(mem);
              final typeLabel = _getTypeLabel(mem);

              return InkWell(
                onTap: () {
                  DetailRouter.openDetailScreen(context, mem);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 155,
                  height: 180,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(23),
                      topRight: Radius.circular(23),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: AppTheme.getCardBorder(widget.isDark),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(23),
                            bottomRight: Radius.circular(23),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 110,
                            child: _buildMemoryPreviewImage(mem, widget.isDark),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                cleanTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    typeLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.getTypeColor(mem.type),
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.chevron_right,
                                    color: subtitleColor.withValues(alpha: 0.5),
                                    size: 16,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
