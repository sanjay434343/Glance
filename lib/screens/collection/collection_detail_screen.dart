import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/memory_models.dart';
import '../../core/providers/glance_providers.dart';
import '../../core/services/app_icon_cache.dart';
import '../details/detail_router.dart';

class CollectionDetailScreen extends ConsumerWidget {
  final String collectionTitle;
  final Set<String> targetTypes;
  final String iconAsset;

  const CollectionDetailScreen({
    super.key,
    required this.collectionTitle,
    required this.targetTypes,
    required this.iconAsset,
  });



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
            fallbackIcon: Icon(Icons.apps, color: isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      );
    }

    if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
      return Image.memory(
        base64Decode(mem.imageBase64!.trim()),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 300,
        cacheHeight: 300,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildIconMock(Icons.image, isDark),
      );
    }

    if ((typeLower == 'screenshot' ||
            typeLower == 'photo' ||
            typeLower == 'camera_capture') &&
        mem.thumbnailPath != null &&
        mem.thumbnailPath!.trim().isNotEmpty) {
      return Image.file(
        File(mem.thumbnailPath!.trim()),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 300,
        cacheHeight: 300,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildIconMock(Icons.image, isDark),
      );
    }

    if (typeLower == 'notification' ||
        typeLower == 'sms' ||
        typeLower == 'call_log') {
      return _buildIconMock(
        Icons.notifications_outlined,
        isDark,
        iconColor: const Color(0xFF3478F6),
      );
    }
    if (typeLower == 'pdf' || typeLower == 'document' || typeLower == 'file') {
      return _buildIconMock(
        Icons.picture_as_pdf_outlined,
        isDark,
        iconColor: const Color(0xFFFF9800),
      );
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

    final memoriesAsync = ref.watch(allMemoriesProvider);

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
          collectionTitle,
          style: TextStyle(
            color: textColor,
            fontFamily: 'DMSans',
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: memoriesAsync.when(
        data: (allMemories) {
          final items = allMemories
              .where((m) => targetTypes.contains(m.type.toLowerCase()))
              .toList();
          items.sort(
            (a, b) => b.capturedAt.compareTo(a.capturedAt),
          ); // latest first

          if (items.isEmpty) {
            return Center(
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
                    'No items in ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final Map<String, List<Memory>> groupedItems = {};
          for (final mem in items) {
            final date = DateTime.fromMillisecondsSinceEpoch(mem.capturedAt);
            final dateKey = DateFormat('MMMM d, yyyy').format(date);
            if (!groupedItems.containsKey(dateKey)) {
              groupedItems[dateKey] = [];
            }
            groupedItems[dateKey]!.add(mem);
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                    horizontal: 4.0,
                    vertical: 4.0,
                  ),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4.0,
                          mainAxisSpacing: 4.0,
                          childAspectRatio: 1.0,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final mem = entry.value[index];

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
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
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            'Error loading collection: ',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
