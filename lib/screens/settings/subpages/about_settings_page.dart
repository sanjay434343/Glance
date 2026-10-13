import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

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
          'About Glance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Logo
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: cardBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: cardBorder, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Glance',
                style: TextStyle(
                  fontFamily: 'PlaywriteAR',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 1.0.0 (Release Build)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 28),

              // Architecture Features Card
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    _buildFeatureTile(
                      icon: Icons.shield_rounded,
                      iconColor: const Color(0xFF10B981),
                      title: '100% On-Device Privacy',
                      subtitle: 'Your memories, screenshots, and texts never leave this device. Zero servers.',
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const Divider(height: 1, thickness: 0.5),
                    _buildFeatureTile(
                      icon: Icons.bolt_rounded,
                      iconColor: const Color(0xFF6366F1),
                      title: 'Vulkan & GPU Acceleration',
                      subtitle: 'MediaPipe LLM leverages mobile GPU shaders for low-latency reasoning.',
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const Divider(height: 1, thickness: 0.5),
                    _buildFeatureTile(
                      icon: Icons.storage_rounded,
                      iconColor: const Color(0xFF3478F6),
                      title: 'Embedded SQLite Architecture',
                      subtitle: 'Full-text indexing with high-speed local vector search capabilities.',
                      textColor: textColor,
                      subColor: subColor,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              Text(
                'Built for pure private recall.',
                style: TextStyle(fontSize: 12.5, color: subColor.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required Color iconColor,
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
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: subColor,
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
