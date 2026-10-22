import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Design tokens from `docs/design/ui-spec.md`. Every widget color comes
/// from here (via [MetraColorsContext.colors] or the [ThemeData] built by
/// [metraTheme]); widgets hardcode none.
@immutable
class MetraColors extends ThemeExtension<MetraColors> {
  const MetraColors({
    required this.background,
    required this.sheet,
    required this.dim,
    required this.lifted,
    required this.slot,
    required this.shadow,
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
    required this.pulseResting,
    required this.pulseAccentResting,
    required this.pulseMutedLine,
    required this.disabledText,
    required this.controlOutline,
    required this.accent,
    required this.primary,
    required this.onPrimary,
  });

  /// Dark theme.
  static const stageBlack = MetraColors(
    background: Color(0xFF000000),
    sheet: Color(0xFF111111),
    dim: Color(0x99000000),
    lifted: Color(0xFF2A2A2A),
    slot: Color(0xFF4A4A4A),
    shadow: Color(0xD9000000),
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
    pulseResting: Color(0xFF262626),
    pulseAccentResting: Color(0xFF5A1A16),
    pulseMutedLine: Color(0xFF3A3A3A),
    disabledText: Color(0xFF5A5A5A),
    controlOutline: Color(0xFF6E6E6E),
    accent: Color(0xFFFF3B30),
    primary: Color(0xFFFF3B30),
    onPrimary: Color(0xFF000000),
  );

  /// Light theme. Picked after the dark one; to be checked on a real screen.
  static const daylight = MetraColors(
    background: Color(0xFFF3F1EC),
    sheet: Color(0xFFECE9E2),
    dim: Color(0x59000000),
    lifted: Color(0xFFFFFFFF),
    slot: Color(0xFFA8A39A),
    shadow: Color(0x40000000),
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
    pulseResting: Color(0xFFD8D3C9),
    pulseAccentResting: Color(0xFFF0CCC8),
    pulseMutedLine: Color(0xFFB9B4AA),
    disabledText: Color(0xFFA39E94),
    controlOutline: Color(0xFF8A857C),
    accent: Color(0xFFD7261E),
    primary: Color(0xFF111111),
    onPrimary: Color(0xFFF3F1EC),
  );

  final Color background;

  /// Bottom sheets, dialogs, dropdown panels.
  final Color sheet;

  /// Over the main screen while a dropdown panel is open.
  final Color dim;

  /// A set's songs while reordering: the lifted row, the dashed drop slot,
  /// and the lifted row's shadow.
  final Color lifted;
  final Color slot;
  final Color shadow;

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

  /// Polyrhythm lane cells at rest, quieter than beat blocks; muted cells
  /// are a dashed outline. Sounding: [beatSounding] / [accent].
  final Color pulseResting;
  final Color pulseAccentResting;
  final Color pulseMutedLine;

  /// Text of things that can't be used ("In this set"); exempt from
  /// contrast rules, so never for readable text.
  final Color disabledText;

  /// Outlines that must be seen to be used (unchecked checkboxes, search
  /// fields): 3:1 or better.
  final Color controlOutline;

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
/// The media card's cover (ui-spec.md "Media controls"): always dark, in
/// both themes.
abstract final class CoverColors {
  static const background = Color(0xFF000000);
  static const bpm = Color(0xFFFFFFFF);
  static const rule = Color(0xFF1F1F1F);
  static const minorTick = Color(0xFF4A4A4A);
  static const majorTick = Color(0xFF8C8C8C);
  static const needle = Color(0xFFFF3B30);
}

/// The motion tokens (ui-spec.md "Motion"): one set of values, used for
/// every change on screen instead of ad-hoc durations. Nothing waits for
/// them, and with "Remove animations" on they're all instant ([of]).
abstract final class MetraMotion {
  /// Text that changes in place: a cross-fade, no slide or size change.
  static const swap = Duration(milliseconds: 120);
  static const swapCurve = Curves.easeInOut;

  /// A BPM digit that changes rolls in its slot.
  static const roll = Duration(milliseconds: 140);
  static const rollCurve = Curves.easeOut;

  /// The title and set name: the old fades out fully, then the new in.
  static const fadeOut = Duration(milliseconds: 80);
  static const fadeIn = Duration(milliseconds: 120);

  /// Things going away: fade out (ease-in) while the height closes
  /// (ease-in-out).
  static const leave = Duration(milliseconds: 220);
  static const leaveFade = Curves.easeIn;
  static const leaveSize = Curves.easeInOut;

  /// Things appearing: fade in with a small rise.
  static const arrive = Duration(milliseconds: 200);
  static const arriveCurve = Curves.easeOut;
  static const arriveRise = 6.0;

  /// A beat light's fade back to rest: this long at most, never more than
  /// a third of the time to its next click.
  static const lightFade = Duration(milliseconds: 90);

  /// Above zero while a ±button is held or the tempo ruler moves: the BPM
  /// then updates instantly, so fast changes never lag the finger.
  static final tempoMoving = ValueNotifier<int>(0);

  /// A hold or ruler move began (+1) or ended (−1); after the frame when
  /// called mid-build (a button disabled at the end of the range).
  static void moving(int delta) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => tempoMoving.value += delta,
      );
    } else {
      tempoMoving.value += delta;
    }
  }

  /// Android's "Remove animations".
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or none with "Remove animations" on.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

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
    // Settings' volume sliders (settings.reference.html): a 4px rail in
    // the border color, the filled part and a 24px thumb in the text color.
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: c.text,
      inactiveTrackColor: c.border,
      thumbColor: c.text,
      overlayColor: c.text.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
      showValueIndicator: ShowValueIndicator.never,
    ),
    // A new song's or set's default name is shown selected in the accent.
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: c.accent,
      cursorColor: c.text,
      selectionHandleColor: c.accent,
    ),
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
      dragHandleColor: c.beatResting,
      dragHandleSize: const Size(40, 4),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.sheet),
    popupMenuTheme: PopupMenuThemeData(color: c.sheet),
    dividerTheme: DividerThemeData(color: c.divider),
  );
}

/// Status and navigation bars: transparent (the app draws edge to edge)
/// with icons in contrast to the theme.
SystemUiOverlayStyle systemBarsStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    systemNavigationBarColor: const Color(0x00000000),
    systemNavigationBarDividerColor: const Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: brightness, // iOS
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
  );
}
