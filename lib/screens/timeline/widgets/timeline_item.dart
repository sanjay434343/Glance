import 'package:flutter/material.dart';

class TimelineItem extends StatefulWidget {
  final String time;
  final String title;
  final String subtitle;
  final Widget image;
  final bool isFirst;
  final bool isLast;
  final int count;
  final VoidCallback? onTap;
  final List<Widget>? children;

  const TimelineItem({
    super.key,
    required this.time,
    required this.title,
    required this.subtitle,
    required this.image,
    this.isFirst = false,
    this.isLast = false,
    this.count = 1,
    this.onTap,
    this.children,
  });

  @override
  State<TimelineItem> createState() => _TimelineItemState();
}

class _TimelineItemState extends State<TimelineItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final lineColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final timeColor = isDark ? Colors.grey[500]! : const Color(0xFF6B7280);
    final dotColor = widget.isLast ? const Color(0xFF3478F6) : lineColor;

    const double topOffset = 36.0;

    return CustomPaint(
      painter: _TimelineLinePainter(
        lineColor: lineColor,
        dotColor: dotColor,
        dotBgColor: bgColor,
        isFirst: widget.isFirst,
        isLast: widget.isLast,
        dotCenterY: topOffset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spacer for line and dot column (width: 24)
          const SizedBox(width: 24),
          
          // Time Text
          Padding(
            padding: const EdgeInsets.only(left: 12.0, right: 16.0),
            child: SizedBox(
              width: 56,
              child: Padding(
                padding: const EdgeInsets.only(top: topOffset - 7),
                child: Text(
                  widget.time,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: timeColor,
                  ),
                ),
              ),
            ),
          ),
          
          // Content Card
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (widget.children != null && widget.children!.isNotEmpty) {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                } else if (widget.onTap != null) {
                  widget.onTap!();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCard(context, isDark),
                    if (_isExpanded && widget.children != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0, left: 16.0),
                        child: Column(
                          children: widget.children!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final subtitleColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

    return Row(
      children: [
        // Image thumbnail with optional badge
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: widget.image,
              ),
            ),
            if (widget.count > 1)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.count > 99 ? '99+' : widget.count.toString(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        // Title and Subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Trailing Icon
        if (widget.children != null && widget.children!.isNotEmpty)
          Icon(
            _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: subtitleColor.withValues(alpha: 0.6),
            size: 24,
          )
        else
          Icon(Icons.chevron_right, color: subtitleColor.withValues(alpha: 0.6), size: 20),
      ],
    );
  }
}

class _TimelineLinePainter extends CustomPainter {
  final Color lineColor;
  final Color dotColor;
  final Color dotBgColor;
  final bool isFirst;
  final bool isLast;
  final double dotCenterY;

  const _TimelineLinePainter({
    required this.lineColor,
    required this.dotColor,
    required this.dotBgColor,
    required this.isFirst,
    required this.isLast,
    this.dotCenterY = 36.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const startX = 12.0;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Top vertical connecting line
    if (!isFirst) {
      canvas.drawLine(const Offset(startX, 0), Offset(startX, dotCenterY - 4), linePaint);
    }

    // Bottom vertical connecting line
    if (!isLast) {
      canvas.drawLine(Offset(startX, dotCenterY + 4), Offset(startX, size.height), linePaint);
    }

    // Dot at (startX, dotCenterY)
    if (isLast) {
      final fillPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(startX, dotCenterY), 4.0, fillPaint);
    } else {
      final bgPaint = Paint()
        ..color = dotBgColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(startX, dotCenterY), 4.0, bgPaint);

      final strokePaint = Paint()
        ..color = dotColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(startX, dotCenterY), 4.0, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineLinePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.dotBgColor != dotBgColor ||
        oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.dotCenterY != dotCenterY;
  }
}
