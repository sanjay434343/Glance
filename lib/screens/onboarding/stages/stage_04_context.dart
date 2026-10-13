import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 04 — Contextual intelligence.
/// "It remembers the context, too."
class StageContext extends StatefulWidget {
  final VoidCallback onContinue;
  const StageContext({super.key, required this.onContinue});

  @override
  State<StageContext> createState() => _StageContextState();
}

class _StageContextState extends State<StageContext> with TickerProviderStateMixin {
  late AnimationController _enterController;
  late AnimationController _relatedController;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _relatedController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _enterController.forward();
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _relatedController.forward();
    });
  }

  @override
  void dispose() {
    _enterController.dispose();
    _relatedController.dispose();
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
            opacity: CurvedAnimation(parent: _enterController, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
            child: Text(
              'It remembers\nthe context, too.',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterController,
              curve: const Interval(0.15, 0.65, curve: Curves.easeOut),
            ),
            child: Text(
              'Things you saw around the same time\ncan stay connected.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL),

          // Main item card
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterController,
              curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
            ),
            child: _buildMainCard(context),
          ),

          const SizedBox(height: OnboardingTheme.spacingMD),

          // "Related" label
          FadeTransition(
            opacity: CurvedAnimation(parent: _relatedController, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Related',
                style: OnboardingTheme.label(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: OnboardingTheme.textTertiary,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // Related items
          ..._buildRelatedItems(context),

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

  Widget _buildMainCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OnboardingTheme.card(context),
        borderRadius: BorderRadius.circular(OnboardingTheme.radiusMD),
        border: Border.all(color: OnboardingTheme.cta(context).withValues(alpha: 0.15), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: OnboardingTheme.accentSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.language_outlined, size: 22, color: OnboardingTheme.secondary(context)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WebRTC Guide',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: OnboardingTheme.primary(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  'Website · Apr 16 · 2:14 PM',
                  style: OnboardingTheme.label(context).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRelatedItems(BuildContext context) {
    final items = [
      ('WebRTC Screenshot', 'Screenshot', '2:11 PM', Icons.screenshot_outlined),
      ('Connection example', 'Copied text', '2:18 PM', Icons.content_copy_outlined),
      ('Payment UI', 'Screenshot', '2:22 PM', Icons.screenshot_outlined),
    ];

    return List.generate(items.length, (i) {
      // Safe stagger: begin 0.1–0.5, end 0.4–0.8
      final begin = 0.1 + (i / items.length) * 0.4;
      final end = (begin + 0.3).clamp(0.0, 1.0);
      final opacity = CurvedAnimation(
        parent: _relatedController,
        curve: Interval(begin, end, curve: Curves.easeOut),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FadeTransition(
          opacity: opacity,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(opacity),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: OnboardingTheme.card(context),
                borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
                border: Border.all(color: OnboardingTheme.divider.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: OnboardingTheme.accentSoft.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(items[i].$4, size: 18, color: OnboardingTheme.secondary(context)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].$1,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: OnboardingTheme.primary(context)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${items[i].$2} · ${items[i].$3}',
                          style: OnboardingTheme.label(context).copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
