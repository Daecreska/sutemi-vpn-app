import 'dart:ui';
import 'package:flutter/material.dart';

class SutemiColors {
  static const background = Color(0xFF0B0D13);
  static const surface = Color(0xFF141824);
  static const surfaceElevated = Color(0xFF1B2130);
  static const textPrimary = Color(0xFFF5F7FF);
  static const textSecondary = Color(0xFF939BB4);
  static const mint = Color(0xFF5EE6B5);
  static const cyan = Color(0xFF78E0D6);
  static const violet = Color(0xFFA78BFA);
  static const amber = Color(0xFFF0CA75);
  static const rose = Color(0xFFFF8C9E);
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.16),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.11),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

ThemeData buildSutemiTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SutemiColors.background,
    colorScheme: const ColorScheme.dark(
      surface: SutemiColors.surface,
      primary: SutemiColors.mint,
      secondary: SutemiColors.violet,
      error: SutemiColors.rose,
    ),
    useMaterial3: true,
    fontFamily: 'Plus Jakarta Sans',
  );
}
