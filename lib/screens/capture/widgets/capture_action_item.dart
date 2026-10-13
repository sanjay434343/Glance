import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class CaptureActionItem extends StatelessWidget {
  final dynamic icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final bool isDark;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const CaptureActionItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    required this.isDark,
    this.isFirst = false,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final subtitleColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final defaultIconColor = isDark ? Colors.white : const Color(0xFF111418);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0.0 : 2.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isFirst ? 23 : 6),
          bottom: Radius.circular(isLast ? 23 : 6),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(isFirst ? 23 : 6),
              bottom: Radius.circular(isLast ? 23 : 6),
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.02),
            ),
          ),
          child: Row(
            children: [
              icon is IconData
                  ? Icon(icon, color: iconColor ?? defaultIconColor, size: 24)
                  : HugeIcon(icon: icon, color: iconColor ?? defaultIconColor, size: 24.0),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
