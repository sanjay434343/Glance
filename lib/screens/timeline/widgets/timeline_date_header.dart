import 'package:flutter/material.dart';

class TimelineDateHeader extends StatelessWidget {
  final String date;

  const TimelineDateHeader({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111418);

    return Text(
      date,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
  }
}
