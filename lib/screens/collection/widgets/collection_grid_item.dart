import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class CollectionGridItem extends StatelessWidget {
  final String imagePath;
  final Color iconColor;
  final String title;
  final String count;
  final bool isDark;
  final VoidCallback? onTap;

  const CollectionGridItem({
    super.key,
    required this.imagePath,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = AppTheme.getCardBackground(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subtitleColor = AppTheme.getSecondaryText(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: AppTheme.getCardBorder(isDark),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              imagePath,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count,
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
    );
  }
}
