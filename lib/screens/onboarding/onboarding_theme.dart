import 'package:flutter/material.dart';

/// Shared design tokens for the onboarding flow.
class OnboardingTheme {
  // Colors — Light
  static const Color bgLight = Color(0xFFFAF8F5); // warm off-white
  static const Color textPrimary = Color(0xFF1A1A1E);
  static const Color textSecondary = Color(0xFF8A8A91);
  static const Color textTertiary = Color(0xFFB0B0B6);
  static const Color accent = Color(0xFF2D2F36);
  static const Color accentSoft = Color(0xFFE8E6E2);
  static const Color divider = Color(0xFFE8E6E2);
  static const Color cardBg = Color(0xFFFFFFFF);

  // Colors — Dark
  static const Color bgDark = Color(0xFF1A1A1E);
  static const Color textPrimaryDark = Color(0xFFF0EFED);
  static const Color textSecondaryDark = Color(0xFF8A8A91);
  static const Color accentDark = Color(0xFFF0EFED);
  static const Color cardBgDark = Color(0xFF242428);

  // Spacing
  static const double marginH = 24.0;
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 16.0;
  static const double spacingLG = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Radii
  static const double radiusSM = 12.0;
  static const double radiusMD = 16.0;

  // Durations
  static const Duration transitionDuration = Duration(milliseconds: 350);

  static Color bg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? bgDark : bgLight;

  static Color primary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textPrimaryDark : textPrimary;

  static Color secondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textSecondaryDark : textSecondary;

  static Color card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cardBgDark : cardBg;

  static Color cta(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? accentDark : accent;

  static Color ctaText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? bgDark : Color(0xFFFAF8F5);

  static TextStyle headline(BuildContext context) => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: primary(context),
        height: 1.2,
        letterSpacing: -0.5,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: secondary(context),
        height: 1.5,
      );

  static TextStyle label(BuildContext context) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: secondary(context),
        height: 1.4,
      );
}
