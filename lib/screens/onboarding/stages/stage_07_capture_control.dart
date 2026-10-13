import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 07 — Capture control & permission preparation.
/// "You decide what it remembers."
class StageCaptureControl extends StatefulWidget {
  final VoidCallback onContinue;
  const StageCaptureControl({super.key, required this.onContinue});

  @override
  State<StageCaptureControl> createState() => _StageCaptureControlState();
}

class _StageCaptureControlState extends State<StageCaptureControl> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  final Map<String, bool> _options = {
    'Screenshots': true,
    'Websites': true,
    'Copied text': true,
    'Files & documents': false,
    'Locations': false,
    'Notifications': false,
    'App activity': false,
  };

  final Map<String, IconData> _icons = {
    'Screenshots': Icons.screenshot_outlined,
    'Websites': Icons.language_outlined,
    'Copied text': Icons.content_copy_outlined,
    'Files & documents': Icons.insert_drive_file_outlined,
    'Locations': Icons.place_outlined,
    'Notifications': Icons.notifications_none_outlined,
    'App activity': Icons.apps_outlined,
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = _options.keys.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnboardingTheme.marginH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: OnboardingTheme.spacingXXL + 16),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
            child: Text(
              'You decide what\nit remembers.',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.1, 0.5, curve: Curves.easeOut)),
            child: Text(
              'Choose what the app can capture.\nYou can change this anytime.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingLG),

          // Options list
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: keys.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final key = keys[i];
                final stagger = i / keys.length;
                final anim = CurvedAnimation(
                  parent: _controller,
                  curve: Interval(0.2 + stagger * 0.15, 0.6 + stagger * 0.15, curve: Curves.easeOut),
                );
                return FadeTransition(
                  opacity: anim,
                  child: _buildToggleTile(context, key),
                );
              },
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingMD),

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
              child: const Text('Continue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  Widget _buildToggleTile(BuildContext context, String label) {
    final isOn = _options[label]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: OnboardingTheme.card(context),
        borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
        border: Border.all(
          color: isOn ? OnboardingTheme.cta(context).withValues(alpha: 0.2) : OnboardingTheme.divider.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _icons[label],
            size: 20,
            color: isOn ? OnboardingTheme.primary(context) : OnboardingTheme.textTertiary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isOn ? OnboardingTheme.primary(context) : OnboardingTheme.secondary(context),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: isOn,
              onChanged: (val) => setState(() => _options[label] = val),
              activeTrackColor: OnboardingTheme.cta(context),
            ),
          ),
        ],
      ),
    );
  }
}
