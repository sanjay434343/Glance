import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 08 — First capture / aha moment.
/// "Give it something to remember."
class StageFirstCapture extends StatefulWidget {
  final VoidCallback onContinue;
  const StageFirstCapture({super.key, required this.onContinue});

  @override
  State<StageFirstCapture> createState() => _StageFirstCaptureState();
}

class _StageFirstCaptureState extends State<StageFirstCapture> with TickerProviderStateMixin {
  late AnimationController _enterController;
  late AnimationController _capturedController;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _capturedController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _enterController.forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    _capturedController.dispose();
    super.dispose();
  }

  void _simulateCapture() {
    setState(() => _captured = true);
    _capturedController.forward();
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
            opacity: CurvedAnimation(parent: _enterController, curve: Curves.easeOut),
            child: Text(
              _captured ? 'Captured.' : 'Give it something\nto remember.',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterController,
              curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
            ),
            child: Text(
              _captured
                  ? 'We\'ve already made it searchable.'
                  : 'Capture one thing you might want\nto find later.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL + 8),

          if (!_captured) ...[
            // Capture action buttons
            ..._buildCaptureActions(context),
          ] else ...[
            // Success state
            FadeTransition(
              opacity: CurvedAnimation(parent: _capturedController, curve: Curves.easeOut),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                  CurvedAnimation(parent: _capturedController, curve: Curves.easeOut),
                ),
                child: _buildCapturedCard(context),
              ),
            ),
          ],

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
              child: Text(
                _captured ? 'Continue' : 'Skip for now',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  List<Widget> _buildCaptureActions(BuildContext context) {
    final actions = [
      ('Take a screenshot', Icons.screenshot_outlined),
      ('Save a link', Icons.link_outlined),
      ('Choose something', Icons.add_photo_alternate_outlined),
    ];

    return actions.map((action) {
      final i = actions.indexOf(action);
      final stagger = i / actions.length;
      final anim = CurvedAnimation(
        parent: _enterController,
        curve: Interval(0.3 + stagger * 0.2, 0.7 + stagger * 0.2, curve: Curves.easeOut),
      );

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FadeTransition(
          opacity: anim,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _simulateCapture,
              icon: Icon(action.$2, size: 20),
              label: Text(action.$1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: OnboardingTheme.primary(context),
                side: BorderSide(color: OnboardingTheme.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildCapturedCard(BuildContext context) {
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: OnboardingTheme.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.screenshot_outlined, size: 24, color: OnboardingTheme.secondary(context)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment UI',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: OnboardingTheme.primary(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  'Screenshot · just now',
                  style: OnboardingTheme.label(context).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, size: 22, color: const Color(0xFF4CAF50)),
        ],
      ),
    );
  }
}
