import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_theme.dart';
import 'stages/stage_01_hook.dart';
import 'stages/stage_02_concept.dart';
import 'stages/stage_03_search.dart';
import 'stages/stage_04_context.dart';
import 'stages/stage_05_rediscovery.dart';
import 'stages/stage_06_privacy.dart';
import 'stages/stage_07_capture_control.dart';
import 'stages/stage_08_first_capture.dart';
import 'stages/stage_09_personalization.dart';

/// 9-stage progressive narrative onboarding for Glance.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalStages = 9;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _goNext() async {
    if (_currentPage < _totalStages - 1) {
      _pageController.nextPage(
        duration: OnboardingTheme.transitionDuration,
        curve: Curves.easeInOut,
      );
    } else {
      // Last stage — navigate to permission screen
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      if (mounted) {
        context.go('/permission');
      }
    }
  }

  void _goBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: OnboardingTheme.transitionDuration,
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar + back button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnboardingTheme.marginH,
                vertical: 12,
              ),
              child: Row(
                children: [
                  // Back button (hidden on first page)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: _currentPage > 0
                        ? GestureDetector(
                            onTap: _goBack,
                            child: Icon(
                              Icons.arrow_back_ios_new,
                              size: 18,
                              color: OnboardingTheme.secondary(context),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // Subtle segmented progress
                  Expanded(child: _buildProgress(context)),

                  const SizedBox(width: 48), // balance the back button
                ],
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // controlled navigation only
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  StageHook(onContinue: _goNext),
                  StageConcept(onContinue: _goNext),
                  StageSearch(onContinue: _goNext),
                  StageContext(onContinue: _goNext),
                  StageRediscovery(onContinue: _goNext),
                  StagePrivacy(onContinue: _goNext),
                  StageCaptureControl(onContinue: _goNext),
                  StageFirstCapture(onContinue: _goNext),
                  StagePersonalization(onContinue: _goNext),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Subtle segmented progress indicator (not carousel dots).
  Widget _buildProgress(BuildContext context) {
    return Row(
      children: List.generate(_totalStages, (i) {
        final isCompleted = i < _currentPage;
        final isCurrent = i == _currentPage;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: isCompleted
                  ? OnboardingTheme.cta(context)
                  : isCurrent
                      ? OnboardingTheme.cta(context).withValues(alpha: 0.45)
                      : OnboardingTheme.divider.withValues(alpha: 0.5),
            ),
          ),
        );
      }),
    );
  }
}
