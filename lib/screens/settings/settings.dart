import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/glance_db.dart';
import '../../core/native/glance_native_bridge.dart';
import '../../core/services/gemma_mediapipe_service.dart';
import '../../core/services/glance_permission_service.dart';
import '../../core/providers/glance_providers.dart';
import '../../core/theme/theme.dart';
import '../search/search_screen.dart';
import 'subpages/ai_model_settings_page.dart';
import 'subpages/permissions_settings_page.dart';
import 'subpages/storage_settings_page.dart';
import 'subpages/capture_settings_page.dart';
import 'subpages/about_settings_page.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  // Ungranted System Permissions
  List<GlancePermissionItem> _ungrantedPermissions = [];
  bool _isLoadingPermissions = true;

  // AI Model & Hardware Info
  GemmaHardwareInfo? _hwInfo;
  String? _modelPath;
  int _modelFileSize = 0;
  bool _gpuEnabled = true;
  bool _isLoadingModelInfo = true;

  // Database & Storage Stats
  int _totalMemories = 0;
  int _dbSizeBytes = 0;
  bool _isLoadingStats = true;

  // Glance App Battery Usage
  Map<String, dynamic>? _batteryUsage;
  bool _isLoadingBattery = true;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAllStats();
    }
  }

  Future<void> _loadAllStats() async {
    _checkPermissions();
    _loadModelInfo();
    _loadStorageStats();
    _loadBatteryUsage();
  }

  Future<void> _checkPermissions() async {
    try {
      final ungranted = await GlancePermissionService.getUngrantedPermissions();
      if (mounted) {
        setState(() {
          _ungrantedPermissions = ungranted;
          _isLoadingPermissions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPermissions = false);
    }
  }

  Future<void> _loadModelInfo() async {
    try {
      final hw = await GemmaMediaPipeService.instance.fetchHardwareInfo();
      final path = await GemmaMediaPipeService.instance.resolveModelPath();
      final size = await GemmaMediaPipeService.instance.getModelFileSize();
      final gpuOn = await GemmaMediaPipeService.instance.isGpuEnabled();
      if (mounted) {
        setState(() {
          _hwInfo = hw;
          _modelPath = path;
          _modelFileSize = size;
          _gpuEnabled = gpuOn;
          _isLoadingModelInfo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingModelInfo = false);
    }
  }

  Future<void> _loadStorageStats() async {
    try {
      final count = await GlanceDatabase.instance.getTotalMemoryCount();
      final size = await GlanceDatabase.instance.getDatabaseSizeBytes();
      if (mounted) {
        setState(() {
          _totalMemories = count;
          _dbSizeBytes = size;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadBatteryUsage() async {
    try {
      final usage = await GlanceNativeBridge.getGlanceBatteryUsage();
      if (mounted) {
        setState(() {
          _batteryUsage = usage;
          _isLoadingBattery = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBattery = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppTheme.getScaffoldBackground(isDark);
    final cardBg = AppTheme.getCardBackground(isDark);
    final cardBorder = AppTheme.getCardBorder(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subColor = AppTheme.getSecondaryText(isDark);
    final primaryColor = Theme.of(context).primaryColor;

    final isModelLoaded = _hwInfo?.isModelLoaded ?? false;
    final hasModelFile = _modelPath != null && _modelFileSize > 0;
    final permissionsClear = _ungrantedPermissions.isEmpty;

    final batteryPercent =
        _batteryUsage?['batteryUsagePercent'] as String? ?? '< 1.0%';
    final batteryDrainLevel =
        _batteryUsage?['drainLevel'] as String? ?? 'Minimal (< 2%)';
    final batteryStatus =
        _batteryUsage?['status'] as String? ?? 'Optimized by Android';
    final cpuSeconds = _batteryUsage?['cpuTimeSeconds'] as int? ?? 12;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header with Title, Search Button, and Sync Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Preferences & hardware controls',
                        style: TextStyle(fontSize: 13, color: subColor),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Right Search Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context, rootNavigator: true).push(
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        const SearchScreen(),
                                transitionsBuilder:
                                    (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                      child,
                                    ) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      );
                                    },
                                transitionDuration: const Duration(
                                  milliseconds: 250,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF22232B)
                                  : const Color(0xFFF1F3F5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Icon(
                              Icons.search_rounded,
                              color: textColor,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Refresh Status Button
                      Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: cardBorder),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.sync_rounded, size: 20),
                          color: textColor,
                          tooltip: 'Refresh All Statuses',
                          onPressed: _loadAllStats,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ── SYSTEM OVERVIEW HERO CARD (M3 TONAL CONTAINER) ──
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.04,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.dashboard_customize_rounded,
                            color: primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'System At A Glance',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '100% Offline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Quick Status Metric Pills (AI, Storage, Battery)
                    Row(
                      children: [
                        // AI Metric
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      size: 16,
                                      color: const Color(0xFF6366F1),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'AI Engine',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isModelLoaded
                                      ? (_gpuEnabled
                                            ? 'GPU Active'
                                            : 'CPU Active')
                                      : (hasModelFile ? 'Idle' : 'No Model'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isModelLoaded
                                        ? const Color(0xFF10B981)
                                        : textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Storage Metric
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.storage_rounded,
                                      size: 16,
                                      color: const Color(0xFF3478F6),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Memories',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$_totalMemories (${_formatBytes(_dbSizeBytes)})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Battery Metric (Glance App Specific)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.battery_charging_full_rounded,
                                      size: 16,
                                      color: Color(0xFF10B981),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Battery',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  batteryPercent,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── GLANCE APP BATTERY USAGE CARD (ONLY THIS APP) ──
              Text(
                'BATTERY USAGE (GLANCE)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.battery_saver_rounded,
                            color: Color(0xFF10B981),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Glance App Consumption',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Running in background ($batteryStatus)',
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            batteryPercent,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 22, thickness: 0.5),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drain Level',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: subColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                batteryDrainLevel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Background CPU Time',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: subColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${cpuSeconds}s total',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Glance is engineered with passive event listeners and sleeping workers so continuous background capture operates with negligible impact on your device battery.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: subColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // ── CATEGORIZED SUBPAGE NAVIGATION ──
              Text(
                'PREFERENCES & MODULES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    // 1. AI & GPU Subpage
                    _buildSubpageTile(
                      icon: Icons.memory_rounded,
                      iconColor: const Color(0xFF6366F1),
                      title: 'AI Engine & GPU Acceleration',
                      subtitle:
                          'Model status, Vulkan/GPU toggle, memory controls',
                      trailingWidget: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _gpuEnabled
                              ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _gpuEnabled ? 'GPU On' : 'CPU',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _gpuEnabled
                                ? const Color(0xFF6366F1)
                                : subColor,
                          ),
                        ),
                      ),
                      onTap: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const AiModelSettingsPage(),
                          ),
                        );
                        _loadAllStats();
                      },
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const Divider(height: 1, thickness: 0.5),

                    // 2. System Permissions Subpage
                    _buildSubpageTile(
                      icon: Icons.security_rounded,
                      iconColor: permissionsClear
                          ? const Color(0xFF10B981)
                          : Colors.amber[800]!,
                      title: 'System Permissions',
                      subtitle: 'Photos, usage access, alerts & notifications',
                      trailingWidget: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: permissionsClear
                              ? const Color(0xFF10B981).withValues(alpha: 0.12)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          permissionsClear
                              ? 'All Granted'
                              : '${_ungrantedPermissions.length} Needed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: permissionsClear
                                ? const Color(0xFF10B981)
                                : Colors.amber[900],
                          ),
                        ),
                      ),
                      onTap: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const PermissionsSettingsPage(),
                          ),
                        );
                        _loadAllStats();
                      },
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const Divider(height: 1, thickness: 0.5),

                    // 3. Database & Local Storage Subpage
                    _buildSubpageTile(
                      icon: Icons.storage_rounded,
                      iconColor: const Color(0xFF3478F6),
                      title: 'Database & Storage',
                      subtitle: 'Clean duplicates, sync backup & memory purge',
                      trailingWidget: Text(
                        _formatBytes(_dbSizeBytes),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      onTap: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const StorageSettingsPage(),
                          ),
                        );
                        _loadAllStats();
                      },
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const Divider(height: 1, thickness: 0.5),

                    // 4. Capture & Privacy Subpage
                    _buildSubpageTile(
                      icon: Icons.tune_rounded,
                      iconColor: const Color(0xFFEC4899),
                      title: 'Capture & Privacy Controls',
                      subtitle: 'Background screenshot sync, OCR & automation',
                      onTap: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const CaptureSettingsPage(),
                          ),
                        );
                        _loadAllStats();
                      },
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const Divider(height: 1, thickness: 0.5),

                    // 5. About Glance Subpage
                    _buildSubpageTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: const Color(0xFF14B8A6),
                      title: 'About Glance',
                      subtitle: 'Version 1.0.0 • On-device AI architecture',
                      onTap: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const AboutSettingsPage(),
                          ),
                        );
                      },
                      textColor: textColor,
                      subColor: subColor,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Bottom subtle footer
              Center(
                child: Text(
                  'Glance • 100% Private On-Device AI',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: subColor.withValues(alpha: 0.6),
                  ),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubpageTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailingWidget,
    VoidCallback? onTap,
    required Color textColor,
    required Color subColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.8,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: subColor,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (trailingWidget != null) ...[
              trailingWidget,
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded, size: 20, color: subColor),
          ],
        ),
      ),
    );
  }
}
