import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/glance_db.dart';
import '../../core/models/memory_models.dart';
import '../../core/services/app_icon_cache.dart';
import '../details/detail_router.dart';

class CustomCollectionDetailScreen extends ConsumerStatefulWidget {
  final String collectionId;
  final String title;
  final String iconAsset;

  const CustomCollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.title,
    required this.iconAsset,
  });

  @override
  ConsumerState<CustomCollectionDetailScreen> createState() =>
      _CustomCollectionDetailScreenState();
}

class _CustomCollectionDetailScreenState
    extends ConsumerState<CustomCollectionDetailScreen> {
  List<Memory>? _memories;
  static const int _batchSize = 20;
  int _displayedCount = _batchSize;
  bool _isLoadingMore = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadMemories();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      if (!_isLoadingMore &&
          _memories != null &&
          _displayedCount < _memories!.length) {
        setState(() {
          _isLoadingMore = true;
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _displayedCount += _batchSize;
              _isLoadingMore = false;
            });
          }
        });
      }
    }
  }

  Future<void> _loadMemories() async {
    final mems = await GlanceDatabase.instance.getMemoriesForCollection(
      widget.collectionId,
    );
    if (mounted) {
      setState(() {
        _memories = mems;
      });
    }
  }

  Widget _buildIconMock(IconData icon, bool isDark, {Color? iconColor}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6),
      ),
      child: Center(
        child: Icon(
          icon,
          color: iconColor ?? (isDark ? Colors.white70 : Colors.black54),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildMemoryIcon(Memory mem, bool isDark) {
    final typeLower = mem.type.toLowerCase();

    if (typeLower == 'app_activity' &&
        mem.sourcePackage != null &&
        mem.sourcePackage!.trim().isNotEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6),
        ),
        child: Center(
          child: AppIconWidget(
            packageName: mem.sourcePackage!.trim(),
            size: 42,
            fallbackIcon: Icon(
              Icons.apps,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      );
    }

    // Prioritize actual image file / thumbnail on disk so it covers the square card nicely
    final isImageType =
        typeLower == 'screenshot' ||
        typeLower == 'photo' ||
        typeLower == 'image' ||
        typeLower == 'camera_capture';

    if (isImageType) {
      final imgPath =
          (mem.filePath != null && File(mem.filePath!.trim()).existsSync())
          ? mem.filePath!.trim()
          : (mem.thumbnailPath != null &&
                    File(mem.thumbnailPath!.trim()).existsSync()
                ? mem.thumbnailPath!.trim()
                : null);

      if (imgPath != null) {
        return Image.file(
          File(imgPath),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: 400,
          cacheHeight: 400,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              _buildIconMock(Icons.image, isDark),
        );
      }
    }

    if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
      return Image.memory(
        base64Decode(mem.imageBase64!.trim()),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 400,
        cacheHeight: 400,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildIconMock(Icons.image, isDark),
      );
    }

    if (mem.thumbnailPath != null &&
        mem.thumbnailPath!.trim().isNotEmpty &&
        File(mem.thumbnailPath!.trim()).existsSync()) {
      return Image.file(
        File(mem.thumbnailPath!.trim()),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 400,
        cacheHeight: 400,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildIconMock(Icons.image, isDark),
      );
    }

    if (mem.filePath != null &&
        mem.filePath!.trim().isNotEmpty &&
        File(mem.filePath!.trim()).existsSync() &&
        (mem.filePath!.endsWith('.png') ||
            mem.filePath!.endsWith('.jpg') ||
            mem.filePath!.endsWith('.jpeg') ||
            mem.filePath!.endsWith('.webp'))) {
      return Image.file(
        File(mem.filePath!.trim()),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 400,
        cacheHeight: 400,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildIconMock(Icons.image, isDark),
      );
    }

    if (typeLower == 'notification' ||
        typeLower == 'sms' ||
        typeLower == 'call_log' ||
        typeLower == 'copied_text' ||
        typeLower == 'clipboard' ||
        typeLower == 'note') {
      return _buildTextPreviewCard(mem, isDark);
    }
    if (typeLower == 'pdf' || typeLower == 'document' || typeLower == 'file') {
      if (mem.thumbnailPath != null &&
          mem.thumbnailPath!.trim().isNotEmpty &&
          File(mem.thumbnailPath!.trim()).existsSync()) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(mem.thumbnailPath!.trim()),
              fit: BoxFit.cover,
              cacheWidth: 300,
              cacheHeight: 300,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  _buildDocumentTextPreview(mem, isDark),
            ),
            // Bottom gradient fade matching notification cards
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.35, 0.65, 0.85, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        (isDark ? Colors.black : Colors.white).withValues(
                          alpha: 0.35,
                        ),
                        (isDark ? Colors.black : Colors.white).withValues(
                          alpha: 0.82,
                        ),
                        (isDark ? Colors.black : Colors.white).withValues(
                          alpha: 0.98,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'PDF',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                mem.title.trim(),
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }
      return _buildDocumentTextPreview(mem, isDark);
    }
    if (typeLower == 'copied_text' || typeLower == 'clipboard') {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6),
        ),
        child: Center(
          child: Image.asset(
            'assets/icons/copied_text.png',
            width: 36,
            height: 36,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.content_paste_outlined,
              color: Color(0xFF9C27B0),
              size: 26,
            ),
          ),
        ),
      );
    }
    if (typeLower == 'location') {
      return _buildIconMock(
        Icons.location_on_outlined,
        isDark,
        iconColor: Colors.pink,
      );
    }
    if (typeLower == 'webpage' || typeLower == 'url') {
      return _buildIconMock(
        Icons.language_outlined,
        isDark,
        iconColor: Colors.blueAccent,
      );
    }

    return _buildIconMock(Icons.layers_outlined, isDark);
  }

  Widget _buildDocumentTextPreview(Memory mem, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E2128) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C323D)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);

    final ext = mem.title.contains('.')
        ? mem.title.split('.').last.toUpperCase()
        : 'DOC';

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 14,
                          color: Color(0xFFFF9800),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          ext,
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    mem.title.trim().isNotEmpty ? mem.title.trim() : 'Document',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      mem.content.trim().isNotEmpty
                          ? mem.content.trim()
                          : (mem.filePath ?? 'Document file on device'),
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 16.0,
                        fontWeight: FontWeight.w500,
                        color: textSub,
                        height: 1.3,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ],
              ),
            ),
            // Inner fade overlay: subtle at mid, much higher and stronger on the bottom (same as notification card)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.28, 0.55, 0.80, 1.0],
                      colors: [
                        cardBg.withValues(alpha: 0.0),
                        cardBg.withValues(alpha: 0.0),
                        cardBg.withValues(alpha: 0.35),
                        cardBg.withValues(alpha: 0.82),
                        cardBg.withValues(alpha: 1.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextPreviewCard(Memory mem, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E2128) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C323D)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

    final rawApp = (mem.sourceApp ?? mem.source ?? 'MESSAGES')
        .trim()
        .toUpperCase();

    // Resolve real package name and fallbacks
    String? pkg = mem.sourcePackage?.trim();
    Color accentColor = const Color(0xFF3B82F6);
    IconData fallbackIconData = Icons.notifications_active_rounded;

    if (rawApp.contains('GMAIL') || rawApp.contains('MAIL')) {
      pkg ??= 'com.google.android.gm';
      accentColor = const Color(0xFFEA4335);
      fallbackIconData = Icons.mail_rounded;
    } else if (rawApp.contains('SMS') || rawApp.contains('MESSAGE')) {
      pkg ??= 'com.google.android.apps.messaging';
      accentColor = const Color(0xFF10B981);
      fallbackIconData = Icons.chat_bubble_rounded;
    } else if (rawApp.contains('WHATSAPP')) {
      pkg ??= 'com.whatsapp';
      accentColor = const Color(0xFF25D366);
      fallbackIconData = Icons.chat_rounded;
    } else if (rawApp.contains('CALL')) {
      pkg ??= 'com.google.android.dialer';
      accentColor = const Color(0xFF8B5CF6);
      fallbackIconData = Icons.call_rounded;
    }

    final Widget appIconWidget = (pkg != null && pkg.isNotEmpty)
        ? AppIconWidget(
            packageName: pkg,
            size: 18,
            borderRadius: BorderRadius.circular(4),
            fallbackIcon: Icon(fallbackIconData, size: 16, color: accentColor),
          )
        : Icon(fallbackIconData, size: 16, color: accentColor);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            // Card Content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Badge with Real App Icon
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        appIconWidget,
                        const SizedBox(width: 5),
                        Text(
                          rawApp,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 14.5pt Title
                  Text(
                    mem.title.trim().isNotEmpty
                        ? mem.title.trim()
                        : 'Notification',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // 16pt Content Text
                  Expanded(
                    child: Text(
                      mem.content.trim(),
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 16.0,
                        fontWeight: FontWeight.w500,
                        color: textSub,
                        height: 1.3,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ],
              ),
            ),

            // Inner fade overlay: subtle at mid, much higher and stronger on the bottom
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.28, 0.55, 0.80, 1.0],
                      colors: [
                        cardBg.withValues(alpha: 0.0),
                        cardBg.withValues(alpha: 0.0),
                        cardBg.withValues(alpha: 0.35),
                        cardBg.withValues(alpha: 0.82),
                        cardBg.withValues(alpha: 1.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: textColor,
            fontFamily: 'DMSans',
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: _memories == null
          ? const Center(child: CircularProgressIndicator())
          : _memories!.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 64,
                    color: textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No items in ${widget.title}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : Builder(
              builder: (context) {
                final visibleItems = _memories!.take(_displayedCount).toList();
                final bool hasMore = _displayedCount < _memories!.length;

                final Map<String, List<Memory>> groupedItems = {};
                for (final mem in visibleItems) {
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    mem.capturedAt,
                  );
                  final dateKey = DateFormat('MMMM d, yyyy').format(date);
                  if (!groupedItems.containsKey(dateKey)) {
                    groupedItems[dateKey] = [];
                  }
                  groupedItems[dateKey]!.add(mem);
                }

                return CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 16.0)),
                    for (final entry in groupedItems.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 6.0,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12.0,
                                mainAxisSpacing: 12.0,
                                childAspectRatio: 1.05,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final mem = entry.value[index];

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(23),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(23),
                                onTap: () {
                                  DetailRouter.openDetailScreen(context, mem);
                                },
                                child: _buildMemoryIcon(mem, isDark),
                              ),
                            );
                          }, childCount: entry.value.length),
                        ),
                      ),
                    ],
                    if (hasMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const SliverToBoxAdapter(child: SizedBox(height: 36.0)),
                  ],
                );
              },
            ),
    );
  }
}
