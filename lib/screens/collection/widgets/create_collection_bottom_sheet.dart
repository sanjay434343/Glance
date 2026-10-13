import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/glance_db.dart';
import '../../../core/models/memory_models.dart';
import '../../../core/providers/glance_providers.dart';

class CreateCollectionBottomSheet extends ConsumerStatefulWidget {
  const CreateCollectionBottomSheet({super.key});

  @override
  ConsumerState<CreateCollectionBottomSheet> createState() =>
      _CreateCollectionBottomSheetState();
}

class _CreateCollectionBottomSheetState
    extends ConsumerState<CreateCollectionBottomSheet> {
  final TextEditingController _titleController = TextEditingController();
  final Set<String> _selectedMemoryIds = {};
  
  String _selectedFilter = 'All';

  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _createCollection(List<Memory> allMemories) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a title')));
      return;
    }

    if (_selectedMemoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final collectionId = 'col_${DateTime.now().millisecondsSinceEpoch}';

      await GlanceDatabase.instance.createCollection(
        collectionId,
        title,
        icon: 'assets/icons/documens.png',
      );

      final selectedMemories = allMemories
          .where((m) => _selectedMemoryIds.contains(m.id))
          .toList();

      for (final mem in selectedMemories) {
        await GlanceDatabase.instance.addMemoryAndRelated(collectionId, mem);
      }

      if (mounted) {
        ref.invalidate(customCollectionsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Collection created!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Widget _buildMemoryThumbnail(Memory mem, bool isDark) {
    if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
      return Image.memory(
        base64Decode(mem.imageBase64!.trim()),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else if (mem.thumbnailPath != null && mem.thumbnailPath!.isNotEmpty) {
      return Image.file(
        File(mem.thumbnailPath!),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else {
      final typeLower = mem.type.toLowerCase();
      IconData icon = Icons.memory;
      Color color = Colors.grey;

      if (typeLower.contains('web')) {
        icon = Icons.language;
        color = Colors.blue;
      } else if (typeLower.contains('text') ||
          typeLower.contains('clipboard')) {
        icon = Icons.content_paste;
        color = Colors.purple;
      } else if (typeLower.contains('location')) {
        icon = Icons.location_on;
        color = Colors.pink;
      } else if (typeLower.contains('pdf') || typeLower.contains('doc')) {
        icon = Icons.picture_as_pdf;
        color = Colors.orange;
      }

      return Container(
        width: double.infinity,
        height: double.infinity,
        color: isDark ? Colors.white10 : Colors.grey[200],
        child: Icon(icon, color: color, size: 30),
      );
    }
  }

  Widget _buildFilterChip(String label, String iconAsset, bool isDark) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : (isDark ? Colors.white10 : Colors.grey[200]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              iconAsset,
              width: 16,
              height: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
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
    final memoriesAsync = ref.watch(allMemoriesProvider);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          top: 24,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Create Collection',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _isCreating
                      ? null
                      : () {
                          memoriesAsync.whenData(
                            (memories) => _createCollection(memories),
                          );
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                  child: _isCreating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text(
                          'Create',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Name your collection...',
                hintStyle: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            autofocus: false,
            ),

            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'assets/icons/all.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Images', 'assets/icons/images.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('App Activity', 'assets/icons/ap_activity.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Copied Text', 'assets/icons/copied_text.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Documents', 'assets/icons/documens.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Location', 'assets/icons/location.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Notification', 'assets/icons/notification.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Screenshot', 'assets/icons/screenshot.png', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Website', 'assets/icons/website.png', isDark),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: memoriesAsync.when(
                data: (allMemories) {
                  final memories = allMemories.where((m) {
                    if (_selectedFilter == 'All') return true;
                    final type = m.type.toLowerCase();
                    if (_selectedFilter == 'Images') {
                      return type.contains('photo') || type.contains('camera');
                    }
                    if (_selectedFilter == 'App Activity') {
                      return type.contains('app');
                    }
                    if (_selectedFilter == 'Copied Text') {
                      return type.contains('text') || type.contains('clipboard');
                    }
                    if (_selectedFilter == 'Documents') {
                      return type.contains('pdf') || type.contains('doc') || type.contains('file');
                    }
                    if (_selectedFilter == 'Location') {
                      return type.contains('location');
                    }
                    if (_selectedFilter == 'Notification') {
                      return type.contains('notification');
                    }
                    if (_selectedFilter == 'Screenshot') {
                      return type.contains('screenshot');
                    }
                    if (_selectedFilter == 'Website') {
                      return type.contains('web') || type.contains('url');
                    }
                    return false;
                  }).toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                  if (memories.isEmpty) {
                    return const Center(child: Text('No memories match this filter.'));
                  }

                  final Map<String, List<Memory>> groupedItems = {};
                  for (final mem in memories) {
                    final date = DateTime.fromMillisecondsSinceEpoch(mem.createdAt);
                    final dateKey = DateFormat('MMMM d, yyyy').format(date);
                    if (!groupedItems.containsKey(dateKey)) {
                      groupedItems[dateKey] = [];
                    }
                    groupedItems[dateKey]!.add(mem);
                  }

                  return CustomScrollView(
                    slivers: [
                      for (final entry in groupedItems.entries) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final mem = entry.value[index];
                              final isSelected = _selectedMemoryIds.contains(mem.id);

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedMemoryIds.remove(mem.id);
                                    } else {
                                      _selectedMemoryIds.add(mem.id);
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                                        : (isDark ? Colors.white10 : Colors.grey[100]),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(context).primaryColor
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: const BorderRadius.vertical(
                                                top: Radius.circular(14),
                                              ),
                                              child: _buildMemoryThumbnail(mem, isDark),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              mem.title,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                            child: Icon(
                                              Icons.check_circle,
                                              color: Theme.of(context).primaryColor,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: entry.value.length,
                          ),
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
