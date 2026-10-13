import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/memory_models.dart';
import '../../core/providers/glance_providers.dart';
import '../../core/services/app_icon_cache.dart';
import '../details/detail_router.dart';
import 'widgets/timeline_header.dart';
import 'widgets/timeline_tabs.dart';
import 'widgets/timeline_date_header.dart';
import 'widgets/timeline_item.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  int _selectedTabIndex =
      0; // 0: Days (Today), 1: Weeks (This Week), 2: Months (This Month)

  static const int _batchSize = 20;
  int _displayedCount = _batchSize;
  bool _isLoadingMore = false;
  late final ScrollController _scrollController;

  List<Memory>? _lastMemories;
  int? _lastTabIndex;
  List<_TimelineRowItem>? _cachedRows;

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
        _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoadingMore && _cachedRows != null && _displayedCount < _cachedRows!.length) {
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

  Future<void> _scanDevice() async {
    try {
      final scanner = ref.read(deviceMemoryScannerProvider);
      final hasNew = await scanner.syncDeviceData();
      if (hasNew && mounted) {
        ref.invalidate(allMemoriesProvider);
      }
    } catch (_) {}
  }

  List<_TimelineRowItem> _getOrBuildRows(List<Memory> allMemories) {
    if (identical(_lastMemories, allMemories) &&
        _lastTabIndex == _selectedTabIndex &&
        _cachedRows != null) {
      return _cachedRows!;
    }
    _lastMemories = allMemories;
    _lastTabIndex = _selectedTabIndex;
    _displayedCount = _batchSize; // reset batch size when dataset or tab changes
    _cachedRows = _computeRows(allMemories);
    return _cachedRows!;
  }

  List<_TimelineRowItem> _computeRows(List<Memory> allMemories) {
    final now = DateTime.now();
    final todayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .millisecondsSinceEpoch;
    final monthStart = DateTime(
      now.year,
      now.month,
      1,
    ).millisecondsSinceEpoch;

    var memories = allMemories.where((mem) {
      if (_selectedTabIndex == 0) {
        return mem.capturedAt >= todayStart;
      } else if (_selectedTabIndex == 1) {
        return mem.capturedAt >= weekStart;
      } else if (_selectedTabIndex == 2) {
        return mem.capturedAt >= monthStart;
      }
      return true;
    }).toList();

    // Sort reverse-chronologically: newest on top, oldest at bottom
    memories.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    // Fast O(N) deduplication using minute-bucket key
    final List<Memory> uniqueMemories = [];
    final Set<String> seenKeys = <String>{};
    for (final mem in memories) {
      final bucket = mem.capturedAt ~/ 60000;
      final key = '${mem.type}_${mem.title}_${mem.content}_$bucket';
      if (seenKeys.add(key)) {
        uniqueMemories.add(mem);
      }
    }
    memories = uniqueMemories;

    if (memories.isEmpty) {
      return [];
    }

    // Group memories by date string (Today at top, Yesterday, previous dates at bottom)
    final Map<String, List<Memory>> groupedByDate = {};
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayStr = DateFormat(
      'yyyy-MM-dd',
    ).format(now.subtract(const Duration(days: 1)));

    for (final mem in memories) {
      final memDate = DateTime.fromMillisecondsSinceEpoch(mem.capturedAt);
      final dateKey = DateFormat('yyyy-MM-dd').format(memDate);

      String displayDate;
      if (dateKey == todayStr) {
        displayDate = 'Today, ${DateFormat('MMM d').format(memDate)}';
      } else if (dateKey == yesterdayStr) {
        displayDate = 'Yesterday, ${DateFormat('MMM d').format(memDate)}';
      } else {
        displayDate = DateFormat('EEE, MMM d, yyyy').format(memDate);
      }

      groupedByDate.putIfAbsent(displayDate, () => []).add(mem);
    }

    final List<_TimelineRowItem> rows = [];
    for (final group in groupedByDate.entries) {
      final dateLabel = group.key;
      final memList = group.value;

      rows.add(_DateHeaderRowItem(dateLabel));
      rows.add(const _SpacingRowItem(16));

      final clusters = _clusterMemoriesByMinute(memList);
      for (int i = 0; i < clusters.length; i++) {
        rows.add(
          _ClusterRowItem(
            clusters[i],
            isFirst: i == 0,
            isLast: i == clusters.length - 1,
          ),
        );
      }
      rows.add(const _SpacingRowItem(24));
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final memoriesAsync = ref.watch(allMemoriesProvider);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _scanDevice();
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TimelineHeader(),
                      const SizedBox(height: 24),
                      TimelineTabs(
                        selectedIndex: _selectedTabIndex,
                        onTabChanged: (index) {
                          setState(() {
                            _selectedTabIndex = index;
                          });
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              ...memoriesAsync.when(
                data: (allMemories) {
                  final allRows = _getOrBuildRows(allMemories);

                  if (allRows.isEmpty) {
                    final timeFrameName = _selectedTabIndex == 0
                        ? 'Today'
                        : (_selectedTabIndex == 1 ? 'This Week' : 'This Month');
                    return [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 60.0),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.timeline,
                                    size: 64,
                                    color: isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No timeline activity captured for $timeFrameName',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ];
                  }

                  final visibleRows = allRows.take(_displayedCount).toList();

                  return [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      sliver: SliverList.builder(
                        itemCount: visibleRows.length,
                        itemBuilder: (context, index) {
                          final row = visibleRows[index];
                          if (row is _DateHeaderRowItem) {
                            return TimelineDateHeader(date: row.date);
                          } else if (row is _SpacingRowItem) {
                            return SizedBox(height: row.height);
                          } else if (row is _ClusterRowItem) {
                            final cluster = row.cluster;
                            final primaryMem = cluster.items.first;
                            final timeStr = DateFormat('h:mm a').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                primaryMem.capturedAt,
                              ),
                            );

                            return TimelineItem(
                              key: ValueKey(
                                '${primaryMem.id}_${primaryMem.capturedAt}',
                              ),
                              time: timeStr,
                              title: cluster.title,
                              subtitle: cluster.subtitle,
                              image: _buildImageForMemory(primaryMem, isDark),
                              count: cluster.items.length,
                              isFirst: row.isFirst,
                              isLast: row.isLast,
                              onTap: () {
                                DetailRouter.openDetailScreen(
                                  context,
                                  primaryMem,
                                  sameTimeMemories: cluster.items,
                                );
                              },
                              children: cluster.items.length > 1
                                  ? cluster.items.map((mem) {
                                      return _buildChildItemCard(
                                        mem,
                                        isDark,
                                        cluster.items,
                                      );
                                    }).toList()
                                  : null,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ];
                },
                loading: () => [
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ],
                error: (err, stack) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60.0),
                      child: Center(
                        child: Text(
                          'Error loading timeline: $err',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildItemCard(
    Memory mem,
    bool isDark,
    List<Memory> clusterItems,
  ) {
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2E2E2E)
        : const Color(0xFFEBEBEB);
    final textColor = isDark ? Colors.white70 : const Color(0xFF111418);
    final timeColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

    final cleanTitle = _getCleanTitle(mem);
    final timeStr = DateFormat(
      'h:mm a',
    ).format(DateTime.fromMillisecondsSinceEpoch(mem.capturedAt));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () {
          DetailRouter.openDetailScreen(
            context,
            mem,
            sameTimeMemories: clusterItems,
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: _buildImageForMemory(mem, isDark, size: 28),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cleanTitle,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(timeStr, style: TextStyle(color: timeColor, fontSize: 11)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: timeColor),
            ],
          ),
        ),
      ),
    );
  }

  String _getCleanTitle(Memory mem) {
    final typeLower = mem.type.toLowerCase();

    if (typeLower == 'screenshot') {
      return 'Captured Screenshot';
    }
    if (typeLower == 'photo' || typeLower == 'camera_capture') {
      return 'Captured Image';
    }

    String title = mem.title;
    if (typeLower == 'app_activity') {
      if (mem.sourceApp != null &&
          mem.sourceApp!.isNotEmpty &&
          !mem.sourceApp!.startsWith('com.')) {
        return mem.sourceApp!;
      }
    }

    if (title.startsWith('com.') ||
        (title.contains('.') && !title.contains(' '))) {
      if (mem.sourceApp != null &&
          mem.sourceApp!.isNotEmpty &&
          !mem.sourceApp!.startsWith('com.')) {
        return mem.sourceApp!;
      }
      final parts = title.split('.');
      String lastPart = parts.last;
      if (lastPart.isNotEmpty) {
        return lastPart[0].toUpperCase() + lastPart.substring(1);
      }
    }

    if (title.isEmpty) {
      if (mem.content.isNotEmpty) {
        return mem.content;
      }
      return mem.sourceApp ?? 'Captured Activity';
    }

    return title;
  }

  Widget _buildImageForMemory(Memory mem, bool isDark, {double size = 48.0}) {
    final typeLower = mem.type.toLowerCase();

    // App activity icon from DB / memory cache
    if (typeLower == 'app_activity' &&
        mem.sourcePackage != null &&
        mem.sourcePackage!.trim().isNotEmpty) {
      return AppIconWidget(
        packageName: mem.sourcePackage!.trim(),
        size: size,
        borderRadius: BorderRadius.circular(6),
        fallbackIcon: Image.asset(
          'assets/icons/ap_activity.png',
          width: size,
          height: size,
        ),
      );
    }

    // Screenshot or photo: Prioritize DB-stored Base64 copy
    if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
      return Image.memory(
        base64Decode(mem.imageBase64!.trim()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 96,
        cacheHeight: 96,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          typeLower == 'screenshot'
              ? 'assets/icons/screenshot.png'
              : 'assets/icons/images.png',
          width: size,
          height: size,
        ),
      );
    }

    final imgPath = mem.thumbnailPath ?? mem.filePath;
    if ((typeLower == 'screenshot' ||
            typeLower == 'photo' ||
            typeLower == 'camera_capture') &&
        imgPath != null &&
        imgPath.trim().isNotEmpty) {
      return Image.file(
        File(imgPath.trim()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 96,
        cacheHeight: 96,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          typeLower == 'screenshot'
              ? 'assets/icons/screenshot.png'
              : 'assets/icons/images.png',
          width: size,
          height: size,
        ),
      );
    }

    if (typeLower == 'screenshot') {
      return Image.asset(
        'assets/icons/screenshot.png',
        width: size,
        height: size,
      );
    }

    if (typeLower == 'photo' || typeLower == 'camera_capture') {
      return Image.asset('assets/icons/images.png', width: size, height: size);
    }

    if (typeLower == 'pdf' || typeLower == 'document') {
      if (imgPath != null &&
          imgPath.trim().isNotEmpty &&
          File(imgPath.trim()).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(imgPath.trim()),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 96,
            cacheHeight: 96,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              'assets/icons/documens.png',
              width: size,
              height: size,
            ),
          ),
        );
      }
      return Image.asset(
        'assets/icons/documens.png',
        width: size,
        height: size,
      );
    }

    if (typeLower == 'copied_text' || typeLower == 'clipboard') {
      return Image.asset(
        'assets/icons/copied_text.png',
        width: size,
        height: size,
      );
    }

    if (typeLower == 'location') {
      return Image.asset(
        'assets/icons/location.png',
        width: size,
        height: size,
      );
    }

    if (typeLower == 'notification') {
      return Image.asset(
        'assets/icons/notification.png',
        width: size,
        height: size,
      );
    }

    if (typeLower == 'website' || typeLower == 'browser') {
      return Image.asset('assets/icons/website.png', width: size, height: size);
    }

    // Default icon for call_log, sms, calendar, etc.
    return Image.asset('assets/icons/all.png', width: size, height: size);
  }
}

