import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/config/design_tokens.dart';
import 'package:private_agent/widgets/onboarding/onboarding_stepper.dart';

const _labels = ['Overview', 'Permissions', 'Setup'];

Widget _wrap({required int current, ValueChanged<int>? onSelect}) {
  return MaterialApp(
    theme: onboardingTheme(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(Space.x3),
        child: OnboardingStepper(
          labels: _labels,
          current: current,
          onSelect: onSelect ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders one tile per step', (tester) async {
    await tester.pumpWidget(_wrap(current: 0));

    for (var i = 0; i < _labels.length; i++) {
      expect(find.byKey(OnboardingStepper.tileKey(i)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the step you are on is labelled', (tester) async {
    await tester.pumpWidget(_wrap(current: 1));

    // Three labels stop fitting at the first accessibility text step, so the
    // label travels with the position instead of being drawn three times.
    expect(find.text('PERMISSIONS'), findsOneWidget);
    expect(find.text('OVERVIEW'), findsNothing);
    expect(find.text('SETUP'), findsNothing);
  });

  testWidgets('completed steps are checked, the rest are numbered',
      (tester) async {
    await tester.pumpWidget(_wrap(current: 2));

    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.text('03'), findsOneWidget);
    expect(find.text('01'), findsNothing);
  });

  testWidgets('a step behind you is tappable and reports its index',
      (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(_wrap(current: 2, onSelect: picked.add));

    await tester.tap(find.byKey(OnboardingStepper.tileKey(0)));
    await tester.pump();

    expect(picked, [0]);
  });

  testWidgets('the current and upcoming steps are not tappable',
      (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(_wrap(current: 1, onSelect: picked.add));

    // The pill-and-chips row this replaces looked equally tappable in both
    // directions, while only going back is allowed. Asserted on the callbacks
    // rather than on taps, because "nothing happened" is the same observation
    // whether the tile ignored the tap or was never hit.
    final taps = tester
        .widgetList<InkWell>(find.byType(InkWell))
        .map((w) => w.onTap)
        .toList();

    expect(taps.length, 3);
    expect(taps[0], isNotNull);
    expect(taps[1], isNull);
    expect(taps[2], isNull);
    expect(picked, isEmpty);
  });

  testWidgets('announces position as one sentence to a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(current: 1));

    expect(
      find.bySemanticsLabel('Step 2 of 3, Permissions'),
      findsOneWidget,
    );

    handle.dispose();
  });
}
