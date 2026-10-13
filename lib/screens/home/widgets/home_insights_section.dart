import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../../core/models/memory_models.dart';

class HomeInsightsSection extends StatelessWidget {
  final List<Memory> memories;
  final bool isDark;
  final VoidCallback? onExploreTap;

  const HomeInsightsSection({
    super.key,
    required this.memories,
    required this.isDark,
    this.onExploreTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.getPrimaryText(isDark);
    final textSecondary = AppTheme.getSecondaryText(isDark);
    final cardBg = AppTheme.getCardBackground(isDark);
    final cardBorder = AppTheme.getCardBorder(isDark);

    // Calculate dynamic insights from real memories
    final totalCount = memories.length;
    final now = DateTime.now();
    final todayCount = memories.where((m) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.capturedAt);
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;

    // Frequent apps breakdown
    final Map<String, int> appCounts = {};
    for (final m in memories) {
      final app = m.sourceApp ?? m.source ?? 'Other';
      if (app.trim().isNotEmpty) {
        appCounts[app] = (appCounts[app] ?? 0) + 1;
      }
    }
    final sortedApps = appCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topApp = sortedApps.isNotEmpty ? sortedApps.first.key : 'None';
    final topAppCount = sortedApps.isNotEmpty ? sortedApps.first.value : 0;

    // AI processed count
    final processedCount = memories.where((m) => m.isProcessed || (m.summary != null && m.summary!.isNotEmpty)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3478F6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: Color(0xFF3478F6),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Memory Insights',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            if (onExploreTap != null)
              GestureDetector(
                onTap: onExploreTap,
                child: Text(
                  'View all',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF3478F6),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // Metrics Grid (2x2)
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Today Captured',
                value: '$todayCount',
                subtitle: totalCount > 0 ? '${((todayCount / totalCount) * 100).toStringAsFixed(0)}% of total' : 'No records',
                icon: Icons.today_rounded,
                accentColor: const Color(0xFF3478F6),
                textColor: textColor,
                textSecondary: textSecondary,
                cardBg: cardBg,
                cardBorder: cardBorder,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'Top Source App',
                value: topApp.length > 10 ? '${topApp.substring(0, 10)}…' : topApp,
                subtitle: topAppCount > 0 ? '$topAppCount memories' : 'Awaiting data',
                icon: Icons.apps_rounded,
                accentColor: const Color(0xFF5856D6),
                textColor: textColor,
                textSecondary: textSecondary,
                cardBg: cardBg,
                cardBorder: cardBorder,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'AI Indexed',
                value: '$processedCount',
                subtitle: '$totalCount total items',
                icon: Icons.psychology_rounded,
                accentColor: const Color(0xFF34C759),
                textColor: textColor,
                textSecondary: textSecondary,
                cardBg: cardBg,
                cardBorder: cardBorder,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'Recall Ready',
                value: totalCount > 0 ? '100%' : '0%',
                subtitle: 'Offline searchable',
                icon: Icons.shield_rounded,
                accentColor: const Color(0xFFFF9500),
                textColor: textColor,
                textSecondary: textSecondary,
                cardBg: cardBg,
                cardBorder: cardBorder,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color textColor,
    required Color textSecondary,
    required Color cardBg,
    required Color cardBorder,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                  letterSpacing: -0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textSecondary.withOpacity(0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
