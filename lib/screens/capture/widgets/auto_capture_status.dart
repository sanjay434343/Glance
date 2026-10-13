import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class AutoCaptureStatus extends StatelessWidget {
  const AutoCaptureStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF162016) : const Color(0xFFF0FDF4); // Very light green
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final subtitleColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.green.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto capture is ON',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Screenshots, links, app activity\nand more are saved locally.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: subtitleColor, size: 20.0),
        ],
      ),
    );
  }
}
