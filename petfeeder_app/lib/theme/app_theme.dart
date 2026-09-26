import 'package:flutter/material.dart';

class AppTheme {
  // Palette - Warm, Tactile, Modern Pet Care
  static const Color primary = Color(0xFFE07A5F);       // Terracotta Clay
  static const Color primaryDark = Color(0xFFC85A3D);
  static const Color primaryLight = Color(0xFFFDE8E1);
  
  static const Color darkSlate = Color(0xFF1E293B);      // Deep Charcoal
  static const Color background = Color(0xFFF7F5F0);     // Warm Cream
  static const Color surface = Color(0xFFFFFFFF);        // Pure White Card
  
  static const Color accentGreen = Color(0xFF2A9D8F);    // Sage Green (Healthy/Success)
  static const Color accentAmber = Color(0xFFF4A261);    // Warm Gold (Warning/Attention)
  static const Color accentCoral = Color(0xFFE76F51);    // Coral Red (Critical/Jam/Empty)
  
  static const Color textMain = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textLight = Color(0xFF94A3B8);
  static const Color border = Color(0xFFE2E8F0);

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: accentGreen,
        surface: surface,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textMain),
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
