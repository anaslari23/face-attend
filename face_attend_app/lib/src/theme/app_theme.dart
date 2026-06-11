import 'package:flutter/material.dart';

class FaceAttendColors {
  const FaceAttendColors._();

  static const background = Color(0xFFF7F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF0EDE6);
  static const ink = Color(0xFF25231F);
  static const muted = Color(0xFF736E66);
  static const border = Color(0xFFE3DED4);
  static const accent = Color(0xFF45685A);
  static const accentSoft = Color(0xFFE6EEE8);
  static const success = Color(0xFF3F7D58);
  static const warning = Color(0xFFB9822B);
  static const danger = Color(0xFFB55249);
  static const overlay = Color(0xE625231F);
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
        bottom: BorderSide(color: FaceAttendColors.border, width: 0.6),
      ),
      titleTextStyle: TextStyle(
        color: FaceAttendColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: FaceAttendColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: FaceAttendColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FaceAttendColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: FaceAttendColors.muted, fontSize: 14),
      prefixIconColor: FaceAttendColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FaceAttendColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FaceAttendColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: FaceAttendColors.accent,
          width: 1.4,
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
