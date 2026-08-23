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
    // The route transition still has to run.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(_nextKey), findsOneWidget);
    expect(find.byKey(SplashScreen.logoKey), findsNothing);
  });

  testWidgets('honours "remove animations" without stranding the user',
      (tester) async {
    await tester.pumpWidget(_wrap(disableAnimations: true));

    // The composed end state is shown immediately rather than animating, and
    // the screen still hands over instead of sitting on a still frame.
    await tester.pump();
    final logo =
        tester.widget<FadeTransition>(find.byKey(SplashScreen.logoFadeKey));
    expect(logo.opacity.value, equals(1));

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(_nextKey), findsOneWidget);
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
