import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/glance_db.dart';
import '../../../core/providers/glance_providers.dart';
import '../../../core/theme/theme.dart';

class StorageSettingsPage extends ConsumerStatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  ConsumerState<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends ConsumerState<StorageSettingsPage> {
  int _totalMemories = 0;
  int _dbSizeBytes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final count = await GlanceDatabase.instance.getTotalMemoryCount();
      final size = await GlanceDatabase.instance.getDatabaseSizeBytes();
      if (mounted) {
        setState(() {
          _totalMemories = count;
          _dbSizeBytes = size;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleCleanDuplicates() async {
    final messenger = ScaffoldMessenger.of(context);
    final deletedCount = await GlanceDatabase.instance.cleanAllDuplicateMemories();
    ref.invalidate(allMemoriesProvider);
    await _loadStats();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          deletedCount > 0
              ? 'Removed $deletedCount duplicate memories!'
              : 'Database is already clean. No duplicates found.',
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSyncToMediaStorage() async {
    final messenger = ScaffoldMessenger.of(context);
    await GlanceDatabase.instance.syncToMediaStorage();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Database synchronized to media storage!'),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleWipeAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text('Wipe All Memories?'),
          ],
        ),
        content: const Text(
          'This will permanently delete all indexed memories, screenshots, notes, and AI vector embeddings from your device database.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Wipe Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final deleted = await GlanceDatabase.instance.clearAllMemories();
      ref.invalidate(allMemoriesProvider);
      await _loadStats();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Cleared $deleted memories from local database.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Database & Storage',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: textColor,
            tooltip: 'Refresh Stats',
            onPressed: _loadStats,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── OVERVIEW HERO CARD ──
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.storage_rounded, color: primaryColor, size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_totalMemories Memories Saved',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Database Size: ${_formatBytes(_dbSizeBytes)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: subColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Storage Path',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: subColor),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '/storage/emulated/0/Android/media/com.example.glance/.glance/glance.db',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: isDark ? Colors.grey[300] : const Color(0xFF374151),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── MAINTENANCE & PURGE ACTIONS ──
                    Text(
                      'DATABASE MAINTENANCE',
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
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          _buildStorageActionTile(
                            icon: Icons.cleaning_services_outlined,
                            iconColor: const Color(0xFF10B981),
                            title: 'Clean Duplicate Entries',
                            subtitle: 'Removes identical screenshots and duplicate logs',
                            onTap: _handleCleanDuplicates,
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildStorageActionTile(
                            icon: Icons.sync_rounded,
                            iconColor: const Color(0xFF3478F6),
                            title: 'Sync to Media Storage',
                            subtitle: 'Verifies database integrity in hidden media store',
                            onTap: _handleSyncToMediaStorage,
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildStorageActionTile(
                            icon: Icons.delete_forever_outlined,
                            iconColor: Colors.red,
                            title: 'Wipe All Saved Memories',
                            subtitle: 'Irreversibly deletes all memories, notes, and vectors',
                            onTap: _handleWipeAllData,
                            textColor: Colors.red,
                            subColor: subColor,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStorageActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color textColor,
    required Color subColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
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
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: subColor),
          ],
        ),
      ),
    );
  }
}
