import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../utils/shared_preferences.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.system,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppClr.primaryColor,
      scaffoldBackgroundColor: AppClr.lightBackground,
      cardColor: AppClr.cardBackground,

      colorScheme: const ColorScheme.light(
        primary: AppClr.primaryColor,
        secondary: AppClr.secondaryColor,
        surface: AppClr.cardBackground,
        background: AppClr.lightBackground,
        error: AppClr.errorColor,
        onPrimary: AppClr.white,
        onSecondary: AppClr.white,
        onSurface: AppClr.textPrimary,
        onBackground: AppClr.textPrimary,
        onError: AppClr.white,
      ),

      textTheme: TextTheme(
        displayLarge: AppTextStyles.h1,
        displayMedium: AppTextStyles.h2,
        displaySmall: AppTextStyles.h3,
        headlineLarge: AppTextStyles.h4,
        headlineMedium: AppTextStyles.h5,
        headlineSmall: AppTextStyles.h6,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
        labelLarge: AppTextStyles.buttonText,
        labelMedium: AppTextStyles.label,
        labelSmall: AppTextStyles.caption,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppClr.primaryColor,
          foregroundColor: AppClr.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppClr.grey100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.errorColor, width: 1),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppClr.primaryColor,
      scaffoldBackgroundColor: AppClr.darkBackground,
      cardColor: AppClr.darkCardBackground,

      colorScheme: const ColorScheme.dark(
        primary: AppClr.primaryColor,
        secondary: AppClr.secondaryColor,
        surface: AppClr.darkCardBackground,
        background: AppClr.darkBackground,
        error: AppClr.errorColor,
        onPrimary: AppClr.white,
        onSecondary: AppClr.white,
        onSurface: AppClr.textDark,
        onBackground: AppClr.textDark,
        onError: AppClr.white,
      ),

      textTheme: TextTheme(
        displayLarge: AppTextStyles.h1.copyWith(color: AppClr.textDark),
        displayMedium: AppTextStyles.h2.copyWith(color: AppClr.textDark),
        displaySmall: AppTextStyles.h3.copyWith(color: AppClr.textDark),
        headlineLarge: AppTextStyles.h4.copyWith(color: AppClr.textDark),
        headlineMedium: AppTextStyles.h5.copyWith(color: AppClr.textDark),
        headlineSmall: AppTextStyles.h6.copyWith(color: AppClr.textDark),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(color: AppClr.textDark),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(color: AppClr.textDark),
        bodySmall: AppTextStyles.bodySmall.copyWith(color: AppClr.grey400),
        labelLarge: AppTextStyles.buttonText,
        labelMedium: AppTextStyles.label.copyWith(color: AppClr.grey400),
        labelSmall: AppTextStyles.caption.copyWith(color: AppClr.grey400),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppClr.primaryColor,
          foregroundColor: AppClr.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppClr.grey800,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.errorColor, width: 1),
        ),
      ),
    );
  }

  static Future<void> toggleTheme() async {
    if (themeModeNotifier.value == ThemeMode.light) {
      themeModeNotifier.value = ThemeMode.dark;
      await SharedPreferencesHelper.setBool('isDarkMode', true);
    } else {
      themeModeNotifier.value = ThemeMode.light;
      await SharedPreferencesHelper.setBool('isDarkMode', false);
    }
  }

  static Future<void> initializeTheme() async {
    final isDarkMode = SharedPreferencesHelper.getBool('isDarkMode') ?? false;
    themeModeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }
}
