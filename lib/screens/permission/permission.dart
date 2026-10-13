import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isRequesting = false;

  Future<void> _completePermissionFlow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_permission', true);
    if (mounted) {
      context.go('/home');
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isRequesting = true;
    });

    try {
      await [
        Permission.photos,
        Permission.storage,
        Permission.notification,
        Permission.camera,
      ].request();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isRequesting = false;
      });
      await _completePermissionFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFFAF8F5);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? const Color(0xFFF0EFED) : const Color(0xFF111418);
    final subTextColor = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6B7280);
    final borderColor = isDark ? const Color(0xFF2E2E32) : const Color(0xFFE8E6E2);
    final ctaBg = isDark ? const Color(0xFFF0EFED) : const Color(0xFF1A1A1E);
    final ctaText = isDark ? const Color(0xFF121212) : Colors.white;
    final iconBg = isDark ? const Color(0xFF282830) : const Color(0xFFF0EFEB);
    final iconColor = isDark ? Colors.white : const Color(0xFF1A1A1E);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Icon Header Badge
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cardBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    size: 34,
                    color: iconColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Permissions for Glance',
                style: TextStyle(
                  fontFamily: 'PlaywriteAR',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'To index your screenshots and help you rediscovery anything instantly on your phone.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: subTextColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Permission items
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildPermissionCard(
                      icon: Icons.photo_library_outlined,
                      title: 'Photos & Media Storage',
                      subtitle: 'Required to index your screenshots and local photos for fast on-device recall.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      iconBg: iconBg,
                      iconColor: iconColor,
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    const SizedBox(height: 12),
                    _buildPermissionCard(
                      icon: Icons.notifications_active_outlined,
                      title: 'Notifications',
                      subtitle: 'Delivers memory digests, capture confirmations, and processing status.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      iconBg: iconBg,
                      iconColor: iconColor,
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    const SizedBox(height: 12),
                    _buildPermissionCard(
                      icon: Icons.camera_alt_outlined,
                      title: 'Camera Access',
                      subtitle: 'Allows quick instant capture of physical notes, receipts, and book snippets.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      iconBg: iconBg,
                      iconColor: iconColor,
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    const SizedBox(height: 16),

                    // Privacy notice pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B231C) : const Color(0xFFEDF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2E4530) : const Color(0xFFC8E6C9),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 20,
                            color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '100% On-Device & Private. Your data never leaves your device.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Action buttons
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isRequesting ? null : _requestPermissions,
                  style: FilledButton.styleFrom(
                    backgroundColor: ctaBg,
                    foregroundColor: ctaText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isRequesting
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: ctaText,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Allow & Continue',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: _isRequesting ? null : _completePermissionFlow,
                  style: TextButton.styleFrom(
                    foregroundColor: subTextColor,
                  ),
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color cardBg,
    required Color borderColor,
    required Color iconBg,
    required Color iconColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
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
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 13,
                    height: 1.35,
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
