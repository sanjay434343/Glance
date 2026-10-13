import 'dart:async';
import 'package:flutter/material.dart';
import 'package:glance/core/services/vision_service.dart';
import 'package:glance/core/services/document_extraction_service.dart';
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
  StreamSubscription<VisionQueueStatus>? _visionSubscription;
  StreamSubscription<DocumentProcessingStatus>? _docSubscription;
  VisionQueueStatus? _currentVisionStatus;
  DocumentProcessingStatus? _currentDocStatus;

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

    _visionSubscription = VisionService.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _currentVisionStatus = status;
        });
        _evaluateAnimation();
      }
    });

    _docSubscription = DocumentExtractionService.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _currentDocStatus = status;
        });
        _evaluateAnimation();
      }
    });

    _evaluateAnimation();
  }

  void _evaluateAnimation() {
    final isVisionActive = (_currentVisionStatus?.isProcessing ?? false) ||
        VisionService.instance.isProcessing;
    final isDocActive = (_currentDocStatus?.isProcessing ?? false) ||
        DocumentExtractionService.instance.isProcessing;

    final isActive = isVisionActive || isDocActive;

    if (isActive) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _visionSubscription?.cancel();
    _docSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVisionActive = (_currentVisionStatus?.isProcessing ?? false) ||
        VisionService.instance.isProcessing;
    final visionQueueLen = _currentVisionStatus?.queueLength ?? VisionService.instance.queueLength;

    final isDocActive = (_currentDocStatus?.isProcessing ?? false) ||
        DocumentExtractionService.instance.isProcessing;
    final docRemaining = _currentDocStatus?.remainingCount ?? 0;

    if (!isVisionActive && visionQueueLen == 0 && !isDocActive) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dynamic label and color: Orange for Docs, Indigo for Vision AI
    String statusText = 'Processing';
    Color themeColor = const Color(0xFF6366F1);
    Color bgColor = isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF);
    Color textColor = isDark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3);

    if (isDocActive) {
      themeColor = const Color(0xFFFF9800);
      bgColor = isDark ? const Color(0xFF3D2300) : const Color(0xFFFFF3E0);
      textColor = isDark ? const Color(0xFFFFCC80) : const Color(0xFFE65100);
      statusText = docRemaining > 0 ? 'Indexing Docs ($docRemaining)' : 'Indexing Docs';
    } else if (isVisionActive) {
      statusText = visionQueueLen > 0 ? 'Vision AI ($visionQueueLen)' : 'Vision AI';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.35),
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
                color: themeColor,
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.6),
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
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
