import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/config/design_tokens.dart';

void main() {
  group('spacing', () {
    test('is an 8dp grid with a single 4dp half-step', () {
      expect(Space.half, 4);
      for (final step in [Space.x1, Space.x2, Space.x3, Space.x4, Space.x5, Space.x6]) {
        expect(step % 8, 0, reason: '$step is off the 8dp grid');
      }
    });

    test('the page gutter is a scale value, not an ad-hoc number', () {
      // The screens this replaces used 20dp gutters against 16dp card padding,
      // which is the drift the closed scale exists to prevent.
      expect(Space.gutter, Space.x3);
    });
  });

  group('radii', () {
    test('the layout scale is 12/16/24', () {
      expect(Corner.control, 12);
      expect(Corner.card, 16);
      expect(Corner.sheet, 24);
    });

    test('and rises with the size of the thing it is cutting', () {
      // Two sub-control steps exist and are the only ones: a 26dp stepper tile
      // at 12 is a lozenge, and an 8dp state mark at 12 is a dot.
      expect(Corner.mark, lessThan(Corner.tick));
      expect(Corner.tick, lessThan(Corner.control));
    });

    test('the BorderRadius constants track the scalars', () {
      expect(Corner.markR, BorderRadius.circular(Corner.mark));
      expect(Corner.tickR, BorderRadius.circular(Corner.tick));
      expect(Corner.controlR, BorderRadius.circular(Corner.control));
      expect(Corner.cardR, BorderRadius.circular(Corner.card));
      expect(Corner.sheetR, BorderRadius.circular(Corner.sheet));
    });
  });

  group('the accent', () {
    test('is a single lime, not a purple/blue gradient pair', () {
      final hsl = HSLColor.fromColor(Brand.signal);

      // Lime sits in the 60-90 degree band. The brief's "no Material purple,
      // no purple-to-blue gradient" is the constraint being locked down here:
      // both live in 220-300, and this asserts the accent is nowhere near it.
      expect(hsl.hue, greaterThan(60));
      expect(hsl.hue, lessThan(90));
      expect(hsl.saturation, greaterThan(0.5));
    });

    test('is bright enough to carry black text, which is why it needs no glow',
        () {
      expect(HSLColor.fromColor(Brand.signal).lightness, greaterThan(0.5));
      expect(Brand.onSignal, Brand.ink);
    });
  });

  group('elevation', () {
    test('there is one shadow in the system', () {
      expect(Brand.lift.length, 1);
    });

    test('surfaces separate by hairline', () {
      expect(Brand.hairline().top.color, Brand.line);
      expect(Brand.hairline(color: Brand.lineStrong).top.color, Brand.lineStrong);
    });
  });

  group('type', () {
    test('machine data is set in mono and prose is not', () {
      expect(AppType.data.fontFamily, AppType.mono);
      expect(AppType.dataSmall.fontFamily, AppType.mono);
      expect(AppType.display.fontFamily, isNull);
      expect(AppType.body.fontFamily, isNull);
    });

    test('the ramp is ordered, so hierarchy comes from size not colour', () {
      expect(AppType.display.fontSize!, greaterThan(AppType.title.fontSize!));
      expect(AppType.title.fontSize!, greaterThan(AppType.bodyStrong.fontSize!));
      expect(AppType.bodyStrong.fontSize!, greaterThan(AppType.body.fontSize!));
      expect(AppType.body.fontSize!, greaterThan(AppType.caption.fontSize!));
    });

    test('no style in the ramp is tinted with the accent', () {
      // The accent means "armed". A headline is not a state.
      const ramp = [
        AppType.display,
        AppType.title,
        AppType.bodyStrong,
        AppType.body,
        AppType.caption,
        AppType.eyebrow,
        AppType.data,
        AppType.dataSmall,
        AppType.label,
      ];
      for (final style in ramp) {
        expect(style.color, isNot(Brand.signal));
      }
    });
  });

  group('onboardingTheme', () {
    test('paints the flow, so Material surfaces stay inside the palette', () {
      final theme = onboardingTheme();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, Brand.ink);
      expect(theme.colorScheme.primary, Brand.signal);
      expect(theme.colorScheme.onPrimary, Brand.onSignal);
      expect(theme.dividerTheme.color, Brand.line);
      expect(theme.textSelectionTheme.cursorColor, Brand.signal);
      expect(theme.progressIndicatorTheme.color, Brand.signal);
    });

    test('dialogs and sheets are flat', () {
      final theme = onboardingTheme();
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.bottomSheetTheme.elevation, 0);
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    });
  });
}
