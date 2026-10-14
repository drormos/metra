import 'package:flutter/material.dart';

/// Design tokens from `docs/design/ui-spec.md`. Every widget color comes
/// from here (via [MetraColorsContext.colors] or the [ThemeData] built by
/// [metraTheme]); widgets hardcode none.
@immutable
class MetraColors extends ThemeExtension<MetraColors> {
  const MetraColors({
    required this.background,
    required this.sheet,
    required this.surface,
    required this.divider,
    required this.selectedRow,
    required this.border,
    required this.text,
    required this.muted,
    required this.beatResting,
    required this.beatSounding,
    required this.accentResting,
    required this.accentSounding,
    required this.mutedFill,
    required this.mutedLine,
    required this.tickResting,
    required this.tickSounding,
    required this.accent,
    required this.primary,
    required this.onPrimary,
  });

  /// Dark theme.
  static const stageBlack = MetraColors(
    background: Color(0xFF000000),
    sheet: Color(0xFF111111),
    surface: Color(0xFF1A1A1A),
    divider: Color(0xFF1F1F1F),
    selectedRow: Color(0xFF242424),
    border: Color(0xFF2E2E2E),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFF8C8C8C),
    beatResting: Color(0xFF3A3A3A),
    beatSounding: Color(0xFFFFFFFF),
    accentResting: Color(0xFF8E2620),
    accentSounding: Color(0xFFFF4A3D),
    mutedFill: Color(0xFF1A1A1A),
    mutedLine: Color(0xFF7A7A7A),
    tickResting: Color(0xFF2A2A2A),
    tickSounding: Color(0xFFD0D0D0),
    accent: Color(0xFFFF3B30),
    primary: Color(0xFFFF3B30),
    onPrimary: Color(0xFF000000),
  );

  /// Light theme. Picked after the dark one; to be checked on a real screen.
  static const daylight = MetraColors(
    background: Color(0xFFF3F1EC),
    sheet: Color(0xFFECE9E2),
    surface: Color(0xFFE3DFD6),
    divider: Color(0xFFDCD8CF),
    selectedRow: Color(0xFFDAD5CB),
    border: Color(0xFFCFCAC0),
    text: Color(0xFF111111),
    muted: Color(0xFF5E5A52),
    beatResting: Color(0xFFB9B4AA),
    beatSounding: Color(0xFF111111),
    accentResting: Color(0xFFE9B0AA),
    accentSounding: Color(0xFFD7261E),
    mutedFill: Color(0xFFE3DFD6),
    mutedLine: Color(0xFF8A857C),
    tickResting: Color(0xFFD8D3C9),
    tickSounding: Color(0xFF5E5A52),
    accent: Color(0xFFD7261E),
    primary: Color(0xFF111111),
    onPrimary: Color(0xFFF3F1EC),
  );

  final Color background;

  /// Bottom sheets.
  final Color sheet;

  /// Filled buttons.
  final Color surface;

  /// Lines between list rows; the ruler's rules.
  final Color divider;

  /// The current row in a list (current song, current set).
  final Color selectedRow;

  /// Outlines and frames.
  final Color border;
  final Color text;
  final Color muted;

  /// Beat blocks show their type at rest and light only while sounding.
  final Color beatResting;
  final Color beatSounding;
  final Color accentResting;
  final Color accentSounding;

  /// Muted beats never light: a dark fill with one diagonal line.
  final Color mutedFill;
  final Color mutedLine;

  /// Subdivision strip under each beat block.
  final Color tickResting;
  final Color tickSounding;

  /// Tempo needle, current-song marker, checkmarks.
  final Color accent;
  final Color primary;
  final Color onPrimary;

  @override
  MetraColors copyWith() => this;

  // Theme switches snap; no color animation between the two palettes.
  @override
  MetraColors lerp(MetraColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension MetraColorsContext on BuildContext {
  MetraColors get colors => Theme.of(this).extension<MetraColors>()!;
}

/// Saira 500/600 for body text; Saira Extra Condensed 600/700 for the BPM
/// number, song title, time signature and ±buttons. Bundled in
/// `assets/fonts/`.
abstract final class MetraFonts {
  static const body = 'Saira';
  static const condensed = 'SairaExtraCondensed';
}

ThemeData metraTheme(MetraColors c, Brightness brightness) {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );
  const label = TextStyle(
    fontFamily: MetraFonts.body,
    fontWeight: FontWeight.w600,
  );
  return ThemeData(
    brightness: brightness,
    fontFamily: MetraFonts.body,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.divider,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accentSounding,
      onSecondary: c.onPrimary,
      error: c.accentSounding,
      onError: c.onPrimary,
      surface: c.background,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerHighest: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainer: c.surface,
      outline: c.border,
      outlineVariant: c.border,
    ),
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: shape,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border, width: 2),
        shape: shape,
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.text, textStyle: label),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.sheet,
      modalBackgroundColor: c.sheet,
      dragHandleColor: c.muted,
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.sheet),
    popupMenuTheme: PopupMenuThemeData(color: c.sheet),
    dividerTheme: DividerThemeData(color: c.divider),
  );
}
