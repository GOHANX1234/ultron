import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/screens/onboarding_screen.dart';
import 'package:private_agent/widgets/app_buttons.dart';
import 'package:private_agent/widgets/onboarding/onboarding_stepper.dart';
import 'package:private_agent/widgets/ultron_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accessibility = MethodChannel('com.ultron.llm/accessibility');
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

/// Stands in for the two plugins the screen consults on the way up.
///
/// Both are asked for state, not for permission: the accessibility service
/// reports that it is off, and every runtime permission reports denied (0 is
/// PermissionStatus.denied). That is the interesting case — a fresh install
/// with nothing granted — and it is the state the Continue gate is built for.
void _mockPlatform() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(_accessibility, (call) async {
    if (call.method == 'isServiceRunning') return false;
    return null;
  });

  messenger.setMockMethodCallHandler(_permissions, (call) async {
    if (call.method == 'checkPermissionStatus') return 0;
    if (call.method == 'checkServiceStatus') return 0;
    return 0;
  });
}

void _unmockPlatform() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_accessibility, null);
  messenger.setMockMethodCallHandler(_permissions, null);
}

/// Settles the two futures started in initState without waiting on the page
/// animation, which is not running yet.
///
/// The viewport is set to a phone rather than left at the 800x600 test default:
/// these pages are written to a ~400dp column, and at 800dp wide the headline
/// stops wrapping where it is meant to, which changes the very geometry the
/// assertions below are about.
Future<void> _boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.7;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scrolls a control into view, then taps it.
///
/// Every page here is a scroll view taller than the screen, so its footer
/// action starts below the fold. A bare `tap()` on one only warns -- it still
/// dispatches at an offset outside the view, where nothing receives it, so the
/// step silently does not advance and the failure surfaces later as a missing
/// widget on the next page.
Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockPlatform();
  });

  tearDown(_unmockPlatform);

  testWidgets('opens on the overview, with the mark and a real stepper',
      (tester) async {
    await _boot(tester);

    expect(find.byType(UltronWordmark), findsOneWidget);
    expect(find.byType(OnboardingStepper), findsOneWidget);
    expect(find.text('STEP 01 / 03'), findsOneWidget);
    expect(
      find.text('Ultron runs your phone\nfrom one written instruction.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing on the flow is blurred', (tester) async {
    await _boot(tester);

    // The glass panels this replaces were BackdropFilters over a flat grey.
    // Surfaces are separated by a hairline now, and the absence is asserted so
    // one cannot creep back in.
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('the overview hands over to the permission screen',
      (tester) async {
    await _boot(tester);

    await _press(
      tester,
      find.widgetWithText(PrimaryButton, 'Review permissions'),
    );

    expect(find.text('What Ultron needs\naccess to.'), findsOneWidget);
    expect(find.text('STEP 02 / 03'), findsOneWidget);
  });

  testWidgets('Continue is gated until the two required permissions are on',
      (tester) async {
    await _boot(tester);
    await _press(
      tester,
      find.widgetWithText(PrimaryButton, 'Review permissions'),
    );

    final gate = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Continue'),
    );
    expect(gate.onPressed, isNull);

    // ...and it says why, once, in the footer rather than as a badge on every
    // row it is waiting on.
    expect(
      find.text(
        'Continue unlocks once screen control and the microphone are on.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the permission screen counts what is granted', (tester) async {
    await _boot(tester);
    await _press(
      tester,
      find.widgetWithText(PrimaryButton, 'Review permissions'),
    );

    expect(find.text('GRANTED 0 / 6'), findsOneWidget);
    expect(find.text('GRANTED'), findsNothing);
  });

  testWidgets('a step already visited is reachable from the stepper',
      (tester) async {
    await _boot(tester);
    await _press(
      tester,
      find.widgetWithText(PrimaryButton, 'Review permissions'),
    );

    await _press(tester, find.byKey(OnboardingStepper.tileKey(0)));

    expect(find.text('STEP 01 / 03'), findsOneWidget);
  });
}
