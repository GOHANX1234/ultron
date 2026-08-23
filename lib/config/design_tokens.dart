import 'package:flutter/material.dart';

/// The Ultron-3 design tokens.
///
/// Three rules this file exists to enforce, because the screens that came
/// before it broke all three:
///
///  1. **One accent.** [Brand.signal] is the only chromatic colour in the
///     product surface. It means *armed* — a granted permission, the active
///     step, the primary action. Nothing decorative is ever tinted with it, and
///     there is no second brand colour to gradient into.
///  2. **A closed spacing and radius scale.** [Space] is an 8dp grid with a
///     single 4dp half-step; [Corner] has three values. Ad-hoc numbers in
///     layout code are how padding drifts between two cards that should match.
///  3. **One elevation.** Surfaces are separated by a hairline [Brand.line],
///     not by blur or shadow. [Brand.lift] is the only shadow in the system and
///     is reserved for things that genuinely float above the page (dialogs).
abstract final class Space {
  /// The half-step. Only for optical nudges inside a component (icon to label),
  /// never for layout between components.
  static const double half = 4;

  static const double x1 = 8;
  static const double x2 = 16;
  static const double x3 = 24;
  static const double x4 = 32;
  static const double x5 = 40;
  static const double x6 = 48;

  /// The page gutter. On the 8dp grid on purpose — the old screens used 20.
  static const double gutter = x3;
}

/// The radius scale. Controls are [control], cards are [card], and only
/// full-bleed sheets and dialogs get [sheet].
abstract final class Corner {
  /// State marks — the 7-9dp squares that stand in for an indicator light. A
  /// chamfer rather than a scale step: at [control] an 8dp square is a circle,
  /// and a circle reads as a bullet instead of a light.
  static const double mark = 2;

  /// Controls under 32dp: the stepper tiles, the Grant control.
  static const double tick = 8;

  static const double control = 12;
  static const double card = 16;
  static const double sheet = 24;

  static const BorderRadius markR = BorderRadius.all(Radius.circular(mark));
  static const BorderRadius tickR = BorderRadius.all(Radius.circular(tick));
  static const BorderRadius controlR = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetR = BorderRadius.all(Radius.circular(sheet));
}

/// The palette. Deliberately dark-only: onboarding is a fixed surface that has
/// to read the same on every device before the user has any settings, so it
/// does not follow the system theme the way the rest of the app does.
///
/// The neutrals are true greys with a faint warm bias rather than the blue-grey
/// slate ramp used elsewhere, so the lime accent does not turn cyan next to
/// them.
abstract final class Brand {
  /// Page background.
  static const Color ink = Color(0xFF0B0B0C);

  /// Card and panel fill.
  static const Color surface = Color(0xFF141416);

  /// Inputs, selected rows, pressed states — one step up from [surface].
  static const Color surfaceHigh = Color(0xFF1C1C1F);

  /// The hairline that does the work shadows used to do.
  static const Color line = Color(0xFF2A2A2E);
  static const Color lineStrong = Color(0xFF3D3D43);

  static const Color textPrimary = Color(0xFFF4F4F1);
  static const Color textSecondary = Color(0xFFA3A3A0);
  static const Color textTertiary = Color(0xFF6F6F6D);

  /// The accent. Acid lime, bright enough that its foreground is black — which
  /// is what keeps a primary button from needing a glow to look pressable.
  static const Color signal = Color(0xFFCBF13C);
  static const Color onSignal = Color(0xFF0B0B0C);

  /// Only for genuine cautions (the restricted-settings step), never for
  /// "you haven't done this yet".
  static const Color caution = Color(0xFFE0A33C);

  /// Validation failures.
  static const Color danger = Color(0xFFE5484D);

  /// The system's single shadow, for dialogs only.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  static Border hairline({Color? color}) =>
      Border.fromBorderSide(BorderSide(color: color ?? line));
}

/// The type ramp.
///
/// The pairing is a grotesk (Roboto, the platform UI face — already bundled, so
/// no font dependency) for everything editorial, against the platform monospace
/// for machine data: keys, endpoints, model ids, step numbers, counts. Splitting
/// prose from data by *face* is what gives the credentials form its voice; the
/// old screens set everything in one semibold sans and reached for colour
/// instead.
abstract final class AppType {
  /// Android resolves this to Roboto Mono. Android-only app, so no asset.
  static const String mono = 'monospace';

  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    color: Brand.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontSize: 19,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: Brand.textPrimary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14.5,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: Brand.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: Brand.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: Brand.textTertiary,
  );

  /// Tracked-out caps. The only place case is used as a device.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: Brand.textTertiary,
  );

  static const TextStyle data = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    height: 1.35,
    color: Brand.textSecondary,
  );

  static const TextStyle dataSmall = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 0.2,
    color: Brand.textTertiary,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: Brand.textPrimary,
  );
}

/// The onboarding [ThemeData].
///
/// Wrapping the flow in its own theme rather than styling each widget is what
/// keeps the parts of Material we do not build ourselves — dialog surfaces,
/// bottom sheets, snackbars, the text-selection handles — inside the palette.
ThemeData onboardingTheme() {
  const scheme = ColorScheme.dark(
    primary: Brand.signal,
    onPrimary: Brand.onSignal,
    secondary: Brand.signal,
    onSecondary: Brand.onSignal,
    surface: Brand.surface,
    onSurface: Brand.textPrimary,
    error: Brand.danger,
    onError: Brand.textPrimary,
    outline: Brand.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.ink,
    canvasColor: Brand.ink,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: Brand.line,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Corner.sheetR),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Brand.surfaceHigh,
      contentTextStyle: AppType.bodyStrong,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: Corner.controlR,
        side: const BorderSide(color: Brand.line),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Brand.signal,
      selectionColor: Color(0x33CBF13C),
      selectionHandleColor: Brand.signal,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Brand.signal,
      linearTrackColor: Brand.line,
      circularTrackColor: Brand.line,
    ),
  );
}
