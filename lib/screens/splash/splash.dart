import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/gemma_mediapipe_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _initApp();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    final hasSeenPermission = prefs.getBool('has_seen_permission') ?? false;

    // Model initialization is deferred to VisionService on Home Screen to keep launch light and responsive

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        if (hasSeenOnboarding && hasSeenPermission) {
          // Returning user: visited onboarding and permission -> go straight to Home
          context.go('/home');
        } else if (!hasSeenOnboarding) {
          // First-time user: start onboarding
          context.go('/onboarding');
        } else {
          // Completed onboarding but not permission -> continue to permission
          context.go('/permission');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final borderColor = isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Card Container with Logo moving randomly then fixing to target percentage padding (top: 10%, right: 2%, bottom: 30%, left: 20%)
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  final t = _animController.value;

                  // Random floating movement amplitude decreases smoothly to 0 as it settles
                  final settleFactor = (1.0 - CurvedAnimation(
                    parent: _animController,
                    curve: const Interval(0.6, 1.0, curve: Curves.easeInOutCubic),
                  ).value);

                  final randomX = math.sin(t * math.pi * 6) * 18.0 * settleFactor;
                  final randomY = math.cos(t * math.pi * 5) * 14.0 * settleFactor;

                  return Transform.translate(
                    offset: Offset(randomX, randomY),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        return Padding(
                          padding: EdgeInsets.only(
                            top: h * 0.10,    // 10% top padding
                            right: w * 0.02,  // 2% right padding
                            bottom: h * 0.30, // 30% bottom padding
                            left: w * 0.20,   // 20% left padding
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Glance',
              style: TextStyle(
                fontFamily: 'PlaywriteAR',
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
