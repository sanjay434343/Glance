import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import '../../../core/services/app_icon_cache.dart';
import '../../../core/services/vision_service.dart';
import '../../../core/theme/theme.dart';

class HomeActivityItem extends StatefulWidget {
  final String memoryId;
  final String title;
  final String type;
  final String timeAgo;
  final IconData icon;
  final bool isDark;
  final String? sourcePackage;
  final String? imagePath;
  final String? imageBase64;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const HomeActivityItem({
    super.key,
    required this.memoryId,
    required this.title,
    required this.type,
    required this.timeAgo,
    required this.icon,
    required this.isDark,
    this.sourcePackage,
    this.imagePath,
    this.imageBase64,
    this.onTap,
    this.padding,
  });

  @override
  State<HomeActivityItem> createState() => _HomeActivityItemState();
}

class _HomeActivityItemState extends State<HomeActivityItem> with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;
  StreamSubscription<VisionQueueStatus>? _subscription;
  bool _isProcessing = false;

  bool get _isVisionEligible {
    final t = widget.type.toLowerCase();
    return (widget.imageBase64 != null && widget.imageBase64!.trim().isNotEmpty) ||
        (widget.imagePath != null && widget.imagePath!.trim().isNotEmpty) ||
        t == 'screenshot' ||
        t == 'photo' ||
        t == 'image' ||
        t == 'camera_capture';
  }

  @override
  void initState() {
    super.initState();
    if (_isVisionEligible) {
      _subscription = VisionService.instance.statusStream.listen((status) {
        if (mounted) {
          final isProcessingMe = status.isProcessing && status.currentTaskMemoryId == widget.memoryId;
          if (isProcessingMe != _isProcessing) {
            setState(() {
              _isProcessing = isProcessingMe;
              if (_isProcessing) {
                _startPulseAnimation();
              } else {
                _stopPulseAnimation();
              }
            });
          }
        }
      });
    }
  }

  void _startPulseAnimation() {
    _pulseController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation ??= Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
    _pulseController?.repeat(reverse: true);
  }

  void _stopPulseAnimation() {
    _pulseController?.stop();
    _pulseController?.reset();
  }

  @override
  void didUpdateWidget(covariant HomeActivityItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memoryId != widget.memoryId && _isProcessing) {
      _stopPulseAnimation();
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = widget.isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final typeColor = AppTheme.getTypeColor(widget.type);
    final iconBg = widget.isDark ? typeColor.withValues(alpha: 0.15) : typeColor.withValues(alpha: 0.1);

    Widget buildDefaultIcon() => Icon(widget.icon, color: typeColor, size: 24);

    Widget leadingWidget;
    if (widget.imageBase64 != null && widget.imageBase64!.trim().isNotEmpty) {
      // Decode image directly from Base64 stored in database - zero disk access dependency
      leadingWidget = Image.memory(
        base64Decode(widget.imageBase64!.trim()),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        cacheWidth: 104,
        cacheHeight: 104,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          if (widget.imagePath != null && widget.imagePath!.trim().isNotEmpty) {
            final f = File(widget.imagePath!.trim());
            if (f.existsSync()) {
              return Image.file(f, width: 52, height: 52, fit: BoxFit.cover, cacheWidth: 104, cacheHeight: 104);
            }
          }
          return buildDefaultIcon();
        },
      );
    } else if (widget.imagePath != null && widget.imagePath!.trim().isNotEmpty) {
      leadingWidget = Image.file(
        File(widget.imagePath!.trim()),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        cacheWidth: 104,
        cacheHeight: 104,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          if (frame == null) {
            return Shimmer.fromColors(
              baseColor: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              highlightColor: widget.isDark ? Colors.grey[700]! : Colors.grey[100]!,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.black : Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) => buildDefaultIcon(),
      );
    } else if (widget.sourcePackage != null && widget.sourcePackage!.trim().isNotEmpty) {
      leadingWidget = AppIconWidget(
        packageName: widget.sourcePackage!.trim(),
        size: 52,
        fallbackIcon: buildDefaultIcon(),
      );
    } else {
      leadingWidget = buildDefaultIcon();
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: widget.padding ?? const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            if (_pulseAnimation != null)
              AnimatedBuilder(
                animation: _pulseAnimation!,
                builder: (context, child) {
                  return Opacity(
                    opacity: _isProcessing ? _pulseAnimation!.value : 1.0,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                        boxShadow: _isProcessing ? [
                          BoxShadow(
                            color: const Color(0xFF3478F6).withValues(alpha: 0.5 * _pulseAnimation!.value),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ] : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: child,
                    ),
                  );
                },
                child: leadingWidget,
              )
            else
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: leadingWidget,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        widget.timeAgo,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Icon(Icons.chevron_right, color: textSecondary.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }
}

