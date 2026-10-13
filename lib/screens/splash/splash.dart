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
      duration: const Duration(milliseconds: 2000),
    )..forward();

    _handleSplashNavigation();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleSplashNavigation() async {
    final startTime = DateTime.now();

    // 1. In background, perform hardware scan once if not yet verified
    final prefs = await SharedPreferences.getInstance();
    final alreadyVerified = prefs.getBool('hardware_compatibility_verified') ?? false;

    if (!alreadyVerified) {
      try {
        final hw = await GemmaMediaPipeService.instance.fetchHardwareInfo();
        final meetsOs = hw.sdkInt >= 31;
        final meetsRam = hw.totalRamGB >= 7.2;
        final meetsGpu = hw.hasGpu;

        await prefs.setBool('hardware_compatibility_verified', true);
        await prefs.setBool('hardware_meets_os_12', meetsOs);
        await prefs.setBool('hardware_meets_ram_8gb', meetsRam);
        await prefs.setBool('hardware_meets_gpu', meetsGpu);
        await prefs.setString('hardware_cpu_name', hw.cpuName);
        await prefs.setString('hardware_gpu_name', hw.gpuName);
        await prefs.setDouble('hardware_total_ram_gb', hw.totalRamGB);
        await prefs.setInt('hardware_android_sdk', hw.sdkInt);
      } catch (_) {
        await prefs.setBool('hardware_compatibility_verified', true);
      }
    }

    // 2. Ensure splash stays visible for exactly 2 seconds
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final remainingMs = 2000 - elapsedMs;
    if (remainingMs > 0) {
      await Future.delayed(Duration(milliseconds: remainingMs));
    }

    if (mounted) {
      _navigateNext(prefs);
    }
  }

  void _navigateNext(SharedPreferences prefs) {
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    final hasSeenPermission = prefs.getBool('has_seen_permission') ?? false;

    if (hasSeenOnboarding && hasSeenPermission) {
      context.go('/home');
    } else if (!hasSeenOnboarding) {
      context.go('/onboarding');
    } else {
      context.go('/permission');
    }
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Circular Card Container with Animated Logo
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: cardBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    final t = _animController.value;
                    final settleFactor = (1.0 - CurvedAnimation(
                      parent: _animController,
                      curve: const Interval(0.6, 1.0, curve: Curves.easeInOutCubic),
                    ).value);

                    final randomX = math.sin(t * math.pi * 6) * 16.0 * settleFactor;
                    final randomY = math.cos(t * math.pi * 5) * 12.0 * settleFactor;

                    return Transform.translate(
                      offset: Offset(randomX, randomY),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final h = constraints.maxHeight;
                          return Padding(
                            padding: EdgeInsets.only(
                              top: h * 0.10,
                              right: w * 0.02,
                              bottom: h * 0.30,
                              left: w * 0.20,
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
            ],
          ),
        ),
      ),
    );
  }
}
