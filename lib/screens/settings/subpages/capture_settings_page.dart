import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme.dart';
import '../widgets/privacy_hero_card.dart';

class CaptureSettingsPage extends StatefulWidget {
  const CaptureSettingsPage({super.key});

  @override
  State<CaptureSettingsPage> createState() => _CaptureSettingsPageState();
}

class _CaptureSettingsPageState extends State<CaptureSettingsPage> {
  bool _bgCapture = true;
  bool _autoOcr = true;
  bool _notifCapture = true;
  bool _usageTracking = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bgCapture = prefs.getBool('pref_bg_capture') ?? true;
      _autoOcr = prefs.getBool('pref_auto_ocr') ?? true;
      _notifCapture = prefs.getBool('pref_notif_capture') ?? true;
      _usageTracking = prefs.getBool('pref_usage_tracking') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _setPreference(String key, bool val, void Function(bool) update) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
    setState(() {
      update(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppTheme.getScaffoldBackground(isDark);
    final cardBg = AppTheme.getCardBackground(isDark);
    final cardBorder = AppTheme.getCardBorder(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subColor = AppTheme.getSecondaryText(isDark);

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
          'Capture & Privacy',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: true,
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
                    const PrivacyHeroCard(),
                    const SizedBox(height: 24),

                    Text(
                      'AUTOMATION CONTROLS',
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
                          _buildSwitchTile(
                            icon: Icons.screenshot_monitor_rounded,
                            iconColor: const Color(0xFF6366F1),
                            title: 'Background Sync',
                            subtitle: 'Syncs new screenshots as you browse other apps',
                            value: _bgCapture,
                            onChanged: (v) => _setPreference('pref_bg_capture', v, (val) => _bgCapture = val),
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildSwitchTile(
                            icon: Icons.document_scanner_rounded,
                            iconColor: const Color(0xFF10B981),
                            title: 'Smart OCR Indexing',
                            subtitle: 'Extracts and indexes text from images on-device',
                            value: _autoOcr,
                            onChanged: (v) => _setPreference('pref_auto_ocr', v, (val) => _autoOcr = val),
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildSwitchTile(
                            icon: Icons.notifications_active_rounded,
                            iconColor: const Color(0xFFF59E0B),
                            title: 'Notification Ingestion',
                            subtitle: 'Captures incoming chat messages and alerts',
                            value: _notifCapture,
                            onChanged: (v) => _setPreference('pref_notif_capture', v, (val) => _notifCapture = val),
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),
                          _buildSwitchTile(
                            icon: Icons.timeline_rounded,
                            iconColor: const Color(0xFFEC4899),
                            title: 'Usage Context Tracking',
                            subtitle: 'Records app usage intervals for timeline context',
                            value: _usageTracking,
                            onChanged: (v) => _setPreference('pref_usage_tracking', v, (val) => _usageTracking = val),
                            textColor: textColor,
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

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color textColor,
    required Color subColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
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
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            activeColor: const Color(0xFF6366F1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
