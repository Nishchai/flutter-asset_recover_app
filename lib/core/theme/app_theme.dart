import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:flutter/material.dart';

/// Builds [ThemeData] and exposes semantic colors from `theme_config.json`.
///
/// Wrap reads through [AppPalette] (available via `Theme.of(context)` extension
/// or directly from the held instance) so screens never hard-code colors.
class AppTheme {
  AppTheme(this._config) : palette = AppPalette(_config.themeConfig);

  final ConfigService _config;
  final AppPalette palette;

  ThemeData build() {
    final shape = (_config.themeConfig['shape'] as Map?) ?? const {};
    final typo = (_config.themeConfig['typography'] as Map?) ?? const {};
    final inputRadius = (shape['inputRadius'] as num?)?.toDouble() ?? 10;
    final buttonRadius = (shape['buttonRadius'] as num?)?.toDouble() ?? 12;
    final fontFamily = typo['fontFamily'] as String?;

    final scheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      secondary: palette.secondary,
      surface: palette.surface,
      error: palette.danger,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      fontFamily: fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: palette.primary, width: 1.6),
        ),
      ),
      // Primary CTA = dark pill with yellow text (Figma "Call Customer",
      // "Submit & Navigate", "Proceed to collect"). The yellow-filled variant
      // is PillButton.yellow in shared/widgets.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.pillDark,
          foregroundColor: palette.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.onSurface,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.primaryLight,
      ),
    );
  }
}

/// Semantic palette parsed from `theme_config.json` colors.
class AppPalette {
  AppPalette(Map<String, dynamic> themeConfig)
      : _colors = (themeConfig['colors'] as Map?)?.cast<String, dynamic>() ??
            const {},
        _caseColors =
            (themeConfig['caseTypeColors'] as Map?)?.cast<String, dynamic>() ??
                const {},
        _outcomeColors =
            (themeConfig['outcomeColors'] as Map?)?.cast<String, dynamic>() ??
                const {};

  final Map<String, dynamic> _colors;
  final Map<String, dynamic> _caseColors;
  final Map<String, dynamic> _outcomeColors;

  Color _c(String key, [String fallback = '#000000']) =>
      hexToColor((_colors[key] as String?) ?? fallback);

  Color get primary => _c('primary', '#E2E300');
  Color get primaryDark => _c('primaryDark', '#BFC000');
  Color get primaryLight => _c('primaryLight', '#FAFBD6');
  Color get secondary => _c('secondary', '#1B2335');
  Color get background => _c('background', '#F6F6F3');
  Color get surface => _c('surface', '#FFFFFF');
  Color get onPrimary => _c('onPrimary', '#15171C');
  Color get onSurface => _c('onSurface', '#16181F');
  Color get muted => _c('muted', '#8A8F98');
  Color get border => _c('border', '#E6E7E9');
  Color get success => _c('success', '#2EA86A');
  Color get warning => _c('warning', '#E6A312');
  Color get danger => _c('danger', '#E5484D');
  Color get info => _c('info', '#5B6CFF');
  Color get scannerBackground => _c('scannerBackground', '#0A0D14');

  // Dark hero / header surfaces (Figma dark sections).
  Color get heroTop => _c('heroTop', '#0A0D14');
  Color get heroBottom => _c('heroBottom', '#1B2336');
  Color get darkSurface => _c('darkSurface', '#141A27');
  Color get darkBorder => _c('darkBorder', '#2A3142');
  Color get onDark => _c('onDark', '#FFFFFF');
  Color get mutedDark => _c('mutedDark', '#8A93A6');
  Color get pillDark => _c('pillDark', '#101319');
  Color get chipBg => _c('chipBg', '#F1F2F4');

  /// The dark hero gradient used by headers and result screens.
  Gradient get heroGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [heroTop, heroBottom],
      );

  Color caseTypeColor(String caseType) =>
      hexToColor((_caseColors[caseType] as String?) ?? '#6B7280');

  Color outcomeColor(String resolution) =>
      hexToColor((_outcomeColors[resolution] as String?) ?? '#8A8F98');

  /// Parses `#RRGGBB` or `#AARRGGBB` into a [Color].
  static Color hexToColor(String hex) {
    var value = hex.replaceAll('#', '').trim();
    if (value.length == 6) value = 'FF$value';
    return Color(int.parse(value, radix: 16));
  }
}
