import 'package:flutter/material.dart';

ThemeData clubTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF9BBE45),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF182F3B),
        onPrimary: Colors.white,
        secondary: const Color(0xFFC4E66B),
        onSecondary: const Color(0xFF243313),
        secondaryContainer: const Color(0xFFE5F1C5),
        onSecondaryContainer: const Color(0xFF243313),
        surface: const Color(0xFFF6F8F3),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.primary,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: scheme.secondaryContainer,
    ),
  );
}
