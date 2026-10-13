import 'dart:async';
import 'package:flutter/material.dart';
import 'package:glance/core/services/vision_service.dart';
import '../../search/search_screen.dart';

class HomeTopBar extends StatelessWidget {
  final Color iconColor;
  final VoidCallback? onSearchTap;

  const HomeTopBar({
    super.key,
    required this.iconColor,
    this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Image.asset(
          'assets/images/logo.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
        ),
        const Spacer(),
        const VisionHeartbeatIndicator(),
        const SizedBox(width: 8),
        // ── Top Right Search Icon Button ──
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onSearchTap ??
                () {
                  Navigator.of(context, rootNavigator: true).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const SearchScreen(),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      transitionDuration: const Duration(milliseconds: 250),
                    ),
                  );
                },
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF22232B) : const Color(0xFFF1F3F5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Icon(
                Icons.search_rounded,
                color: iconColor,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pulsing Heartbeat Indicator for background Vision Queue processing
class VisionHeartbeatIndicator extends StatefulWidget {
  const VisionHeartbeatIndicator({super.key});

  @override
  State<VisionHeartbeatIndicator> createState() =>
      _VisionHeartbeatIndicatorState();
}

class _VisionHeartbeatIndicatorState extends State<VisionHeartbeatIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<VisionQueueStatus>? _subscription;
  VisionQueueStatus? _currentStatus;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _subscription = VisionService.instance.statusStream.listen((status) {
      if (mounted) {
        final wasProcessing = _currentStatus?.isProcessing ?? false;
        final isProcessing = status.isProcessing;

        setState(() {
          _currentStatus = status;
        });

        if (isProcessing && !wasProcessing) {
          _pulseController.repeat(reverse: true);
        } else if (!isProcessing && wasProcessing) {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _currentStatus;
    final isProcessing =
        status?.isProcessing ?? VisionService.instance.isProcessing;
    final queueLen = status?.queueLength ?? VisionService.instance.queueLength;

    if (!isProcessing && queueLen == 0) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusText = queueLen > 0 ? 'Processing ($queueLen)' : 'Processing';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(20), // Pill shape
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
