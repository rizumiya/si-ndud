import 'package:flutter/material.dart';

class AppTheme {
  static const Color backgroundDark = Color(0xFF0B1120);
  static const Color surfaceDark = Color(0xFF151F32);
  static const Color surfaceElevated = Color(0xFF1E293B);
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color coralAccent = Color(0xFFFF4D6D);
  static const Color limeAccent = Color(0xFF22C55E);
  static const Color amberAccent = Color(0xFFF59E0B);
  static const Color violetAccent = Color(0xFFA855F7);

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: cyanAccent,
      brightness: Brightness.dark,
      surface: surfaceDark,
      primary: cyanAccent,
      secondary: limeAccent,
      tertiary: coralAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.07),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceDark,
        indicatorColor: cyanAccent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
