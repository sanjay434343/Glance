import 'package:flutter/material.dart';

import '../../../core/services/glance_permission_service.dart';
import '../../../core/theme/theme.dart';

class PermissionsSettingsPage extends StatefulWidget {
  const PermissionsSettingsPage({super.key});

  @override
  State<PermissionsSettingsPage> createState() => _PermissionsSettingsPageState();
}

class _PermissionsSettingsPageState extends State<PermissionsSettingsPage> with WidgetsBindingObserver {
  List<GlancePermissionItem> _ungrantedPermissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final ungranted = await GlancePermissionService.getUngrantedPermissions();
      if (mounted) {
        setState(() {
          _ungrantedPermissions = ungranted;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

    final allClear = _ungrantedPermissions.isEmpty;

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
          'System Permissions',
          style: TextStyle(
            fontFamily: 'DMSans',
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
            tooltip: 'Re-check Permissions',
            onPressed: () {
              setState(() => _isLoading = true);
              _checkPermissions();
            },
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
                    // ── STATUS HERO CARD ──
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: allClear
                              ? const Color(0xFF10B981).withValues(alpha: 0.35)
                              : Colors.amber.withValues(alpha: 0.35),
                        ),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: allClear
                                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                  : Colors.amber.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              allClear ? Icons.verified_rounded : Icons.warning_amber_rounded,
                              color: allClear ? const Color(0xFF10B981) : Colors.amber[800],
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  allClear ? 'All Permissions Granted' : 'Permissions Action Required',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  allClear
                                      ? 'Glance is fully authorized to index your visual moments.'
                                      : '${_ungrantedPermissions.length} permissions needed for full functionality.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── PENDING PERMISSIONS ──
                    if (!allClear) ...[
                      Text(
                        'REQUIRED ACTIONS',
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
                          children: _ungrantedPermissions.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            final isLast = idx == _ungrantedPermissions.length - 1;

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(item.icon, color: Colors.amber[800], size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w600,
                                                color: textColor,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.subtitle,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: subColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await item.onRequest();
                                          _checkPermissions();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: const Text(
                                          'Grant',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast) const Divider(height: 1, thickness: 0.5),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── PERMISSION DETAILS OVERVIEW ──
                    Text(
                      'ACTIVE PERMISSIONS',
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
                          _buildPermissionInfoTile(
                            icon: Icons.photo_library_outlined,
                            title: 'Photos & Media Storage',
                            subtitle: 'Allows Glance to index screenshots and images for rapid local recall.',
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildPermissionInfoTile(
                            icon: Icons.notifications_active_outlined,
                            title: 'Notifications & Alerts',
                            subtitle: 'Sends memory digests, system updates, and capture confirmations.',
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildPermissionInfoTile(
                            icon: Icons.apps_rounded,
                            title: 'Usage Access',
                            subtitle: 'Tracks active applications and context intervals for smarter summaries.',
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildPermissionInfoTile(
                            icon: Icons.camera_alt_outlined,
                            title: 'Camera Access',
                            subtitle: 'Enables instant camera capture of notes, receipts, and whiteboard items.',
                            textColor: textColor,
                            subColor: subColor,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Privacy Assurance Pill
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B231C) : const Color(0xFFEDF7ED),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2E4530) : const Color(0xFFC8E6C9),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 22,
                            color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Glance operates strictly offline. Granted permissions are never used to upload or share your personal data.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20),
                                height: 1.35,
                              ),
                            ),
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

  Widget _buildPermissionInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 18),
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
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
