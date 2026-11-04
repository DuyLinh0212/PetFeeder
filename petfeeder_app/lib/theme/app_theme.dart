import 'package:flutter/material.dart';

class AppTheme {
  static const primary = Color(0xFF08B989);
  static const primaryDark = Color(0xFF087A62);
  static const primaryLight = Color(0xFFDDF9F1);
  static const darkSlate = Color(0xFF183F3A);
  static const background = Color(0xFFF2F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const accentGreen = Color(0xFF08A975);
  static const accentAmber = Color(0xFFB47722);
  static const accentCoral = Color(0xFFC44949);
  static const textMain = Color(0xFF222A34);
  static const textMuted = Color(0xFF68717D);
  static const textLight = Color(0xFF808995);
  static const border = Color(0xFFE2EAF0);
  static const pagePadding = EdgeInsets.fromLTRB(20, 12, 20, 24);

  static ThemeData get themeData {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: Colors.white,
      secondary: accentAmber,
      surface: surface,
      error: accentCoral,
      onSurface: textMain,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );
    const shape = StadiumBorder();
    final buttons = ElevatedButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      elevation: 0,
      shape: shape,
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(
        bodyColor: textMain,
        displayColor: textMain,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textMain,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 58,
        titleSpacing: 8,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFFF4F7F9)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttons),
      filledButtonTheme: FilledButtonThemeData(style: buttons),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 56),
          side: const BorderSide(color: border),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: background,
        selectedColor: primary,
        checkmarkColor: Colors.white,
        side: const BorderSide(color: border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        labelStyle: const TextStyle(
          fontFamily: 'Roboto',
          color: textMain,
          fontWeight: FontWeight.w600,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: primary,
        inactiveTrackColor: primaryLight,
        thumbColor: primary,
        overlayColor: primary.withAlpha(20),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryLight,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? primary : textMuted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
    );
  }
}
