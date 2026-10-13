import 'package:flutter/material.dart';

class TimelineTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  const TimelineTabs({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F4F6);
    
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _buildTab(context, 'Days', index: 0, isDark: isDark),
          _buildTab(context, 'Weeks', index: 1, isDark: isDark),
          _buildTab(context, 'Months', index: 2, isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, String label, {required int index, required bool isDark}) {
    final isSelected = selectedIndex == index;
    final selectedBg = isDark ? const Color(0xFF3478F6).withValues(alpha: 0.2) : const Color(0xFFE8F0FE);
    final selectedText = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1A73E8);
    final unselectedText = isDark ? Colors.grey[500] : const Color(0xFF6B7280);

    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: isSelected
              ? BoxDecoration(
                  color: selectedBg,
                  borderRadius: BorderRadius.circular(20),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? selectedText : unselectedText,
            ),
          ),
        ),
      ),
    );
  }
}
