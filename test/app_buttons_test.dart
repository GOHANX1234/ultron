import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/config/design_tokens.dart';
import 'package:private_agent/widgets/app_buttons.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: onboardingTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

TextStyle _labelStyle(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

void main() {
  testWidgets('primary fires once when enabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Continue', onPressed: () => taps++)),
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(taps, 1);
    expect(_labelStyle(tester, 'Continue').color, Brand.onSignal);
  });

  testWidgets('a null callback is the disabled state, and it is inert',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PrimaryButton(label: 'Continue', onPressed: null)),
    );

    // Tapping must not throw, and the state has to be visible rather than just
    // logically off: fill drops to a surface and the label goes tertiary.
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    expect(_labelStyle(tester, 'Continue').color, Brand.textTertiary);
  });

  testWidgets('busy blocks input while the request is out', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        PrimaryButton(label: 'Verify', busy: true, onPressed: () => taps++),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Verify'));
    await tester.pump();
    expect(taps, 0);

    // The label stays put, so the button does not resize mid-request.
    expect(find.text('Verify'), findsOneWidget);
  });

  testWidgets('the icon sits after the label with no trailing gap',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        PrimaryButton(
          label: 'Review permissions',
          icon: Icons.arrow_forward_rounded,
          onPressed: () {},
        ),
      ),
    );

    final label = tester.getRect(find.text('Review permissions'));
    final icon = tester.getRect(find.byIcon(Icons.arrow_forward_rounded));
    final button = tester.getRect(find.byType(InkWell));

    expect(icon.left, greaterThan(label.right - 1));

    // The label-plus-icon cluster is centred in the button: an earlier version
    // left a gap after the icon, which pushed the pair visibly left. The
    // cluster's left edge is the label's own padding, so the invariant is that
    // the space before it matches the space after the icon.
    expect(
      label.left - Space.x2 - button.left,
      closeTo(button.right - icon.right, 1.5),
    );
  });

  testWidgets('secondary is an outline with no fill, and it fires',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(SecondaryButton(label: 'Back', onPressed: () => taps++)),
    );

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(taps, 1);
    expect(_labelStyle(tester, 'Back').color, Brand.textPrimary);
  });

  testWidgets('both styles share one height, so a footer row sits level',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        Row(
          children: [
            SecondaryButton(label: 'Back', expand: false, onPressed: () {}),
            Expanded(
              child: PrimaryButton(label: 'Continue', onPressed: () {}),
            ),
          ],
        ),
      ),
    );

    final back = tester.getRect(find.text('Back'));
    final next = tester.getRect(find.text('Continue'));
    expect(back.center.dy, closeTo(next.center.dy, 0.5));
  });
}
