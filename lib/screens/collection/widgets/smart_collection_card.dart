import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class SmartCollectionCard extends StatelessWidget {
  final Widget image;
  final String title;
  final String itemsCount;
  final bool isDark;
  final VoidCallback? onTap;
  final double? height;
  final double imageHeight;

  const SmartCollectionCard({
    super.key,
    required this.image,
    required this.title,
    required this.itemsCount,
    required this.isDark,
    this.onTap,
    this.height = 180,
    this.imageHeight = 110,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.getPrimaryText(isDark);
    final subtitleColor = AppTheme.getSecondaryText(isDark);
    final bgColor = AppTheme.getCardBackground(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(23),
            topRight: Radius.circular(23),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: AppTheme.getCardBorder(isDark),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(23),
                  topRight: Radius.circular(23),
                  bottomLeft: Radius.circular(23),
                  bottomRight: Radius.circular(23),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: imageHeight,
                  child: image,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 6.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            itemsCount,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: subtitleColor,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: subtitleColor.withValues(alpha: 0.5),
                          size: 14,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
