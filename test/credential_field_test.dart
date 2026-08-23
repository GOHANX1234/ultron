import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/config/design_tokens.dart';
import 'package:private_agent/widgets/onboarding/credential_field.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: onboardingTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(Space.x3), child: child),
    ),
  );
}

void main() {
  testWidgets('secrets are masked, and the reveal toggle is the caller\'s flag',
      (tester) async {
    final controller = TextEditingController(text: 'sk-secret');
    addTearDown(controller.dispose);
    var toggles = 0;

    await tester.pumpWidget(
      _wrap(
        CredentialField(
          label: 'API key',
          controller: controller,
          obscure: true,
          onToggleObscure: () => toggles++,
        ),
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(CredentialField.fieldKey('API key')),
    );
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);

    await tester.tap(find.byKey(CredentialField.toggleKey('API key')));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('there is no toggle unless one is wired up', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(CredentialField(label: 'Endpoint', controller: controller)),
    );

    expect(find.byKey(CredentialField.toggleKey('Endpoint')), findsNothing);
  });

  testWidgets('what the user types is set in the data face', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        CredentialField(
          label: 'Endpoint',
          controller: controller,
          hint: 'https://api.example.com/v1',
        ),
      ),
    );

    // Mono is not decoration here: in mono a mistyped `l` for `1` in an
    // endpoint is visibly different, and it is what makes the screen read as a
    // credentials form rather than a settings page.
    final field = tester.widget<TextField>(
      find.byKey(CredentialField.fieldKey('Endpoint')),
    );
    expect(field.style!.fontFamily, AppType.mono);
    expect(field.decoration!.hintStyle!.fontFamily, AppType.mono);
    expect(find.text('https://api.example.com/v1'), findsOneWidget);
  });

  testWidgets('the label is an eyebrow and optional is marked as such',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        CredentialField(
          label: 'Voice API key',
          controller: controller,
          optional: true,
          helper: 'Leave blank to keep Ultron silent.',
        ),
      ),
    );

    expect(find.text('VOICE API KEY'), findsOneWidget);
    expect(find.text('OPTIONAL'), findsOneWidget);
    expect(find.text('Leave blank to keep Ultron silent.'), findsOneWidget);
  });

  testWidgets('an in-field action fires, and can be disabled mid-request',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var fetches = 0;

    await tester.pumpWidget(
      _wrap(
        CredentialField(
          label: 'Model',
          controller: controller,
          actionLabel: 'Fetch',
          onAction: () => fetches++,
        ),
      ),
    );

    await tester.tap(find.byKey(CredentialField.actionKey('Model')));
    await tester.pump();
    expect(fetches, 1);

    await tester.pumpWidget(
      _wrap(
        CredentialField(
          label: 'Model',
          controller: controller,
          actionLabel: 'Fetch',
          onAction: null,
        ),
      ),
    );
    await tester.tap(find.byKey(CredentialField.actionKey('Model')));
    await tester.pump();
    expect(fetches, 1);
  });

  testWidgets('a validation failure is shown on the field, not only in prose',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        CredentialField(
          label: 'API key',
          controller: controller,
          hasError: true,
        ),
      ),
    );

    final decorated = tester.widget<Container>(
      find
          .ancestor(
            of: find.byKey(CredentialField.fieldKey('API key')),
            matching: find.byType(Container),
          )
          .first,
    );
    final border = (decorated.decoration as BoxDecoration).border!;
    expect(border.top.color, Brand.danger);
  });
}
