import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 05 — Emotional rediscovery value.
/// "Some things are worth finding again."
class StageRediscovery extends StatefulWidget {
  final VoidCallback onContinue;
  const StageRediscovery({super.key, required this.onContinue});

  @override
  State<StageRediscovery> createState() => _StageRediscoveryState();
}

class _StageRediscoveryState extends State<StageRediscovery> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
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
              'Some things are\nworth finding again.',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.55, curve: Curves.easeOut)),
            child: Text(
              'Your past can surface naturally, without\nasking you to remember it first.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL + 8),

          // "On This Day" card
          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.35, 0.75, curve: Curves.easeOut)),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
                CurvedAnimation(parent: _controller, curve: const Interval(0.35, 0.75, curve: Curves.easeOut)),
              ),
              child: _buildOnThisDayCard(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingLG),

          // Rediscoveries concept
          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: OnboardingTheme.card(context),
                borderRadius: BorderRadius.circular(OnboardingTheme.radiusMD),
                border: Border.all(color: OnboardingTheme.divider.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, size: 18, color: OnboardingTheme.secondary(context)),
                      const SizedBox(width: 8),
                      Text(
                        'Rediscoveries',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: OnboardingTheme.primary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Relevant fragments from your past surfaced by time and context.',
                    style: OnboardingTheme.body(context).copyWith(fontSize: 14),
                  ),
                ],
              ),
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
              child: const Text('Continue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  Widget _buildOnThisDayCard(BuildContext context) {
    final items = [
      ('Photo', Icons.photo_outlined),
      ('Website', Icons.language_outlined),
      ('Location', Icons.place_outlined),
      ('Screenshot', Icons.screenshot_outlined),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OnboardingTheme.card(context),
        borderRadius: BorderRadius.circular(OnboardingTheme.radiusMD),
        border: Border.all(color: OnboardingTheme.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today, last year',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: OnboardingTheme.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: items.map((item) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 64,
                  decoration: BoxDecoration(
                    color: OnboardingTheme.accentSoft.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.$2, size: 22, color: OnboardingTheme.secondary(context)),
                      const SizedBox(height: 4),
                      Text(
                        item.$1,
                        style: TextStyle(fontSize: 11, color: OnboardingTheme.secondary(context)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'You were here.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: OnboardingTheme.secondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
