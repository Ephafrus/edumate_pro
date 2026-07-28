import 'package:flutter/material.dart';

/// Theming for EduMate Pro. Modern Material 3, built from a seed colour and
/// brightness so users can configure their own look & feel (see
/// [AppThemeOption]). Defaults to a friendly school indigo.
class AppTheme {
  /// Selectable seed palette with school-friendly tones.
  static const seeds = <AppThemeOption>[
    AppThemeOption('Indigo', Color(0xFF3F51B5)),
    AppThemeOption('School Blue', Color(0xFF1C6DD0)),
    AppThemeOption('Teal', Color(0xFF028090)),
    AppThemeOption('Emerald', Color(0xFF1B9C85)),
    AppThemeOption('Sunshine', Color(0xFFF9A825)),
    AppThemeOption('Plum', Color(0xFF7B4397)),
    AppThemeOption('Coral', Color(0xFFE0555C)),
    AppThemeOption('Crimson', Color(0xFFD32F2F)),
    AppThemeOption('Sky', Color(0xFF039BE5)),
  ];

  static const Color defaultSeed = Color(0xFF3F51B5);

  static ThemeData build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? scheme.surface : const Color(0xFFF7F9FA),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? scheme.surfaceContainer : Colors.white,
        foregroundColor: scheme.primary,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHighest : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? scheme.surfaceContainer : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  /// Kept for callers that want a quick default light theme.
  static ThemeData light() => build(defaultSeed, Brightness.light);
}

/// A named seed colour offered in the appearance settings.
class AppThemeOption {
  const AppThemeOption(this.name, this.color);
  final String name;
  final Color color;
}