class _TimelineCluster {
  final List<Memory> items;
  final String title;
  final String subtitle;

  _TimelineCluster({
    required this.items,
    required this.title,
    required this.subtitle,
  });
}

List<_TimelineCluster> _clusterMemoriesByMinute(List<Memory> rawMemories) {
  if (rawMemories.isEmpty) return [];

  final List<_TimelineCluster> clusters = [];
  List<Memory> currentGroup = [rawMemories.first];

  for (int i = 1; i < rawMemories.length; i++) {
    final prev = currentGroup.last;
    final curr = rawMemories[i];

    final isSameType = prev.type.toLowerCase() == curr.type.toLowerCase();
    final isSameApp =
        prev.sourcePackage != null && prev.sourcePackage == curr.sourcePackage;
    final timeDiffMs = (curr.capturedAt - prev.capturedAt).abs();

    if ((isSameType || isSameApp) && timeDiffMs <= 60000) {
      // Deduplicate exact zero-change duplicates within the group
      bool isExactDuplicate = false;
      for (final existing in currentGroup) {
        final sameFile =
            (curr.filePath ?? '') == (existing.filePath ?? '') &&
            (curr.thumbnailPath ?? '') == (existing.thumbnailPath ?? '');
        final sameTitle = curr.title.trim() == existing.title.trim();
        final sameContent = curr.content.trim() == existing.content.trim();
        final sameTime = curr.capturedAt == existing.capturedAt;

        if (sameFile && sameTitle && sameContent && sameTime) {
          isExactDuplicate = true;
          break;
        }
        if (curr.filePath != null &&
            curr.filePath!.isNotEmpty &&
            curr.filePath == existing.filePath &&
            sameContent) {
          isExactDuplicate = true;
          break;
        }
      }

      if (!isExactDuplicate) {
        currentGroup.add(curr);
      }
    } else {
      clusters.add(_makeCluster(currentGroup));
      currentGroup = [curr];
    }
  }

  if (currentGroup.isNotEmpty) {
    clusters.add(_makeCluster(currentGroup));
  }

  return clusters;
}

