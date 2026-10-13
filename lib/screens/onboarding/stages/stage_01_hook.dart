import 'dart:async';
import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 01 — Problem recognition hook.
/// "You know you saw it."
class StageHook extends StatefulWidget {
  final VoidCallback onContinue;
  const StageHook({super.key, required this.onContinue});

  @override
  State<StageHook> createState() => _StageHookState();
}

class _StageHookState extends State<StageHook> with TickerProviderStateMixin {
  late AnimationController _headlineController;
  late AnimationController _bodyController;
  late AnimationController _fragmentController;
  late Animation<double> _headlineFade;
  late Animation<double> _bodyFade;

  final List<String> _fragments = [
    'that website about WebRTC...',
    'that payment screenshot...',
    'that address...',
    'that error message...',
  ];
  int _currentFragment = 0;
  Timer? _fragmentTimer;

  @override
  void initState() {
    super.initState();

    _headlineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _bodyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fragmentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _headlineFade = CurvedAnimation(parent: _headlineController, curve: Curves.easeOut);
    _bodyFade = CurvedAnimation(parent: _bodyController, curve: Curves.easeOut);

    _headlineController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _bodyController.forward();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        _fragmentController.forward();
        _startFragmentCycle();
      }
    });
  }

  void _startFragmentCycle() {
    _fragmentTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _fragmentController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _currentFragment = (_currentFragment + 1) % _fragments.length;
        });
        _fragmentController.forward();
      });
    });
  }

  @override
  void dispose() {
    _fragmentTimer?.cancel();
    _headlineController.dispose();
    _bodyController.dispose();
    _fragmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnboardingTheme.marginH),
      child: Column(
        children: [
          const Spacer(flex: 3),

          // Headline
          FadeTransition(
            opacity: _headlineFade,
            child: Text(
              'You know you saw it.',
              style: OnboardingTheme.headline(context),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingLG),

          // Supporting text
          FadeTransition(
            opacity: _bodyFade,
            child: Text(
              'A website. A screenshot. A sentence.\nA place. But you can\'t remember where.',
              style: OnboardingTheme.body(context),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),

          // Animated floating fragment
          FadeTransition(
            opacity: CurvedAnimation(parent: _fragmentController, curve: Curves.easeInOut),
            child: Text(
              _fragments[_currentFragment],
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: OnboardingTheme.textTertiary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const Spacer(flex: 4),

          // CTA
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
              child: const Text('Find it', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }
}
