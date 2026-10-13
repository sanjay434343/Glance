import 'package:flutter/material.dart';

class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final IconData? actionIcon;
  final Color titleColor;
  final Color actionColor;
  final VoidCallback? onActionTap;

  const HomeSectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.actionIcon,
    required this.titleColor,
    required this.actionColor,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        if (actionText != null)
          GestureDetector(
            onTap: onActionTap,
            child: Text(
              actionText!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: actionColor,
              ),
            ),
          )
        else if (actionIcon != null)
          GestureDetector(
            onTap: onActionTap,
            child: Icon(actionIcon, color: actionColor, size: 20),
          ),
      ],
    );
  }
}