_TimelineCluster _makeCluster(List<Memory> items) {
  final first = items.first;
  final typeLower = first.type.toLowerCase();
  final count = items.length;

  String title;
  String subtitle;

  if (typeLower == 'screenshot') {
    title = count > 1 ? 'Captured Screenshots' : 'Captured Screenshot';
    subtitle = count > 1
        ? 'Captured in short succession'
        : 'Captured screenshot';
  } else if (typeLower == 'photo' || typeLower == 'camera_capture') {
    title = count > 1 ? 'Captured Images' : 'Captured Image';
    subtitle = count > 1
        ? 'Captured in short succession'
        : 'Camera photo captured';
  } else if (typeLower == 'notification') {
    final isWhatsapp =
        first.sourceApp?.toLowerCase().contains('whatsapp') ?? false;
    final cleanApp =
        (first.sourceApp != null && !first.sourceApp!.startsWith('com.'))
        ? first.sourceApp!
        : 'Notification';
    title = isWhatsapp
        ? (count > 1 ? 'WhatsApp Notifications' : 'WhatsApp Notification')
        : (count > 1 ? '$cleanApp Notifications' : cleanApp);
    subtitle = count > 1
        ? 'Multiple notifications'
        : (first.content.isNotEmpty ? first.content : 'Notification');
  } else if (typeLower == 'app_activity') {
    final cleanApp =
        (first.sourceApp != null && !first.sourceApp!.startsWith('com.'))
        ? first.sourceApp!
        : (first.title.startsWith('com.')
              ? first.title.split('.').last
              : first.title);
    title = count > 1 ? '$cleanApp Activity' : 'Opened $cleanApp';
    subtitle = cleanApp;
  } else if (typeLower == 'call_log') {
    title = count > 1 ? 'Phone Calls' : first.title;
    subtitle = first.content.isNotEmpty ? first.content : 'Phone Call';
  } else if (typeLower == 'sms') {
    title = count > 1 ? 'Text Messages' : first.title;
    subtitle = count > 1 ? 'Multiple SMS messages' : first.content;
  } else if (typeLower == 'pdf' || typeLower == 'document') {
    title = count > 1 ? 'Documents' : first.title;
    subtitle = first.filePath ?? 'Document';
  } else if (typeLower == 'copied_text' || typeLower == 'clipboard') {
    title = count > 1 ? 'Copied Texts' : 'Copied Text';
    subtitle = count > 1
        ? 'Copied to clipboard'
        : (first.content.isNotEmpty ? first.content : 'Copied text');
  } else {
    title = first.title;
    subtitle = first.sourceApp ?? 'Captured Activity';
  }

  return _TimelineCluster(items: items, title: title, subtitle: subtitle);
}

abstract class _TimelineRowItem {
  const _TimelineRowItem();
}

class _DateHeaderRowItem extends _TimelineRowItem {
  final String date;
  const _DateHeaderRowItem(this.date);
}

class _ClusterRowItem extends _TimelineRowItem {
  final _TimelineCluster cluster;
  final bool isFirst;
  final bool isLast;
  const _ClusterRowItem(
    this.cluster, {
    required this.isFirst,
    required this.isLast,
  });
}

class _SpacingRowItem extends _TimelineRowItem {
  final double height;
  const _SpacingRowItem(this.height);
}
