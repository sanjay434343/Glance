import 'dart:async';
import 'dart:io';
import '../../../core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/providers/glance_providers.dart';
import '../../core/models/memory_models.dart';
import '../details/detail_router.dart';
import 'widgets/home_top_bar.dart';
import 'widgets/home_filter_chip.dart';
import 'widgets/home_activity_item.dart';
import 'widgets/animated_item.dart';
import 'widgets/home_continue_card.dart';
import 'widgets/home_section_header.dart';
import 'widgets/home_insights_section.dart';
import 'widgets/ai_chat_dialog.dart';
import '../../core/services/global_capture_service.dart';
import '../../core/services/glance_permission_service.dart';
import 'widgets/ungranted_permissions_banner.dart';
import 'widgets/model_download_banner.dart';
import '../../core/services/model_download_service.dart';
import '../../core/services/gemma_mediapipe_service.dart';
import '../model_download/model_download_screen.dart';
import 'see_all_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  StreamSubscription<GlobalCaptureEvent>? _captureSubscription;
  StreamSubscription<ModelDownloadProgress>? _downloadSubscription;
  List<GlancePermissionItem> _ungrantedPermissions = [];
  String _selectedCategory = 'All';

  bool _hasModelFileOnPath = false;
  bool _isModelLoadedInRam = false;
  bool _isAutoLoadingModel = false;
  ModelDownloadProgress? _downloadProgress;

  // ── Cached memories for flicker-free rendering ──
  List<Memory> _displayedMemories = [];
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnimatedItem.resetAll();
    _checkPermissions();
    _checkModelFile();

    // Listen to background model downloader progress
    _downloadProgress = ModelDownloadService.instance.currentProgress;
    _downloadSubscription = ModelDownloadService.instance.progressStream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress;
        });
        if (progress.isCompleted) {
          _handleAutoLoadAfterDownload();
        }
      },
    );

    // Initialize Global Capture Service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(globalCaptureServiceProvider);

      // Seed the displayed list from whatever the provider already has
      final current = ref.read(allMemoriesProvider);
      current.whenData((memories) {
        if (mounted && !_initialLoadDone) {
          setState(() {
            _displayedMemories = memories;
            _initialLoadDone = true;
          });
        }
      });
    });

    _captureSubscription = GlobalCaptureService.instance.eventStream.listen((
      event,
    ) {
      // StreamProvider will automatically yield new data from DB stream
    });
  }

  Future<void> _handleAutoLoadAfterDownload() async {
    setState(() {
      _isAutoLoadingModel = true;
    });

    try {
      final path = await GemmaMediaPipeService.instance.resolveModelPath();
      if (path != null && path.isNotEmpty) {
        await GemmaMediaPipeService.instance.initModel(
          customModelPath: path,
          preferredBackend: 'AUTO',
        );
      }
    } catch (_) {}

    await _checkModelFile();

    if (mounted) {
      setState(() {
        _isAutoLoadingModel = false;
      });
    }
  }

  Future<void> _checkModelFile() async {
    try {
      // 1. Strictly verify if a .task file exists in the designated media storage path
      bool fileOnPath = false;
      final mediaDir = Directory(GemmaMediaPipeService.primaryModelsDirectory);
      if (mediaDir.existsSync()) {
        final taskFiles = mediaDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.task'))
            .toList();
        fileOnPath = taskFiles.isNotEmpty;
      }

      // 2. Also check if model is currently loaded in RAM
      final hw = await GemmaMediaPipeService.instance.fetchHardwareInfo();
      final isLoadedInRam = hw?.isModelLoaded ?? false;

      if (mounted) {
        setState(() {
          _hasModelFileOnPath = fileOnPath;
          _isModelLoadedInRam = isLoadedInRam;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkPermissions() async {
    try {
      final ungranted = await GlancePermissionService.getUngrantedPermissions();
      if (mounted) {
        setState(() {
          _ungrantedPermissions = ungranted;
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _checkModelFile();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureSubscription?.cancel();
    _downloadSubscription?.cancel();
    super.dispose();
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
      case 'notification':
      case 'call_log':
      case 'sms':
      case 'calendar_event':
        return Icons.notifications_outlined;
      default:
        return Icons.grid_view;
    }
  }

  String _formatTimeAgo(int capturedAtMs) {
    final diffSec =
        (DateTime.now().millisecondsSinceEpoch - capturedAtMs) ~/ 1000;
    if (diffSec < 60) return 'Just now';
    if (diffSec < 3600) return '${diffSec ~/ 60} min ago';
    if (diffSec < 86400) return '${diffSec ~/ 3600} hours ago';
    return '${diffSec ~/ 86400} days ago';
  }

  Future<void> _handleRescanAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.published_with_changes_rounded,
              color: Color(0xFF6366F1),
            ),
            SizedBox(width: 10),
            Text('Rescan All Images?'),
          ],
        ),
        content: const Text(
          'This will override previous scan history and re-analyze all saved images and screenshots using Vision AI to generate updated titles, summaries, and tags under 500 characters.\n\nDo you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: const Text('Rescan All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final count = await GlobalCaptureService.instance.forceRescanAll();
      ref.invalidate(allMemoriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? 'Overrode previous scans. Rescanning $count images with Vision AI...'
                  : 'No images found to rescan.',
            ),
            backgroundColor: const Color(0xFF6366F1),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppTheme.getScaffoldBackground(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final textSecondary = AppTheme.getSecondaryText(isDark);

    // ── Listen for provider updates WITHOUT triggering a rebuild ──
    // Only setState when new data arrives (already debounced at 3s in the provider).
    ref.listen<AsyncValue<List<Memory>>>(allMemoriesProvider, (_, next) {
      next.whenData((memories) {
        if (mounted) {
          setState(() {
            _displayedMemories = memories;
            _initialLoadDone = true;
          });
        }
      });
    });

    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AiChatDialog.show(context),
        backgroundColor: const Color(0xFF3478F6),
        icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
        label: const Text(
          'Ask AI Memory',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF3478F6),
          onRefresh: () async {
            await GlobalCaptureService.instance.onUserActionDetected(actionName: 'Pull-to-refresh');
            ref.invalidate(allMemoriesProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Bar with Search Icon on Top Right ──
              HomeTopBar(iconColor: textColor),
              const SizedBox(height: 18),

              // ── Filter Chips ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    HomeFilterChip(
                      label: 'All',
                      imagePath: 'assets/icons/all.png',
                      isSelected: _selectedCategory == 'All',
                      isDark: isDark,
                      onTap: () => setState(() => _selectedCategory = 'All'),
                    ),
                    HomeFilterChip(
                      label: 'Screenshots',
                      imagePath: 'assets/icons/screenshot.png',
                      isSelected: _selectedCategory == 'Screenshots',
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _selectedCategory = 'Screenshots'),
                    ),
                    HomeFilterChip(
                      label: 'Images',
                      imagePath: 'assets/icons/images.png',
                      isSelected: _selectedCategory == 'Images',
                      isDark: isDark,
                      onTap: () => setState(() => _selectedCategory = 'Images'),
                    ),
                    HomeFilterChip(
                      label: 'Websites',
                      imagePath: 'assets/icons/website.png',
                      isSelected: _selectedCategory == 'Websites',
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _selectedCategory = 'Websites'),
                    ),
                    HomeFilterChip(
                      label: 'Files',
                      imagePath: 'assets/icons/documens.png',
                      isSelected: _selectedCategory == 'Files',
                      isDark: isDark,
                      onTap: () => setState(() => _selectedCategory = 'Files'),
                    ),
                    HomeFilterChip(
                      label: 'App Activity',
                      imagePath: 'assets/icons/ap_activity.png',
                      isSelected: _selectedCategory == 'App Activity',
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _selectedCategory = 'App Activity'),
                    ),
                    HomeFilterChip(
                      label: 'Notification',
                      imagePath: 'assets/icons/notification.png',
                      isSelected: _selectedCategory == 'Notification',
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _selectedCategory = 'Notification'),
                    ),
                    HomeFilterChip(
                      label: 'Locations',
                      imagePath: 'assets/icons/location.png',
                      isSelected: _selectedCategory == 'Locations',
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _selectedCategory = 'Locations'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── AI Model Download Banner (Shown if not downloaded or actively downloading) ──
              ModelDownloadBanner(
                hasModelOnPath: _hasModelFileOnPath,
                isLoadedInRam: _isModelLoadedInRam,
                isAutoLoading: _isAutoLoadingModel,
                downloadProgress: _downloadProgress,
                isDark: isDark,
                onTap: () async {
                  await Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => const ModelDownloadScreen(),
                    ),
                  );
                  _checkModelFile();
                },
              ),

              // ── Ungranted Permissions (Hidden once all granted) ──
              UngrantedPermissionsBanner(
                ungrantedPermissions: _ungrantedPermissions,
                isDark: isDark,
                onPermissionChanged: _checkPermissions,
              ),

              // ── Recent Activity ──
              HomeSectionHeader(
                title: 'Recent activity',
                actionText: 'See all >',
                titleColor: textColor,
                actionColor: const Color(0xFF3478F6),
                onActionTap: () {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(MaterialPageRoute(builder: (_) => const SeeAllPage()));
                },
              ),
              const SizedBox(height: 20),

              // ── Stable Activity List — rendered from local cached state ──
              _buildActivityList(isDark, textSecondary),

              const SizedBox(height: 32),

              // ── Memory Insights & Stats ──
              HomeInsightsSection(
                memories: _displayedMemories,
                isDark: isDark,
                onExploreTap: () {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(MaterialPageRoute(builder: (_) => const SeeAllPage()));
                },
              ),

              // Spacer for bottom nav
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    ),
  );
  }

  // ── Build the activity list from local cached state (no provider-driven rebuild) ──
  Widget _buildActivityList(bool isDark, Color textSecondary) {
    // Still loading initial data — show shimmer
    if (!_initialLoadDone) {
      return Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
        child: Column(
          children: List.generate(
            10,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 2),
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.getCardBackground(isDark),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(index == 0 ? 23 : 6),
                  bottom: Radius.circular(index == 9 ? 23 : 6),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Filter by selected category
    final filteredMemories = _displayedMemories.where((mem) {
      if (_selectedCategory == 'All') return true;
      if (_selectedCategory == 'Screenshots' && mem.type == 'screenshot')
        return true;
      if (_selectedCategory == 'Images' &&
          (mem.type == 'photo' ||
              mem.type == 'image' ||
              mem.type == 'camera_capture'))
        return true;
      if (_selectedCategory == 'Websites' &&
          (mem.type == 'webpage' || mem.type == 'url'))
        return true;
      if (_selectedCategory == 'Files' &&
          (mem.type == 'pdf' || mem.type == 'document'))
        return true;
      if (_selectedCategory == 'App Activity' && mem.type == 'app_activity')
        return true;
      if (_selectedCategory == 'Notification' &&
          (mem.type == 'notification' ||
              mem.type == 'call_log' ||
              mem.type == 'sms' ||
              mem.type == 'calendar_event'))
        return true;
      if (_selectedCategory == 'Locations' && mem.type == 'location')
        return true;
      return false;
    }).toList();

    if (filteredMemories.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        alignment: Alignment.center,
        child: Text(
          _selectedCategory == 'All'
              ? 'No recent activity captured yet.\nOpen apps, copy text, or take photos on your device!'
              : 'No recent activity for $_selectedCategory.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary, height: 1.5),
        ),
      );
    }

    final displayList = filteredMemories.take(10).toList();
    return Column(
      children: displayList.asMap().entries.map((entry) {
        final index = entry.key;
        final mem = entry.value;

        double topRadius = 6;
        double bottomRadius = 6;

        if (index == 0) {
          topRadius = 23;
        }
        if (index == displayList.length - 1) {
          bottomRadius = 23;
        }

        return AnimatedItem(
          key: ValueKey(mem.id),
          index: index,
          child: Container(
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
              sourcePackage: mem.sourcePackage,
              imagePath: mem.filePath ?? mem.thumbnailPath,
              imageBase64: mem.imageBase64,
              padding: const EdgeInsets.all(16),
              onTap: () {
                DetailRouter.openDetailScreen(context, mem);
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}
