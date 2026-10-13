import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/memory_models.dart';
import '../../core/database/glance_db.dart';
import '../../core/native/glance_native_bridge.dart';
import 'package:intl/intl.dart';
import 'widgets/related_memories_carousel.dart';

class AppActivityDetailScreen extends StatefulWidget {
  final Memory memory;

  const AppActivityDetailScreen({super.key, required this.memory});

  @override
  State<AppActivityDetailScreen> createState() => _AppActivityDetailScreenState();
}

class _AppActivityDetailScreenState extends State<AppActivityDetailScreen> {
  late Memory _memory;
  int _usageTimeMs = 0;
  int _openCount = 0;
  int _totalAppCaptures = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _memory = widget.memory;
    _parseStatsFromSummary(_memory);
    _loadRealAppUsageData();
  }

  void _parseStatsFromSummary(Memory mem) {
    if (mem.summary != null && mem.summary!.isNotEmpty) {
      try {
        final map = jsonDecode(mem.summary!);
        _usageTimeMs = map['usageTimeMs'] as int? ?? 0;
        _openCount = map['openCount'] as int? ?? 0;
      } catch (_) {}
    }
  }

  Future<void> _loadRealAppUsageData() async {
    try {
      // 1. Fetch latest record from SQLite database
      final dbMem = await GlanceDatabase.instance.getMemory(widget.memory.id);
      if (dbMem != null) {
        _memory = dbMem;
        _parseStatsFromSummary(dbMem);
      }

      // 2. Query real live app activity from system if package is available
      final pkg = _memory.sourcePackage;
      if (pkg != null && pkg.isNotEmpty) {
        final liveApps = await GlanceNativeBridge.getAppActivity();
        final match = liveApps.firstWhere(
          (a) => a['packageName'] == pkg,
          orElse: () => {},
        );

        if (match.isNotEmpty) {
          final liveUsage = match['usageTimeMs'] as int? ?? 0;
          final liveOpens = match['openCount'] as int? ?? 0;
          final liveTs = match['timestamp'] as int? ?? _memory.capturedAt;

          if (liveUsage > 0 || liveOpens > 0) {
            _usageTimeMs = liveUsage;
            _openCount = liveOpens;

            // Persist the real captured stats to SQLite DB
            final statsJson = jsonEncode({
              'openCount': _openCount,
              'usageTimeMs': _usageTimeMs,
            });
            final updated = Memory(
              id: _memory.id,
              type: _memory.type,
              title: _memory.title,
              content: _memory.content,
              source: _memory.source,
              sourceApp: _memory.sourceApp,
              sourcePackage: pkg,
              url: _memory.url,
              filePath: _memory.filePath,
              thumbnailPath: _memory.thumbnailPath,
              summary: statsJson,
              capturedAt: liveTs,
              createdAt: _memory.createdAt,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
            _memory = updated;
            await GlanceDatabase.instance.insertMemory(updated);
          }
        }

        // 3. Count total real memories in database for this app
        final allMem = await GlanceDatabase.instance.getAllMemories();
        _totalAppCaptures = allMem.where((m) =>
          m.sourcePackage == pkg || (m.sourceApp != null && m.sourceApp == _memory.title)
        ).length;
      }
    } catch (e) {
      debugPrint('[AppActivityDetailScreen] Error fetching real activity: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '0m';
    final totalSec = ms ~/ 1000;
    if (totalSec < 60) return '${totalSec}s';
    final mins = totalSec ~/ 60;
    if (mins < 60) {
      final remSec = totalSec % 60;
      return remSec > 0 ? '${mins}m ${remSec}s' : '${mins}m';
    }
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    return remMins > 0 ? '${hours}h ${remMins}m' : '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    final memory = _memory;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    // Expressive M3 palette with pure white background in light mode
    final bgColor = isDark ? const Color(0xFF121315) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E2024) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final buttonColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1D21);
    const buttonIconColor = Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2E3238) : const Color(0xFFE2E8F0);

    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(memory.capturedAt),
    );

    final durationStr = _formatDuration(_usageTimeMs);
    final openCount = _openCount;
    final usageTimeMs = _usageTimeMs;

    final appCleanName = memory.title;
    final tags = ['App', 'Activity', appCleanName, 'Screen Time', 'Usage'];

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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Package: ${memory.sourcePackage ?? memory.title}',
                        style: const TextStyle(fontFamily: 'DMSans'),
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
                    Icons.info_outline_rounded,
                    color: buttonIconColor,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TweenAnimationBuilder<double>(
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
                    // HERO APP PREVIEW CARD
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
                            // Center Icon Showcase with gradient backdrop
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? [const Color(0xFF1E2228), const Color(0xFF131518)]
                                      : [const Color(0xFFFDFEFE), const Color(0xFFF1F4F9)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // App Icon with shadow
                                    Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF25282E)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(26),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: (memory.imageBase64 != null && memory.imageBase64!.isNotEmpty)
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(26),
                                              child: Image.memory(
                                                base64Decode(memory.imageBase64!),
                                                width: 96,
                                                height: 96,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Icon(
                                                  Icons.apps_rounded,
                                                  size: 48,
                                                  color: primaryColor,
                                                ),
                                              ),
                                            )
                                          : FutureBuilder<String?>(
                                              future: memory.sourcePackage != null
                                                  ? GlanceDatabase.instance
                                                      .getAppIcon(memory.sourcePackage!)
                                                  : Future.value(null),
                                              builder: (context, snapshot) {
                                                if (snapshot.hasData &&
                                                    snapshot.data!.isNotEmpty) {
                                                  try {
                                                    return ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(26),
                                                      child: Image.memory(
                                                        base64Decode(snapshot.data!),
                                                        width: 96,
                                                        height: 96,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, _, _) =>
                                                            Icon(
                                                          Icons.apps_rounded,
                                                          size: 48,
                                                          color: primaryColor,
                                                        ),
                                                      ),
                                                    );
                                                  } catch (_) {}
                                                }
                                                return Icon(
                                                  Icons.apps_rounded,
                                                  size: 48,
                                                  color: primaryColor,
                                                );
                                              },
                                            ),
                                    ),
                                    const SizedBox(height: 18),

                                    // Usage Duration Highlight
                                    Text(
                                      durationStr,
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontFamily: 'DMSans',
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      openCount > 0 ? '$openCount Opens' : 'Recorded Activity',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
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

                            // Bottom-Right Package Pill
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.touch_app_rounded, size: 13, color: primaryColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$openCount Opens',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
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
                            appCleanName,
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
                                icon: Icons.apps_rounded,
                                label: 'Application',
                                isDark: isDark,
                                primaryColor: primaryColor,
                              ),
                              _buildMetaBadge(
                                icon: Icons.timer_rounded,
                                label: durationStr,
                                isDark: isDark,
                                primaryColor: primaryColor,
                              ),
                              _buildMetaBadge(
                                icon: Icons.touch_app_rounded,
                                label: '$openCount Sessions',
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
                            children: tags.map((t) {
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
                          // RECORDED USAGE STATISTICS CARD
                          // ==========================================
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.insights_rounded,
                                      size: 18,
                                      color: primaryColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'RECORDED USAGE STATISTICS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _buildStatItem(
                                  icon: Icons.timer_outlined,
                                  label: 'Total Foreground Screen Time',
                                  value: durationStr,
                                  subValue: usageTimeMs > 0
                                      ? '${(usageTimeMs / 1000).toStringAsFixed(0)}s total active duration'
                                      : 'Foreground session recorded',
                                  isDark: isDark,
                                  textColor: textColor,
                                  textSecondary: textSecondary,
                                  primaryColor: primaryColor,
                                ),
                                const Divider(height: 24),
                                _buildStatItem(
                                  icon: Icons.touch_app_outlined,
                                  label: 'App Launch Count',
                                  value: '$openCount ${openCount == 1 ? "Launch" : "Launches"}',
                                  subValue: 'Recorded foreground sessions on device',
                                  isDark: isDark,
                                  textColor: textColor,
                                  textSecondary: textSecondary,
                                  primaryColor: primaryColor,
                                ),
                                const Divider(height: 24),
                                _buildStatItem(
                                  icon: Icons.access_time_rounded,
                                  label: 'Last Recorded Session',
                                  value: dateStr,
                                  subValue: 'System usage event timestamp',
                                  isDark: isDark,
                                  textColor: textColor,
                                  textSecondary: textSecondary,
                                  primaryColor: primaryColor,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ==========================================
                          // DETAILS CARD
                          // ==========================================
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                      color: primaryColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'DETAILS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildDetailRow(
                                  'Application Name',
                                  appCleanName,
                                  textColor,
                                  textSecondary,
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  'Package Name',
                                  memory.sourcePackage ?? 'system.app',
                                  textColor,
                                  textSecondary,
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  'Foreground Usage Time',
                                  durationStr,
                                  textColor,
                                  textSecondary,
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  'Total Launches',
                                  '$openCount',
                                  textColor,
                                  textSecondary,
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  'Associated Captures',
                                  '$_totalAppCaptures in Glance',
                                  textColor,
                                  textSecondary,
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  'Captured At',
                                  dateStr,
                                  textColor,
                                  textSecondary,
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  'Storage Status',
                                  'Offline SQLite DB',
                                  textColor,
                                  textSecondary,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ==========================================
                          // RELATED CAPTURES CAROUSEL
                          // ==========================================
                          RelatedMemoriesCarousel(
                            currentMemory: memory,
                            tags: tags,
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

  Widget _buildDetailRow(
    String label,
    String value,
    Color textColor,
    Color textSecondary,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required String subValue,
    required bool isDark,
    required Color textColor,
    required Color textSecondary,
    required Color primaryColor,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: primaryColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subValue,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
