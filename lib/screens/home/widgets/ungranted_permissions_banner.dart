import 'package:flutter/material.dart';
import '../../../core/services/glance_permission_service.dart';
import '../../../core/theme/theme.dart';

class UngrantedPermissionsBanner extends StatelessWidget {
  final List<GlancePermissionItem> ungrantedPermissions;
  final bool isDark;
  final VoidCallback onPermissionChanged;

  const UngrantedPermissionsBanner({
    super.key,
    required this.ungrantedPermissions,
    required this.isDark,
    required this.onPermissionChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (ungrantedPermissions.isEmpty) {
      return const SizedBox.shrink();
    }

    final cardBg = AppTheme.getCardBackground(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subColor = AppTheme.getSecondaryText(isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.withValues(alpha: isDark ? 0.35 : 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: isDark ? 0.05 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: Colors.amber[800],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Permissions Needed',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${ungrantedPermissions.length} pending',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.amber[300] : Colors.amber[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 6),
          ...ungrantedPermissions.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == ungrantedPermissions.length - 1;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 20,
                        color: isDark ? Colors.grey[300] : const Color(0xFF374151),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: subColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await item.onRequest();
                          onPermissionChanged();
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF3478F6).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF3478F6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Grant',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast) const Divider(height: 1, thickness: 0.4),
              ],
            );
          }),
        ],
      ),
    );
  }
}
