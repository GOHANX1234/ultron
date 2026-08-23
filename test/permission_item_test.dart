import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/config/design_tokens.dart';
import 'package:private_agent/widgets/onboarding/permission_item.dart';

const _name = 'Microphone';
const _why = 'Speech is transcribed while you hold the mic button.';
const _consequence = 'Without it, you can still type every instruction.';

Widget _wrap({required bool granted, VoidCallback? onGrant, String? label}) {
  return MaterialApp(
    theme: onboardingTheme(),
    home: Scaffold(
      body: PermissionItem(
        name: _name,
        why: _why,
        consequence: _consequence,
        granted: granted,
        onGrant: onGrant ?? () {},
        grantLabel: label ?? 'Grant',
      ),
    ),
  );
}

void main() {
  testWidgets('states the mechanism and the cost of declining', (tester) async {
    await tester.pumpWidget(_wrap(granted: false));

    expect(find.text(_name), findsOneWidget);
    expect(find.text(_why), findsOneWidget);
    expect(find.text(_consequence), findsOneWidget);
  });

  testWidgets('never nags', (tester) async {
    await tester.pumpWidget(_wrap(granted: false));

    // The screen this replaces put an "ACTION NEEDED" badge on every ungranted
    // row. The consequence line carries that information without shouting.
    expect(find.textContaining('ACTION'), findsNothing);
    expect(find.textContaining('REQUIRED'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('the grant control calls back and can be relabelled',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(granted: false, onGrant: () => taps++, label: 'Set up'),
    );

    expect(find.text('Set up'), findsOneWidget);
    await tester.tap(find.byKey(PermissionItem.grantKey(_name)));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('granted replaces the control instead of disabling it',
      (tester) async {
    await tester.pumpWidget(_wrap(granted: true));

    expect(find.byKey(PermissionItem.grantedKey(_name)), findsOneWidget);
    expect(find.text('GRANTED'), findsOneWidget);
    expect(find.byKey(PermissionItem.grantKey(_name)), findsNothing);

    // Still explains itself once granted: a user who revoked it later should
    // find the same sentence, not an empty row.
    expect(find.text(_why), findsOneWidget);
  });

  testWidgets('carries no decorative icon', (tester) async {
    await tester.pumpWidget(_wrap(granted: false));

    // Six rounded-square glyphs down the left edge made every item look
    // equally important, which is the opposite of a hierarchy.
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('grant is an outline, not a second primary action',
      (tester) async {
    await tester.pumpWidget(_wrap(granted: false));

    final material = tester.widget<Material>(
      find.byKey(PermissionItem.grantKey(_name)),
    );
    expect(material.color, Brand.surfaceHigh);
    expect(material.color, isNot(Brand.signal));
  });
}
