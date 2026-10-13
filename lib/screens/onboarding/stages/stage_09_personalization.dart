import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 09 — Optional personalization.
/// "What do you usually want to find?"
class StagePersonalization extends StatefulWidget {
  final VoidCallback onContinue;
  const StagePersonalization({super.key, required this.onContinue});

  @override
  State<StagePersonalization> createState() => _StagePersonalizationState();
}

class _StagePersonalizationState extends State<StagePersonalization> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Set<String> _selected = {};

  final List<String> _options = [
    'Work',
    'Study',
    'Travel',
    'Shopping',
    'Places',
    'Ideas',
    'Projects',
    'Everything',
  ];

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnboardingTheme.marginH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: OnboardingTheme.spacingXXL + 16),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
            child: Text(
              'What do you usually\nwant to find?',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.1, 0.5, curve: Curves.easeOut)),
            child: Text(
              'Choose anything. You can change this later.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL),

          // Chips grid
          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.8, curve: Curves.easeOut)),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _options.map((option) => _buildChip(context, option)).toList(),
            ),
          ),

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
              child: const Text('Start exploring', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final isSelected = _selected.contains(label);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selected.remove(label);
          } else {
            _selected.add(label);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? OnboardingTheme.cta(context) : OnboardingTheme.card(context),
          borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
          border: Border.all(
            color: isSelected
                ? OnboardingTheme.cta(context)
                : OnboardingTheme.divider.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isSelected ? OnboardingTheme.ctaText(context) : OnboardingTheme.primary(context),
          ),
        ),
      ),
    );
  }
}
