import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 06 — Privacy trust building.
/// "This is your memory. Not ours."
class StagePrivacy extends StatefulWidget {
  final VoidCallback onContinue;
  const StagePrivacy({super.key, required this.onContinue});

  @override
  State<StagePrivacy> createState() => _StagePrivacyState();
}

class _StagePrivacyState extends State<StagePrivacy> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final privacyPoints = [
      _PrivacyPoint(Icons.phone_android_outlined, 'On-device processing', 'Process supported data locally whenever possible.'),
      _PrivacyPoint(Icons.lock_outline, 'Private by default', 'Do not require cloud storage for the core experience.'),
      _PrivacyPoint(Icons.tune_outlined, 'You decide', 'Choose what the app can capture and index.'),
      _PrivacyPoint(Icons.delete_outline, 'Delete anytime', 'Provide clear controls to remove indexed data.'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnboardingTheme.marginH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: OnboardingTheme.spacingXXL + 16),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.35, curve: Curves.easeOut)),
            child: Text(
              'This is your memory.\nNot ours.',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.1, 0.45, curve: Curves.easeOut)),
            child: Text(
              'Your personal data should remain\nunder your control.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL + 8),

          // Privacy points
          ...List.generate(privacyPoints.length, (i) {
            final stagger = i / privacyPoints.length;
            final anim = CurvedAnimation(
              parent: _controller,
              curve: Interval(0.25 + stagger * 0.2, 0.65 + stagger * 0.2, curve: Curves.easeOut),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
                  child: _buildPrivacyTile(context, privacyPoints[i]),
                ),
              ),
            );
          }),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: widget.onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: OnboardingTheme.cta(context),
                foregroundColor: OnboardingTheme.ctaText(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
                ),
                elevation: 0,
              ),
              child: const Text('Choose what to remember', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  Widget _buildPrivacyTile(BuildContext context, _PrivacyPoint point) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnboardingTheme.card(context),
        borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
        border: Border.all(color: OnboardingTheme.divider.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: OnboardingTheme.accentSoft.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(point.icon, size: 20, color: OnboardingTheme.secondary(context)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: OnboardingTheme.primary(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  point.description,
                  style: OnboardingTheme.label(context).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPoint {
  final IconData icon;
  final String title;
  final String description;
  const _PrivacyPoint(this.icon, this.title, this.description);
}
