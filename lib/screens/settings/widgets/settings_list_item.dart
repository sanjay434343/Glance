import 'package:flutter/material.dart';

class SettingsListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final bool hasChevron;
  final bool isDark;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const SettingsListItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.hasChevron = false,
    required this.isDark,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = titleColor ?? (isDark ? Colors.white : const Color(0xFF111418));
    final subColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final iColor = iconColor ?? textColor;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: subtitle != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: subtitle != null ? 2.0 : 0.0),
            child: Icon(icon, color: iColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: subColor,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: subColor,
              ),
            ),
          if (hasChevron)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(Icons.chevron_right, color: subColor, size: 20),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      );
    }

    return content;
  }
}
