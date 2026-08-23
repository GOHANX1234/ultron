import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/screens/splash_screen.dart';

const Key _nextKey = Key('next-screen');

Widget _wrap({bool disableAnimations = false}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: SplashScreen(
          next: (_) => const Scaffold(body: SizedBox(key: _nextKey)),
        ),
      ),
    ),
  );
}

/// Pumps a fixed number of small frames.
///
/// Not pumpAndSettle: the splash keeps a looping controller running for as long
/// as it is on screen, so settling never happens. Frame-by-frame also matters
/// for route transitions — a controller started inside a frame gets its time
/// baseline from its *first* tick, so a single large pump advances it by zero
/// and the outgoing route is never removed.
Future<void> _frames(WidgetTester tester, {int count = 24}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  testWidgets('composes the mark, wordmark and tagline', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(SplashScreen.logoKey), findsOneWidget);
    expect(find.byKey(SplashScreen.wordmarkKey), findsOneWidget);
    expect(find.text('Automation agent'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tear the tree down so the looping idle controller is disposed inside the
    // test rather than left running past it.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('the entrance is staged, not all at once', (tester) async {
    await tester.pumpWidget(_wrap());

    // A frame into the timeline the mark has started and the tagline has not:
    // if every element shared one interval this would read as a single pop.
    await tester.pump(const Duration(milliseconds: 250));
    final logoEarly =
        tester.widget<FadeTransition>(find.byKey(SplashScreen.logoFadeKey));
    final taglineEarly =
        tester.widget<FadeTransition>(find.byKey(SplashScreen.taglineFadeKey));

    expect(logoEarly.opacity.value, greaterThan(0));
    expect(taglineEarly.opacity.value, equals(0));

    await tester.pump(const Duration(milliseconds: 1400));
    expect(taglineEarly.opacity.value, greaterThan(0));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('replaces itself with next when the timeline finishes',
      (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byKey(_nextKey), findsNothing);

    await tester.pump(SplashScreen.entrance);
    // Surfaced here rather than at the end of the test, so a throw from the
    // handover is not reported as a missing widget.
    expect(tester.takeException(), isNull);

    // The route transition still has to run.
    await _frames(tester);

    expect(find.byKey(_nextKey), findsOneWidget);
    expect(find.byKey(SplashScreen.logoKey), findsNothing);
  });

  testWidgets('honours "remove animations" without stranding the user',
      (tester) async {
    await tester.pumpWidget(_wrap(disableAnimations: true));

    // The assertion is about the outcome, not about which frame the handover
    // lands on: the reduced timeline plus its page transition is well under a
    // second, so by here the user is on the next screen rather than parked on
    // a still frame for the full 2.1s entrance.
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_nextKey), findsOneWidget);
    expect(SplashScreen.reducedEntrance, lessThan(SplashScreen.entrance));
  });

  testWidgets('disposes both tickers', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));

    // An undisposed repeating controller fails the test binding here rather
    // than leaking silently on device.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });
}
