import 'package:flutter/material.dart';

ColorScheme _scheme(
  Color? seed,
  Brightness brightness, {
  Object? dynamicScheme,
}) {
  final base = dynamicScheme != null
      ? _fromDynamicScheme(dynamicScheme, brightness)
      : ColorScheme.fromSeed(
          seedColor: seed ?? const Color(0xFF7C5CFF),
          brightness: brightness,
        );
  return _neutralSurfaces(base, brightness);
}

/// Replaces tinted surfaces with neutral grays so the app matches the
/// system light/dark look instead of picking up a wallpaper/seed tint.
ColorScheme _neutralSurfaces(ColorScheme scheme, Brightness brightness) {
  if (brightness == Brightness.dark) {
    return scheme.copyWith(
      surface: const Color(0xFF121212),
      onSurface: const Color(0xFFE3E3E3),
      surfaceDim: const Color(0xFF121212),
      surfaceBright: const Color(0xFF383838),
      surfaceContainerLowest: const Color(0xFF0D0D0D),
      surfaceContainerLow: const Color(0xFF1A1A1A),
      surfaceContainer: const Color(0xFF1E1E1E),
      surfaceContainerHigh: const Color(0xFF282828),
      surfaceContainerHighest: const Color(0xFF333333),
      onSurfaceVariant: const Color(0xFFC4C4C4),
      outline: const Color(0xFF8E8E8E),
      outlineVariant: const Color(0xFF444444),
      surfaceTint: Colors.transparent,
    );
  }
  return scheme.copyWith(
    surface: const Color(0xFFFAFAFA),
    onSurface: const Color(0xFF1B1B1B),
    surfaceDim: const Color(0xFFDADADA),
    surfaceBright: const Color(0xFFFAFAFA),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF4F4F4),
    surfaceContainer: const Color(0xFFEEEEEE),
    surfaceContainerHigh: const Color(0xFFE8E8E8),
    surfaceContainerHighest: const Color(0xFFE2E2E2),
    onSurfaceVariant: const Color(0xFF474747),
    outline: const Color(0xFF777777),
    outlineVariant: const Color(0xFFC7C7C7),
    surfaceTint: Colors.transparent,
  );
}

ColorScheme _fromDynamicScheme(dynamic scheme, Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: scheme.primary as Color,
    brightness: brightness,
  );
  return base.copyWith(
    primary: scheme.primary as Color,
    onPrimary: scheme.onPrimary as Color,
    primaryContainer: scheme.primaryContainer as Color,
    onPrimaryContainer: scheme.onPrimaryContainer as Color,
    secondary: scheme.secondary as Color,
    onSecondary: scheme.onSecondary as Color,
    secondaryContainer: scheme.secondaryContainer as Color,
    onSecondaryContainer: scheme.onSecondaryContainer as Color,
    tertiary: scheme.tertiary as Color,
    onTertiary: scheme.onTertiary as Color,
    tertiaryContainer: scheme.tertiaryContainer as Color,
    onTertiaryContainer: scheme.onTertiaryContainer as Color,
    error: scheme.error as Color,
    onError: scheme.onError as Color,
    errorContainer: scheme.errorContainer as Color,
    onErrorContainer: scheme.onErrorContainer as Color,
    surface: scheme.surface as Color,
    onSurface: scheme.onSurface as Color,
    surfaceDim: scheme.surfaceDim as Color,
    surfaceBright: scheme.surfaceBright as Color,
    surfaceContainerLowest: scheme.surfaceContainerLowest as Color,
    surfaceContainerLow: scheme.surfaceContainerLow as Color,
    surfaceContainer: scheme.surfaceContainer as Color,
    surfaceContainerHigh: scheme.surfaceContainerHigh as Color,
    surfaceContainerHighest: scheme.surfaceContainerHighest as Color,
    onSurfaceVariant: scheme.onSurfaceVariant as Color,
    outline: scheme.outline as Color,
    outlineVariant: scheme.outlineVariant as Color,
    shadow: scheme.shadow as Color,
    scrim: scheme.scrim as Color,
    inverseSurface: scheme.inverseSurface as Color,
    onInverseSurface: scheme.onInverseSurface as Color,
    inversePrimary: scheme.inversePrimary as Color,
    surfaceTint: scheme.surfaceTint as Color,
  );
}

ThemeData buildAppTheme(ColorScheme scheme) {
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      centerTitle: false,
    ),
  );
}

/// App theme from settings: accent color or system colors.
ThemeData appThemeFor({
  required Brightness brightness,
  required bool useSystemColor,
  required Color accent,
  Object? dynamicScheme,
}) {
  return buildAppTheme(
    _scheme(
      accent,
      brightness,
      dynamicScheme: useSystemColor ? dynamicScheme : null,
    ),
  );
}
