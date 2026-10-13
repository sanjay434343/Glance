import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/glance_providers.dart';
import '../details/detail_router.dart';
import 'widgets/home_activity_item.dart';
import 'widgets/home_filter_chip.dart';
import '../../core/theme/theme.dart';

class SeeAllPage extends ConsumerStatefulWidget {
  const SeeAllPage({super.key});

  @override
  ConsumerState<SeeAllPage> createState() => _SeeAllPageState();
}

class _SeeAllPageState extends ConsumerState<SeeAllPage> {
  final String _searchQuery = '';
  String _selectedFilter = 'All';

  static const int _batchSize = 20;
  int _displayedCount = _batchSize;
  int _totalFilteredCount = 0;
  bool _isLoadingMore = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
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
      if (!_isLoadingMore && _displayedCount < _totalFilteredCount) {
        setState(() {
          _isLoadingMore = true;
        });
        Future.delayed(const Duration(milliseconds: 250), () {
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

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'screenshot':
      case 'photo':
      case 'camera_capture':
        return Icons.image_outlined;
      case 'webpage':
      case 'url':
        return Icons.language;
      case 'copied_text':
      case 'clipboard':
        return Icons.content_copy;
      case 'pdf':
      case 'document':
        return Icons.insert_drive_file_outlined;
      case 'location':
        return Icons.place_outlined;
      default:
        return Icons.grid_view;
    }
  }

  String _formatTimeAgo(int capturedAtMs) {
    final diffSec = (DateTime.now().millisecondsSinceEpoch - capturedAtMs) ~/ 1000;
    if (diffSec < 60) return 'Just now';
    if (diffSec < 3600) return '${diffSec ~/ 60} min ago';
    if (diffSec < 86400) return '${diffSec ~/ 3600} hours ago';
    return '${diffSec ~/ 86400} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppTheme.getScaffoldBackground(isDark);
    final cardBg = AppTheme.getCardBackground(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subColor = AppTheme.getSecondaryText(isDark);

    final memoriesAsync = ref.watch(allMemoriesProvider);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'All Activity History',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Row(
              children: [
                HomeFilterChip(label: 'All', imagePath: 'assets/icons/all.png', isSelected: _selectedFilter == 'All', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'All'; _displayedCount = _batchSize; })),
                HomeFilterChip(label: 'Screenshots', imagePath: 'assets/icons/screenshot.png', isSelected: _selectedFilter == 'Screenshots', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'Screenshots'; _displayedCount = _batchSize; })),
                HomeFilterChip(label: 'Websites', imagePath: 'assets/icons/website.png', isSelected: _selectedFilter == 'Websites', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'Websites'; _displayedCount = _batchSize; })),
                HomeFilterChip(label: 'Files', imagePath: 'assets/icons/documens.png', isSelected: _selectedFilter == 'Files', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'Files'; _displayedCount = _batchSize; })),
                HomeFilterChip(label: 'App Activity', imagePath: 'assets/icons/ap_activity.png', isSelected: _selectedFilter == 'App Activity', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'App Activity'; _displayedCount = _batchSize; })),
                HomeFilterChip(label: 'Notification', imagePath: 'assets/icons/notification.png', isSelected: _selectedFilter == 'Notification', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'Notification'; _displayedCount = _batchSize; })),
                HomeFilterChip(label: 'Copied text', imagePath: 'assets/icons/copied_text.png', isSelected: _selectedFilter == 'Copied text', isDark: isDark, onTap: () => setState(() { _selectedFilter = 'Copied text'; _displayedCount = _batchSize; })),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Memories List
          Expanded(
            child: memoriesAsync.when(
              data: (memories) {
                final filtered = memories.where((mem) {
                  final query = _searchQuery.toLowerCase();
                  final titleMatch = mem.title.toLowerCase().contains(query);
                  final appMatch = (mem.sourceApp ?? '').toLowerCase().contains(query);
                  final contentMatch = mem.content.toLowerCase().contains(query);
                  if (!titleMatch && !appMatch && !contentMatch) return false;

                  if (_selectedFilter == 'All') return true;
                  if (_selectedFilter == 'Screenshots' && mem.type == 'screenshot') return true;
                  if (_selectedFilter == 'Websites' && (mem.type == 'webpage' || mem.type == 'url')) return true;
                  if (_selectedFilter == 'Files' && (mem.type == 'pdf' || mem.type == 'document')) return true;
                  if (_selectedFilter == 'App Activity' && mem.type == 'app_activity') return true;
                  if (_selectedFilter == 'Notification' && mem.type == 'notification') return true;
                  if (_selectedFilter == 'Copied text' && (mem.type == 'copied_text' || mem.type == 'clipboard')) return true;
                  return false;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'No memories found matching your search.',
                        style: TextStyle(color: subColor, fontSize: 14),
                      ),
                    ),
                  );
                }

                _totalFilteredCount = filtered.length;
                final visibleItems = filtered.take(_displayedCount).toList();
                final bool hasMore = _displayedCount < filtered.length;

                return ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: visibleItems.length + (hasMore ? 1 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemBuilder: (context, index) {
                    if (index == visibleItems.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: textColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      );
                    }
                    final mem = visibleItems[index];
                    final isBase64Icon = mem.type == 'app_activity';

                    double topRadius = 6;
                    double bottomRadius = 6;

                    if (index == 0) {
                      topRadius = 23;
                    }
                    if (index == filtered.length - 1) {
                      bottomRadius = 23;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.getCardBackground(isDark),
                        border: Border.all(color: AppTheme.getCardBorder(isDark)),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(topRadius),
                          bottom: Radius.circular(bottomRadius),
                        ),
                      ),
                      child: HomeActivityItem(
                        memoryId: mem.id,
                        title: mem.title,
                        type: mem.type,
                        timeAgo: _formatTimeAgo(mem.capturedAt),
                        icon: _getIconForType(mem.type),
                        isDark: isDark,
                        sourcePackage: isBase64Icon ? mem.sourcePackage : null,
                        imagePath: !isBase64Icon ? (mem.filePath ?? mem.thumbnailPath) : null,
                        imageBase64: mem.imageBase64,
                        padding: const EdgeInsets.all(16),
                        onTap: () {
                          DetailRouter.openDetailScreen(context, mem);
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Error loading memories: $err', style: TextStyle(color: subColor)),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
