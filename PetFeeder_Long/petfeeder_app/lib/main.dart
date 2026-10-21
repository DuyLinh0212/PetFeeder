import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PetFeeder · Long',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f6b)),
      scaffoldBackgroundColor: const Color(0xfff4f7f2),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xfff7f9f5),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffd8e3db))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffd8e3db))),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: const Color(0xff087f6b),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
    ),
    home: DashboardScreen(api: ApiService()),
  ));
}
