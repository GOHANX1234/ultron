import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/config/design_tokens.dart';
import 'package:private_agent/widgets/ultron_mark.dart';

void main() {
  testWidgets('the mark takes the size it is asked for', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: UltronMark(size: 40)))),
    );

    expect(tester.getSize(find.byType(UltronMark)), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('it is drawn, not an image asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: UltronMark()))),
    );

    // A painted mark scales to any header without a second asset, and there is
    // no icon font glyph behind it that could drift back towards a sparkle.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the wordmark carries the name and the version separately',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: UltronWordmark()))),
    );

    expect(find.byKey(UltronWordmark.wordKey), findsOneWidget);
    expect(find.text('ULTRON'), findsOneWidget);

    // The version is machine information, so it is set in the data face rather
    // than being spelled into the name.
    final version = tester.widget<Text>(find.text('3'));
    expect(version.style!.fontFamily, AppType.mono);
    expect(find.byType(UltronMark), findsOneWidget);
  });
}
