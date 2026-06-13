import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class FaceAttendColors {
  const FaceAttendColors._();

  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF8FAFC);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const accent = Color(0xFF059669);
  static const accentSoft = Color(0xFFECFDF5);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const overlay = Color(0xE60F172A);
  
  // Tech overlays & high-contrast aesthetics
  static const neonGreen = Color(0xFF00FF66);
  static const neonCyan = Color(0xFF00F0FF);
  static const darkTech = Color(0xFF0A0F1D);
}

ThemeData faceAttendTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FaceAttendColors.accent,
      primary: FaceAttendColors.accent,
      secondary: FaceAttendColors.muted,
      surface: FaceAttendColors.surface,
      error: FaceAttendColors.danger,
    ),
    scaffoldBackgroundColor: FaceAttendColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: FaceAttendColors.surface,
      foregroundColor: FaceAttendColors.ink,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      shape: Border(
        bottom: BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
      titleTextStyle: TextStyle(
        color: FaceAttendColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: FaceAttendColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FaceAttendColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: FaceAttendColors.muted, fontSize: 14),
      prefixIconColor: FaceAttendColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: FaceAttendColors.accent,
          width: 1.6,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: FaceAttendColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FaceAttendColors.accent,
    ),
  );
}

class AppLoader extends StatelessWidget {
  const AppLoader({this.size = 60, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/047a4ca0-1161-11ee-b705-c7984e04e643.json',
        repeat: true,
      ),
    );
  }
}
