import 'package:flutter/material.dart';

class HomeFilterChip extends StatelessWidget {
  final String label;
  final String imagePath;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const HomeFilterChip({
    super.key,
    required this.label,
    required this.imagePath,
    this.isSelected = false,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? const Color(0xFFE8F0FE)
        : (isDark ? const Color(0xFF1E1E1E) : Colors.white);

    final textColor = isSelected
        ? const Color(0xFF1A73E8)
        : (isDark ? Colors.grey[300] : const Color(0xFF4B5563));

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: isSelected
                ? null
                : Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
            boxShadow: isSelected || isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imagePath,
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
