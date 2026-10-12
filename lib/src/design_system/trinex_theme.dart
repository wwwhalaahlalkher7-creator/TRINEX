import 'package:flutter/material.dart';

/// Shared visual foundations for TRINEX-Admin. These tokens are original to
/// this app and deliberately independent from the legacy website interfaces.
abstract final class TrinexColors {
  static const brand = Color(0xFF3859D9);
  static const brandDeep = Color(0xFF203A9A);
  static const ink = Color(0xFF17243A);
  static const muted = Color(0xFF69758A);
  static const canvas = Color(0xFFF4F6FA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE3E8F0);
  static const success = Color(0xFF16845B);
  static const warning = Color(0xFFB86B13);
  static const danger = Color(0xFFB93838);
}

abstract final class TrinexTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: TrinexColors.brand,
      brightness: Brightness.light,
      surface: TrinexColors.surface,
      error: TrinexColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: TrinexColors.canvas,
      dividerColor: TrinexColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: TrinexColors.canvas,
        foregroundColor: TrinexColors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: TrinexColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: TrinexColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF9FAFC),
        labelStyle: const TextStyle(color: TrinexColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: TrinexColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: TrinexColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: TrinexColors.brand, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TrinexColors.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TrinexColors.ink,
          minimumSize: const Size(44, 44),
          side: const BorderSide(color: TrinexColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: TrinexColors.surface,
        indicatorColor: Color(0xFFE8EDFF),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: TrinexColors.ink, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(color: TrinexColors.ink, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: TrinexColors.ink, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: TrinexColors.ink, height: 1.45),
        bodyMedium: TextStyle(color: TrinexColors.muted, height: 1.4),
      ),
    );
  }

  static ThemeData get dark {
    const canvas = Color(0xFF101521);
    const surface = Color(0xFF1A2232);
    const border = Color(0xFF303B50);
    const ink = Color(0xFFE8EDF7);
    const muted = Color(0xFFADB8CC);
    final scheme = ColorScheme.fromSeed(
      seedColor: TrinexColors.brand,
      brightness: Brightness.dark,
      surface: surface,
      error: const Color(0xFFFF7777),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      dividerColor: border,
      appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink, elevation: 0, centerTitle: false),
      cardTheme: CardThemeData(color: surface, elevation: 0, margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: border))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF151C2A), labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFF91A7FF), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), side: const BorderSide(color: border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: ink, fontWeight: FontWeight.w800), headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700), bodyLarge: TextStyle(color: ink, height: 1.5), bodyMedium: TextStyle(color: muted, height: 1.45)),
    );
  }

}
