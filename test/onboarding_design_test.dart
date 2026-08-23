import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards on the design decisions the brief was explicit about.
///
/// Widget tests prove the flow works; these prove it still looks like itself.
/// Every item here is something a later edit could reintroduce in one line
/// without breaking a single behavioural test — a gradient on a button, a blur
/// behind a card, a sparkle next to a heading.
String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

const _surfaces = [
  'lib/screens/onboarding_screen.dart',
  'lib/widgets/app_buttons.dart',
  'lib/widgets/ultron_mark.dart',
  'lib/widgets/onboarding/onboarding_stepper.dart',
  'lib/widgets/onboarding/permission_item.dart',
  'lib/widgets/onboarding/credential_field.dart',
];

void main() {
  test('no gradients anywhere in the flow', () {
    for (final path in _surfaces) {
      final source = _read(path);
      expect(source, isNot(contains('LinearGradient')), reason: path);
      expect(source, isNot(contains('RadialGradient')), reason: path);
      expect(source, isNot(contains('SweepGradient')), reason: path);
      expect(source, isNot(contains('ShaderMask')), reason: path);
    }
  });

  test('no glass: no backdrop blur and no stacked shadows', () {
    for (final path in _surfaces) {
      final source = _read(path);
      expect(source, isNot(contains('BackdropFilter')), reason: path);
      expect(source, isNot(contains('ImageFilter')), reason: path);
      expect(source, isNot(contains('BoxShadow')), reason: path);
    }
  });

  test('no sparkles, stars or magic wands as decoration', () {
    for (final path in _surfaces) {
      final source = _read(path);
      for (final icon in [
        'auto_awesome',
        'star_rounded',
        'auto_fix',
        'bolt_rounded',
      ]) {
        expect(source, isNot(contains(icon)), reason: '$path uses $icon');
      }
    }
  });

  test('colour comes from the token file, never from a literal', () {
    for (final path in _surfaces) {
      final source = _read(path);
      // Colors.transparent and Color(0x..) inside design_tokens are fine; a
      // hex literal out here is how a second accent gets in.
      expect(
        RegExp(r'Color\(0x').hasMatch(source),
        isFalse,
        reason: '$path hardcodes a colour instead of using Brand',
      );
      expect(source, isNot(contains('withOpacity(')), reason: path);
    }
  });

  test('spacing and radii come off the scale', () {
    final source = _read('lib/screens/onboarding_screen.dart');
    expect(source, contains('Space.gutter'));
    expect(source, contains('Corner.cardR'));

    // EdgeInsets built from bare numbers are the drift the scale prevents.
    final literalPadding = RegExp(r'EdgeInsets\.(all|symmetric)\(\s*\d')
        .allMatches(source)
        .length;
    expect(literalPadding, 0, reason: 'padding bypasses Space');
  });

  test('corners come off the radius scale', () {
    // ultron_mark is exempt: the mark is drawn in units of its own size, so its
    // geometry scales with the logo rather than with the layout.
    for (final path in _surfaces.where((p) => !p.contains('ultron_mark'))) {
      final source = _read(path);
      expect(
        RegExp(r'Radius\.circular\(\s*\d').hasMatch(source),
        isFalse,
        reason: '$path sets a radius by hand instead of using Corner',
      );
    }
  });

  test('the flow is dark by decision, not by inheriting the system theme', () {
    final source = _read('lib/screens/onboarding_screen.dart');
    expect(source, contains('onboardingTheme()'));
    expect(source, contains('Brand.ink'));
  });

  test('the old glass and sparkle implementations are gone for good', () {
    final source = _read('lib/screens/onboarding_screen.dart');
    expect(source, isNot(contains('LiquidGlass')));
    expect(source, isNot(contains('GeminiSparkle')));
  });
}
