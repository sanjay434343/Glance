import 'package:flutter/material.dart';

class AppTheme {
  // App-wide colors
  static const Color primaryColor = Color(0xFF3478F6);

  static Color getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'screenshot':
      case 'photo':
      case 'camera_capture':
        return Colors.pinkAccent;
      case 'webpage':
      case 'url':
        return Colors.blueAccent;
      case 'copied_text':
      case 'clipboard':
        return Colors.orangeAccent;
      case 'pdf':
      case 'document':
      case 'file':
        return Colors.redAccent;
      case 'location':
        return Colors.teal;
      case 'notification':
      case 'sms':
      case 'call_log':
        return Colors.indigoAccent;
      case 'app_activity':
        return Colors.purpleAccent;
      default:
        return Colors.blueGrey;
    }
  }

  // Common card backgrounds
  static Color getCardBackground(bool isDark) {
    return isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA);
  }

  // Common scaffold background
  static Color getScaffoldBackground(bool isDark) {
    return isDark ? const Color(0xFF121212) : Colors.white;
  }

  // Common card borders
  static Color getCardBorder(bool isDark) {
    return isDark 
        ? Colors.white.withValues(alpha: 0.05) 
        : Colors.black.withValues(alpha: 0.03);
  }

  // Primary text color
  static Color getPrimaryText(bool isDark) {
    return isDark ? Colors.white : const Color(0xFF111418);
  }

  // Secondary text color
  static Color getSecondaryText(bool isDark) {
    return isDark ? Colors.grey[500]! : const Color(0xFF6B7280);
  }
}
