import 'package:flutter/material.dart';

/// Theming for EduMate Pro. Modern, colourful Material 3 built from a seed
/// colour with the **vibrant** scheme variant, so the whole app picks up a
/// lively school identity. Users customise their own app — palette,
/// light/dark and text size — in Settings (see [AppThemeOption] and
/// ThemeController).
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

  /// Text-size options users can pick in Settings.
  static const textScales = <TextScaleOption>[
    TextScaleOption('Compact', 0.9),
    TextScaleOption('Standard', 1.0),
    TextScaleOption('Comfort', 1.15),
  ];

  static ThemeData build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    );
    final isDark = brightness == Brightness.dark;

    final baseText = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseText.copyWith(
      headlineLarge:
          baseText.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
      headlineMedium:
          baseText.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      headlineSmall:
          baseText.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium:
          baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          isDark ? scheme.surface : scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? scheme.surfaceContainer : scheme.surface,
        foregroundColor: scheme.primary,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? scheme.surfaceContainerHighest : scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? scheme.surfaceContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? scheme.surfaceContainer : scheme.surface,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
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

/// A named text-size option offered in the appearance settings.
class TextScaleOption {
  const TextScaleOption(this.name, this.scale);
  final String name;
  final double scale;
}

/// Colourful gradients derived from the active scheme, used by the hero
/// banner, landing page and drawer header so the "school colours" flow
/// through the app whatever palette the user picked.
extension SchemeGradients on ColorScheme {
  LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, tertiary],
      );

  LinearGradient get softGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primaryContainer,
          tertiaryContainer,
        ],
      );
}
